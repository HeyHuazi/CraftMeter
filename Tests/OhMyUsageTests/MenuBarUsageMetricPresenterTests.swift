import Foundation
import XCTest
@testable import OhMyUsageApplication
@testable import OhMyUsage

final class MenuBarUsageMetricPresenterTests: XCTestCase {
    func testUsageTokensAllSelectionPresentsSingleLifetimeTotal() {
        let summary = UsageAnalyticsMenuBarSummary(
            generatedAt: Date(),
            today: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(outputTokens: 12_400)
            ),
            week: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(outputTokens: 81_200)
            ),
            month: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(outputTokens: 3_200_000)
            ),
            all: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(outputTokens: 9_500_000)
            )
        )

        let items = MenuBarUsageMetricPresenter.presentations(
            style: .usageTokens,
            periodSelection: .all,
            summary: summary,
            language: .zhHans
        )

        XCTAssertEqual(items.map(\.period), [.all])
        XCTAssertEqual(items.map(\.name), ["全部用量"])
        XCTAssertEqual(items.map(\.valueText), ["9.5M"])
    }

    func testEstimatedCostStylePreservesUnknownLowerBound() {
        let summary = UsageAnalyticsMenuBarSummary(
            generatedAt: Date(),
            today: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(estimatedCostUSD: 1.25, unpricedRequestCount: 1)
            ),
            week: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(estimatedCostUSD: 8.6)
            ),
            month: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(estimatedCostUSD: 125)
            ),
            all: UsageAnalyticsPeriodSummary(
                totals: UsageMetricTotals(estimatedCostUSD: 134.85, unpricedRequestCount: 1)
            )
        )

        let items = MenuBarUsageMetricPresenter.presentations(
            style: .estimatedCost,
            periodSelection: .all,
            summary: summary,
            language: .en
        )

        XCTAssertEqual(items.map(\.name), ["All Cost"])
        XCTAssertEqual(items.map(\.valueText), ["≥$135"])
    }

    func testSinglePeriodSelectionProducesOnlyRequestedEntry() {
        let summary = UsageAnalyticsMenuBarSummary(
            generatedAt: Date(),
            today: UsageAnalyticsPeriodSummary(totals: UsageMetricTotals(outputTokens: 1)),
            week: UsageAnalyticsPeriodSummary(totals: UsageMetricTotals(outputTokens: 2)),
            month: UsageAnalyticsPeriodSummary(totals: UsageMetricTotals(outputTokens: 3))
        )

        for (selection, expectedPeriod, expectedValue) in [
            (StatusBarHistoryPeriod.today, MenuBarUsageMetricPresentation.Period.today, "1"),
            (.week, .week, "2"),
            (.month, .month, "3")
        ] {
            let items = MenuBarUsageMetricPresenter.presentations(
                style: .usageTokens,
                periodSelection: selection,
                summary: summary,
                language: .zhHans
            )
            XCTAssertEqual(items.map(\.period), [expectedPeriod])
            XCTAssertEqual(items.map(\.valueText), [expectedValue])
        }
    }

    func testRealtimeStylesDoNotProduceUsageAnalyticsEntries() {
        XCTAssertTrue(MenuBarUsageMetricPresenter.presentations(
            style: .iconPercent,
            periodSelection: .all,
            summary: .empty(),
            language: .zhHans
        ).isEmpty)
        XCTAssertTrue(MenuBarUsageMetricPresenter.presentations(
            style: .barNamePercent,
            periodSelection: .all,
            summary: .empty(),
            language: .zhHans
        ).isEmpty)
    }
}
