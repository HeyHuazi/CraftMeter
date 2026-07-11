import Foundation

/**
 * [INPUT]: Receives normalized usage totals plus provider-aware model pricing quotes.
 * [OUTPUT]: Exposes pricing quotes, provenance counters, and a pure estimator for analytics enrichment.
 * [POS]: OhMyUsageApplication pricing domain; separates usage facts from external catalog schemas and presentation.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

public enum UsageCostSource: String, Codable, Equatable, Sendable {
    case upstreamReported
    case modelsDev
}

public struct ModelPricingQuote: Codable, Equatable, Sendable {
    public var providerID: String
    public var modelID: String
    public var inputUSDPerMillion: Decimal?
    public var outputUSDPerMillion: Decimal?
    public var reasoningUSDPerMillion: Decimal?
    public var cacheReadUSDPerMillion: Decimal?
    public var cacheWriteUSDPerMillion: Decimal?
    public var source: UsageCostSource
    public var sourceURL: String
    public var fetchedAt: Date

    public init(
        providerID: String,
        modelID: String,
        inputUSDPerMillion: Decimal? = nil,
        outputUSDPerMillion: Decimal? = nil,
        reasoningUSDPerMillion: Decimal? = nil,
        cacheReadUSDPerMillion: Decimal? = nil,
        cacheWriteUSDPerMillion: Decimal? = nil,
        source: UsageCostSource = .modelsDev,
        sourceURL: String = "https://models.dev/api.json",
        fetchedAt: Date
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.inputUSDPerMillion = inputUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
        self.reasoningUSDPerMillion = reasoningUSDPerMillion
        self.cacheReadUSDPerMillion = cacheReadUSDPerMillion
        self.cacheWriteUSDPerMillion = cacheWriteUSDPerMillion
        self.source = source
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }
}

public enum UsageCostEstimator {
    public static func enrich(
        totals: UsageMetricTotals,
        quote: ModelPricingQuote?
    ) -> UsageMetricTotals {
        guard totals.requestCount > 0 else { return totals }
        guard totals.reportedCostRequestCount == 0,
              totals.estimatedCostRequestCount == 0,
              totals.unpricedRequestCount > 0,
              let quote else {
            return totals
        }

        var amount = Decimal.zero
        var fullyPriced = true
        amount += componentCost(tokens: totals.inputTokens, rate: quote.inputUSDPerMillion, fullyPriced: &fullyPriced)
        amount += componentCost(tokens: totals.outputTokens, rate: quote.outputUSDPerMillion, fullyPriced: &fullyPriced)
        amount += componentCost(tokens: totals.cacheReadTokens, rate: quote.cacheReadUSDPerMillion, fullyPriced: &fullyPriced)
        amount += componentCost(tokens: totals.cacheWriteTokens, rate: quote.cacheWriteUSDPerMillion, fullyPriced: &fullyPriced)
        amount += componentCost(
            tokens: totals.reasoningTokens,
            rate: quote.reasoningUSDPerMillion ?? quote.outputUSDPerMillion,
            fullyPriced: &fullyPriced
        )

        var enriched = totals
        enriched.estimatedCostUSD += NSDecimalNumber(decimal: amount).doubleValue
        if amount > 0 || fullyPriced {
            enriched.estimatedCostRequestCount += totals.requestCount
        }
        if fullyPriced {
            enriched.unpricedRequestCount = 0
        }
        return enriched
    }

    private static func componentCost(
        tokens: Int,
        rate: Decimal?,
        fullyPriced: inout Bool
    ) -> Decimal {
        guard tokens > 0 else { return .zero }
        guard let rate else {
            fullyPriced = false
            return .zero
        }
        return Decimal(tokens) * rate / Decimal(1_000_000)
    }
}
