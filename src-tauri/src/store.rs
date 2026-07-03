// Incremental event store.
//
// Ingestion (this file) is the only place that touches the JSONL logs. It
// parses each assistant message into a provider/config/price-independent
// RawEvent (just the facts), reads only newly-appended bytes of changed files
// (tracked by a per-file size/mtime/offset manifest), dedupes by message id,
// and persists everything to the cache dir. Aggregation (parser.rs) then works
// purely on these in-memory events — cheap, and recomputed per request because
// the Day/Week/Month windows are relative to "now".
use crate::codex::{parse_codex_line, CodexState};
use chrono::DateTime;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use walkdir::WalkDir;

#[derive(Serialize, Deserialize, Clone, Default)]
pub struct RawCraftCall {
    pub name: String,
    pub display_name: String,
    pub category: String,
    pub status: String,
    pub is_error: bool,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct RawEvent {
    pub ts_ms: i64,
    pub session: String,
    pub model: String, // raw model id (price lookup), normalized later for grouping
    pub project: String, // logical project/workdir name; "unknown" when unavailable
    pub in_tok: f64,
    pub cc: f64, // cache creation
    pub cr: f64, // cache read
    pub out_tok: f64,
    #[serde(default)]
    pub reasoning_tok: f64,
    pub mcp: Vec<String>,    // all mcp__<server> names called (unfiltered)
    pub skills: Vec<String>, // all Skill input.skill ids called (unfiltered)
    pub id: String,          // message id (dedup)
    #[serde(default)]
    pub tool: String,
    #[serde(default)]
    pub enabled_sources: Vec<String>,
    #[serde(default)]
    pub permission_mode: String,
    #[serde(default)]
    pub thinking_level: String,
    #[serde(default)]
    pub craft_calls: Vec<RawCraftCall>,
    // Source log file (manifest key). Lets a truncated/rewritten file purge its
    // own stale events before being re-read, so re-ingestion stays idempotent.
    #[serde(default)]
    pub source: String,
}

#[derive(Serialize, Deserialize, Default)]
struct Manifest {
    // path -> (size, mtime_ms, byte offset already ingested)
    files: HashMap<String, (u64, i64, u64)>,
}

pub struct Store {
    pub events: Vec<RawEvent>,
    // message id -> index in `events`. A single assistant message can be split
    // across several JSONL lines (e.g. thinking on one line, tool_use on the
    // next) that all share its id; we merge their tool calls into one event and
    // count its token usage only once.
    index: HashMap<String, usize>,
    manifest: Manifest,
}

// Bump when the parsing/extraction logic changes in a way that requires
// re-reading logs from scratch (the incremental manifest would otherwise skip
// already-seen bytes and miss newly-extracted facts).
//   v2: count slash-command skill invocations (`/skill`), not just Skill tool_use.
//   v3: merge tool_use across lines sharing a message id (a thinking line + a
//       tool_use line were deduped, dropping the tool call).
//   v4: track a per-event source file (idempotent re-read of truncated logs).
//   v6: split reasoning tokens from output and add project facts.
const STORE_VERSION: u32 = 6;

/// Atomically replace `path`' contents: write a sibling temp file, then rename
/// over the target (same-volume rename is atomic on Windows and Unix). Avoids
/// the half-written/truncated JSON that a crash mid-`fs::write` would leave.
fn write_atomic(path: &std::path::Path, data: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, data)?;
    fs::rename(&tmp, path)
}

fn projects_dir() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join(".claude").join("projects"))
}

fn craft_agent_root() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join(".craft-agent").join("workspaces"))
}

fn codex_sessions_root() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join(".codex").join("sessions"))
}

fn gemini_tmp_root() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join(".gemini").join("tmp"))
}

fn qwen_tmp_root() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join(".qwen").join("tmp"))
}

fn cache_dir() -> Option<PathBuf> {
    let d = dirs::cache_dir()?.join("craftmeter");
    let _ = fs::create_dir_all(&d);
    Some(d)
}

