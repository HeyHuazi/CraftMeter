# Sources/OhMyUsage/Services/
> L2 | 父级: ../../CLAUDE.md

成员清单（analytics 与迁移核心）

ExtendedLocalUsageScanner.swift: 扫描 Gemini CLI、Qwen Code、Craft Agents JSONL，只产出统计事实与 typed facets；Craft `costCents` 明确标记为上游报告费用。
UsageAnalyticsJSONLCursorReader.swift: 从已提交 byte offset 分块读取完整 JSONL 行；未完成尾行不推进 cursor，超长/无效 UTF-8 行只计诊断且不持久化原文。
UsageAnalyticsEventStore.swift: 基于系统 SQLite3 保存 enrichment 前 canonical facts 与 source cursor；支持普通文件替换及 CCSwitch proxy/rollup 专用原子事务，events、checkpoint、offset/high-watermark 同提交。
UsageAnalyticsIndexLifecycleManager.swift: 以独立 staging SQLite 构建完整 generation 后原子发布 active DB/manifest；manifest 绑定构建时完整 source fingerprint，partial/stale generation 不可读，损坏 active index 隔离后重建，并统一清理派生文件。
UsageAnalyticsCCSwitchIndexer.swift: CCSwitch shadow adapter；proxy logs 以安全高水位减 overlap 窗口幂等 upsert，daily rollups 仅事务替换有限日期窗口，并保留 proxy/session/rollup source priority。
UsageAnalyticsStatelessJSONLIndexer.swift: Claude/Gemini/Qwen 首批 shadow ingest adapter；基于文件 identity、size、mtime 判定 append/rebuild，当前不接管 Repository 生产读取。
UsageAnalyticsStatefulJSONLIndexer.swift: Codex/Kimi 累计 token snapshot 的版本化安全 checkpoint adapter，并承载 Craft Agents changed-file replacement；只持久化模型与 token components，不保存 seen raw line 或正文。
UsageAnalyticsRepository.swift: 完整 source fingerprint 匹配时优先读取 active SQLite facts；generation 缺失、过期、损坏或 decode 失败自动回退 legacy scanners，随后两条路径共用 pricing enrichment、dedup/source priority 和 Aggregator。
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
KeychainService.swift: `craftmeter` 凭据 vault，并从历史 service 单向迁移；secure-store 准备流程幂等，已准备状态不再重复触发 Keychain 授权，且读取/保存均先走非交互路径再按需升级到交互式请求。
SecurityCredentialReader.swift: 桌面 OAuth/浏览器凭据导入的低层 generic password reader/writer；生产环境可触达 macOS Keychain，XCTest 默认短路，禁止默认测试读取真实钥匙串或调用 `/usr/bin/security` 写入。
FirstLaunchExperienceStore.swift: 以版本号记录首次启动体验是否已展示，供菜单栏运行时首次成功启动后打开设置窗口。
PostUpdateReleaseNotesStore.swift: 持久化应用内更新后的待展示版本说明。
AppUpdateService.swift: HeyHuazi/CraftMeter latest.json 检测、下载和安装。
LaunchAtLoginService.swift: CraftMeter LaunchAgent 注册与历史 plist 清理。

边界

- Scanner 不做价格、时间窗口或 UI 文案；上游明确费用只作为事实标注来源。
- Event store 只保存 enrichment 前 facts 和安全 parser checkpoint；禁止固化 Models.dev 估值，禁止保存原始 JSONL 行或未完成尾行。
- Source adapters 与 generation builder 不进入 Repository；Repository 只依赖 lifecycle/read abstraction。只有 manifest source fingerprint 与当前完整 fingerprint 相等时 indexed facts 才可见，否则无条件 fallback legacy。
- Repository 只协调价格 enrichment，不实现费率计算；公式保持在 Application 纯函数 estimator。
- 任何 prompt/assistant/tool result 正文不得进入 record 或 cache。
- 新 scanner 必须同时扩展 source fingerprint 与 fixture tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
