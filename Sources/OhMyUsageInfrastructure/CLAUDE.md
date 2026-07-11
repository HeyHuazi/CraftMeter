# Sources/OhMyUsageInfrastructure/
> L2 | 父级: ../CLAUDE.md

成员清单

OhMyUsageInfrastructureModule.swift: Infrastructure target 的模块标记，声明基础设施边界可被上层组合。
UsageCredentialStore.swift: 定义按 `UsageProviderIdentity` 异步读取、保存与移除凭据的窄存储协议。

边界

- 依赖 Domain 的稳定身份，不拥有 Provider 业务策略或展示逻辑。
- 基础设施协议保持窄小；具体 Keychain、文件系统和迁移实现由组合层注入。
- 禁止依赖 SwiftUI/AppKit。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