impl Store {
    /// Load persisted events + offset manifest (empty on first run).
    pub fn load() -> Self {
        let mut events: Vec<RawEvent> = Vec::new();
        let mut manifest = Manifest::default();
        if let Some(dir) = cache_dir() {
            // If the cache was written by an older parser, discard it so ingest
            // does a full rescan and picks up newly-extracted facts.
            let version_ok = fs::read_to_string(dir.join("version"))
                .ok()
                .and_then(|s| s.trim().parse::<u32>().ok())
                == Some(STORE_VERSION);
            if version_ok {
                // events.json and offsets.json are ONE consistent unit: the
                // manifest's per-file byte offsets are only meaningful relative
                // to the events we actually loaded. If either is missing or fails
                // to parse (e.g. a crash left events.json half-written), discard
                // BOTH and fall back to a full rescan — otherwise a good manifest
                // paired with empty/corrupt events would make ingest() skip every
                // already-recorded file and silently lose all history.
                let loaded_events = fs::read_to_string(dir.join("events.json"))
                    .ok()
                    .and_then(|t| serde_json::from_str::<Vec<RawEvent>>(&t).ok());
                let loaded_manifest = fs::read_to_string(dir.join("offsets.json"))
                    .ok()
                    .and_then(|t| serde_json::from_str::<Manifest>(&t).ok());
                if let (Some(e), Some(m)) = (loaded_events, loaded_manifest) {
                    events = e;
                    manifest = m;
                }
            }
        }
        let index = events
            .iter()
            .enumerate()
            .filter(|(_, e)| !e.id.is_empty())
            .map(|(i, e)| (e.id.clone(), i))
            .collect();
        Store {
            events,
            index,
            manifest,
        }
    }

    pub fn save(&self) {
        if let Some(dir) = cache_dir() {
            // Atomic writes so a crash/kill mid-save can't leave a half-written
            // events.json (load() would then discard the pair and lose history).
            // Write events before offsets: if we crash between them, the manifest
            // is merely stale (points at fewer bytes → re-reads a little) rather
            // than ahead of the events on disk.
            if let Ok(t) = serde_json::to_string(&self.events) {
                let _ = write_atomic(&dir.join("events.json"), t.as_bytes());
            }
            if let Ok(t) = serde_json::to_string(&self.manifest) {
                let _ = write_atomic(&dir.join("offsets.json"), t.as_bytes());
            }
            let _ = write_atomic(&dir.join("version"), STORE_VERSION.to_string().as_bytes());
        }
    }

    /// Rebuild the id→index map after the `events` vector is mutated wholesale
    /// (purge/prune shift positions, so partial updates aren't enough).
    fn rebuild_index(&mut self) {
        self.index = self
            .events
            .iter()
            .enumerate()
            .filter(|(_, e)| !e.id.is_empty())
            .map(|(i, e)| (e.id.clone(), i))
            .collect();
    }

    /// Drop every event that came from `key`, then rebuild the index. Used before
    /// re-reading a truncated/rewritten file so re-ingestion is idempotent
    /// (otherwise the cross-line tool_use merge re-appends calls and id-less
    /// events get pushed twice, inflating MCP/Skill counts and token totals).
    fn purge_source(&mut self, key: &str) {
        self.events.retain(|e| e.source != key);
        self.rebuild_index();
    }

    /// Drop events older than `cutoff_ms`. The reports/heatmap only span the last
    /// ~26 weeks, so anything older is dead weight that grows events.json without
    /// bound. Returns whether anything was removed. Old logs already at EOF are
    /// never re-read, so their pruned events don't reappear.
    pub fn prune_before(&mut self, cutoff_ms: i64) -> bool {
        let before = self.events.len();
        self.events.retain(|e| e.ts_ms >= cutoff_ms);
        let removed = self.events.len() != before;
        if removed {
            self.rebuild_index();
        }
        removed
    }

    pub fn ingest(&mut self) -> bool {
        let mut dirty = false;
        if let Some(root) = projects_dir() {
            dirty |= self.ingest_claude_projects(&root);
        }
        if let Some(root) = craft_agent_root() {
            dirty |= self.ingest_craft_agent(&root);
        }
        if let Some(root) = codex_sessions_root() {
            dirty |= self.ingest_codex_sessions(&root);
        }
        if let Some(root) = gemini_tmp_root() {
            dirty |= self.ingest_gemini_like_sessions(&root, "gemini-cli");
        }
        if let Some(root) = qwen_tmp_root() {
            dirty |= self.ingest_gemini_like_sessions(&root, "qwen-code");
        }
        dirty
    }

