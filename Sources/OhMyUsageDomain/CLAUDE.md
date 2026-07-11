# Sources/OhMyUsageDomain/
> L2 | 父级: ../CLAUDE.md

成员清单

AuthModels.swift: 定义认证种类、Keychain 引用与告警阈值等稳定领域值对象，不包含凭据读取实现。
OfficialProviderConfigModels.swift: 定义官方 Provider 的来源模式、网页导入、额度显示与 Provider 专属展示配置。
OhMyUsageDomainModule.swift: Domain target 的模块标记，提供无运行时副作用的可导入边界。
OpenRelayProviderConfigModels.swift: 定义开放中转 Provider 的账户余额与令牌通道配置契约。
ProviderConfiguration.swift: 聚合 Provider 身份、类型与设置，并保持旧扁平 Codable 载荷的兼容编码边界。
ProviderFamily.swift: 定义官方、中转等 Provider 家族分类。
ProviderType.swift: 定义 CraftMeter 支持的稳定 Provider 类型标识集合。
RelayModels.swift: 定义 Relay adapter、认证策略、请求提取与手工覆盖的声明式领域模型。
UsageProviderIdentity.swift: 提供经过规范化校验的 Provider 身份值对象。
UsageQuotaSnapshot.swift: 表达可测试的已用量、上限、剩余量与使用比例，不依赖 UI 或网络。
UsageSnapshot.swift: 表达实时额度窗口、来源可信度、健康状态与新鲜度，供运行时和展示层共享。

边界

- 只保存稳定业务语义和值对象，不读取文件、Keychain、网络或 AppKit 状态。
- 不拥有 Provider 工厂、默认目录、迁移策略或 UI 展示政策。
- Domain 不依赖其他业务 target；上层只能通过公开值对象协作。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
