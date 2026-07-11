import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: Imports public analytics contracts from OhMyUsageApplication.
 * [OUTPUT]: Provides executable-target aliases for analytics models used by services and SwiftUI.
 * [POS]: OhMyUsage Services compatibility facade; contains no analytics business logic.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

typealias UsagePricingState = OhMyUsageApplication.UsagePricingState
typealias UsageMetricTotals = OhMyUsageApplication.UsageMetricTotals
typealias UsageAnalyticsFilterMode = OhMyUsageApplication.UsageAnalyticsFilterMode
typealias UsageAnalyticsRange = OhMyUsageApplication.UsageAnalyticsRange
typealias UsageAnalyticsFilter = OhMyUsageApplication.UsageAnalyticsFilter
typealias UsageAnalyticsRecordSource = OhMyUsageApplication.UsageAnalyticsRecordSource
typealias UsageAnalyticsRecord = OhMyUsageApplication.UsageAnalyticsRecord
typealias UsageAnalyticsFacetKind = OhMyUsageApplication.UsageAnalyticsFacetKind
typealias UsageAnalyticsFacetEvent = OhMyUsageApplication.UsageAnalyticsFacetEvent
typealias UsageAnalyticsBreakdownItem = OhMyUsageApplication.UsageAnalyticsBreakdownItem
typealias UsageTrendBucket = OhMyUsageApplication.UsageTrendBucket
typealias UsageProviderCategoryStats = OhMyUsageApplication.UsageProviderCategoryStats
typealias UsageProviderStats = OhMyUsageApplication.UsageProviderStats
typealias UsageModelStats = OhMyUsageApplication.UsageModelStats
typealias UsageAnalyticsModelOption = OhMyUsageApplication.UsageAnalyticsModelOption
typealias UsageAnalyticsSnapshot = OhMyUsageApplication.UsageAnalyticsSnapshot
typealias UsageAnalyticsFileFingerprint = OhMyUsageApplication.UsageAnalyticsFileFingerprint
typealias UsageAnalyticsSourceFingerprint = OhMyUsageApplication.UsageAnalyticsSourceFingerprint
typealias UsageAnalyticsCacheEntry = OhMyUsageApplication.UsageAnalyticsCacheEntry
