import Foundation

/**
 * [INPUT]: Consumes normalized UsageAnalyticsRecord values and a composable analytics filter.
 * [OUTPUT]: Produces deterministic totals, trends, provider/model breakdowns, selectable dimensions, and natural/all-period menu bar summaries.
 * [POS]: OhMyUsageApplication pure aggregation engine; contains no file IO or UI policy.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

public enum UsageAnalyticsAggregator {
    private enum TrendBucketGranularity: String {
        case hour
        case day
        case sevenDay
        case month
        case quarter
    }

    private struct TrendBucketPlan {
        var starts: [Date]
        var granularity: TrendBucketGranularity
    }

    private struct ProviderKey: Hashable {
        var providerID: String
        var providerName: String
        var categoryName: String
    }

    private struct ModelOptionAccumulator {
        var title: String
        var firstEventAt: Date
        var firstRequestID: String
        var totalTokens: Int

        init(record: UsageAnalyticsRecord) {
            title = displayValue(record.modelID)
            firstEventAt = record.eventAt
            firstRequestID = record.requestID
            totalTokens = 0
            add(record)
        }

        mutating func add(_ record: UsageAnalyticsRecord) {
            totalTokens += record.totals.totalTokens
            if record.eventAt < firstEventAt
                || (record.eventAt == firstEventAt && record.requestID < firstRequestID) {
                title = displayValue(record.modelID)
                firstEventAt = record.eventAt
                firstRequestID = record.requestID
            }
        }
    }

    private struct ModelGroup {
        var modelID: String
        var firstEventAt: Date
        var firstRequestID: String
        var appTypes: Set<String>
        var providerNames: Set<String>
        var totals: UsageMetricTotals

        init(record: UsageAnalyticsRecord) {
            modelID = displayValue(record.modelID)
            firstEventAt = record.eventAt
            firstRequestID = record.requestID
            appTypes = []
            providerNames = []
            totals = UsageMetricTotals()
            add(record)
        }

        mutating func add(_ record: UsageAnalyticsRecord) {
            if record.eventAt < firstEventAt
                || (record.eventAt == firstEventAt && record.requestID < firstRequestID) {
                modelID = displayValue(record.modelID)
                firstEventAt = record.eventAt
                firstRequestID = record.requestID
            }
            appTypes.insert(displayValue(record.appType))
            providerNames.insert(displayValue(record.providerName))
            totals.add(record.totals)
        }
    }

    private struct NamedDimensionKey: Hashable {
        var id: String
        var title: String
    }

    private struct FacetKey: Hashable {
        var kind: UsageAnalyticsFacetKind
        var value: String
        var title: String
    }

    private struct SnapshotAccumulator {
        var totals = UsageMetricTotals()
        var categoryTotals: [String: UsageMetricTotals] = [:]
        var providerTotals: [ProviderKey: UsageMetricTotals] = [:]
        var modelGroups: [String: ModelGroup] = [:]
        var clientTotals: [NamedDimensionKey: UsageMetricTotals] = [:]
        var projectTotals: [NamedDimensionKey: UsageMetricTotals] = [:]
        var facetTotals: [FacetKey: UsageMetricTotals] = [:]
        var firstEventAt: Date?
        var lastEventAt: Date?

        mutating func addFilteredRecord(_ record: UsageAnalyticsRecord) {
            totals.add(record.totals)
            let categoryName = providerCategory(for: record)
            categoryTotals[categoryName, default: UsageMetricTotals()].add(record.totals)
            let providerKey = ProviderKey(
                providerID: record.providerID,
                providerName: record.providerName,
                categoryName: categoryName
            )
            providerTotals[providerKey, default: UsageMetricTotals()].add(record.totals)

            let modelGroupKey = modelKey(record.modelID)
            if var group = modelGroups[modelGroupKey] {
                group.add(record)
                modelGroups[modelGroupKey] = group
            } else {
                modelGroups[modelGroupKey] = ModelGroup(record: record)
            }

            let clientKey = NamedDimensionKey(
                id: dimensionKey(record.clientID),
                title: displayValue(record.clientName)
            )
            clientTotals[clientKey, default: UsageMetricTotals()].add(record.totals)
            let projectKey = NamedDimensionKey(
                id: dimensionKey(record.projectID),
                title: displayValue(record.projectName)
            )
            projectTotals[projectKey, default: UsageMetricTotals()].add(record.totals)
            for facet in Set(record.facets) {
                let facetKey = FacetKey(
                    kind: facet.kind,
                    value: dimensionKey(facet.value),
                    title: displayValue(facet.displayName)
                )
                facetTotals[facetKey, default: UsageMetricTotals()].add(record.totals)
            }

            if firstEventAt == nil || record.eventAt < firstEventAt! {
                firstEventAt = record.eventAt
            }
            if lastEventAt == nil || record.eventAt > lastEventAt! {
                lastEventAt = record.eventAt
            }
        }
    }

    private struct TrendBucketAccumulator {
        var totals = UsageMetricTotals()
        var providerTotals: [String: UsageMetricTotals] = [:]
        var modelTotals: [String: UsageMetricTotals] = [:]

        mutating func add(_ record: UsageAnalyticsRecord) {
            totals.add(record.totals)
            providerTotals[record.providerName, default: UsageMetricTotals()].add(record.totals)
            modelTotals[modelKey(record.modelID), default: UsageMetricTotals()].add(record.totals)
        }
    }

    public static func snapshot(
        records: [UsageAnalyticsRecord],
        filter: UsageAnalyticsFilter,
        calendar: Calendar,
        now: Date,
        diagnostics: [String]
    ) -> UsageAnalyticsSnapshot {
        let interval = rangeInterval(filter.range, calendar: calendar, now: now)
        let dedupedRecords = Array(deduplicated(records, in: interval).values)
        let filteredRecords = dedupedRecords.filter { matchesFilter($0, filter: filter) }
        var accumulator = SnapshotAccumulator()
        for record in filteredRecords {
            accumulator.addFilteredRecord(record)
        }

        let totals = accumulator.totals
        let buckets = trendBuckets(
            from: filteredRecords,
            range: filter.range,
            firstEventAt: accumulator.firstEventAt,
            lastEventAt: accumulator.lastEventAt,
            calendar: calendar,
            now: now
        )

        return UsageAnalyticsSnapshot(
            generatedAt: now,
            filter: filter,
            totals: totals,
            trendBuckets: buckets,
            providerCategoryStats: categoryStats(from: accumulator.categoryTotals, totalTokens: totals.totalTokens),
            providerStats: concreteProviderStats(from: accumulator.providerTotals, totalTokens: totals.totalTokens),
            modelStats: concreteModelStats(from: accumulator.modelGroups, totalTokens: totals.totalTokens),
            clientStats: dimensionStats(from: accumulator.clientTotals, totalTokens: totals.totalTokens),
            projectStats: dimensionStats(from: accumulator.projectTotals, totalTokens: totals.totalTokens),
            facetStats: facetStats(from: accumulator.facetTotals, totalTokens: totals.totalTokens),
            availableModels: modelOptions(from: optionRecords(dedupedRecords, filter: filter, excluding: .model)),
            availableClients: dimensionOptions(from: optionRecords(dedupedRecords, filter: filter, excluding: .client), id: \.clientID, title: \.clientName),
            availableProviders: dimensionOptions(from: optionRecords(dedupedRecords, filter: filter, excluding: .provider), id: \.providerID, title: \.providerName),
            availableProjects: dimensionOptions(from: optionRecords(dedupedRecords, filter: filter, excluding: .project), id: \.projectID, title: \.projectName),
            availableFacetValues: facetOptions(from: optionRecords(dedupedRecords, filter: filter, excluding: .facet), kind: filter.selectedFacetKind),
            diagnostics: diagnostics
        )
    }

    public static func menuBarSummary(
        records: [UsageAnalyticsRecord],
        calendar: Calendar,
        now: Date
    ) -> UsageAnalyticsMenuBarSummary {
        let monthInterval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), end: now)
        let todayInterval = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), end: now)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? todayInterval
        let recordsByKey = deduplicated(records, in: DateInterval(start: .distantPast, end: now))
        var todayTotals = UsageMetricTotals()
        var weekTotals = UsageMetricTotals()
        var monthTotals = UsageMetricTotals()
        var allTotals = UsageMetricTotals()

        for record in recordsByKey.values {
            allTotals.add(record.totals)
            if monthInterval.contains(record.eventAt) {
                monthTotals.add(record.totals)
            }
            if weekInterval.contains(record.eventAt) {
                weekTotals.add(record.totals)
            }
            if todayInterval.contains(record.eventAt) {
                todayTotals.add(record.totals)
            }
        }

        return UsageAnalyticsMenuBarSummary(
            generatedAt: now,
            today: UsageAnalyticsPeriodSummary(totals: todayTotals),
            week: UsageAnalyticsPeriodSummary(totals: weekTotals),
            month: UsageAnalyticsPeriodSummary(totals: monthTotals),
            all: UsageAnalyticsPeriodSummary(totals: allTotals)
        )
    }

    public static func providerCategory(for record: UsageAnalyticsRecord) -> String {
        let explicit = record.providerCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        if record.source == .ccswitchProxy {
            return "中转代理"
        }
        return displayValue(record.providerName)
    }

    public static func rangeInterval(
        _ range: UsageAnalyticsRange,
        calendar: Calendar,
        now: Date
    ) -> DateInterval {
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start = calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour
            let end = calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? now
            return DateInterval(start: start, end: end)
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .all:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    private static func deduplicated(
        _ records: [UsageAnalyticsRecord],
        in interval: DateInterval
    ) -> [String: UsageAnalyticsRecord] {
        var selected: [String: UsageAnalyticsRecord] = [:]
        for record in records {
            guard record.eventAt >= interval.start && record.eventAt < interval.end else {
                continue
            }
            guard let existing = selected[record.dedupKey] else {
                selected[record.dedupKey] = record
                continue
            }
            if record.source.priority > existing.source.priority {
                selected[record.dedupKey] = record
            }
        }
        return selected
    }

    private enum FilterDimension {
        case client
        case provider
        case project
        case model
        case facet
    }

    private static func matchesFilter(
        _ record: UsageAnalyticsRecord,
        filter: UsageAnalyticsFilter,
        excluding excluded: FilterDimension? = nil
    ) -> Bool {
        if excluded != .model,
           let selectedModelID = filter.selectedModelID,
           modelKey(record.modelID) != modelKey(selectedModelID) {
            return false
        }
        if excluded != .client,
           !matchesDimension(record.clientID, selected: filter.selectedClientID) {
            return false
        }
        if excluded != .provider,
           !matchesDimension(record.providerID, selected: filter.selectedProviderID) {
            return false
        }
        if excluded != .project,
           !matchesDimension(record.projectID, selected: filter.selectedProjectID) {
            return false
        }
        if excluded != .facet,
           let kind = filter.selectedFacetKind,
           let value = filter.selectedFacetValue,
           !record.facets.contains(where: {
               $0.kind == kind && dimensionKey($0.value) == dimensionKey(value)
           }) {
            return false
        }
        return true
    }

    private static func optionRecords(
        _ records: [UsageAnalyticsRecord],
        filter: UsageAnalyticsFilter,
        excluding dimension: FilterDimension
    ) -> [UsageAnalyticsRecord] {
        records.filter { matchesFilter($0, filter: filter, excluding: dimension) }
    }

    private static func matchesDimension(_ value: String, selected: String?) -> Bool {
        guard let selected else { return true }
        return modelKey(value) == modelKey(selected)
    }

    private static func dimensionOptions(
        from records: [UsageAnalyticsRecord],
        id: KeyPath<UsageAnalyticsRecord, String>,
        title: KeyPath<UsageAnalyticsRecord, String>
    ) -> [UsageAnalyticsDimensionOption] {
        var totals: [NamedDimensionKey: UsageMetricTotals] = [:]
        for record in records {
            let key = NamedDimensionKey(id: dimensionKey(record[keyPath: id]), title: displayValue(record[keyPath: title]))
            totals[key, default: UsageMetricTotals()].add(record.totals)
        }
        return totals.map { key, value in
            UsageAnalyticsDimensionOption(id: key.id, title: key.title, totalTokens: value.totalTokens, requestCount: value.requestCount)
        }.sorted(by: optionSort)
    }

    private static func facetOptions(
        from records: [UsageAnalyticsRecord],
        kind: UsageAnalyticsFacetKind?
    ) -> [UsageAnalyticsDimensionOption] {
        guard let kind else { return [] }
        var totals: [NamedDimensionKey: UsageMetricTotals] = [:]
        for record in records {
            for facet in Set(record.facets.filter { $0.kind == kind }) {
                let key = NamedDimensionKey(id: dimensionKey(facet.value), title: displayValue(facet.displayName))
                totals[key, default: UsageMetricTotals()].add(record.totals)
            }
        }
        return totals.map { key, value in
            UsageAnalyticsDimensionOption(id: key.id, title: key.title, totalTokens: value.totalTokens, requestCount: value.requestCount)
        }.sorted(by: optionSort)
    }

    private static func dimensionStats(
        from totals: [NamedDimensionKey: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageAnalyticsDimensionStats] {
        totals.map { key, value in
            UsageAnalyticsDimensionStats(id: key.id, title: key.title, totals: value, share: share(tokens: value.totalTokens, totalTokens: totalTokens))
        }.sorted(by: dimensionStatsSort)
    }

    private static func facetStats(
        from totals: [FacetKey: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageAnalyticsFacetStatsGroup] {
        Dictionary(grouping: totals, by: { $0.key.kind }).map { kind, values in
            UsageAnalyticsFacetStatsGroup(
                kind: kind,
                items: values.map { key, value in
                    UsageAnalyticsDimensionStats(id: key.value, title: key.title, totals: value, share: share(tokens: value.totalTokens, totalTokens: totalTokens))
                }.sorted(by: dimensionStatsSort)
            )
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private static func modelOptions(
        from records: [UsageAnalyticsRecord]
    ) -> [UsageAnalyticsModelOption] {
        var totalsByModel: [String: ModelOptionAccumulator] = [:]
        for record in records {
            let key = modelKey(record.modelID)
            if var item = totalsByModel[key] {
                item.add(record)
                totalsByModel[key] = item
            } else {
                totalsByModel[key] = ModelOptionAccumulator(record: record)
            }
        }
        return totalsByModel.map { key, item in
            UsageAnalyticsModelOption(id: key, title: item.title, totalTokens: item.totalTokens)
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                return lhs.title < rhs.title
            }
            return lhs.totalTokens > rhs.totalTokens
        }
    }

    private static func categoryStats(
        from totalsByCategory: [String: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageProviderCategoryStats] {
        totalsByCategory.map { key, totals in
            UsageProviderCategoryStats(
                name: key,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: statsSort)
    }

    private static func concreteProviderStats(
        from totalsByProvider: [ProviderKey: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageProviderStats] {
        totalsByProvider.map { key, totals in
            UsageProviderStats(
                id: "\(key.categoryName)|\(key.providerID)|\(key.providerName)",
                providerID: key.providerID,
                providerName: key.providerName,
                categoryName: key.categoryName,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: providerSort)
    }

    private static func concreteModelStats(
        from groupsByModel: [String: ModelGroup],
        totalTokens: Int
    ) -> [UsageModelStats] {
        groupsByModel.map { _, group in
            UsageModelStats(
                modelID: group.modelID,
                appType: summaryValue(group.appTypes, multipleLabel: "mixed"),
                providerName: summaryValue(group.providerNames, multipleLabel: "多个来源"),
                totals: group.totals,
                share: share(tokens: group.totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: modelSort)
    }

    private static func trendBuckets(
        from records: [UsageAnalyticsRecord],
        range: UsageAnalyticsRange,
        firstEventAt: Date?,
        lastEventAt: Date?,
        calendar: Calendar,
        now: Date
    ) -> [UsageTrendBucket] {
        let plan: TrendBucketPlan
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            plan = TrendBucketPlan(
                starts: (0..<24).compactMap { calendar.date(byAdding: .hour, value: -(23 - $0), to: currentHour) },
                granularity: .hour
            )
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<7).compactMap { calendar.date(byAdding: .day, value: -(6 - $0), to: today) },
                granularity: .day
            )
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<30).compactMap { calendar.date(byAdding: .day, value: -(29 - $0), to: today) },
                granularity: .day
            )
        case .all:
            plan = allRangeTrendPlan(
                firstEventAt: firstEventAt,
                lastEventAt: lastEventAt,
                calendar: calendar
            )
        }

        var bucketsByStart: [Date: TrendBucketAccumulator] = [:]
        for record in records {
            let bucketStart = trendBucketStart(
                for: record.eventAt,
                plan: plan,
                calendar: calendar
            )
            if let bucketStart {
                bucketsByStart[bucketStart, default: TrendBucketAccumulator()].add(record)
            }
        }

        return plan.starts.map { start in
            let end = trendBucketEnd(
                for: start,
                granularity: plan.granularity,
                calendar: calendar
            )
            let accumulator = bucketsByStart[start] ?? TrendBucketAccumulator()
            let totals = accumulator.totals
            return UsageTrendBucket(
                id: "\(plan.granularity.rawValue)-\(Int(start.timeIntervalSince1970))",
                startAt: start,
                endAt: end,
                totals: totals,
                topProviders: breakdown(from: accumulator.providerTotals, totalTokens: totals.totalTokens),
                topModels: breakdown(from: accumulator.modelTotals, totalTokens: totals.totalTokens)
            )
        }
    }

    private static func allRangeTrendPlan(
        firstEventAt: Date?,
        lastEventAt: Date?,
        calendar: Calendar
    ) -> TrendBucketPlan {
        guard let firstEventAt, let lastEventAt else {
            return TrendBucketPlan(starts: [], granularity: .day)
        }

        let firstDay = calendar.startOfDay(for: firstEventAt)
        let lastDay = calendar.startOfDay(for: lastEventAt)
        let dayCount = max(0, calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1

        if dayCount <= 180 {
            var starts: [Date] = []
            var cursor = firstDay
            while cursor <= lastDay {
                starts.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 7, to: cursor),
                      next > cursor else {
                    break
                }
                cursor = next
            }
            return TrendBucketPlan(starts: starts, granularity: .sevenDay)
        }

        let firstMonth = calendar.dateInterval(of: .month, for: firstEventAt)?.start ?? firstDay
        let lastMonth = calendar.dateInterval(of: .month, for: lastEventAt)?.start ?? lastDay
        let monthCount = max(0, calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0) + 1
        if monthCount <= 24 {
            return TrendBucketPlan(
                starts: continuousStarts(from: firstMonth, through: lastMonth, component: .month, step: 1, calendar: calendar),
                granularity: .month
            )
        }

        let firstQuarter = quarterStart(for: firstEventAt, calendar: calendar) ?? firstMonth
        let lastQuarter = quarterStart(for: lastEventAt, calendar: calendar) ?? lastMonth
        return TrendBucketPlan(
            starts: continuousStarts(from: firstQuarter, through: lastQuarter, component: .month, step: 3, calendar: calendar),
            granularity: .quarter
        )
    }

    private static func continuousStarts(
        from start: Date,
        through end: Date,
        component: Calendar.Component,
        step: Int,
        calendar: Calendar
    ) -> [Date] {
        var starts: [Date] = []
        var cursor = start
        while cursor <= end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: component, value: step, to: cursor),
                  next > cursor else {
                break
            }
            cursor = next
        }
        return starts
    }

    private static func trendBucketStart(
        for date: Date,
        plan: TrendBucketPlan,
        calendar: Calendar
    ) -> Date? {
        switch plan.granularity {
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)?.start
        case .day:
            return calendar.startOfDay(for: date)
        case .sevenDay:
            guard let firstStart = plan.starts.first else { return nil }
            let recordDay = calendar.startOfDay(for: date)
            let dayOffset = calendar.dateComponents([.day], from: firstStart, to: recordDay).day ?? 0
            guard dayOffset >= 0 else { return nil }
            return calendar.date(byAdding: .day, value: (dayOffset / 7) * 7, to: firstStart)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        case .quarter:
            return quarterStart(for: date, calendar: calendar)
        }
    }

    private static func trendBucketEnd(
        for start: Date,
        granularity: TrendBucketGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .sevenDay:
            return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .quarter:
            return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        }
    }

    private static func quarterStart(
        for date: Date,
        calendar: Calendar
    ) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year,
              let month = components.month else {
            return nil
        }
        let firstMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: firstMonth,
            day: 1
        ))
    }

    private static func breakdown(
        from totalsByName: [String: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageAnalyticsBreakdownItem] {
        totalsByName.map { name, totals in
            UsageAnalyticsBreakdownItem(
                name: name,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: breakdownSort)
        .prefix(5)
        .map { $0 }
    }

    private static func share(tokens: Int, totalTokens: Int) -> Double {
        guard totalTokens > 0 else { return 0 }
        return Double(tokens) / Double(totalTokens)
    }

    private static func dimensionKey(_ value: String) -> String {
        displayValue(value).lowercased()
    }

    private static func modelKey(_ value: String) -> String {
        dimensionKey(value)
    }

    private static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func summaryValue(_ values: Set<String>, multipleLabel: String) -> String {
        let cleaned = values.map(displayValue).filter { $0 != "unknown" }.sorted()
        if cleaned.count == 1 {
            return cleaned[0]
        }
        if cleaned.isEmpty {
            return "unknown"
        }
        return multipleLabel
    }

    private static func dimensionStatsSort(lhs: UsageAnalyticsDimensionStats, rhs: UsageAnalyticsDimensionStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.title < rhs.title
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func optionSort(lhs: UsageAnalyticsDimensionOption, rhs: UsageAnalyticsDimensionOption) -> Bool {
        if lhs.totalTokens == rhs.totalTokens {
            return lhs.title < rhs.title
        }
        return lhs.totalTokens > rhs.totalTokens
    }

    private static func statsSort(lhs: UsageProviderCategoryStats, rhs: UsageProviderCategoryStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func providerSort(lhs: UsageProviderStats, rhs: UsageProviderStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.providerName < rhs.providerName
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func modelSort(lhs: UsageModelStats, rhs: UsageModelStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.modelID < rhs.modelID
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func breakdownSort(lhs: UsageAnalyticsBreakdownItem, rhs: UsageAnalyticsBreakdownItem) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }
}
