import Foundation

/**
 * [INPUT]: 接收按 filter/fingerprint 组织的 UsageAnalyticsSnapshot，并依赖 Foundation 文件系统与串行 utility 持久化队列。
 * [OUTPUT]: 提供 schema-version 6 的可延迟缓存恢复、同步内存读取、自然周期新鲜度校验，以及 snapshot JSON + 轻量 validation manifest 的后台原子写入。
 * [POS]: OhMyUsageApplication 的历史快照缓存边界；MainActor 只提交/读取不可变快照，校验只写 KB 级 sidecar，不重编码或重写大型 snapshot payload。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

public struct UsageAnalyticsFileFingerprint: Codable, Equatable, Sendable {
    public var roots: [String]
    public var fileCount: Int
    public var totalSize: UInt64
    public var latestModificationTime: Date?

    public init(
        roots: [String],
        fileCount: Int,
        totalSize: UInt64,
        latestModificationTime: Date?
    ) {
        self.roots = roots
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.latestModificationTime = latestModificationTime
    }
}

public struct UsageAnalyticsSourceFingerprint: Codable, Equatable, Sendable {
    public var ccSwitch: UsageAnalyticsFileFingerprint
    public var codex: UsageAnalyticsFileFingerprint
    public var claude: UsageAnalyticsFileFingerprint
    public var kimi: UsageAnalyticsFileFingerprint
    public var gemini: UsageAnalyticsFileFingerprint
    public var qwen: UsageAnalyticsFileFingerprint
    public var craftAgent: UsageAnalyticsFileFingerprint

    public init(
        ccSwitch: UsageAnalyticsFileFingerprint,
        codex: UsageAnalyticsFileFingerprint,
        claude: UsageAnalyticsFileFingerprint,
        kimi: UsageAnalyticsFileFingerprint,
        gemini: UsageAnalyticsFileFingerprint = .empty,
        qwen: UsageAnalyticsFileFingerprint = .empty,
        craftAgent: UsageAnalyticsFileFingerprint = .empty
    ) {
        self.ccSwitch = ccSwitch
        self.codex = codex
        self.claude = claude
        self.kimi = kimi
        self.gemini = gemini
        self.qwen = qwen
        self.craftAgent = craftAgent
    }
}

public extension UsageAnalyticsFileFingerprint {
    static let empty = UsageAnalyticsFileFingerprint(
        roots: [],
        fileCount: 0,
        totalSize: 0,
        latestModificationTime: nil
    )
}

public struct UsageAnalyticsCacheEntry: Codable, Equatable, Sendable {
    public var filter: UsageAnalyticsFilter
    public var snapshot: UsageAnalyticsSnapshot
    public var sourceFingerprint: UsageAnalyticsSourceFingerprint?
    public var refreshedAt: Date
    public var lastFingerprintCheckedAt: Date?

    public init(
        filter: UsageAnalyticsFilter,
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?,
        refreshedAt: Date,
        lastFingerprintCheckedAt: Date?
    ) {
        self.filter = filter
        self.snapshot = snapshot
        self.sourceFingerprint = sourceFingerprint
        self.refreshedAt = refreshedAt
        self.lastFingerprintCheckedAt = lastFingerprintCheckedAt
    }
}

public final class UsageAnalyticsSnapshotCacheStore: @unchecked Sendable {
    private static let currentSchemaVersion = 6

    private struct CachePayload: Codable {
        var schemaVersion: Int
        var entries: [UsageAnalyticsCacheEntry]
    }

    private struct ValidationMetadata: Codable, Equatable {
        var filter: UsageAnalyticsFilter
        var sourceFingerprint: UsageAnalyticsSourceFingerprint?
        var refreshedAt: Date
        var lastFingerprintCheckedAt: Date?
    }

    private struct MetadataPayload: Codable {
        var schemaVersion: Int
        var entries: [ValidationMetadata]
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL
    private let metadataFileURL: URL
    private let nowProvider: () -> Date
    private let maxEntries: Int
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "com.heyhuazi.craftmeter.usage-analytics-cache",
        qos: .utility
    )
    private var entries: [UsageAnalyticsFilter: UsageAnalyticsCacheEntry] = [:]
    private var restored = false
    private var lastPersistedCacheData: Data?
    private var lastPersistedEntries: [UsageAnalyticsCacheEntry]?
    private var lastPersistedMetadataData: Data?
    private var lastPersistedMetadata: [ValidationMetadata]?

    public init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        maxEntries: Int? = nil,
        restoreImmediately: Bool = true
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.maxEntries = max(1, maxEntries ?? RuntimeDiagnosticsLimits.usageAnalyticsCacheMaxEntries)
        let rootDirectory = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDirectory = rootDirectory
            .appendingPathComponent("CraftMeter", isDirectory: true)
        self.fileURL = cacheDirectory
            .appendingPathComponent("usage_analytics_cache.json")
        self.metadataFileURL = cacheDirectory
            .appendingPathComponent("usage_analytics_cache_manifest.json")
        if restoreImmediately {
            restoreIfNeeded()
        }
    }

    public var isRestored: Bool {
        lock.withLock { restored }
    }

    public func restoreIfNeeded() {
        lock.lock()
        guard !restored else {
            lock.unlock()
            return
        }
        restored = true
        lock.unlock()

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(CachePayload.self, from: data),
              payload.schemaVersion == Self.currentSchemaVersion else {
            return
        }

        var restoredEntries = payload.entries
        var restoredMetadata: [ValidationMetadata]?
        var restoredMetadataData: Data?
        if let metadataData = try? Data(contentsOf: metadataFileURL),
           let metadataPayload = try? decoder.decode(MetadataPayload.self, from: metadataData),
           metadataPayload.schemaVersion == Self.currentSchemaVersion {
            let metadataByFilter = Dictionary(
                uniqueKeysWithValues: metadataPayload.entries.map { ($0.filter, $0) }
            )
            restoredEntries = restoredEntries.map { entry in
                guard let metadata = metadataByFilter[entry.filter] else { return entry }
                var updatedEntry = entry
                updatedEntry.sourceFingerprint = metadata.sourceFingerprint
                updatedEntry.refreshedAt = metadata.refreshedAt
                updatedEntry.lastFingerprintCheckedAt = metadata.lastFingerprintCheckedAt
                return updatedEntry
            }
            restoredMetadata = metadataPayload.entries
            restoredMetadataData = metadataData
        }

        lock.lock()
        entries = Dictionary(uniqueKeysWithValues: restoredEntries.map { ($0.filter, $0) })
        pruneLocked()
        let persistedEntries = sortedEntriesLocked()
        lastPersistedEntries = persistedEntries
        lastPersistedCacheData = data
        lastPersistedMetadata = restoredMetadata
        lastPersistedMetadataData = restoredMetadataData
        lock.unlock()
    }

    public func reset() {
        lock.withLock {
            entries.removeAll()
            restored = true
            lastPersistedEntries = nil
            lastPersistedCacheData = nil
            lastPersistedMetadata = nil
            lastPersistedMetadataData = nil
        }
        persistenceQueue.sync {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: metadataFileURL)
        }
    }

    public func entry(for filter: UsageAnalyticsFilter) -> UsageAnalyticsCacheEntry? {
        lock.lock()
        let entry = entries[filter]
        lock.unlock()
        return entry
    }

    public func save(
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?
    ) {
        let persistedEntries = updateEntry(
            snapshot: snapshot,
            sourceFingerprint: sourceFingerprint
        )
        persistenceQueue.sync {
            persistSnapshot(persistedEntries)
            persistMetadata(metadataEntries(from: persistedEntries))
        }
    }

    public func markValidated(
        filter: UsageAnalyticsFilter,
        sourceFingerprint: UsageAnalyticsSourceFingerprint,
        at validatedAt: Date
    ) {
        guard let persistedEntries = updateValidation(
            filter: filter,
            sourceFingerprint: sourceFingerprint,
            at: validatedAt
        ) else { return }
        persistenceQueue.sync {
            persistMetadata(metadataEntries(from: persistedEntries))
        }
    }

    public func saveInBackground(
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?
    ) {
        let persistedEntries = updateEntry(
            snapshot: snapshot,
            sourceFingerprint: sourceFingerprint
        )
        persistenceQueue.async { [weak self] in
            guard let self else { return }
            self.persistSnapshot(persistedEntries)
            self.persistMetadata(self.metadataEntries(from: persistedEntries))
        }
    }

    public func markValidatedInBackground(
        filter: UsageAnalyticsFilter,
        sourceFingerprint: UsageAnalyticsSourceFingerprint,
        at validatedAt: Date
    ) {
        guard let persistedEntries = updateValidation(
            filter: filter,
            sourceFingerprint: sourceFingerprint,
            at: validatedAt
        ) else { return }
        persistenceQueue.async { [weak self] in
            guard let self else { return }
            self.persistMetadata(self.metadataEntries(from: persistedEntries))
        }
    }

    public func shouldProbeFingerprint(
        for filter: UsageAnalyticsFilter,
        now: Date,
        interval: TimeInterval? = nil
    ) -> Bool {
        guard let entry = entry(for: filter) else { return true }
        let checkedAt = entry.lastFingerprintCheckedAt ?? entry.refreshedAt
        return now.timeIntervalSince(checkedAt) >= max(
            1,
            interval ?? RuntimeDiagnosticsLimits.usageAnalyticsFingerprintProbeInterval
        )
    }

    public func isEntryTemporallyFresh(
        for filter: UsageAnalyticsFilter,
        now: Date,
        calendar: Calendar,
        ttl: TimeInterval? = nil
    ) -> Bool {
        guard let entry = entry(for: filter) else { return false }
        guard now.timeIntervalSince(entry.refreshedAt) < max(
            30,
            ttl ?? RuntimeDiagnosticsLimits.usageAnalyticsCacheEntryTTL
        ) else { return false }
        return Self.isSnapshotWindowCurrent(
            generatedAt: entry.snapshot.generatedAt,
            now: now,
            range: filter.range,
            calendar: calendar
        )
    }

    private func updateEntry(
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?
    ) -> [UsageAnalyticsCacheEntry] {
        let now = nowProvider()
        lock.lock()
        entries[snapshot.filter] = UsageAnalyticsCacheEntry(
            filter: snapshot.filter,
            snapshot: snapshot,
            sourceFingerprint: sourceFingerprint,
            refreshedAt: now,
            lastFingerprintCheckedAt: sourceFingerprint == nil ? nil : now
        )
        pruneLocked()
        let persistedEntries = sortedEntriesLocked()
        lock.unlock()
        return persistedEntries
    }

    private func updateValidation(
        filter: UsageAnalyticsFilter,
        sourceFingerprint: UsageAnalyticsSourceFingerprint,
        at validatedAt: Date
    ) -> [UsageAnalyticsCacheEntry]? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[filter] else { return nil }
        entry.sourceFingerprint = sourceFingerprint
        entry.refreshedAt = validatedAt
        entry.lastFingerprintCheckedAt = validatedAt
        entries[filter] = entry
        return sortedEntriesLocked()
    }

    private func persistSnapshot(_ persistedEntries: [UsageAnalyticsCacheEntry]) {
        do {
            lock.lock()
            let unchanged = persistedEntries == lastPersistedEntries
                && fileManager.fileExists(atPath: fileURL.path)
            lock.unlock()
            if unchanged { return }

            let payload = CachePayload(
                schemaVersion: Self.currentSchemaVersion,
                entries: persistedEntries
            )
            let data = try encoder.encode(payload)

            lock.lock()
            let sameData = data == lastPersistedCacheData
                && fileManager.fileExists(atPath: fileURL.path)
            lock.unlock()
            if sameData {
                lock.withLock {
                    lastPersistedEntries = persistedEntries
                }
                return
            }

            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            lock.withLock {
                lastPersistedEntries = persistedEntries
                lastPersistedCacheData = data
            }
        } catch {
            return
        }
    }

    private func metadataEntries(
        from persistedEntries: [UsageAnalyticsCacheEntry]
    ) -> [ValidationMetadata] {
        persistedEntries.map { entry in
            ValidationMetadata(
                filter: entry.filter,
                sourceFingerprint: entry.sourceFingerprint,
                refreshedAt: entry.refreshedAt,
                lastFingerprintCheckedAt: entry.lastFingerprintCheckedAt
            )
        }
    }

    private func persistMetadata(_ persistedMetadata: [ValidationMetadata]) {
        do {
            let unchanged = lock.withLock {
                persistedMetadata == lastPersistedMetadata
                    && fileManager.fileExists(atPath: metadataFileURL.path)
            }
            if unchanged { return }

            let payload = MetadataPayload(
                schemaVersion: Self.currentSchemaVersion,
                entries: persistedMetadata
            )
            let data = try encoder.encode(payload)
            let sameData = lock.withLock {
                data == lastPersistedMetadataData
                    && fileManager.fileExists(atPath: metadataFileURL.path)
            }
            if sameData {
                lock.withLock {
                    lastPersistedMetadata = persistedMetadata
                }
                return
            }

            try fileManager.createDirectory(
                at: metadataFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: metadataFileURL, options: .atomic)
            lock.withLock {
                lastPersistedMetadata = persistedMetadata
                lastPersistedMetadataData = data
            }
        } catch {
            return
        }
    }

    private func pruneLocked() {
        guard entries.count > maxEntries else { return }
        let keepFilters = Set(sortedEntriesLocked().prefix(maxEntries).map(\.filter))
        entries = entries.filter { keepFilters.contains($0.key) }
    }

    private func sortedEntriesLocked() -> [UsageAnalyticsCacheEntry] {
        entries.values.sorted { lhs, rhs in
            if lhs.refreshedAt != rhs.refreshedAt {
                return lhs.refreshedAt > rhs.refreshedAt
            }
            return lhs.filter.range.rawValue < rhs.filter.range.rawValue
        }
    }

    private static func isSnapshotWindowCurrent(
        generatedAt: Date,
        now: Date,
        range: UsageAnalyticsRange,
        calendar: Calendar
    ) -> Bool {
        switch range {
        case .today, .week, .month:
            return calendar.isDate(generatedAt, equalTo: now, toGranularity: .day)
        case .all:
            return calendar.isDate(generatedAt, equalTo: now, toGranularity: .month)
        }
    }
}
