import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

/**
 * [INPUT]: Creates synthetic local JSONL fixtures containing only structural usage fields.
 * [OUTPUT]: Verifies Gemini/Qwen/Craft parsing, privacy boundaries, facets, costs, and composable filters.
 * [POS]: OhMyUsageTests regression guard for CraftMeter-specific analytics ingestion.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class ExtendedLocalUsageScannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CraftMeterExtendedScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testGeminiAndQwenSeparateCachedAndReasoningTokens() throws {
        for source in [ExtendedLocalUsageScanner.Source.gemini, .qwen] {
            let root = temporaryDirectory.appendingPathComponent(source.rawValue, isDirectory: true)
            let chats = root.appendingPathComponent("workspace/chats", isDirectory: true)
            try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
            let fixture = """
            {"type":"assistant","timestamp":"2026-07-10T16:00:00.000Z","uuid":"request-1","model":"model-x","cwd":"/tmp/MyProject","usageMetadata":{"promptTokenCount":100,"cachedContentTokenCount":30,"candidatesTokenCount":50,"thoughtsTokenCount":20},"content":"PRIVATE_RESPONSE_MUST_NOT_SURVIVE"}
            """
            try fixture.write(to: chats.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

            let scanner = ExtendedLocalUsageScanner(rootOverrides: [source: root.path])
            let records = scanner.records(source: source, since: Date(timeIntervalSince1970: 0))

            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records[0].totals.inputTokens, 70)
            XCTAssertEqual(records[0].totals.cacheReadTokens, 30)
            XCTAssertEqual(records[0].totals.outputTokens, 30)
            XCTAssertEqual(records[0].totals.reasoningTokens, 20)
            XCTAssertEqual(records[0].totals.totalTokens, 150)
            XCTAssertEqual(records[0].projectName, "MyProject")
            XCTAssertFalse(String(describing: records[0]).contains("PRIVATE_RESPONSE_MUST_NOT_SURVIVE"))
        }
    }

    func testCraftSessionProducesStrongFacetsWithoutToolResultContent() throws {
        let root = temporaryDirectory.appendingPathComponent("craft", isDirectory: true)
        let workspace = root.appendingPathComponent("code-space/sessions/s-1", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let fixture = """
        {"id":"session-1","model":"claude-opus","createdAt":1783700000000,"tool":"craft-agent","workingDirectory":"/tmp/CraftMeter","permissionMode":"execute","thinkingLevel":"high","enabledSourceSlugs":["github","notion"],"costCents":42,"tokenUsage":{"inputTokens":100,"outputTokens":50,"cacheReadTokens":20,"cacheCreationTokens":10,"reasoningTokens":5}}
        {"type":"tool","toolName":"mcp__github__search","toolDisplayName":"Search GitHub","toolStatus":"completed","isError":false,"toolDisplayMeta":{"category":"research"},"toolInput":{"query":"PRIVATE_QUERY"},"toolResult":"PRIVATE_RESULT"}
        {"type":"tool","toolName":"Skill","toolDisplayName":"Run Skill","toolStatus":"failed","isError":true,"toolDisplayMeta":{"category":"automation"},"toolInput":{"skill":"release-notes"},"toolResult":"PRIVATE_SKILL_RESULT"}
        """
        try fixture.write(to: workspace.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let scanner = ExtendedLocalUsageScanner(rootOverrides: [.craftAgent: root.path])
        let records = scanner.records(source: .craftAgent, since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.clientName, "Craft Agents")
        XCTAssertEqual(record.projectName, "CraftMeter")
        XCTAssertEqual(record.totals.reasoningTokens, 5)
        XCTAssertEqual(record.totals.totalTokens, 185)
        XCTAssertEqual(record.totals.estimatedCostUSD, 0.42, accuracy: 0.0001)
        XCTAssertEqual(Set(record.facets.filter { $0.kind == .craftSource }.map(\.value)), ["github", "notion"])
        XCTAssertEqual(record.facets.first { $0.kind == .mcpServer }?.value, "github")
        XCTAssertEqual(record.facets.first { $0.kind == .skill }?.value, "release-notes")
        XCTAssertEqual(record.facets.first { $0.kind == .permissionMode }?.value, "execute")
        XCTAssertEqual(record.facets.first { $0.kind == .thinkingLevel }?.value, "high")
        XCTAssertEqual(record.facets.first { $0.kind == .craftTool && $0.value == "Skill" }?.isError, true)
        let description = String(describing: record)
        XCTAssertFalse(description.contains("PRIVATE_QUERY"))
        XCTAssertFalse(description.contains("PRIVATE_RESULT"))
        XCTAssertFalse(description.contains("PRIVATE_SKILL_RESULT"))
    }

    func testAggregatorIncludesReasoningCostAndComposableDimensions() {
        let now = Date(timeIntervalSince1970: 1_783_700_100)
        let matching = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: now,
            appType: "craft-agent",
            clientID: "craft-agent",
            clientName: "Craft Agents",
            providerID: "craft-provider",
            providerName: "Craft Agents",
            providerCategory: "Craft",
            modelID: "claude-opus",
            projectID: "craftmeter",
            projectName: "CraftMeter",
            sessionID: "s1",
            requestID: "r1",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: 10,
                outputTokens: 5,
                reasoningTokens: 3,
                estimatedCostUSD: 0.25
            )
        )
        let excluded = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: now,
            appType: "gemini-cli",
            clientID: "gemini-cli",
            clientName: "Gemini CLI",
            providerID: "google",
            providerName: "Google",
            providerCategory: "Google",
            modelID: "gemini",
            projectID: "other",
            requestID: "r2",
            totals: UsageMetricTotals(inputTokens: 999)
        )
        let filter = UsageAnalyticsFilter(
            selectedClientID: "craft-agent",
            selectedProviderID: "craft-provider",
            selectedProjectID: "craftmeter",
            range: .last24Hours
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = UsageAnalyticsAggregator.snapshot(
            records: [matching, excluded],
            filter: filter,
            calendar: calendar,
            now: now,
            diagnostics: []
        )

        XCTAssertEqual(snapshot.totals.totalTokens, 18)
        XCTAssertEqual(snapshot.totals.reasoningTokens, 3)
        XCTAssertEqual(snapshot.totals.estimatedCostUSD, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.providerCategoryStats.map(\.name), ["Craft"])
    }
}
