# Changelog

All notable changes to CraftMeter will be documented in this file.

## Unreleased

- Prepared repository for open source release.
- Added `.gitignore`, `LICENSE`, `CONTRIBUTING.md`, public architecture documentation, and GitHub Actions CI.
- Improved menubar popover layout for narrow 380px window: Top burn header, detail rows, footer truncation, and card radius consistency.

## 2026-06-27

- Renamed project from `CraftAgentTokenStatistics` to `CraftMeter`.
- Renamed CLI from `cats` to `meter`.
- Unified billable token semantics: `input + output + cacheCreation`.
- Fixed CLI `--help` exit code.
- Rebuilt app layout around Overview, Activity, and Top Burn sections.
- Added model-level breakdown grouped by model ID and inferred model tier.
- Added 365-day heatmap.
- Added Core tests for session parsing and aggregation semantics.
