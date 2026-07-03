use crate::store::RawEvent;
use chrono::DateTime;

#[derive(Clone)]
pub(crate) struct CodexState {
    session: String,
    model: String,
    project: String,
    turn_id: String,
    seq: u64,
}

impl CodexState {
    pub(crate) fn new(session: String) -> Self {
        Self {
            session,
            model: String::new(),
            project: "unknown".to_string(),
            turn_id: String::new(),
            seq: 0,
        }
    }
}

fn json_f64(v: Option<&serde_json::Value>) -> f64 {
    v.and_then(|x| x.as_f64().or_else(|| x.as_i64().map(|n| n as f64)))
        .unwrap_or(0.0)
}

pub(crate) fn parse_codex_line(line: &str, state: &mut CodexState) -> Option<RawEvent> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let ts = v.get("timestamp").and_then(|x| x.as_str()).unwrap_or("");
    let ts_ms = DateTime::parse_from_rfc3339(ts)
        .ok()
        .map(|t| t.timestamp_millis())
        .unwrap_or(0);
    let payload = v.get("payload")?;

    match v.get("type").and_then(|x| x.as_str()) {
        Some("session_meta") => {
            if let Some(id) = payload.get("id").and_then(|x| x.as_str()) {
                if !id.is_empty() {
                    state.session = id.to_string();
                }
            }
            if let Some(cwd) = payload.get("cwd").and_then(|x| x.as_str()) {
                state.project = std::path::Path::new(cwd)
                    .file_name()
                    .and_then(|s| s.to_str())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("unknown")
                    .to_string();
            }
            None
        }
        Some("turn_context") => {
            if let Some(turn) = payload.get("turn_id").and_then(|x| x.as_str()) {
                state.turn_id = turn.to_string();
            }
            if let Some(model) = payload.get("model").and_then(|x| x.as_str()) {
                state.model = model.to_string();
            }
            None
        }
        Some("event_msg") => parse_codex_event_msg(payload, ts_ms, state),
        _ => None,
    }
}

fn parse_codex_event_msg(
    payload: &serde_json::Value,
    ts_ms: i64,
    state: &mut CodexState,
) -> Option<RawEvent> {
    if payload.get("type").and_then(|x| x.as_str()) != Some("token_count") {
        return None;
    }

    let usage = payload.get("info")?.get("last_token_usage")?;
    let input = json_f64(usage.get("input_tokens"));
    let cached = json_f64(usage.get("cached_input_tokens"));
    let output = json_f64(usage.get("output_tokens"));
    let reasoning = json_f64(usage.get("reasoning_output_tokens"));
    if input + cached + output + reasoning <= 0.0 {
        return None;
    }

    state.seq += 1;
    let model = if state.model.is_empty() {
        "unknown".to_string()
    } else {
        state.model.clone()
    };
    let id = format!(
        "codex:{}:{}:{}:{}",
        state.session, state.turn_id, ts_ms, state.seq
    );

    Some(RawEvent {
        ts_ms,
        session: state.session.clone(),
        model,
        project: state.project.clone(),
        in_tok: input,
        cc: 0.0,
        cr: cached,
        out_tok: output,
        reasoning_tok: reasoning,
        mcp: Vec::new(),
        skills: Vec::new(),
        id,
        tool: "codex".to_string(),
        enabled_sources: Vec::new(),
        permission_mode: String::new(),
        thinking_level: String::new(),
        craft_calls: Vec::new(),
        source: String::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_count_uses_last_usage_without_private_text() {
        let mut state = CodexState::new("fallback-session".to_string());

        parse_codex_line(
            r#"{"timestamp":"2026-07-03T10:00:00.000Z","type":"session_meta","payload":{"id":"codex-session-1","cwd":"/private/project"}}"#,
            &mut state,
        );
        parse_codex_line(
            r#"{"timestamp":"2026-07-03T10:00:01.000Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.3-codex"}}"#,
            &mut state,
        );
        let ignored = parse_codex_line(
            r#"{"timestamp":"2026-07-03T10:00:02.000Z","type":"response_item","payload":{"item":{"type":"message","content":[{"type":"output_text","text":"private assistant text"}]}}}"#,
            &mut state,
        );
        let ev = parse_codex_line(
            r#"{"timestamp":"2026-07-03T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":300,"reasoning_output_tokens":40,"total_tokens":1340},"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":4,"total_tokens":17},"model_context_window":258400}}}"#,
            &mut state,
        )
        .unwrap();

        assert!(ignored.is_none());
        assert_eq!(ev.session, "codex-session-1");
        assert_eq!(ev.model, "gpt-5.3-codex");
        assert_eq!(ev.tool, "codex");
        assert_eq!(ev.in_tok, 10.0);
        assert_eq!(ev.cr, 2.0);
        assert_eq!(ev.cc, 0.0);
        assert_eq!(ev.out_tok, 3.0);
        assert_eq!(ev.reasoning_tok, 4.0);
        assert_eq!(ev.project, "project");
        assert!(ev.id.starts_with("codex:codex-session-1:turn-1:"));
        assert!(ev.mcp.is_empty());
        assert!(ev.skills.is_empty());
        assert!(ev.craft_calls.is_empty());
    }
}
