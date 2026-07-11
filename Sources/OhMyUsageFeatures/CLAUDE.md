# Sources/OhMyUsageFeatures/
> L2 | 父级: ../CLAUDE.md

成员清单

OhMyUsageFeaturesModule.swift: Features target 的模块标记，声明跨 Application/Presentation 的 feature 组装边界。
UsageFeatureAssembly.swift: 根据 feature descriptor 构造刷新请求和纯摘要展示状态，不启动完整运行时。
UsageFeatureDescriptor.swift: 描述 Provider feature 的身份、标题与默认强制刷新政策。

边界

- 组合 Domain、Application 与 Presentation 的公开契约，不持有 AppViewModel 或平台控制器。
- Assembly 只创建值对象，不读取环境、不执行 IO、不声称完成应用启动。
- 新 feature 必须通过窄 descriptor/assembly 扩展，避免向 executable 泄漏跨层细节。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
