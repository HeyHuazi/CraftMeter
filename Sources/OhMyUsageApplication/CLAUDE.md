# Sources/OhMyUsageApplication/
> L2 | 父级: ../CLAUDE.md

成员清单（analytics 核心）

UsageAnalyticsTypes.swift: 定义 totals、费用来源计数与 reported/estimated/partial 状态、统一组合 filter、基础维度 option/stats、typed facet stats、record、trend、snapshot 与菜单栏摘要；reasoning 和 cost 属于一等字段。
ModelPricing.swift: 定义 Provider 感知的 USD/百万 Token 费率、来源证据与纯函数 estimator；上游报告费用优先，缺失实际使用 Token 类型费率时保持 partial。
UsageAnalyticsAggregator.swift: 纯函数去重后建立单一 filtered-records 管线，统一 totals/trend/breakdown；基础维度使用 faceted-search options，Craft facet 保持可重叠归因。
UsageAnalyticsSnapshotCacheStore.swift: schema-version 4 快照缓存、时间新鲜度和 fingerprint 校验；费用来源计数变更使旧快照安全失效。
RuntimeDiagnostics.swift: cache 容量、扫描行长和刷新间隔限制。
ProviderRefreshScheduler.swift: Provider 刷新调度策略。
BackoffPolicy.swift: 网络失败退避策略。
VisibleClockController.swift: 可见界面的轻量时钟驱动。

法则

- 禁止 Foundation 文件 IO 进入 aggregator。
- record 是核心事实；MCP/Skill/Craft 多值信息进入 facet event。
- totalTokens 必须包含 reasoning。
- unknown pricing 通过 `unpricedRequestCount` 保持可见；已知下界使用 partial，不得把未知费用归零。
- Scanner 不访问价格目录；费用估算只发生在 Repository enrichment 与 Application 纯函数 estimator。
- 修改 Codable 模型必须同步 cache schema version 与 tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
