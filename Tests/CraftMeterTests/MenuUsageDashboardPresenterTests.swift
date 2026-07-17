import XCTest
@testable import OhMyUsage
@testable import OhMyUsageApplication

/**
 * [INPUT]: 构造 UsageAnalyticsSnapshot、模型 totals、趋势桶与菜单指标/维度选择。
 * [OUTPUT]: 验证菜单 Dashboard 的自然周期文案、趋势柱 Token 提示、逐模型费用排序、小额精度和未知费用语义。
 * [POS]: CraftMeterTests 的菜单历史统计纯展示回归套件，不依赖 SwiftUI 渲染或日志扫描。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class MenuUsageDashboardPresenterTests: XCTestCase {
    func testNaturalRangeTitlesAreLocalized() {
        XCTAssertEqual(MenuUsageDashboardPresenter.rangeTitle(.today, language: .zhHans), "今天")
        XCTAssertEqual(MenuUsageDashboardPresenter.rangeTitle(.week, language: .zhHans), "本周")
        XCTAssertEqual(MenuUsageDashboardPresenter.rangeTitle(.month, language: .en), "Month")
        XCTAssertEqual(MenuUsageDashboardPresenter.rangeTitle(.all, language: .en), "All")
    }

    func testSmallNonZeroCostKeepsFourDecimalPlacesAndPartialLowerBound() {
        XCTAssertEqual(
            UsageAnalyticsDisplayFormatter.cost(
                UsageMetricTotals(
                    requestCount: 1,
                    estimatedCostUSD: 0.0042,
                    estimatedCostRequestCount: 1
                )
            ),
            "$0.0042"
        )
        XCTAssertEqual(
            UsageAnalyticsDisplayFormatter.cost(
                UsageMetricTotals(
                    requestCount: 2,
                    estimatedCostUSD: 0.0042,
                    estimatedCostRequestCount: 1,
                    unpricedRequestCount: 1
                )
            ),
            "≥$0.0042"
        )
    }

    func testTrendItemsCarryTokenTextForInlineBarHint() throws {
        let start = Date(timeIntervalSince1970: 1_786_262_400) // 2026-08-12 00:00:00 UTC
        let bucket = UsageTrendBucket(
            id: "day-1786262400",
            startAt: start,
            endAt: start.addingTimeInterval(24 * 60 * 60),
            totals: UsageMetricTotals(
                requestCount: 7,
                inputTokens: 1_000,
                outputTokens: 500,
                estimatedCostUSD: 0.0042,
                estimatedCostRequestCount: 7
            ),
            topProviders: [],
            topModels: [
                UsageAnalyticsBreakdownItem(
                    name: "gpt-5",
                    totals: UsageMetricTotals(requestCount: 4, inputTokens: 800),
                    share: 0.7
                )
            ]
        )
        let snapshot = UsageAnalyticsSnapshot(
            generatedAt: start,
            filter: UsageAnalyticsFilter(range: .month),
            totals: bucket.totals,
            trendBuckets: [bucket],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [],
            availableModels: [],
            diagnostics: []
        )

        let presentation = MenuUsageDashboardPresenter.build(
            snapshot: snapshot,
            language: .zhHans,
            metric: .tokens,
            breakdown: .model
        )

        let item = try XCTUnwrap(presentation.trendItems.first)
        XCTAssertEqual(item.tokensText, "1.5K")
        XCTAssertTrue(item.accessibilityLabel.contains("1.5K"))
    }

    func testTrendItemsAlwaysUseTokensForInlineHintEvenWhenChartMetricIsCost() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let bucket = UsageTrendBucket(
            id: "month-1782864000",
            startAt: start,
            endAt: end,
            totals: UsageMetricTotals(requestCount: 12, inputTokens: 2_000, unpricedRequestCount: 12),
            topProviders: [
                UsageAnalyticsBreakdownItem(
                    name: "Claude Code",
                    totals: UsageMetricTotals(requestCount: 12, inputTokens: 2_000),
                    share: 1
                )
            ],
            topModels: []
        )
        let snapshot = UsageAnalyticsSnapshot(
            generatedAt: end,
            filter: UsageAnalyticsFilter(range: .all),
            totals: bucket.totals,
            trendBuckets: [bucket],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [],
            availableModels: [],
            diagnostics: []
        )

        let presentation = MenuUsageDashboardPresenter.build(
            snapshot: snapshot,
            language: .zhHans,
            metric: .cost,
            breakdown: .model
        )

        let item = try XCTUnwrap(presentation.trendItems.first)
        XCTAssertEqual(item.value, 0)
        XCTAssertEqual(item.tokensText, "2.0K")
        XCTAssertEqual(item.accessibilityLabel, "7月 —")
    }

    func testCostRankingSortsModelsAndKeepsUnknownShareAbsent() {
        let snapshot = UsageAnalyticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1),
            filter: UsageAnalyticsFilter(range: .month),
            totals: UsageMetricTotals(
                requestCount: 3,
                inputTokens: 300,
                estimatedCostUSD: 3,
                estimatedCostRequestCount: 2,
                unpricedRequestCount: 1
            ),
            trendBuckets: [],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [
                UsageModelStats(
                    modelID: "gpt-5",
                    appType: "codex",
                    providerName: "OpenAI",
                    totals: UsageMetricTotals(
                        requestCount: 1,
                        inputTokens: 100,
                        estimatedCostUSD: 2,
                        reportedCostRequestCount: 0,
                        estimatedCostRequestCount: 1
                    ),
                    share: 1.0 / 3.0
                ),
                UsageModelStats(
                    modelID: "claude-sonnet-4-6",
                    appType: "claude",
                    providerName: "Anthropic",
                    totals: UsageMetricTotals(
                        requestCount: 1,
                        inputTokens: 100,
                        estimatedCostUSD: 1,
                        reportedCostRequestCount: 0,
                        estimatedCostRequestCount: 1
                    ),
                    share: 1.0 / 3.0
                ),
                UsageModelStats(
                    modelID: "relay-model",
                    appType: "codex",
                    providerName: "OpenRouter Relay",
                    totals: UsageMetricTotals(requestCount: 1, inputTokens: 100, unpricedRequestCount: 1),
                    share: 1.0 / 3.0
                )
            ],
            availableModels: [],
            diagnostics: []
        )

        let presentation = MenuUsageDashboardPresenter.build(
            snapshot: snapshot,
            language: .zhHans,
            metric: .cost,
            breakdown: .model
        )

        XCTAssertEqual(presentation.rankingItems.map(\.title), ["gpt-5", "claude-sonnet-4-6", "relay-model"])
        XCTAssertEqual(presentation.rankingItems[0].value, "$2.00")
        XCTAssertEqual(presentation.rankingItems[0].subtitle, "预估金额 $2.00")
        XCTAssertEqual(try XCTUnwrap(presentation.rankingItems[0].share), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(presentation.rankingItems[2].value, "—")
        XCTAssertNil(presentation.rankingItems[2].share)
        XCTAssertEqual(presentation.rankingItems[2].subtitle, "无法估算")
        XCTAssertTrue(presentation.pricingMessage.contains("下界"))

        let englishPresentation = MenuUsageDashboardPresenter.build(
            snapshot: snapshot,
            language: .en,
            metric: .cost,
            breakdown: .model
        )
        XCTAssertEqual(englishPresentation.rankingItems[0].subtitle, "Estimated $2.00")

        let tokenPresentation = MenuUsageDashboardPresenter.build(
            snapshot: snapshot,
            language: .zhHans,
            metric: .tokens,
            breakdown: .model
        )
        XCTAssertEqual(tokenPresentation.rankingItems[0].value, "100")
        XCTAssertEqual(tokenPresentation.rankingItems[0].subtitle, "预估金额 $1.00")
    }
}
