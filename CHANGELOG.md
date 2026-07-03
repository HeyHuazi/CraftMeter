# Changelog

All notable changes to CraftMeter will be documented in this file.

## Unreleased

- Added a GitHub Releases workflow for tagged macOS DMG builds and documented the release artifact policy.
- Made **Tauri + React + Rust** the single active architecture for CraftMeter.
- Removed the legacy SwiftPM implementation from the main tree; old Swift code remains in Git history.
- Added Codex CLI ingestion from `~/.codex/sessions/**/*.jsonl` using `token_count.last_token_usage`.
- Added Gemini CLI ingestion from `~/.gemini/tmp/**/chats/*.jsonl` using assistant `usageMetadata`.
- Added Qwen Code ingestion from `~/.qwen/tmp/**/chats/*.jsonl` using assistant `usageMetadata`.
- Added `RawEvent.project` and project-level dashboard distribution.
- Split reasoning tokens from ordinary output tokens and surfaced reasoning in metrics, series, client usage, and UI.
- Added `PeriodReport.window` and day/week/month offsets for historical natural windows: previous day, previous week, previous month, and forward navigation back to current.
- Added AI client distribution for Claude Code, Craft Agent, Codex, Gemini CLI, and Qwen Code.
- Added Craft Agent attribution for sources, categories, status, permission mode, thinking level, and tool calls; the tool-call list is currently hidden in the UI while backend facts remain available.
- Added screenshot export from the popover.
- Reworked the menubar popover into a compact period dashboard with model tokens, cost donut, trend chart, project distribution, MCP, Skills, and Craft Agent attribution.
- Rewrote README, CONTRIBUTING, and architecture docs around the current Tauri/Rust backend.
- Added `.gitignore`, `LICENSE`, public architecture documentation, and GitHub Actions CI.
- Bumped the cache schema for ingestion/model changes.

## 2026-06-27

- Renamed project from `CraftAgentTokenStatistics` to `CraftMeter`.
- Renamed CLI from `cats` to `meter`.
- Unified billable token semantics: `input + output + cacheCreation`.
- Fixed CLI `--help` exit code.
- Rebuilt app layout around Overview, Activity, and Top Burn sections.
- Added model-level breakdown grouped by model ID and inferred model tier.
- Added 365-day heatmap.
- Added Core tests for session parsing and aggregation semantics.
