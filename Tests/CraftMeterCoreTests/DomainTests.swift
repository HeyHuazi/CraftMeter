// ============================================================================
// L3 CONTRACT — DomainTests.swift
//
// INPUT:  构造的 session.jsonl 第一行字节流
// OUTPUT: 断言 SessionRecord 解析正确性 + aggregate 聚合正确性
// POS:    纯单元测试 · 不触碰真实文件系统
// ============================================================================

import XCTest
@testable import CraftMeterCore

final class DomainTests: XCTestCase {

    // MARK: - SessionRecord.from(firstLine:)

    func testParseMinimalValidJSON() {
        let json = """
        {"id":"260225-test","workspaceRootPath":"~/.craft-agent/workspaces/my-workspace","model":"claude-sonnet-4-5","llmConnection":"anthropic-api","createdAt":1772110490703,"tokenUsage":{"costUsd":21.0152,"inputTokens":1000,"outputTokens":2000,"cacheReadTokens":500,"cacheCreationTokens":300,"contextWindow":200000}}
        """.data(using: .utf8)!

        let rec = SessionRecord.from(firstLine: [UInt8](json))
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.workspace, "my-workspace")
        XCTAssertEqual(rec?.model, "claude-sonnet-4-5")
        XCTAssertEqual(rec?.llmConnection, "anthropic-api")
        XCTAssertEqual(rec?.costCents, 2102)              // 21.0152 → 21.02 → 2102 cents
        XCTAssertEqual(rec?.inputTokens, 1000)
        XCTAssertEqual(rec?.outputTokens, 2000)
        XCTAssertEqual(rec?.cacheReadTokens, 500)
        XCTAssertEqual(rec?.cacheCreationTokens, 300)
        XCTAssertEqual(rec?.billableTokens, 3300)          // 1000+2000+300; cacheRead excluded
        XCTAssertEqual(rec?.sessionStatus, "unknown")
        XCTAssertEqual(rec?.labels, [])
    }

    func testParseMissingOptionalsFallsBackGracefully() {
        let json = """
        {"id":"bare-session"}
        """.data(using: .utf8)!

        let rec = SessionRecord.from(firstLine: [UInt8](json))
        XCTAssertEqual(rec?.model, "unknown")
        XCTAssertEqual(rec?.llmConnection, "unknown")
        XCTAssertEqual(rec?.workspace, "")
        XCTAssertEqual(rec?.costCents, 0)
        XCTAssertEqual(rec?.billableTokens, 0)
    }

    func testBillableTokensExcludeCacheReadTokens() {
        let json = """
        {"id":"billable","tokenUsage":{"inputTokens":10,"outputTokens":20,"cacheReadTokens":9999,"cacheCreationTokens":30}}
        """

        let rec = SessionRecord.from(jsonLine: json)
        XCTAssertEqual(rec?.billableTokens, 60)
        XCTAssertEqual(rec?.cacheReadTokens, 9999)
    }

    func testParseMalformedJSONReturnsNil() {
        let malformed = "{ this is not valid json".data(using: .utf8)!
        XCTAssertNil(SessionRecord.from(firstLine: [UInt8](malformed)))
    }

    func testParseWindowsBackslashEscapeReturnsNil() {
        // session.jsonl with C:\Users\... path causes invalid \U escape
        let bad = #"{"id":"x","workspaceRootPath":"C:\Users\foo"}"#.data(using: .utf8)!
        XCTAssertNil(SessionRecord.from(firstLine: [UInt8](bad)))
    }

    func testParseBasenameWithTrailingSlash() {
        let json = """
        {"id":"x","workspaceRootPath":"~/.craft-agent/workspaces/digital-garden/"}
        """.data(using: .utf8)!
        let rec = SessionRecord.from(firstLine: [UInt8](json))
        XCTAssertEqual(rec?.workspace, "digital-garden")
    }

    // MARK: - aggregate()

    func testAggregateEmptyReturnsEmptyStats() {
        let stats = aggregate(records: [])
        XCTAssertEqual(stats, .empty)
        XCTAssertEqual(stats.sessionCount, 0)
        XCTAssertTrue(stats.top5ByBillable.isEmpty)
    }

    func testAggregateSingleSessionProducesMatchingTotals() {
        let rec = SessionRecord.from(jsonLine: makeJSON(costUSD: 1.50, tokens: 100))!
        let stats = aggregate(records: [rec])
        XCTAssertEqual(stats.totalCostCents, 150)
        XCTAssertEqual(stats.totalBillableTokens, 100)
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.top5ByBillable.count, 1)
    }

    func testAggregateTop5SortedByBillableTokensDescending() {
        let records = (1...10).map { i in
            SessionRecord.from(jsonLine: makeJSON(costUSD: Double(i), tokens: i * 100))!
        }
        let stats = aggregate(records: records)
        XCTAssertEqual(stats.top5ByBillable.count, 5)
        // billable tokens 1000, 900, 800, 700, 600 — top 5
        XCTAssertEqual(stats.top5ByBillable[0].billableTokens, 1000)
        XCTAssertEqual(stats.top5ByBillable[4].billableTokens, 600)
    }

    func testAggregate30DayBucketsAlwaysReturns30Points() {
        let records = [SessionRecord.from(jsonLine: makeJSON(costUSD: 1, tokens: 100))!]
        let stats = aggregate(records: records)
        XCTAssertEqual(stats.dailyBuckets30d.count, 30)
    }

    func testAggregateOlderSessionsExcludedFrom30DayBuckets() {
        let oldMs = Int64(Date().addingTimeInterval(-60 * 86400).timeIntervalSince1970 * 1000)
        let oldJSON = """
        {"id":"old","createdAt":\(oldMs),"tokenUsage":{"costUsd":1,"inputTokens":99999}}
        """
        let rec = SessionRecord.from(jsonLine: oldJSON)!
        let stats = aggregate(records: [rec])
        // 99999 tokens shouldn't appear in 30-day sum
        let sum30d = stats.dailyBuckets30d.reduce(0) { $0 + $1.tokens }
        XCTAssertEqual(sum30d, 0, "Old session should be excluded from 30-day buckets")
    }

    func testAggregateWorkspaceBreakdownSortedByTokensDesc() {
        let r1 = SessionRecord.from(jsonLine: makeJSON(workspace: "alpha", tokens: 100))!
        let r2 = SessionRecord.from(jsonLine: makeJSON(workspace: "beta", tokens: 9999))!
        let stats = aggregate(records: [r1, r2])
        XCTAssertEqual(stats.workspaceBreakdown.count, 2)
        XCTAssertEqual(stats.workspaceBreakdown[0].workspace, "beta")
        XCTAssertEqual(stats.workspaceBreakdown[1].workspace, "alpha")
    }

    // MARK: - Stats.with()

    func testStatsWithOverridesMalformedCount() {
        let base = aggregate(records: [])
        let overridden = base.with(malformedCount: 5, scannedBy: "test")
        XCTAssertEqual(overridden.malformedCount, 5)
        XCTAssertEqual(overridden.scannedBy, "test")
        XCTAssertEqual(overridden.sessionCount, base.sessionCount)
    }

    // MARK: - Helpers

    private func makeJSON(
        workspace: String = "ws",
        costUSD: Double = 0,
        tokens: Int = 0,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> String {
        """
        {"id":"\(UUID().uuidString)","workspaceRootPath":"~/.craft-agent/workspaces/\(workspace)","createdAt":\(createdAt),"tokenUsage":{"costUsd":\(costUSD),"inputTokens":\(tokens)}}
        """
    }
}
