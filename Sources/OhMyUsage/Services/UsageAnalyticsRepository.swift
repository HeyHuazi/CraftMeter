import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: Coordinates CCSwitch/local scanners and a provider-aware model pricing catalog for Claude, Codex, Kimi, Gemini, Qwen, and Craft Agents.
 * [OUTPUT]: Returns price-enriched snapshots, natural/all-period menu bar summaries, plus a complete source fingerprint for cache validation.
 * [POS]: OhMyUsage Services analytics repository; IO/enrichment orchestration only, with pricing math and aggregation delegated to OhMyUsageApplication.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsRepository: @unchecked Sendable {
    typealias CCSwitchSourceFingerprintProvider = (_ ccSwitchReader: CCSwitchUsageLogReader) -> UsageAnalyticsFileFingerprint
    typealias LocalSourceFingerprintProvider = (
        _ claudeAllConfigDirs: [String]
    ) -> CachedLocalSourceFingerprint

    struct CachedLocalSourceFingerprint: Equatable, Sendable {
        var codex: UsageAnalyticsFileFingerprint
        var claude: UsageAnalyticsFileFingerprint
        var kimi: UsageAnalyticsFileFingerprint
        var gemini: UsageAnalyticsFileFingerprint
        var qwen: UsageAnalyticsFileFingerprint
        var craftAgent: UsageAnalyticsFileFingerprint

        init(
            codex: UsageAnalyticsFileFingerprint,
            claude: UsageAnalyticsFileFingerprint,
            kimi: UsageAnalyticsFileFingerprint,
            gemini: UsageAnalyticsFileFingerprint = .empty,
            qwen: UsageAnalyticsFileFingerprint = .empty,
            craftAgent: UsageAnalyticsFileFingerprint = .empty
        ) {
            self.codex = codex
            self.claude = claude
            self.kimi = kimi
            self.gemini = gemini
            self.qwen = qwen
            self.craftAgent = craftAgent
        }
    }

    private final class LocalSourceFingerprintCache: @unchecked Sendable {
        private struct Entry {
            var fingerprint: CachedLocalSourceFingerprint
            var checkedAt: Date
        }

        private let ttl: TimeInterval
        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        init(ttl: TimeInterval) {
            self.ttl = ttl
        }

        func fingerprint(for key: String, now: Date) -> CachedLocalSourceFingerprint? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return nil }
            guard now.timeIntervalSince(entry.checkedAt) < ttl else {
                entries.removeValue(forKey: key)
                return nil
            }
            return entry.fingerprint
        }

        func store(_ fingerprint: CachedLocalSourceFingerprint, for key: String, now: Date) {
            lock.lock()
            entries[key] = Entry(fingerprint: fingerprint, checkedAt: now)
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    private static let localSourceFingerprintCache = LocalSourceFingerprintCache(ttl: 60)

    private let ccSwitchReader: CCSwitchUsageLogReader
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let ccSwitchSourceFingerprintProvider: CCSwitchSourceFingerprintProvider
    private let localSourceFingerprintProvider: LocalSourceFingerprintProvider
    private let pricingCatalog: ModelPricingCatalog

    init(
        ccSwitchReader: CCSwitchUsageLogReader = CCSwitchUsageLogReader(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        ccSwitchSourceFingerprintProvider: @escaping CCSwitchSourceFingerprintProvider = UsageAnalyticsRepository.defaultCCSwitchSourceFingerprint,
        localSourceFingerprintProvider: @escaping LocalSourceFingerprintProvider = UsageAnalyticsRepository.defaultLocalSourceFingerprint,
        pricingCatalog: ModelPricingCatalog = ModelPricingCatalog()
    ) {
        self.ccSwitchReader = ccSwitchReader
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.ccSwitchSourceFingerprintProvider = ccSwitchSourceFingerprintProvider
        self.localSourceFingerprintProvider = localSourceFingerprintProvider
        self.pricingCatalog = pricingCatalog
        self.pricingCatalog.refreshIfNeeded()
    }

    func snapshot(
        filter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String] = []
    ) -> UsageAnalyticsSnapshot {
        let now = nowProvider()
        let interval = UsageAnalyticsAggregator.rangeInterval(filter.range, calendar: calendar, now: now)
        var diagnostics: [String] = []
        var records: [UsageAnalyticsRecord] = []

        let ccSwitchResult = ccSwitchReader.readUsageLogs(since: interval.start, until: interval.end)
        records.append(contentsOf: ccSwitchResult.records.map(\.analyticsRecord))
        diagnostics.append(contentsOf: ccSwitchResult.diagnostics)

        let localResult = readLocalRecords(
            since: interval.start,
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        records.append(contentsOf: localResult.records)
        diagnostics.append(contentsOf: localResult.diagnostics)

        records = pricingCatalog.enrich(records)
        return UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: filter,
            calendar: calendar,
            now: now,
            diagnostics: diagnostics
        )
    }

    func menuBarSummary(
        claudeAllConfigDirs: [String] = []
    ) -> UsageAnalyticsMenuBarSummary {
        let now = nowProvider()
        let scanStart = Date.distantPast
        var records: [UsageAnalyticsRecord] = []

        let ccSwitchResult = ccSwitchReader.readUsageLogs(since: scanStart, until: now)
        records.append(contentsOf: ccSwitchResult.records.map(\.analyticsRecord))
        records.append(contentsOf: readLocalRecords(
            since: scanStart,
            claudeAllConfigDirs: claudeAllConfigDirs
        ).records)

        records = pricingCatalog.enrich(records)
        return UsageAnalyticsAggregator.menuBarSummary(
            records: records,
            calendar: calendar,
            now: now
        )
    }

    func sourceFingerprint(claudeAllConfigDirs: [String] = []) -> UsageAnalyticsSourceFingerprint {
        let now = nowProvider()
        let ccSwitch = ccSwitchSourceFingerprintProvider(ccSwitchReader)
        let cacheKey = Self.localSourceFingerprintCacheKey(
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        let localFingerprint: CachedLocalSourceFingerprint
        if let cached = Self.localSourceFingerprintCache.fingerprint(for: cacheKey, now: now) {
            localFingerprint = cached
        } else {
            localFingerprint = localSourceFingerprintProvider(claudeAllConfigDirs)
            Self.localSourceFingerprintCache.store(localFingerprint, for: cacheKey, now: now)
        }
        return UsageAnalyticsSourceFingerprint(
            ccSwitch: ccSwitch,
            codex: localFingerprint.codex,
            claude: localFingerprint.claude,
            kimi: localFingerprint.kimi,
            gemini: localFingerprint.gemini,
            qwen: localFingerprint.qwen,
            craftAgent: localFingerprint.craftAgent
        )
    }

    static func clearSourceFingerprintCacheForTesting() {
        localSourceFingerprintCache.removeAll()
    }

    private func readLocalRecords(
        since: Date,
        claudeAllConfigDirs: [String]
    ) -> (records: [UsageAnalyticsRecord], diagnostics: [String]) {
        var records: [UsageAnalyticsRecord] = []
        var diagnostics: [String] = []

        do {
            let codexEvents = try CodexLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: codexEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "codex",
                    providerID: "ohmyusage-codex-local",
                    providerName: "Codex"
                )
            })
        } catch {
            diagnostics.append("Codex 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let claudeEvents = try ClaudeLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, allConfigDirs: claudeAllConfigDirs, since: since)
            records.append(contentsOf: claudeEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "claude",
                    providerID: "ohmyusage-claude-local",
                    providerName: "Claude"
                )
            })
        } catch {
            diagnostics.append("Claude 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let kimiEvents = try KimiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: kimiEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "kimi",
                    providerID: "ohmyusage-kimi-local",
                    providerName: "Kimi"
                )
            })
        } catch {
            diagnostics.append("Kimi 本地日志读取失败：\(error.localizedDescription)")
        }

        let extendedScanner = ExtendedLocalUsageScanner()
        for source in ExtendedLocalUsageScanner.Source.allCases {
            records.append(contentsOf: extendedScanner.records(source: source, since: since))
        }

        return (records, diagnostics)
    }

    private func analyticsRecord(
        event: LocalUsageEvent,
        appType: String,
        providerID: String,
        providerName: String
    ) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: event.eventAt,
            appType: appType,
            providerID: providerID,
            providerName: providerName,
            modelID: event.modelID,
            requestID: event.signature,
            totals: usageTotals(from: event)
        )
    }

    private func usageTotals(from event: LocalUsageEvent) -> UsageMetricTotals {
        let componentTotal = event.inputTokens
            + event.outputTokens
            + event.cacheReadTokens
            + event.cacheWriteTokens
        if componentTotal > 0 {
            return UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                cacheReadTokens: event.cacheReadTokens,
                cacheWriteTokens: event.cacheWriteTokens,
                unpricedRequestCount: 1
            )
        }
        return UsageMetricTotals(
            requestCount: 1,
            successCount: 1,
            outputTokens: event.totalTokens,
            unpricedRequestCount: 1
        )
    }

    private static func defaultCCSwitchSourceFingerprint(
        ccSwitchReader: CCSwitchUsageLogReader
    ) -> UsageAnalyticsFileFingerprint {
        usageAnalyticsFileFingerprint(from: ccSwitchReader.sourceFingerprint())
    }

    private static func defaultLocalSourceFingerprint(
        claudeAllConfigDirs: [String]
    ) -> CachedLocalSourceFingerprint {
        let extendedScanner = ExtendedLocalUsageScanner()
        return CachedLocalSourceFingerprint(
            codex: usageAnalyticsFileFingerprint(
                from: LocalUsageSourceFingerprintBuilder.codexFingerprint(scope: .allAccounts)
            ),
            claude: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.claudeFingerprint(
                scope: .allAccounts,
                currentConfigDir: nil,
                allConfigDirs: claudeAllConfigDirs
            )),
            kimi: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.kimiFingerprint()),
            gemini: extendedScanner.fingerprint(source: .gemini),
            qwen: extendedScanner.fingerprint(source: .qwen),
            craftAgent: extendedScanner.fingerprint(source: .craftAgent)
        )
    }

    private static func localSourceFingerprintCacheKey(
        claudeAllConfigDirs: [String]
    ) -> String {
        let normalizedDirs = Set(claudeAllConfigDirs.compactMap { dir -> String? in
            let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let expanded = (trimmed as NSString).expandingTildeInPath
            return (expanded as NSString).standardizingPath
        })
        return "claude=\(normalizedDirs.sorted().joined(separator: "\u{1F}"))"
    }

    private static func usageAnalyticsFileFingerprint(
        from fingerprint: LocalUsageSourceFingerprint
    ) -> UsageAnalyticsFileFingerprint {
        UsageAnalyticsFileFingerprint(
            roots: fingerprint.roots,
            fileCount: fingerprint.fileCount,
            totalSize: fingerprint.totalSize,
            latestModificationTime: fingerprint.latestModificationTime
        )
    }
}
