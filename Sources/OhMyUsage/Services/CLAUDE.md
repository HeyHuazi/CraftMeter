# Sources/OhMyUsage/Services/
> L2 | 父级: ../../CLAUDE.md

成员清单（analytics 与迁移核心）

ExtendedLocalUsageScanner.swift: 扫描 Gemini CLI、Qwen Code、Craft Agents JSONL，只产出统计事实与 typed facets。
UsageAnalyticsRepository.swift: 协调 CCSwitch、Claude、Codex、Kimi 与扩展 scanner，汇总 diagnostics 与完整 fingerprint。
UsageAnalyticsTypes.swift: 将 Application target analytics 公共契约别名暴露给 executable。
UsageAnalyticsAggregator.swift: Application 聚合器的 executable 兼容别名。
UsageAnalyticsSnapshotCacheStore.swift: Application schema-version cache 的 executable 兼容别名。
ClaudeLocalUsageService.swift: Claude Code 本地 usage scanner。
CodexLocalUsageService.swift: Codex 本地 usage scanner 与 summary builder。
KimiLocalUsageService.swift: Kimi wire.jsonl usage scanner。
LocalUsageHistoryRepository.swift: Provider 本地趋势 cache、fingerprint 与 stale fallback。
ConfigStore.swift: CraftMeter 配置快照加载、恢复与保存。
ConfigStorePaths.swift: CraftMeter 主目录与 OhMyUsage/AIPlanMonitor 迁移来源定义。
LegacyConfigImporter.swift: 旧配置和 supplemental files 单向导入；OhMyUsage 目录只读保留。
KeychainService.swift: `craftmeter` 凭据 vault，并从历史 service 单向迁移。
AppUpdateService.swift: HeyHuazi/CraftMeter latest.json 检测、下载和安装。
LaunchAtLoginService.swift: CraftMeter LaunchAgent 注册与历史 plist 清理。

边界

- Scanner 不做价格、时间窗口或 UI 文案。
- Repository 不实现聚合算法。
- 任何 prompt/assistant/tool result 正文不得进入 record 或 cache。
- 新 scanner 必须同时扩展 source fingerprint 与 fixture tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