    fn ingest_claude_projects(&mut self, root: &std::path::Path) -> bool {
        let mut dirty = false;
        for entry in WalkDir::new(root)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
        {
            let path = entry.path();
            let key = path.to_string_lossy().to_string();
            let Ok(meta) = fs::metadata(path) else {
                continue;
            };
            let size = meta.len();
            let mtime_ms = meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);

            let mut offset = match self.manifest.files.get(&key).copied() {
                Some((psize, pmtime, poff)) => {
                    if psize == size && pmtime == mtime_ms {
                        continue;
                    }
                    if size < poff {
                        self.purge_source(&key);
                        0
                    } else {
                        poff
                    }
                }
                None => 0,
            };

            let Ok(mut f) = fs::File::open(path) else {
                continue;
            };
            if f.seek(SeekFrom::Start(offset)).is_err() {
                continue;
            }
            let mut buf = Vec::new();
            if f.read_to_end(&mut buf).is_err() {
                continue;
            }
            let process_until = match buf.iter().rposition(|&b| b == b'\n') {
                Some(i) => i + 1,
                None => 0,
            };
            for line in buf[..process_until].split(|&b| b == b'\n') {
                if line.is_empty() {
                    continue;
                }
                let Ok(s) = std::str::from_utf8(line) else {
                    continue;
                };
                if let Some(mut ev) = parse_line(s) {
                    ev.source = key.clone();
                    if ev.project.is_empty() || ev.project == "unknown" {
                        ev.project = project_from_claude_path(path);
                    }
                    if !ev.id.is_empty() {
                        if let Some(&i) = self.index.get(&ev.id) {
                            let prev = &mut self.events[i];
                            prev.mcp.extend(ev.mcp);
                            prev.skills.extend(ev.skills);
                            prev.craft_calls.extend(ev.craft_calls);
                            continue;
                        }
                        self.index.insert(ev.id.clone(), self.events.len());
                    }
                    self.events.push(ev);
                }
            }
            offset += process_until as u64;
            self.manifest.files.insert(key, (size, mtime_ms, offset));
            dirty = true;
        }
        dirty
    }

    fn ingest_craft_agent(&mut self, root: &std::path::Path) -> bool {
        let mut dirty = false;
        for entry in WalkDir::new(root)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path()
                    .file_name()
                    .map(|x| x == "session.jsonl")
                    .unwrap_or(false)
            })
        {
            let path = entry.path();
            let key = path.to_string_lossy().to_string();
            let Ok(meta) = fs::metadata(path) else {
                continue;
            };
            let size = meta.len();
            let mtime_ms = meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            let prev = self.manifest.files.get(&key).copied();
            if let Some((psize, pmtime, _)) = prev {
                if psize == size && pmtime == mtime_ms {
                    continue;
                }
            }
            self.purge_source(&key);
            if let Ok(text) = fs::read_to_string(path) {
                if let Some(ev) = parse_craft_session(&text) {
                    let mut ev = ev;
                    ev.source = key.clone();
                    if !ev.id.is_empty() {
                        self.index.insert(ev.id.clone(), self.events.len());
                    }
                    self.events.push(ev);
                    dirty = true;
                }
            }
            self.manifest.files.insert(key, (size, mtime_ms, size));
        }
        dirty
    }

    fn ingest_codex_sessions(&mut self, root: &std::path::Path) -> bool {
        let mut dirty = false;
        for entry in WalkDir::new(root)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
        {
            let path = entry.path();
            let key = path.to_string_lossy().to_string();
            let Ok(meta) = fs::metadata(path) else {
                continue;
            };
            let size = meta.len();
            let mtime_ms = meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);

            let mut offset = match self.manifest.files.get(&key).copied() {
                Some((psize, pmtime, poff)) => {
                    if psize == size && pmtime == mtime_ms {
                        continue;
                    }
                    if size < poff {
                        self.purge_source(&key);
                        0
                    } else {
                        poff
                    }
                }
                None => 0,
            };

            let Ok(mut f) = fs::File::open(path) else {
                continue;
            };
            let fallback_session = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("codex-session")
                .to_string();
            let mut state = CodexState::new(fallback_session);
            if offset > 0 {
                let mut prefix = vec![0; offset as usize];
                if f.seek(SeekFrom::Start(0)).is_err() || f.read_exact(&mut prefix).is_err() {
                    continue;
                }
                for line in prefix.split(|&b| b == b'\n') {
                    if line.is_empty() {
                        continue;
                    }
                    let Ok(s) = std::str::from_utf8(line) else {
                        continue;
                    };
                    let _ = parse_codex_line(s, &mut state);
                }
            }
            if f.seek(SeekFrom::Start(offset)).is_err() {
                continue;
            }
            let mut buf = Vec::new();
            if f.read_to_end(&mut buf).is_err() {
                continue;
            }
            let process_until = match buf.iter().rposition(|&b| b == b'\n') {
                Some(i) => i + 1,
                None => 0,
            };
            for line in buf[..process_until].split(|&b| b == b'\n') {
                if line.is_empty() {
                    continue;
                }
                let Ok(s) = std::str::from_utf8(line) else {
                    continue;
                };
                if let Some(mut ev) = parse_codex_line(s, &mut state) {
                    ev.source = key.clone();
                    if !ev.id.is_empty() {
                        if self.index.contains_key(&ev.id) {
                            continue;
                        }
                        self.index.insert(ev.id.clone(), self.events.len());
                    }
                    self.events.push(ev);
                }
            }
            offset += process_until as u64;
            self.manifest.files.insert(key, (size, mtime_ms, offset));
            dirty = true;
        }
        dirty
    }
    fn ingest_gemini_like_sessions(&mut self, root: &std::path::Path, tool: &str) -> bool {
        let mut dirty = false;
        for entry in WalkDir::new(root)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .filter(|e| e.path().components().any(|c| c.as_os_str() == "chats"))
        {
            let path = entry.path();
            let key = path.to_string_lossy().to_string();
            let Ok(meta) = fs::metadata(path) else {
                continue;
            };
            let size = meta.len();
            let mtime_ms = meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);

            let mut offset = match self.manifest.files.get(&key).copied() {
                Some((psize, pmtime, poff)) => {
                    if psize == size && pmtime == mtime_ms {
                        continue;
                    }
                    if size < poff {
                        self.purge_source(&key);
                        0
                    } else {
                        poff
                    }
                }
                None => 0,
            };

            let Ok(mut f) = fs::File::open(path) else {
                continue;
            };
            if f.seek(SeekFrom::Start(offset)).is_err() {
                continue;
            }
            let mut buf = Vec::new();
            if f.read_to_end(&mut buf).is_err() {
                continue;
            }
            let process_until = match buf.iter().rposition(|&b| b == b'\n') {
                Some(i) => i + 1,
                None => 0,
            };
            for line in buf[..process_until].split(|&b| b == b'\n') {
                if line.is_empty() {
                    continue;
                }
                let Ok(s) = std::str::from_utf8(line) else {
                    continue;
                };
                if let Some(mut ev) = parse_gemini_like_line(s, path, root, tool) {
                    ev.source = key.clone();
                    if !ev.id.is_empty() {
                        if self.index.contains_key(&ev.id) {
                            continue;
                        }
                        self.index.insert(ev.id.clone(), self.events.len());
                    }
                    self.events.push(ev);
                }
            }
            offset += process_until as u64;
            self.manifest.files.insert(key, (size, mtime_ms, offset));
            dirty = true;
        }
        dirty
    }
}

