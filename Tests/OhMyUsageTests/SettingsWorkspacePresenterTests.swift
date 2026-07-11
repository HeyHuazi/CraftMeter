/**
 * [INPUT]: 依赖 XCTest 与 OhMyUsage 的 SettingsWorkspacePresenter
 * [OUTPUT]: 验证设置页头文案和侧边栏结构的回归测试
 * [POS]: Tests 的设置呈现契约测试，防止导航项与产品信息意外漂移
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import XCTest
@testable import OhMyUsage

final class SettingsWorkspacePresenterTests: XCTestCase {
    func testHeaderPresentationUsesOverviewCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .overview,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Settings Overview")
        XCTAssertEqual(
            presentation.subtitle,
            "A scannable workspace for monitoring, permissions, and service configuration."
        )
        XCTAssertEqual(presentation.refreshButtonTitle, "Refresh All")
    }

    func testHeaderPresentationUsesCustomEndpointCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .customProviders,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Custom Endpoints")
        XCTAssertEqual(
            presentation.subtitle,
            "Configure Relay, New API, and third-party balance endpoints."
        )
    }

    func testSidebarPresentationBuildsExpectedSectionsAndLabels() {
        let presentation = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.appTitle, "CraftMeter")
        XCTAssertEqual(presentation.appSubtitle, "Monitoring workspace")
        XCTAssertEqual(presentation.sections.map(\.id), ["main"])
        XCTAssertEqual(
            presentation.sections[0].items.map(\.title),
            ["Usage", "General", "Menubar", "Official", "Relay"]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.tab),
            [.usageAnalytics, .general, .menuBar, .officialProviders, .customProviders]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.icon),
            [
                "settings_sidebar_usage_icon",
                "settings_sidebar_general_icon",
                "settings_sidebar_menubar_icon",
                "settings_sidebar_official_icon",
                "settings_sidebar_relay_icon"
            ]
        )
        XCTAssertEqual(
            presentation.sections[0].items.first?.iconName(isSelected: true),
            "settings_sidebar_usage_icon_selected"
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
