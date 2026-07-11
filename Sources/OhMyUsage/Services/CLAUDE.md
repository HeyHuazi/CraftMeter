# Sources/OhMyUsage/Services/
> L2 | 父级: ../../CLAUDE.md

成员清单（analytics 与迁移核心）

ExtendedLocalUsageScanner.swift: 扫描 Gemini CLI、Qwen Code、Craft Agents JSONL，只产出统计事实与 typed facets；Craft `costCents` 明确标记为上游报告费用。
UsageAnalyticsRepository.swift: 协调 CCSwitch、Claude、Codex、Kimi 与扩展 scanner，在去重聚合前统一执行价格 enrichment，汇总 diagnostics、完整 fingerprint，并以一次全历史读取生成今日/本周/本月/全部菜单栏摘要。
ModelPricingCatalog.swift: 隔离 Models.dev 外部 schema、bundled/last-known-good 目录、24 小时后台刷新、原子缓存、费率验证及保守 Provider+model 匹配；中转/OpenRouter/Azure/Bedrock 不套官方直连价格。
UsageAnalyticsTypes.swift: 将 Application target 的费用来源、费率 quote/estimator、totals、组合 filter、通用维度/facet stats、snapshot 与菜单栏摘要公共契约别名暴露给 executable。
UsageAnalyticsAggregator.swift: Application 聚合器的 executable 兼容别名。
UsageAnalyticsSnapshotCacheStore.swift: Application schema-version cache 的 executable 兼容别名。
ClaudeLocalUsageService.swift: Claude Code 本地 usage scanner。
CodexLocalUsageService.swift: Codex 本地 usage scanner 与 summary builder。
KimiLocalUsageService.swift: Kimi wire.jsonl usage scanner。
LocalUsageHistoryRepository.swift: Provider 本地趋势 cache、fingerprint 与 stale fallback。
ConfigStore.swift: CraftMeter 配置快照加载、恢复与保存。
ConfigStorePaths.swift: CraftMeter 主目录与 OhMyUsage/AIPlanMonitor 迁移来源定义。
LegacyConfigImporter.swift: 旧配置和 supplemental files 单向导入；OhMyUsage 目录只读保留。
BrowserCredentialService.swift: 统一发现浏览器 Cookie、命名 Cookie 与 Bearer 候选，并以短 TTL 缓存受控实时读取结果。
RelayBrowserImportCoordinator.swift: 对 Relay 新增/编辑执行无副作用浏览器凭据预检，输出脱敏来源、User ID 缺失和验证下一步，不写配置或 Keychain。
KeychainService.swift: `craftmeter` 凭据 vault，并从历史 service 单向迁移。
FirstLaunchExperienceStore.swift: 以版本号记录首次启动体验是否已展示，供菜单栏运行时首次成功启动后打开设置窗口。
PostUpdateReleaseNotesStore.swift: 持久化应用内更新后的待展示版本说明。
AppUpdateService.swift: HeyHuazi/CraftMeter latest.json 检测、下载和安装。
LaunchAtLoginService.swift: CraftMeter LaunchAgent 注册与历史 plist 清理。

边界

- Scanner 不做价格、时间窗口或 UI 文案；上游明确费用只作为事实标注来源。
- Repository 只协调价格 enrichment，不实现费率计算；公式保持在 Application 纯函数 estimator。
- 任何 prompt/assistant/tool result 正文不得进入 record 或 cache。
- 新 scanner 必须同时扩展 source fingerprint 与 fixture tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