fn json_num(v: Option<&serde_json::Value>) -> f64 {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|n| n as f64)))
        .unwrap_or(0.0)
}

fn project_from_path_or_cwd(
    cwd: Option<&str>,
    path: &std::path::Path,
    root: &std::path::Path,
) -> String {
    if let Some(cwd) = cwd {
        if let Some(name) = std::path::Path::new(cwd)
            .file_name()
            .and_then(|s| s.to_str())
        {
            if !name.is_empty() {
                return name.to_string();
            }
        }
    }
    path.strip_prefix(root)
        .ok()
        .and_then(|p| p.components().next())
        .and_then(|c| c.as_os_str().to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("unknown")
        .to_string()
}

fn parse_gemini_like_line(
    line: &str,
    path: &std::path::Path,
    root: &std::path::Path,
    tool: &str,
) -> Option<RawEvent> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    if v.get("type").and_then(|x| x.as_str()) != Some("assistant") {
        return None;
    }
    let ts = v.get("timestamp").and_then(|x| x.as_str())?;
    let ts_ms = DateTime::parse_from_rfc3339(ts).ok()?.timestamp_millis();
    let usage = v.get("usageMetadata")?;
    let cached = json_num(usage.get("cachedContentTokenCount"));
    let thoughts = json_num(usage.get("thoughtsTokenCount"));
    let input = (json_num(usage.get("promptTokenCount")) - cached).max(0.0);
    let output = (json_num(usage.get("candidatesTokenCount")) - thoughts).max(0.0);
    if input + cached + output + thoughts <= 0.0 {
        return None;
    }
    let session = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("gemini-session")
        .to_string();
    let id = v
        .get("uuid")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string())
        .unwrap_or_else(|| format!("{tool}:{session}:{ts_ms}"));
    Some(RawEvent {
        ts_ms,
        session,
        model: v
            .get("model")
            .and_then(|x| x.as_str())
            .unwrap_or("unknown")
            .to_string(),
        project: project_from_path_or_cwd(v.get("cwd").and_then(|x| x.as_str()), path, root),
        in_tok: input,
        cc: 0.0,
        cr: cached,
        out_tok: output,
        reasoning_tok: thoughts,
        mcp: Vec::new(),
        skills: Vec::new(),
        id,
        tool: tool.to_string(),
        enabled_sources: Vec::new(),
        permission_mode: String::new(),
        thinking_level: String::new(),
        craft_calls: Vec::new(),
        source: String::new(),
    })
}

