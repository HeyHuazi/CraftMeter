import Foundation

/**
 * [INPUT]: Receives normalized request facts from local scanners and proxy log readers.
 * [OUTPUT]: Exposes analytics totals, filters, records, facets, breakdowns, snapshots, and natural/all-period menu bar summaries.
 * [POS]: OhMyUsageApplication analytics contract; the single semantic boundary between ingestion, aggregation, cache, and UI.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

public enum UsagePricingState: String, Codable, Equatable, Sendable {
    case reported
    case estimated
    case mixed
    case partial
    case unknown
}

public struct UsageMetricTotals: Codable, Equatable, Sendable {
    public var requestCount: Int
    public var successCount: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var reasoningTokens: Int
    public var estimatedCostUSD: Double
    public var reportedCostRequestCount: Int
    public var estimatedCostRequestCount: Int
    public var unpricedRequestCount: Int

    public init(
        requestCount: Int = 0,
        successCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        reasoningTokens: Int = 0,
        estimatedCostUSD: Double = 0,
        reportedCostRequestCount: Int? = nil,
        estimatedCostRequestCount: Int = 0,
        unpricedRequestCount: Int = 0
    ) {
        self.requestCount = requestCount
        self.successCount = successCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.reportedCostRequestCount = reportedCostRequestCount
            ?? (estimatedCostUSD > 0 && unpricedRequestCount == 0 ? requestCount : 0)
        self.estimatedCostRequestCount = estimatedCostRequestCount
        self.unpricedRequestCount = unpricedRequestCount
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens + reasoningTokens
    }

    public var pricingState: UsagePricingState {
        if unpricedRequestCount > 0 {
            return estimatedCostUSD > 0 ? .partial : .unknown
        }
        if reportedCostRequestCount > 0 && estimatedCostRequestCount > 0 {
            return .mixed
        }
        if reportedCostRequestCount > 0 {
            return .reported
        }
        if estimatedCostRequestCount > 0 {
            return .estimated
        }
        return .unknown
    }

    public var successRate: Double {
        guard requestCount > 0 else { return 0 }
        return Double(successCount) / Double(requestCount)
    }

    public var cacheRate: Double {
        let denominator = inputTokens + cacheReadTokens + cacheWriteTokens
        guard denominator > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(denominator)
    }

    public mutating func add(_ other: UsageMetricTotals) {
        requestCount += other.requestCount
        successCount += other.successCount
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheWriteTokens += other.cacheWriteTokens
        reasoningTokens += other.reasoningTokens
        estimatedCostUSD += other.estimatedCostUSD
        reportedCostRequestCount += other.reportedCostRequestCount
        estimatedCostRequestCount += other.estimatedCostRequestCount
        unpricedRequestCount += other.unpricedRequestCount
    }
}

public struct UsageAnalyticsPeriodSummary: Equatable, Sendable {
    public var totals: UsageMetricTotals

    public init(totals: UsageMetricTotals = UsageMetricTotals()) {
        self.totals = totals
    }
}

public struct UsageAnalyticsMenuBarSummary: Equatable, Sendable {
    public var generatedAt: Date
    public var today: UsageAnalyticsPeriodSummary
    public var week: UsageAnalyticsPeriodSummary
    public var month: UsageAnalyticsPeriodSummary
    public var all: UsageAnalyticsPeriodSummary

    public init(
        generatedAt: Date,
        today: UsageAnalyticsPeriodSummary = UsageAnalyticsPeriodSummary(),
        week: UsageAnalyticsPeriodSummary = UsageAnalyticsPeriodSummary(),
        month: UsageAnalyticsPeriodSummary = UsageAnalyticsPeriodSummary(),
        all: UsageAnalyticsPeriodSummary = UsageAnalyticsPeriodSummary()
    ) {
        self.generatedAt = generatedAt
        self.today = today
        self.week = week
        self.month = month
        self.all = all
    }

    public static func empty(at date: Date = .distantPast) -> UsageAnalyticsMenuBarSummary {
        UsageAnalyticsMenuBarSummary(generatedAt: date)
    }
}

public enum UsageAnalyticsFilterMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case byModel

    public var id: String { rawValue }
}

public enum UsageAnalyticsRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case last24Hours
    case last7Days
    case last30Days
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last24Hours: return "最近24小时"
        case .last7Days: return "7天"
        case .last30Days: return "30天"
        case .all: return "全部"
        }
    }
}

public struct UsageAnalyticsFilter: Codable, Equatable, Hashable, Sendable {
    public var mode: UsageAnalyticsFilterMode
    public var selectedModelID: String?
    public var selectedClientID: String?
    public var selectedProviderID: String?
    public var selectedProjectID: String?
    public var selectedFacetKind: UsageAnalyticsFacetKind?
    public var selectedFacetValue: String?
    public var range: UsageAnalyticsRange

    public init(
        mode: UsageAnalyticsFilterMode = .all,
        selectedModelID: String? = nil,
        selectedClientID: String? = nil,
        selectedProviderID: String? = nil,
        selectedProjectID: String? = nil,
        selectedFacetKind: UsageAnalyticsFacetKind? = nil,
        selectedFacetValue: String? = nil,
        range: UsageAnalyticsRange = .last30Days
    ) {
        self.mode = mode
        self.selectedModelID = selectedModelID
        self.selectedClientID = selectedClientID
        self.selectedProviderID = selectedProviderID
        self.selectedProjectID = selectedProjectID
        self.selectedFacetKind = selectedFacetKind
        self.selectedFacetValue = selectedFacetValue
        self.range = range
    }
}

public enum UsageAnalyticsRecordSource: Int, Codable, Equatable, Sendable {
    case ccswitchDailyRollup = 0
    case ohMyUsageLocal = 1
    case ccswitchSession = 2
    case ccswitchProxy = 3

    public var priority: Int { rawValue }
}

public enum UsageAnalyticsFacetKind: String, Codable, CaseIterable, Hashable, Sendable {
    case mcpServer
    case skill
    case craftSource
    case craftTool
    case craftCategory
    case craftStatus
    case permissionMode
    case thinkingLevel
}

public struct UsageAnalyticsFacetEvent: Codable, Equatable, Hashable, Sendable {
    public var kind: UsageAnalyticsFacetKind
    public var value: String
    public var displayName: String
    public var status: String?
    public var isError: Bool

    public init(
        kind: UsageAnalyticsFacetKind,
        value: String,
        displayName: String? = nil,
        status: String? = nil,
        isError: Bool = false
    ) {
        self.kind = kind
        self.value = value
        self.displayName = displayName ?? value
        self.status = status
        self.isError = isError
    }
}

public struct UsageAnalyticsRecord: Equatable, Sendable {
    public var source: UsageAnalyticsRecordSource
    public var eventAt: Date
    public var appType: String
    public var clientID: String
    public var clientName: String
    public var providerID: String
    public var providerName: String
    public var providerCategory: String
    public var modelID: String
    public var projectID: String
    public var projectName: String
    public var sessionID: String
    public var requestID: String
    public var totals: UsageMetricTotals
    public var facets: [UsageAnalyticsFacetEvent]

    public init(
        source: UsageAnalyticsRecordSource,
        eventAt: Date,
        appType: String,
        clientID: String? = nil,
        clientName: String? = nil,
        providerID: String,
        providerName: String,
        providerCategory: String? = nil,
        modelID: String,
        projectID: String = "",
        projectName: String = "",
        sessionID: String = "",
        requestID: String,
        totals: UsageMetricTotals,
        facets: [UsageAnalyticsFacetEvent] = []
    ) {
        self.source = source
        self.eventAt = eventAt
        self.appType = appType
        self.clientID = clientID ?? appType
        self.clientName = clientName ?? appType
        self.providerID = providerID
        self.providerName = providerName
        self.providerCategory = providerCategory ?? ""
        self.modelID = modelID
        self.projectID = projectID
        self.projectName = projectName
        self.sessionID = sessionID
        self.requestID = requestID
        self.totals = totals
        self.facets = facets
    }

    public var dedupKey: String {
        let minute = Int(eventAt.timeIntervalSince1970 / 60)
        return [
            normalized(clientID),
            normalized(modelID),
            "\(totals.inputTokens)",
            "\(totals.outputTokens)",
            "\(totals.cacheReadTokens)",
            "\(totals.cacheWriteTokens)",
            "\(totals.reasoningTokens)",
            "\(minute)"
        ].joined(separator: "|")
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct UsageAnalyticsBreakdownItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(name: String, totals: UsageMetricTotals, share: Double) {
        self.name = name
        self.totals = totals
        self.share = share
    }
}

public struct UsageTrendBucket: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var startAt: Date
    public var endAt: Date
    public var totals: UsageMetricTotals
    public var topProviders: [UsageAnalyticsBreakdownItem]
    public var topModels: [UsageAnalyticsBreakdownItem]

    public init(
        id: String,
        startAt: Date,
        endAt: Date,
        totals: UsageMetricTotals,
        topProviders: [UsageAnalyticsBreakdownItem],
        topModels: [UsageAnalyticsBreakdownItem]
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.totals = totals
        self.topProviders = topProviders
        self.topModels = topModels
    }
}

public struct UsageProviderCategoryStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(name: String, totals: UsageMetricTotals, share: Double) {
        self.name = name
        self.totals = totals
        self.share = share
    }
}

public struct UsageProviderStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var providerID: String
    public var providerName: String
    public var categoryName: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(
        id: String,
        providerID: String,
        providerName: String,
        categoryName: String,
        totals: UsageMetricTotals,
        share: Double
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.categoryName = categoryName
        self.totals = totals
        self.share = share
    }
}

public struct UsageModelStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String { modelID }
    public var modelID: String
    public var appType: String
    public var providerName: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(
        modelID: String,
        appType: String,
        providerName: String,
        totals: UsageMetricTotals,
        share: Double
    ) {
        self.modelID = modelID
        self.appType = appType
        self.providerName = providerName
        self.totals = totals
        self.share = share
    }
}

public struct UsageAnalyticsDimensionOption: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var totalTokens: Int
    public var requestCount: Int

    public init(id: String, title: String, totalTokens: Int, requestCount: Int) {
        self.id = id
        self.title = title
        self.totalTokens = totalTokens
        self.requestCount = requestCount
    }
}

public struct UsageAnalyticsDimensionStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(id: String, title: String, totals: UsageMetricTotals, share: Double) {
        self.id = id
        self.title = title
        self.totals = totals
        self.share = share
    }
}

public struct UsageAnalyticsFacetStatsGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UsageAnalyticsFacetKind { kind }
    public var kind: UsageAnalyticsFacetKind
    public var items: [UsageAnalyticsDimensionStats]

    public init(kind: UsageAnalyticsFacetKind, items: [UsageAnalyticsDimensionStats]) {
        self.kind = kind
        self.items = items
    }
}

public struct UsageAnalyticsModelOption: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var totalTokens: Int

    public init(id: String, title: String, totalTokens: Int) {
        self.id = id
        self.title = title
        self.totalTokens = totalTokens
    }
}

public struct UsageAnalyticsSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var filter: UsageAnalyticsFilter
    public var totals: UsageMetricTotals
    public var trendBuckets: [UsageTrendBucket]
    public var providerCategoryStats: [UsageProviderCategoryStats]
    public var providerStats: [UsageProviderStats]
    public var modelStats: [UsageModelStats]
    public var clientStats: [UsageAnalyticsDimensionStats]
    public var projectStats: [UsageAnalyticsDimensionStats]
    public var facetStats: [UsageAnalyticsFacetStatsGroup]
    public var availableModels: [UsageAnalyticsModelOption]
    public var availableClients: [UsageAnalyticsDimensionOption]
    public var availableProviders: [UsageAnalyticsDimensionOption]
    public var availableProjects: [UsageAnalyticsDimensionOption]
    public var availableFacetValues: [UsageAnalyticsDimensionOption]
    public var diagnostics: [String]

    public init(
        generatedAt: Date,
        filter: UsageAnalyticsFilter,
        totals: UsageMetricTotals,
        trendBuckets: [UsageTrendBucket],
        providerCategoryStats: [UsageProviderCategoryStats],
        providerStats: [UsageProviderStats],
        modelStats: [UsageModelStats],
        clientStats: [UsageAnalyticsDimensionStats] = [],
        projectStats: [UsageAnalyticsDimensionStats] = [],
        facetStats: [UsageAnalyticsFacetStatsGroup] = [],
        availableModels: [UsageAnalyticsModelOption],
        availableClients: [UsageAnalyticsDimensionOption] = [],
        availableProviders: [UsageAnalyticsDimensionOption] = [],
        availableProjects: [UsageAnalyticsDimensionOption] = [],
        availableFacetValues: [UsageAnalyticsDimensionOption] = [],
        diagnostics: [String]
    ) {
        self.generatedAt = generatedAt
        self.filter = filter
        self.totals = totals
        self.trendBuckets = trendBuckets
        self.providerCategoryStats = providerCategoryStats
        self.providerStats = providerStats
        self.modelStats = modelStats
        self.clientStats = clientStats
        self.projectStats = projectStats
        self.facetStats = facetStats
        self.availableModels = availableModels
        self.availableClients = availableClients
        self.availableProviders = availableProviders
        self.availableProjects = availableProjects
        self.availableFacetValues = availableFacetValues
        self.diagnostics = diagnostics
    }

    public static func empty(filter: UsageAnalyticsFilter, generatedAt: Date = Date()) -> UsageAnalyticsSnapshot {
        UsageAnalyticsSnapshot(
            generatedAt: generatedAt,
            filter: filter,
            totals: UsageMetricTotals(),
            trendBuckets: [],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [],
            availableModels: [],
            diagnostics: []
        )
    }
}
