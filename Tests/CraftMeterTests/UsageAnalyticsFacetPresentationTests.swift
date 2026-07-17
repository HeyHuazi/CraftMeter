import XCTest
@testable import OhMyUsage

/**
 * [INPUT]: 依赖 UsageFacetPanelPresentation、UsageAnalyticsFacetKind 中文展示标题与 typed facet 统计值对象。
 * [OUTPUT]: 验证 Craft 活动面板的中文维度文案、稳定维度顺序、选择回退、Top 12 截断及非求和摘要语义。
 * [POS]: Settings analytics 纯展示模型回归测试；不启动 SwiftUI、不读取日志、不触达缓存或系统资源。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsFacetPresentationTests: XCTestCase {
    func testFacetKindTitlesUseChinesePresentationLabelsWithoutChangingIdentifiers() {
        XCTAssertEqual(
            UsageAnalyticsFacetKind.allCases.map(\.title),
            ["MCP 服务", "技能", "数据源", "工具", "分类", "状态", "权限模式", "思考等级"]
        )
        XCTAssertEqual(UsageAnalyticsFacetKind.craftCategory.rawValue, "craftCategory")
    }

    func testAvailableGroupsFollowFacetKindOrderInsteadOfInputOrder() {
        let presentation = UsageFacetPanelPresentation(
            groups: [
                group(.craftTool, items: [item(id: "tool", tokens: 20, share: 0.2)]),
                group(.mcpServer, items: [item(id: "mcp", tokens: 30, share: 0.3)]),
                group(.skill, items: [item(id: "skill", tokens: 10, share: 0.1)])
            ],
            requestedKind: .craftTool
        )

        XCTAssertEqual(presentation.availableGroups.map(\.kind), [.mcpServer, .skill, .craftTool])
        XCTAssertEqual(presentation.selectedKind, .craftTool)
    }

    func testMissingSelectionFallsBackToFirstAvailableGroup() {
        let presentation = UsageFacetPanelPresentation(
            groups: [
                group(.skill, items: [item(id: "skill", tokens: 10, share: 0.1)]),
                group(.craftTool, items: [item(id: "tool", tokens: 20, share: 0.2)])
            ],
            requestedKind: .mcpServer
        )

        XCTAssertEqual(presentation.selectedKind, .skill)
        XCTAssertEqual(presentation.selectedItems.map(\.id), ["skill"])
    }

    func testVisibleItemsAreExplicitlyLimitedToTwelve() {
        let items = (0..<15).map { index in
            item(id: "tool-\(index)", tokens: 1_000 - index, share: 1 - Double(index) / 100)
        }
        let presentation = UsageFacetPanelPresentation(
            groups: [group(.craftTool, items: items)],
            requestedKind: .craftTool
        )

        XCTAssertEqual(presentation.visibleItems.count, 12)
        XCTAssertEqual(presentation.hiddenItemCount, 3)
        XCTAssertEqual(presentation.visibleItems.last?.id, "tool-11")
    }

    func testSummaryUsesTopItemWithoutSummingOverlappingCoverage() {
        let first = item(id: "source-a", tokens: 800, share: 0.8)
        let second = item(id: "source-b", tokens: 700, share: 0.7)
        let presentation = UsageFacetPanelPresentation(
            groups: [group(.craftSource, items: [first, second])],
            requestedKind: .craftSource
        )

        XCTAssertEqual(presentation.topItem, first)
        XCTAssertEqual(presentation.topItem?.share, 0.8)
        XCTAssertGreaterThan(first.share + second.share, 1)
    }

    private func group(
        _ kind: UsageAnalyticsFacetKind,
        items: [UsageAnalyticsDimensionStats]
    ) -> UsageAnalyticsFacetStatsGroup {
        UsageAnalyticsFacetStatsGroup(kind: kind, items: items)
    }

    private func item(
        id: String,
        tokens: Int,
        share: Double
    ) -> UsageAnalyticsDimensionStats {
        UsageAnalyticsDimensionStats(
            id: id,
            title: id,
            totals: UsageMetricTotals(
                requestCount: 10,
                successCount: 8,
                inputTokens: tokens
            ),
            share: share
        )
    }
}
