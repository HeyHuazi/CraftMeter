# Sources/OhMyUsage/
> L2 | 父级: ../CLAUDE.md

成员目录

App/: macOS 生命周期、AppViewModel 会话状态、状态栏/窗口控制器与功能 coordinator。
Models/: executable 兼容模型、Provider descriptor、默认目录与设置草稿等产品策略。
Providers/: 官方与中转 Provider 的具体网络、网页观察和凭据适配实现。
Services/: 文件系统、Keychain、迁移、扫描器、analytics repository、更新与本地运行时服务。
UI/: SwiftUI 菜单栏、设置工作台、纯 presenter 与视觉支持组件。
Utils/: 本地化等 executable 共享工具。
Resources/: 图标、Relay adapter manifest 与 SwiftPM bundle 资源。

边界

- executable 承载 macOS 平台接入与具体实现组合，稳定值对象优先归属分层 target。
- SwiftUI 不读取日志；scanner 只产出统计事实；聚合算法委托 Application target。
- 新增顶级成员目录、资源类别或运行时数据流时同步本文件和根 CLAUDE.md。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
