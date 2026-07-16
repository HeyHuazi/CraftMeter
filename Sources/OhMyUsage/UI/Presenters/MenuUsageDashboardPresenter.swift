import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 UsageAnalyticsSnapshot、AppLanguage 与菜单选择的指标/维度状态。
 * [OUTPUT]: 对外提供菜单历史 Dashboard 的摘要、趋势柱 Token 提示、排行、费用来源和空状态展示模型。
 * [POS]: UI/Presenters 的历史统计展示边界；隔离 analytics 事实与 324px 菜单布局，不参与扫描和聚合。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum MenuUsageMetricMode: String, CaseIterable, Hashable {
    case tokens
    case cost
}

enum MenuUsageBreakdown: String, CaseIterable, Hashable {
    case model
    case project
    case client
}

struct MenuUsageSummaryItem: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
}

struct MenuUsageTrendItem: Identifiable, Equatable {
    var id: String
    var value: Double
    var label: String
    var accessibilityLabel: String
    var tokensText: String
}

struct MenuUsageRankingItem: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var share: Double?
    var subtitle: String?
    var modelBrand: UsageAnalyticsModelBrandPresentation?
}

struct MenuUsageDashboardPresentation: Equatable {
    var summaryItems: [MenuUsageSummaryItem]
    var trendItems: [MenuUsageTrendItem]
    var rankingItems: [MenuUsageRankingItem]
    var pricingMessage: String
    var emptyMessage: String?
}

enum UsageAnalyticsDisplayFormatter {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return String(value)
    }

    static func cost(_ totals: UsageMetricTotals) -> String {
        guard totals.pricingState != .unknown else { return "—" }
        let digits = totals.estimatedCostUSD > 0 && totals.estimatedCostUSD < 0.01 ? 4 : 2
        let amount = String(format: "$%.*f", digits, totals.estimatedCostUSD)
        return totals.pricingState == .partial ? "≥\(amount)" : amount
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, value) * 100)
    }
}

enum MenuUsageDashboardPresenter {
    static func build(
        snapshot: UsageAnalyticsSnapshot,
        language: AppLanguage,
        metric: MenuUsageMetricMode,
        breakdown: MenuUsageBreakdown
    ) -> MenuUsageDashboardPresentation {
        let totals = snapshot.totals
        let summary = [
            MenuUsageSummaryItem(id: "tokens", title: text("总 Token", "Tokens", language), value: UsageAnalyticsDisplayFormatter.tokens(totals.totalTokens)),
            MenuUsageSummaryItem(id: "cost", title: text("费用", "Cost", language), value: UsageAnalyticsDisplayFormatter.cost(totals)),
            MenuUsageSummaryItem(id: "requests", title: text("请求", "Requests", language), value: UsageAnalyticsDisplayFormatter.tokens(totals.requestCount)),
            MenuUsageSummaryItem(id: "cache", title: text("缓存命中", "Cache hit", language), value: UsageAnalyticsDisplayFormatter.percent(totals.cacheRate))
        ]

        return MenuUsageDashboardPresentation(
            summaryItems: summary,
            trendItems: snapshot.trendBuckets.map { bucket in
                let label = trendLabel(bucket.startAt, endAt: bucket.endAt)
                let metricValueText = metricText(bucket.totals, metric: metric)
                return MenuUsageTrendItem(
                    id: bucket.id,
                    value: metricValue(bucket.totals, metric: metric),
                    label: label,
                    accessibilityLabel: "\(label) \(metricValueText)",
                    tokensText: UsageAnalyticsDisplayFormatter.tokens(bucket.totals.totalTokens)
                )
            },
            rankingItems: rankingItems(snapshot: snapshot, language: language, metric: metric, breakdown: breakdown),
            pricingMessage: pricingMessage(totals.pricingState, language: language),
            emptyMessage: totals.requestCount == 0 && totals.totalTokens == 0
                ? text("当前周期暂无使用数据", "No usage in this period", language)
                : nil
        )
    }

    static func rangeTitle(_ range: UsageAnalyticsRange, language: AppLanguage) -> String {
        switch range {
        case .today: return text("今天", "Today", language)
        case .week: return text("本周", "Week", language)
        case .month: return text("本月", "Month", language)
        case .all: return text("全部", "All", language)
        }
    }

    static func metricTitle(_ metric: MenuUsageMetricMode, language: AppLanguage) -> String {
        switch metric {
        case .tokens: return text("Token", "Tokens", language)
        case .cost: return text("费用", "Cost", language)
        }
    }

