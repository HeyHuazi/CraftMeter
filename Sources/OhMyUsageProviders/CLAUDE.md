# Sources/OhMyUsageProviders/
> L2 | 父级: ../CLAUDE.md

成员清单

OhMyUsageProvidersModule.swift: Providers target 的模块标记，声明 Provider runtime 契约边界。
UsageProviderFetching.swift: 定义按 Provider 身份异步获取 `UsageQuotaSnapshot` 的最小运行时协议。

边界

- 只定义 Provider 获取契约，不拥有具体 HTTP、浏览器、Keychain 或 UI 实现。
- 输出 Domain 快照，不泄漏供应商响应结构。
- 禁止依赖 Infrastructure、Application、Presentation 或平台 UI 框架。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
