import Foundation
import XCTest
@testable import OhMyUsageApplication
@testable import OhMyUsage

/**
 * [INPUT]: Exercises pricing quotes, usage totals, Models.dev payloads, and provider/model analytics facts.
 * [OUTPUT]: Proves deterministic estimation, conservative matching, validation, and last-known-good refresh behavior.
 * [POS]: OhMyUsageTests pricing contract suite; guards cost truthfulness independently from scanners and SwiftUI.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class ModelPricingTests: XCTestCase {
    func testEstimatorPricesAllTokenComponentsPerMillion() throws {
        let quote = ModelPricingQuote(
            providerID: "anthropic",
            modelID: "claude-sonnet-4-6",
            inputUSDPerMillion: 3,
            outputUSDPerMillion: 15,
            reasoningUSDPerMillion: 20,
            cacheReadUSDPerMillion: 0.3,
            cacheWriteUSDPerMillion: 3.75,
            fetchedAt: try fixedDate("2026-07-11T17:43:00Z")
        )
        let totals = UsageMetricTotals(
            requestCount: 1,
            successCount: 1,
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000,
            cacheWriteTokens: 1_000_000,
            reasoningTokens: 1_000_000,
            unpricedRequestCount: 1
        )

        let enriched = UsageCostEstimator.enrich(totals: totals, quote: quote)

        XCTAssertEqual(enriched.estimatedCostUSD, 42.05, accuracy: 0.000_001)
        XCTAssertEqual(enriched.estimatedCostRequestCount, 1)
        XCTAssertEqual(enriched.unpricedRequestCount, 0)
        XCTAssertEqual(enriched.pricingState, .estimated)
    }

    func testEstimatorUsesOutputRateForReasoningWhenCatalogHasNoSeparateRate() throws {
        let quote = ModelPricingQuote(
            providerID: "openai",
            modelID: "gpt-5",
            inputUSDPerMillion: 1.25,
            outputUSDPerMillion: 10,
            fetchedAt: try fixedDate("2026-07-11T17:43:00Z")
        )
        let enriched = UsageCostEstimator.enrich(
            totals: UsageMetricTotals(requestCount: 1, reasoningTokens: 500_000, unpricedRequestCount: 1),
            quote: quote
        )

        XCTAssertEqual(enriched.estimatedCostUSD, 5, accuracy: 0.000_001)
        XCTAssertEqual(enriched.pricingState, .estimated)
    }

    func testEstimatorKeepsPartialStateWhenUsedTokenTypeHasNoRate() throws {
        let quote = ModelPricingQuote(
            providerID: "openai",
            modelID: "gpt-5",
            inputUSDPerMillion: 1,
            outputUSDPerMillion: 10,
            fetchedAt: try fixedDate("2026-07-11T17:43:00Z")
        )
        let enriched = UsageCostEstimator.enrich(
            totals: UsageMetricTotals(
                requestCount: 1,
                inputTokens: 1_000_000,
                cacheWriteTokens: 1_000_000,
                unpricedRequestCount: 1
            ),
            quote: quote
        )

        XCTAssertEqual(enriched.estimatedCostUSD, 1, accuracy: 0.000_001)
        XCTAssertEqual(enriched.estimatedCostRequestCount, 1)
        XCTAssertEqual(enriched.unpricedRequestCount, 1)
        XCTAssertEqual(enriched.pricingState, .partial)
    }

    func testEstimatorDoesNotReplaceUpstreamReportedCost() throws {
        let quote = ModelPricingQuote(
            providerID: "openai",
            modelID: "gpt-5",
            inputUSDPerMillion: 999,
            outputUSDPerMillion: 999,
            fetchedAt: try fixedDate("2026-07-11T17:43:00Z")
        )
        let totals = UsageMetricTotals(
            requestCount: 1,
            inputTokens: 1_000_000,
            estimatedCostUSD: 2.5,
            reportedCostRequestCount: 1
        )

        let enriched = UsageCostEstimator.enrich(totals: totals, quote: quote)

        XCTAssertEqual(enriched.estimatedCostUSD, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(enriched.reportedCostRequestCount, 1)
        XCTAssertEqual(enriched.estimatedCostRequestCount, 0)
        XCTAssertEqual(enriched.pricingState, .reported)
    }

    func testCatalogMatchesOfficialProviderButRejectsRelayAndOpenRouter() throws {
        let catalog = ModelPricingCatalog(bundledData: fixtureCatalogData())
        let official = record(
            source: .ohMyUsageLocal,
            appType: "codex",
            providerID: "ohmyusage-codex-local",
            providerName: "Codex",
            modelID: "gpt-5"
        )
        let relay = record(
            source: .ccswitchProxy,
            appType: "codex",
            providerID: "relay-a",
            providerName: "OpenRouter Relay",
            modelID: "gpt-5"
        )

        XCTAssertEqual(catalog.quote(for: official)?.providerID, "openai")
        XCTAssertNil(catalog.quote(for: relay))
    }

    func testCatalogRefreshPersistsValidatedLastKnownGoodAndRejectsInvalidRates() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("model-pricing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = try fixedDate("2026-07-12T01:43:00Z")
        let validRemote = """
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5": {"id":"gpt-5","cost":{"input":2,"output":20,"cache_read":0.2}}
            }
          }
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://models.dev/api.json")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let catalog = ModelPricingCatalog(
            baseDirectoryURL: root,
            nowProvider: { now },
            dataLoader: { _ in (validRemote, response) },
            bundledData: fixtureCatalogData(fetchedAt: "2001-01-01T00:00:00Z")
        )

        catalog.refreshIfNeeded()
        await catalog.waitForRefreshForTesting()

        let quote = try XCTUnwrap(catalog.quote(for: record(
            source: .ohMyUsageLocal,
            appType: "codex",
            providerID: "codex-local",
            providerName: "Codex",
            modelID: "gpt-5"
        )))
        XCTAssertEqual(quote.inputUSDPerMillion, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("model_pricing_catalog.json").path))

        let invalidRemote = """
        {"openai":{"id":"openai","models":{"gpt-5":{"id":"gpt-5","cost":{"input":-1,"output":20}}}}}
        """.data(using: .utf8)!
        let fallback = ModelPricingCatalog(
            baseDirectoryURL: root,
            nowProvider: { now.addingTimeInterval(2 * 24 * 60 * 60) },
            dataLoader: { _ in (invalidRemote, response) },
            bundledData: fixtureCatalogData(fetchedAt: "2001-01-01T00:00:00Z")
        )
        fallback.refreshIfNeeded()
        await fallback.waitForRefreshForTesting()
        XCTAssertEqual(fallback.quote(for: record(
            source: .ohMyUsageLocal,
            appType: "codex",
            providerID: "codex-local",
            providerName: "Codex",
            modelID: "gpt-5"
        ))?.inputUSDPerMillion, 2)
    }

    private func fixtureCatalogData(fetchedAt: String = "2026-07-11T17:43:00Z") -> Data {
        """
        {
          "schemaVersion": 1,
          "fetchedAt": "\(fetchedAt)",
          "sourceURL": "https://models.dev/api.json",
          "providers": [
            {
              "id": "openai",
              "models": [
                {"id":"gpt-5","cost":{"input":1.25,"output":10,"cache_read":0.125}}
              ]
            }
          ]
        }
        """.data(using: .utf8)!
    }

    private func record(
        source: UsageAnalyticsRecordSource,
        appType: String,
        providerID: String,
        providerName: String,
        modelID: String
    ) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: source,
            eventAt: Date(timeIntervalSince1970: 1),
            appType: appType,
            providerID: providerID,
            providerName: providerName,
            modelID: modelID,
            requestID: UUID().uuidString,
            totals: UsageMetricTotals(requestCount: 1, inputTokens: 1, unpricedRequestCount: 1)
        )
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