    static func breakdownTitle(_ breakdown: MenuUsageBreakdown, language: AppLanguage) -> String {
        switch breakdown {
        case .model: return text("模型", "Model", language)
        case .project: return text("项目", "Project", language)
        case .client: return text("客户端", "Client", language)
        }
    }

    private static func rankingItems(
        snapshot: UsageAnalyticsSnapshot,
        language: AppLanguage,
        metric: MenuUsageMetricMode,
        breakdown: MenuUsageBreakdown
    ) -> [MenuUsageRankingItem] {
        let totalValue = metricValue(snapshot.totals, metric: metric)
        let rows: [(String, String, UsageMetricTotals, UsageAnalyticsModelBrandPresentation?)]
        switch breakdown {
        case .model:
            rows = snapshot.modelStats.map {
                (
                    $0.id,
                    $0.modelID,
                    $0.totals,
                    UsageAnalyticsModelBrandResolver.resolve(
                        modelID: $0.modelID,
                        providerName: $0.providerName,
                        appType: $0.appType
                    )
                )
            }
        case .project:
            rows = snapshot.projectStats.map { ($0.id, $0.title, $0.totals, nil) }
        case .client:
            rows = snapshot.clientStats.map { ($0.id, $0.title, $0.totals, nil) }
        }

        return rows
            .sorted { lhs, rhs in
                let lhsValue = metricValue(lhs.2, metric: metric)
                let rhsValue = metricValue(rhs.2, metric: metric)
                return lhsValue == rhsValue ? lhs.1 < rhs.1 : lhsValue > rhsValue
            }
            .prefix(6)
            .map { id, title, totals, brand in
                let value = metricValue(totals, metric: metric)
                let comparable = metric == .tokens || (totals.pricingState != .unknown && snapshot.totals.pricingState != .unknown)
                return MenuUsageRankingItem(
                    id: id,
                    title: title,
                    value: metricText(totals, metric: metric),
                    share: comparable && totalValue > 0 ? value / totalValue : nil,
                    subtitle: breakdown == .model ? estimatedCostSubtitle(totals, language: language) : nil,
                    modelBrand: brand
                )
            }
    }

    private static func metricValue(_ totals: UsageMetricTotals, metric: MenuUsageMetricMode) -> Double {
        switch metric {
        case .tokens: return Double(totals.totalTokens)
        case .cost: return totals.pricingState == .unknown ? 0 : totals.estimatedCostUSD
        }
    }

    private static func metricText(_ totals: UsageMetricTotals, metric: MenuUsageMetricMode) -> String {
        switch metric {
        case .tokens: return UsageAnalyticsDisplayFormatter.tokens(totals.totalTokens)
        case .cost: return UsageAnalyticsDisplayFormatter.cost(totals)
        }
    }

    private static func pricingMessage(_ state: UsagePricingState, language: AppLanguage) -> String {
        switch state {
        case .reported:
            return text("费用来自上游日志", "Cost reported upstream", language)
        case .estimated:
            return text("按 Models.dev 公开模型价格估算", "Estimated from public Models.dev pricing", language)
        case .mixed:
            return text("包含上游报告值与公开模型价估算", "Reported and public model estimates", language)
        case .partial:
            return text("已知费用为下界，部分模型未定价", "Known cost is a lower bound", language)
        case .unknown:
            return text("暂无可靠模型价格", "No reliable model pricing", language)
        }
    }

    private static func estimatedCostSubtitle(_ totals: UsageMetricTotals, language: AppLanguage) -> String {
        guard totals.pricingState != .unknown else {
            return text("无法估算", "Unable to estimate", language)
        }
        return text(
            "预估金额 \(UsageAnalyticsDisplayFormatter.cost(totals))",
            "Estimated \(UsageAnalyticsDisplayFormatter.cost(totals))",
            language
        )
    }

    private static func trendLabel(_ startAt: Date, endAt: Date) -> String {
        let formatter = DateFormatter()
        let duration = endAt.timeIntervalSince(startAt)
        if duration <= 90 * 60 {
            formatter.dateFormat = "H"
        } else if duration <= 36 * 60 * 60 {
            formatter.dateFormat = "d"
        } else if duration <= 8 * 24 * 60 * 60 {
            formatter.dateFormat = "M/d"
        } else {
            formatter.dateFormat = "M月"
        }
        return formatter.string(from: startAt)
    }

    private static func text(_ zhHans: String, _ english: String, _ language: AppLanguage) -> String {
        language == .zhHans ? zhHans : english
    }
}
