# Sources/OhMyUsage/App/
> L2 | 父级: ../../../CLAUDE.md

成员清单（启动与运行时核心）

OhMyUsageApp.swift: SwiftUI `@main` 入口，仅声明无可见内容的 Settings scene，将生命周期交给 AppLifecycleDelegate。
RuntimeGuards.swift: 单实例锁、重复启动激活桥与应用生命周期编排；菜单栏启动完成后协调更新说明和版本化首次启动反馈。
StatusBarController.swift: 组装状态栏按钮、菜单面板与设置窗口入口；按互斥样式和历史周期选择构建条目，历史统计使用 `menu_usage_analytics_icon.svg` 并遵循统一前景色策略。
MenuBarUsageAnalyticsCoordinator.swift: 基于 source fingerprint 与自然日边界去重菜单栏历史摘要后台扫描，仅使用额度或预估花费样式触发 IO。
MenuBarUsageMetricPresenter.swift: 将自然周期或全量 totals 投影为使用额度/预估花费的单个展示项，并保留 unknown pricing 下界语义。
SettingsWindowController.swift: 管理唯一设置窗口及 accessory/regular activation policy 切换，保证菜单栏应用按需获得 Dock 与前台焦点。
AppUpdateCoordinator.swift: 协调版本检查、下载、安装状态和更新后说明调度，不承担网络传输实现。
AppViewModel.swift: executable 运行时状态与 coordinator 组合根；向 ProviderFactory 与 Relay 浏览器导入协调器注入同一凭据发现服务，新启动持久化逻辑不得继续回填到此类。
AppViewModel+ProviderConfiguration.swift: Provider 配置、凭据和 Relay 诊断动作门面；浏览器导入先以 `browserOnly` 无副作用预检/验证，再由用户确认后的正常 Provider 刷新持久化凭据。
AppViewModel+StatusBarDisplay.swift: 菜单栏 Provider、四种互斥样式、历史周期与摘要刷新桥接，统一经配置 coordinator 持久化并通知重绘。
AppStatusBarPreferencesCoordinator.swift: 菜单栏偏好的原子 mutation 边界，规范化 Provider 与展示样式选择并声明持久化/重绘副作用。
StatusBarDisplayRenderer.swift: 最终 AppKit attributed title 绘制器；实时百分比样式与历史绝对值样式共享稳定尺寸渲染原语。
AppViewModel+PermissionsAndReset.swift: 权限操作与本地数据重置入口，委托专用 coordinator 执行状态变更，并同步清除首次启动体验版本。

边界

- AppLifecycleDelegate 只编排启动顺序，不实现业务扫描、Provider 请求或持久化细节。
- 菜单栏必须先成功创建，再展示首次启动或更新后的可见窗口。
- 更新说明优先于首次启动设置窗口，避免两个窗口竞争焦点。
- 首次启动完成状态由 Services 中的版本化 store 管理，禁止使用散落的 UserDefaults key。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
