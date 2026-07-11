# Sources/
> L2 | 父级: ../CLAUDE.md

成员清单

OhMyUsage/: CraftMeter executable，组合 App、Services、Providers、UI 与 Resources；产品名已切换，target 名暂保留。
OhMyUsageDomain/: 稳定领域值对象与 Provider/额度/认证契约，不依赖其他业务 target。
OhMyUsageInfrastructure/: Keychain 等基础设施协议实现，依赖 Domain。
OhMyUsageProviders/: Provider fetching runtime 契约，依赖 Domain。
OhMyUsageApplication/: analytics、刷新调度、退避和诊断的应用层纯逻辑，依赖 Domain。
OhMyUsagePresentation/: 菜单与设置的纯展示模型，依赖 Domain。
OhMyUsageFeatures/: feature 描述与组装，依赖 Domain/Application/Presentation。
OhMyUsageBootstrap/: composition root，依赖 Domain/Application/Features/Presentation。

依赖方向

```text
Domain <- Infrastructure
Domain <- Providers
Domain <- Application
Domain <- Presentation
Domain + Application + Presentation <- Features
Domain + Application + Features + Presentation <- Bootstrap
all targets <- OhMyUsage executable
```

法则

- target 之间只能按 `Package.swift` 单向依赖。
- analytics contract 归 Application；文件 IO 归 executable Services。
- Provider 网络协议与历史 analytics 是两条独立数据流。
- 新 target 或目录增删必须同步本文件与根 CLAUDE.md。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
