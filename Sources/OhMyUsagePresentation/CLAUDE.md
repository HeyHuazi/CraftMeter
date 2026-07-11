# Sources/OhMyUsagePresentation/
> L2 | 父级: ../CLAUDE.md

成员清单

MenuPermissionGuidePresentation.swift: 将权限状态转换为菜单可展示的引导值对象，不触发系统授权动作。
OhMyUsagePresentationModule.swift: Presentation target 的模块标记，提供纯展示边界。
UsagePresentationModels.swift: 将领域额度快照格式化为 Provider 摘要展示状态，保持 UI 框架无关。

边界

- 只做确定性的展示模型转换，不读取文件、发起网络或修改应用状态。
- 可以依赖 Domain，但不依赖 Application、Infrastructure、Providers 或 AppKit。
- 文案与格式化结果必须可直接单元测试。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