fn project_from_claude_path(path: &std::path::Path) -> String {
    path.parent()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        .map(|s| s.trim_start_matches('-').replace('-', "/"))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

/// Parse one JSONL line into a RawEvent (assistant messages only).
fn parse_line(line: &str) -> Option<RawEvent> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    match v.get("type")?.as_str()? {
        "assistant" => parse_assistant(&v),
        // Skills invoked via slash command (e.g. `/find-skills`) are logged as a
        // user message with a <command-name> tag, NOT as a Skill tool_use, so
        // they need a separate path or they'd never be counted.
        "user" => parse_user_command(&v),
        _ => None,
    }
}

/// Extract the inner text of `<tag>...</tag>` from `s`, if present.
fn extract_tag(s: &str, tag: &str) -> Option<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = s.find(&open)? + open.len();
    let rest = &s[start..];
    let end = rest.find(&close)?;
    Some(rest[..end].to_string())
}

/// A user message that is a slash-command invocation of a skill, e.g.
/// `<command-name>/find-skills</command-name>`. The skill name is left
/// unfiltered here; compute_event drops non-user skills via the whitelist.
fn parse_user_command(v: &serde_json::Value) -> Option<RawEvent> {
    let text = v.get("message")?.get("content")?.as_str()?;
    let raw = extract_tag(text, "command-name")?;
    let skill = raw.trim().trim_start_matches('/').trim().to_string();
    if skill.is_empty() {
        return None;
    }
    let ts = v.get("timestamp")?.as_str()?;
    let ts_ms = DateTime::parse_from_rfc3339(ts).ok()?.timestamp_millis();
    let session = v
        .get("sessionId")
        .and_then(|s| s.as_str())
        .unwrap_or("")
        .to_string();
    // dedup key: the line's own uuid (command messages have no message.id)
    let id = v.get("uuid").and_then(|i| i.as_str())?.to_string();
    if id.is_empty() {
        return None;
    }
    Some(RawEvent {
        ts_ms,
        session,
        model: String::new(), // not an LLM request → no model/tokens/cost
        project: String::new(),
        in_tok: 0.0,
        cc: 0.0,
        cr: 0.0,
        out_tok: 0.0,
        reasoning_tok: 0.0,
        mcp: Vec::new(),
        skills: vec![skill],
        id,
        tool: "claude-code".to_string(),
        enabled_sources: Vec::new(),
        permission_mode: String::new(),
        thinking_level: String::new(),
        craft_calls: Vec::new(),
        source: String::new(),
    })
}

