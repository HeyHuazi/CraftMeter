import SwiftUI

/**
 * [INPUT]: 依赖 SwiftUI 的 Color 与 CGFloat，为设置工作台和菜单面板提供统一视觉常量。
 * [OUTPUT]: 对外提供颜色、圆角、间距、控件尺寸、菜单 600px 首选外框及 520px 共享内容视口 Token。
 * [POS]: UI/Settings 的视觉基元目录；菜单根视图和子页面必须复用同一 contentViewportHeight，并以 panelPreferredHeight 锁定紧凑外框。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum SettingsVisualTokens {
    enum Smoothing {
        static let continuous: CGFloat = 0.6
    }

    enum Radius {
        static let compact: CGFloat = 6
        static let control: CGFloat = 8
        static let panel: CGFloat = 10
        static let card: CGFloat = 12
        static let menuPanel: CGFloat = 20
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let thin: CGFloat = 0.5
    }

    enum Text {
        static let primary = Color.white.opacity(0.80)
        static let secondary = Color.white.opacity(0.55)
        static let tertiary = Color.white.opacity(0.40)
        static let muted = Color.white.opacity(0.30)
        static let disabled = Color.white.opacity(0.35)
    }

    enum Fill {
        static let clear = Color.clear
        static let control = Color.white.opacity(0.15)
        static let controlStrong = Color.white.opacity(0.18)
        static let rowHover = Color.white.opacity(0.05)
        static let selectedRow = Color.white.opacity(0.08)
        static let selectedControl = Color.white.opacity(0.80)
        static let selectedControlStrong = Color.white.opacity(0.82)
        static let selectedText = Color.black.opacity(0.88)
        static let knob = Color.white.opacity(0.88)
    }

    enum Status {
        static let sufficient = Color(hex: 0x69BD64)
        static let positive = Color(hex: 0x69BD65)
        static let success = Color(hex: 0x51DB42)
        static let warning = Color(hex: 0xD87E3E)
        static let warningStrong = Color(hex: 0xE88B2D)
        static let error = Color(hex: 0xD05757)
        static let destructive = Color(hex: 0xD05858)
        static let destructiveAccent = Color(hex: 0xEB654F)
        static let discoveryError = Color(hex: 0xD83E3E)
        static let accentBlue = Color(hex: 0x2F7CF6)
        static let blockedStripe = Color(hex: 0x4D4D4D)
    }

    enum SettingsLayout {
        static let rowHeight: CGFloat = 24
        static let compactRowHeight: CGFloat = 28
        static let compactControlHeight: CGFloat = 24
        static let configurationWidth: CGFloat = 566
    }

    enum Sidebar {
        static let rowWidth: CGFloat = 164
        static let rowHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 12
        static let addButtonHeight: CGFloat = 28
        static let addButtonBottomPadding: CGFloat = 14
        static let iconSize: CGFloat = 14
        static let headerIconSize: CGFloat = 24
    }

    enum Pane {
        static let shellPadding: CGFloat = 20
        static let dashboardSpacing: CGFloat = 16
        static let sidebarWidth: CGFloat = 280
        static let cardPadding: CGFloat = 18
        static let cardOuterPadding: CGFloat = 20
        static let cardContentSpacing: CGFloat = 18
        static let titleSpacing: CGFloat = 6
    }

    enum Menu {
        static let panelBackground = Color(hex: 0x232323)
        static let cardBackground = Color.black
        static let groupBackground = Color.black.opacity(0.30)
        static let panelWidth: CGFloat = 324
        static let panelPreferredHeight: CGFloat = 600
        static let panelMaxHeight: CGFloat = 800
        static let panelTopPadding: CGFloat = 12
        static let panelBottomPadding: CGFloat = 8
        static let panelHorizontalPadding: CGFloat = 8
        static let panelContentSpacing: CGFloat = 8
        static let cardSpacing: CGFloat = 4
        static let cardPadding: CGFloat = 12
        static let cardHeaderHeight: CGFloat = 24
        static let headerHeight: CGFloat = 16
        static let headerHorizontalPadding: CGFloat = 12
        static let headerActionIconSize: CGFloat = 16
        static let headerActionSpacing: CGFloat = 12
        static let headerActionIconOpacity: Double = 0.4
        static let cardsViewportCornerRadius: CGFloat = 12
        static let contentViewportHeight: CGFloat = 520
        static let dashboardSectionSpacing: CGFloat = 6
        static let dividerHeight: CGFloat = 1
        static let progressTrackHeight: CGFloat = 4
    }
}
