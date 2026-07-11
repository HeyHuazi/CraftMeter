# Sources/OhMyUsageBootstrap/
> L2 | 父级: ../CLAUDE.md

成员清单

OhMyUsageBootstrapModule.swift: Bootstrap target 的模块标记，声明 composition root 所属边界。
OhMyUsageCompositionRoot.swift: 组合 `UsageFeatureAssembly`，为 executable 提供 Provider descriptor、刷新请求与摘要状态创建入口。

边界

- 只依赖 Domain/Application/Features/Presentation 的公开契约。
- 当前保持纯值组合；不得直接依赖 AppViewModel、窗口控制器或具体 Provider 实现。
- 运行时依赖下沉时由本层逐步接管装配，禁止在 executable 内继续扩散全局构造逻辑。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
