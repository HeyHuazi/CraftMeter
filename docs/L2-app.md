L2 模块地图

# Sources/CraftMeterApp/

## 职责
macOS menubar 应用主可执行目标。@main 入口，MenuBarExtra popover (380×500 B-layout)，5min 后台 timer + 实时状态栏数字 + Settings scene。

## 成员清单
- App.swift: @main App struct，MenuBarExtra 注册 + Settings scene；label 由 @AppStorage("menubarDisplay") 驱动（默认今日 $）
- ViewModel.swift: @MainActor ObservableObject，唯一调度 refresh，持有 Timer
- StatsView.swift: popover 根视图 (380×500)，编排 OverviewSection → ActivitySection → TopBurnSection + footer + SessionDetail overlay
- SettingsView.swift: 状态栏显示模式 Picker（todayCost/totalCost/todayTokens/iconOnly），@AppStorage 持久化

## 公开 API
- 无（可执行目标内部）

## 依赖
- SwiftUI, AppKit (NSApplication)
- CraftMeterCore

## 子模块
- Components/ — 见 [docs/L2-components.md](L2-components.md)

## 法则
- ViewModel 是唯一的状态源
- 后台 IO 必须 `Task.detached`，结果回 MainActor
- drill-down 路由用 @State<Detail?>，不引入 NavigationStack（在 MenuBarExtra popover 内行为不稳定）
- 状态栏 label 必须 .monospacedDigit()，防数字变化重排
