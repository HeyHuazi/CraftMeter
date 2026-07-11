# Sources/OhMyUsageApplication/
> L2 | 父级: ../CLAUDE.md

成员清单（analytics 核心）

UsageAnalyticsTypes.swift: 定义 totals、组合 filter、record、facet、trend、breakdown 与 snapshot；reasoning 和 cost 属于一等字段。
UsageAnalyticsAggregator.swift: 纯函数去重、范围筛选、组合维度筛选、趋势与 provider/model breakdown。
UsageAnalyticsSnapshotCacheStore.swift: schema-version 快照缓存、时间新鲜度和 fingerprint 校验。
RuntimeDiagnostics.swift: cache 容量、扫描行长和刷新间隔限制。
ProviderRefreshScheduler.swift: Provider 刷新调度策略。
BackoffPolicy.swift: 网络失败退避策略。
VisibleClockController.swift: 可见界面的轻量时钟驱动。

法则

- 禁止 Foundation 文件 IO 进入 aggregator。
- record 是核心事实；MCP/Skill/Craft 多值信息进入 facet event。
- totalTokens 必须包含 reasoning。
- unknown pricing 通过 `unpricedRequestCount` 保持可见。
- 修改 Codable 模型必须同步 cache schema version 与 tests。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
