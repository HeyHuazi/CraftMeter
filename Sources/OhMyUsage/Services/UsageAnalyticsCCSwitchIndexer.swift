import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 CCSwitch 只读 reader、源数据库文件身份和事务 event store。
 * [OUTPUT]: 对外提供 proxy overlap high-watermark upsert 与 bounded daily rollup replacement shadow ingest。
 * [POS]: Services analytics 批次 C3 CCSwitch adapter；保留 proxy/session/rollup 来源语义，不接管 Repository 生产读取。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsCCSwitchIndexer {
    struct Configuration: Sendable {
        var databasePath: String
        var parserSchema: Int
        var initialSince: Date
        var overlap: TimeInterval
        var rollupRefreshDays: Int
        var now: Date

        init(
            databasePath: String,
            parserSchema: Int,
            initialSince: Date = .distantPast,
            overlap: TimeInterval = 10 * 60,
            rollupRefreshDays: Int = 3,
            now: Date = Date()
        ) {
            self.databasePath = databasePath
            self.parserSchema = parserSchema
            self.initialSince = initialSince
            self.overlap = overlap
            self.rollupRefreshDays = rollupRefreshDays
            self.now = now
        }
    }

    private struct Checkpoint: Codable, Equatable, Sendable {
        var proxyHighWatermark: Date?
    }

    private let store: UsageAnalyticsEventStore
    private let fileManager: FileManager

    init(store: UsageAnalyticsEventStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func ingest(_ configuration: Configuration) throws -> UsageAnalyticsIngestDiagnostics {
        let databaseURL = URL(
            fileURLWithPath: (configuration.databasePath as NSString).expandingTildeInPath
        ).standardizedFileURL
        guard let snapshot = databaseSnapshot(databaseURL) else {
            return UsageAnalyticsIngestDiagnostics(source: .ccSwitch)
        }

        let path = databaseURL.path
        let existing = try store.cursor(source: .ccSwitch, normalizedPath: path)
        let requiresRebuild = existing == nil
            || existing?.identity != snapshot.identity
            || existing?.parserSchema != configuration.parserSchema
        if !requiresRebuild,
           existing?.observedSize == snapshot.size,
           existing?.observedModificationTime == snapshot.modifiedAtRef {
            return UsageAnalyticsIngestDiagnostics(source: .ccSwitch, discoveredFileCount: 1)
        }

        let previousCheckpoint = requiresRebuild ? Checkpoint() : decode(existing?.checkpoint)
        let proxySince = requiresRebuild
            ? configuration.initialSince
            : max(
                configuration.initialSince,
                previousCheckpoint.proxyHighWatermark?.addingTimeInterval(-configuration.overlap)
                    ?? configuration.initialSince
            )
        let rollupSince = requiresRebuild
            ? configuration.initialSince
            : Calendar.utc.startOfDay(
                for: configuration.now.addingTimeInterval(
                    -TimeInterval(max(1, configuration.rollupRefreshDays)) * 24 * 60 * 60
                )
            )
        let until = configuration.now.addingTimeInterval(1)
        let reader = CCSwitchUsageLogReader(databasePath: path, fileManager: fileManager)
        let proxy = reader.readProxyUsageLogs(since: proxySince, until: until)
        let rollups = reader.readDailyUsageRollups(since: rollupSince, until: until)
        let proxyRecords = proxy.records.map(\.analyticsRecord)
        let rollupRecords = rollups.records.map(\.analyticsRecord)
        let highWatermark = maxDate(
            previousCheckpoint.proxyHighWatermark,
            proxy.records.map(\.eventAt).max()
        )
        let checkpoint = Checkpoint(proxyHighWatermark: highWatermark)
        let cursor = UsageAnalyticsSourceFileCursor(
            source: .ccSwitch,
            normalizedPath: path,
            identity: snapshot.identity,
            observedSize: snapshot.size,
            observedModificationTime: snapshot.modifiedAtRef,
            committedOffset: 0,
            parserSchema: configuration.parserSchema,
            checkpoint: try JSONEncoder().encode(checkpoint),
            lastCompleteEventAt: maxDate(
                highWatermark,
                rollups.records.map(\.eventAt).max()
            )
        )

        if requiresRebuild {
            try store.commitFileIngest(
                cursor: cursor,
                records: proxyRecords + rollupRecords,
                replaceExistingFileRecords: true
            )
        } else {
            try store.commitCCSwitchIngest(
                cursor: cursor,
                proxyRecords: proxyRecords,
                refreshedRollupRecords: rollupRecords,
                rollupSince: rollupSince
            )
        }

        return UsageAnalyticsIngestDiagnostics(
            source: .ccSwitch,
            discoveredFileCount: 1,
            changedFileCount: 1,
            emittedRecordCount: proxyRecords.count + rollupRecords.count,
            rebuiltFileCount: requiresRebuild ? 1 : 0,
            invalidLineCount: proxy.diagnostics.count + rollups.diagnostics.count
        )
    }

    private func decode(_ data: Data?) -> Checkpoint {
        guard let data, let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else {
            return Checkpoint()
        }
        return checkpoint
    }

    private func databaseSnapshot(_ url: URL) -> (
        identity: UsageAnalyticsFileIdentity,
        size: UInt64,
        modifiedAtRef: TimeInterval?
    )? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let walURL = URL(fileURLWithPath: "\(url.path)-wal")
        let walValues = try? walURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let mainSize = UInt64(max(0, values.fileSize ?? 0))
        let walSize = UInt64(max(0, walValues?.fileSize ?? 0))
        let modifiedAt = [values.contentModificationDate, walValues?.contentModificationDate]
            .compactMap { $0 }
            .max()?
            .timeIntervalSinceReferenceDate
        return (
            UsageAnalyticsFileIdentity(
                volumeIdentifier: (attributes?[.systemNumber] as? NSNumber)?.uint64Value,
                fileIdentifier: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
            ),
            mainSize + walSize,
            modifiedAt
        )
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
