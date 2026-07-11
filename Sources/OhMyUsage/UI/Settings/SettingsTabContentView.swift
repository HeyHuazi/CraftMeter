/**
 * [INPUT]: 依赖 SwiftUI 与 SettingsTab 导航状态，接收各设置页面的 ViewBuilder 内容
 * [OUTPUT]: 对外提供按当前标签选择唯一设置页面的 SettingsTabContentView
 * [POS]: UI/Settings 的内容路由器，不持有业务状态，只负责标签到页面的穷尽映射
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import SwiftUI

struct SettingsTabContentView<
    Overview: View,
    General: View,
    MenuBar: View,
    UsageAnalytics: View,
    Permissions: View,
    LocalData: View,
    OfficialProviders: View,
    CustomProviders: View
>: View {
    var selectedTab: SettingsTab
    var overview: Overview
    var general: General
    var menuBar: MenuBar
    var usageAnalytics: UsageAnalytics
    var permissions: Permissions
    var localData: LocalData
    var officialProviders: OfficialProviders
    var customProviders: CustomProviders

    init(
        selectedTab: SettingsTab,
        @ViewBuilder overview: () -> Overview,
        @ViewBuilder general: () -> General,
        @ViewBuilder menuBar: () -> MenuBar,
        @ViewBuilder usageAnalytics: () -> UsageAnalytics,
        @ViewBuilder permissions: () -> Permissions,
        @ViewBuilder localData: () -> LocalData,
        @ViewBuilder officialProviders: () -> OfficialProviders,
        @ViewBuilder customProviders: () -> CustomProviders
    ) {
        self.selectedTab = selectedTab
        self.overview = overview()
        self.general = general()
        self.menuBar = menuBar()
        self.usageAnalytics = usageAnalytics()
        self.permissions = permissions()
        self.localData = localData()
        self.officialProviders = officialProviders()
        self.customProviders = customProviders()
    }

    var body: some View {
        switch selectedTab {
        case .overview:
            overview
        case .general:
            general
        case .menuBar:
            menuBar
        case .usageAnalytics:
            usageAnalytics
        case .permissions:
            permissions
        case .localData:
            localData
        case .officialProviders:
            officialProviders
        case .customProviders:
            customProviders
        }
    }
}
