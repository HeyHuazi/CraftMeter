import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖菜单栏历史展示样式、周期选择、自然/全量摘要与应用语言。
 * [OUTPUT]: 对外提供单个所选周期的用量或费用展示项。
 * [POS]: App 的纯展示策略，连接 analytics 事实与 StatusBarDisplayEntry 渲染模型。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct MenuBarUsageMetricPresentation: Equatable {
    enum Period: CaseIterable, Equatable {
        case today
        case week
        case month
        case all
    }

    enum IconKind: Equatable {
        case tokens
        case cost
    }

    var period: Period
    var name: String
    var valueText: String
    var iconKind: IconKind
}

enum MenuBarUsageMetricPresenter {
    static func presentations(
        style: StatusBarDisplayStyle,
        periodSelection: StatusBarHistoryPeriod,
        summary: UsageAnalyticsMenuBarSummary,
        language: AppLanguage
    ) -> [MenuBarUsageMetricPresentation] {
        guard let iconKind = iconKind(for: style) else { return [] }
        return periods(for: periodSelection).map { period in
            let totals = totals(for: period, summary: summary)
            return MenuBarUsageMetricPresentation(
                period: period,
                name: name(for: period, style: style, language: language),
                valueText: valueText(iconKind: iconKind, totals: totals),
                iconKind: iconKind
            )
        }
    }

    private static func periods(
        for selection: StatusBarHistoryPeriod
    ) -> [MenuBarUsageMetricPresentation.Period] {
        switch selection {
        case .today: return [.today]
        case .week: return [.week]
        case .month: return [.month]
        case .all: return [.all]
        }
    }

    private static func totals(
        for period: MenuBarUsageMetricPresentation.Period,
        summary: UsageAnalyticsMenuBarSummary
    ) -> UsageMetricTotals {
        switch period {
        case .today: return summary.today.totals
        case .week: return summary.week.totals
        case .month: return summary.month.totals
        case .all: return summary.all.totals
        }
    }

    private static func name(
        for period: MenuBarUsageMetricPresentation.Period,
        style: StatusBarDisplayStyle,
        language: AppLanguage
    ) -> String {
        switch (period, style, language) {
        case (.today, .usageTokens, .zhHans): return "今日用量"
        case (.week, .usageTokens, .zhHans): return "本周用量"
        case (.month, .usageTokens, .zhHans): return "本月用量"
        case (.all, .usageTokens, .zhHans): return "全部用量"
        case (.today, .estimatedCost, .zhHans): return "今日花费"
        case (.week, .estimatedCost, .zhHans): return "本周花费"
        case (.month, .estimatedCost, .zhHans): return "本月花费"
        case (.all, .estimatedCost, .zhHans): return "全部花费"
        case (.today, .usageTokens, .en): return "Tokens Today"
        case (.week, .usageTokens, .en): return "Tokens Week"
        case (.month, .usageTokens, .en): return "Tokens Month"
        case (.all, .usageTokens, .en): return "All Tokens"
        case (.today, .estimatedCost, .en): return "Cost Today"
        case (.week, .estimatedCost, .en): return "Cost Week"
        case (.month, .estimatedCost, .en): return "Cost Month"
        case (.all, .estimatedCost, .en): return "All Cost"
        case (_, .iconPercent, _), (_, .barNamePercent, _): return ""
        }
    }

    private static func valueText(
        iconKind: MenuBarUsageMetricPresentation.IconKind,
        totals: UsageMetricTotals
    ) -> String {
        switch iconKind {
        case .tokens:
            return compactNumber(totals.totalTokens)
        case .cost:
            let amount = compactCost(totals.estimatedCostUSD)
            switch totals.pricingState {
            case .reported, .estimated, .mixed:
                return amount
            case .partial:
                return "≥\(amount)"
            case .unknown:
                return "--"
            }
        }
    }

    private static func iconKind(for style: StatusBarDisplayStyle) -> MenuBarUsageMetricPresentation.IconKind? {
        switch style {
        case .usageTokens: return .tokens
        case .estimatedCost: return .cost
        case .iconPercent, .barNamePercent: return nil
        }
    }

    private static func compactNumber(_ value: Int) -> String {
        let magnitude = abs(Double(value))
        if magnitude >= 1_000_000_000 {
            return compact(value: Double(value) / 1_000_000_000, suffix: "B")
        }
        if magnitude >= 1_000_000 {
            return compact(value: Double(value) / 1_000_000, suffix: "M")
        }
        if magnitude >= 1_000 {
            return compact(value: Double(value) / 1_000, suffix: "K")
        }
        return String(value)
    }

    private static func compactCost(_ value: Double) -> String {
        if abs(value) >= 1_000 {
            return "$\(compact(value: value / 1_000, suffix: "K"))"
        }
        if abs(value) >= 100 {
            return String(format: "$%.0f", value)
        }
        if abs(value) >= 10 {
            return String(format: "$%.1f", value)
        }
        return String(format: "$%.2f", value)
    }

    private static func compact(value: Double, suffix: String) -> String {
        let formatted = abs(value) >= 100
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted.replacingOccurrences(of: ".0", with: ""))\(suffix)"
    }
}
