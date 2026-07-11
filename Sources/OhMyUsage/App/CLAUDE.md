# Sources/OhMyUsage/App/
> L2 | 父级: ../../../CLAUDE.md

成员清单（启动与运行时核心）

OhMyUsageApp.swift: SwiftUI `@main` 入口，仅声明无可见内容的 Settings scene，将生命周期交给 AppLifecycleDelegate。
RuntimeGuards.swift: 单实例锁、重复启动激活桥与应用生命周期编排；菜单栏启动完成后协调更新说明和版本化首次启动反馈。
StatusBarController.swift: 组装状态栏按钮、菜单面板与设置窗口入口，驱动 AppViewModel 启停和轻量刷新。
SettingsWindowController.swift: 管理唯一设置窗口及 accessory/regular activation policy 切换，保证菜单栏应用按需获得 Dock 与前台焦点。
AppUpdateCoordinator.swift: 协调版本检查、下载、安装状态和更新后说明调度，不承担网络传输实现。
AppViewModel.swift: executable 运行时状态与 coordinator 组合根；新启动持久化逻辑不得继续回填到此类。
AppViewModel+PermissionsAndReset.swift: 权限操作与本地数据重置入口，委托专用 coordinator 执行状态变更，并同步清除首次启动体验版本。

边界

- AppLifecycleDelegate 只编排启动顺序，不实现业务扫描、Provider 请求或持久化细节。
- 菜单栏必须先成功创建，再展示首次启动或更新后的可见窗口。
- 更新说明优先于首次启动设置窗口，避免两个窗口竞争焦点。
- 首次启动完成状态由 Services 中的版本化 store 管理，禁止使用散落的 UserDefaults key。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