fn parse_craft_session(text: &str) -> Option<RawEvent> {
    let mut lines = text.lines();
    let first = lines.next()?;
    let meta: serde_json::Value = serde_json::from_str(first).ok()?;

    let id = meta.get("id")?.as_str()?.to_string();
    let model = meta
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();
    let ts_ms = meta.get("createdAt").and_then(|v| v.as_i64()).unwrap_or(0);
    let tool = meta
        .get("tool")
        .and_then(|v| v.as_str())
        .unwrap_or("craft-agent")
        .to_string();
    let permission_mode = meta
        .get("permissionMode")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let thinking_level = meta
        .get("thinkingLevel")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let enabled_sources = meta
        .get("enabledSourceSlugs")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_else(Vec::new);

    let usage = meta.get("tokenUsage");
    let g = |k: &str| -> f64 {
        usage
            .and_then(|u| u.get(k))
            .and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|n| n as f64)))
            .unwrap_or(0.0)
    };

    let mut craft_calls = Vec::new();
    let mut mcp = Vec::new();
    let mut skills = Vec::new();
    for line in lines {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        if v.get("type").and_then(|t| t.as_str()) != Some("tool") {
            continue;
        }
        let name = v
            .get("toolName")
            .and_then(|x| x.as_str())
            .unwrap_or("")
            .to_string();
        let display_name = v
            .get("toolDisplayName")
            .and_then(|x| x.as_str())
            .unwrap_or(&name)
            .to_string();
        let status = v
            .get("toolStatus")
            .and_then(|x| x.as_str())
            .unwrap_or("unknown")
            .to_string();
        let is_error = v.get("isError").and_then(|x| x.as_bool()).unwrap_or(false);
        let category = v
            .get("toolDisplayMeta")
            .and_then(|m| m.get("category"))
            .and_then(|x| x.as_str())
            .unwrap_or("unknown")
            .to_string();
        if let Some(rest) = name.strip_prefix("mcp__") {
            mcp.push(rest.split("__").next().unwrap_or("").to_string());
        } else if name == "Skill" {
            if let Some(sk) = v
                .get("toolInput")
                .and_then(|i| i.get("skill"))
                .and_then(|s| s.as_str())
            {
                if !sk.is_empty() {
                    skills.push(sk.to_string());
                }
            }
        }
        craft_calls.push(RawCraftCall {
            name,
            display_name,
            category,
            status,
            is_error,
        });
    }

    Some(RawEvent {
        ts_ms,
        session: id.clone(),
        model,
        project: meta
            .get("workingDirectory")
            .or_else(|| meta.get("cwd"))
            .and_then(|v| v.as_str())
            .and_then(|p| std::path::Path::new(p).file_name())
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string(),
        in_tok: g("inputTokens"),
        cc: g("cacheCreationTokens"),
        cr: g("cacheReadTokens"),
        out_tok: g("outputTokens"),
        reasoning_tok: g("reasoningTokens"),
        mcp,
        skills,
        id,
        tool,
        enabled_sources,
        permission_mode,
        thinking_level,
        craft_calls,
        source: String::new(),
    })
}

fn parse_assistant(v: &serde_json::Value) -> Option<RawEvent> {
    let msg = v.get("message")?;
    let model = msg
        .get("model")
        .and_then(|m| m.as_str())
        .unwrap_or("unknown");
    if model == "<synthetic>" {
        return None;
    }
    let ts = v.get("timestamp")?.as_str()?;
    let ts_ms = DateTime::parse_from_rfc3339(ts).ok()?.timestamp_millis();
    let session = v
        .get("sessionId")
        .and_then(|s| s.as_str())
        .unwrap_or("")
        .to_string();
    let id = msg
        .get("id")
        .and_then(|i| i.as_str())
        .unwrap_or("")
        .to_string();

    let usage = msg.get("usage");
    let g = |k: &str| -> f64 {
        usage
            .and_then(|u| u.get(k))
            .and_then(|x| x.as_f64())
            .unwrap_or(0.0)
    };

    let mut mcp = Vec::new();
    let mut skills = Vec::new();
    if let Some(content) = msg.get("content").and_then(|c| c.as_array()) {
        for block in content {
            if block.get("type").and_then(|t| t.as_str()) != Some("tool_use") {
                continue;
            }
            let name = block.get("name").and_then(|n| n.as_str()).unwrap_or("");
            if let Some(rest) = name.strip_prefix("mcp__") {
                mcp.push(rest.split("__").next().unwrap_or("").to_string());
            } else if name == "Skill" {
                if let Some(sk) = block
                    .get("input")
                    .and_then(|i| i.get("skill"))
                    .and_then(|s| s.as_str())
                {
                    if !sk.is_empty() {
                        skills.push(sk.to_string());
                    }
                }
            }
        }
    }

    Some(RawEvent {
        ts_ms,
        session,
        model: model.to_string(),
        project: String::new(),
        in_tok: g("input_tokens"),
        cc: g("cache_creation_input_tokens"),
        cr: g("cache_read_input_tokens"),
        out_tok: g("output_tokens"),
        reasoning_tok: 0.0,
        mcp,
        skills,
        id,
        tool: "claude-code".to_string(),
        enabled_sources: Vec::new(),
        permission_mode: String::new(),
        thinking_level: String::new(),
        craft_calls: Vec::new(),
        source: String::new(),
    })
}
