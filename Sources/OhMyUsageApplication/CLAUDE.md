# Sources/OhMyUsageApplication/
> L2 | 父级: ../CLAUDE.md

成员清单（analytics 核心）

UsageAnalyticsTypes.swift: 定义 totals、费用来源计数与 reported/estimated/partial 状态、统一组合 filter、基础维度 option/stats、typed facet stats、record、trend、snapshot 与菜单栏摘要；历史范围统一为今天/本周/本月/全部自然周期，reasoning 和 cost 属于一等字段。
UsageAnalyticsEventStoreTypes.swift: 定义 indexed source、文件身份、source cursor、安全 checkpoint 和 ingest/read diagnostics 纯数据契约；不包含文件枚举、JSONL 解析或 SQLite。
ModelPricing.swift: 定义 provider 优先、exact model 消歧回退的 USD/百万 Token 费率、来源证据与纯函数 estimator；上游报告费用优先，缺失实际使用 Token 类型费率时保持 partial。
UsageAnalyticsAggregator.swift: 纯函数去重后建立单一 filtered-records 管线，统一 totals/trend/breakdown；今天按小时、本周和本月按自然日、全量按跨度自适应趋势桶，基础维度使用 faceted-search options，Craft facet 保持可重叠归因。
UsageAnalyticsSnapshotCacheStore.swift: schema-version 6 的 snapshot payload + 轻量 validation manifest 双文件缓存；支持延迟恢复和后台原子写入，fingerprint 验证只更新 KB 级 sidecar、不重写大型快照，自然周期与价格语义变化仍使旧缓存安全失效。
RuntimeDiagnostics.swift: cache 容量、扫描行长和刷新间隔限制。
ProviderRefreshScheduler.swift: Provider 刷新调度策略。
BackoffPolicy.swift: 网络失败退避策略。
VisibleClockController.swift: 可见界面的轻量时钟驱动。

法则

- 禁止 Foundation 文件 IO 进入 aggregator。
- Event store 契约只描述事实与 cursor；SQLite、FileHandle 和 source 路径策略留在 executable Services。
- record 是核心事实；MCP/Skill/Craft 多值信息进入 facet event。
- totalTokens 必须包含 reasoning。
- unknown pricing 通过 `unpricedRequestCount` 保持可见；已知下界使用 partial，不得把未知费用归零。
- Scanner 不访问价格目录；费用估算只发生在 Repository enrichment 与 Application 纯函数 estimator。
- 修改 Codable 模型必须同步 cache schema version 与 tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
