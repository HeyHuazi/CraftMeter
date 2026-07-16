import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 UsageAnalyticsEventStore 构建完整 staging generation，并管理 active SQLite/manifest/sidecar 文件。
 * [OUTPUT]: 对外提供绑定 source fingerprint 的完整 generation 原子发布、匹配 active store 安全打开、损坏隔离和派生 analytics 文件重置。
 * [POS]: Services analytics 生命周期边界；partial/stale backfill 永不成为 production-readable active index，且不承担 source ingest 细节。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsIndexLifecycleManager: @unchecked Sendable {
    struct Manifest: Codable, Equatable, Sendable {
        var schemaVersion: Int
        var generationID: UUID
        var completedAt: Date
        var sourceFingerprint: UsageAnalyticsSourceFingerprint
    }

    enum LifecycleError: Error, Equatable {
        case incompleteGeneration
        case staleGeneration
        case publishFailed
    }

    private static let manifestSchemaVersion = 2
    private let activeDatabaseURL: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let queue = DispatchQueue(
        label: "com.heyhuazi.craftmeter.analytics-index-lifecycle",
        qos: .utility
    )

    init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        let root = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CraftMeter", isDirectory: true)
        activeDatabaseURL = root.appendingPathComponent("usage_analytics_events.sqlite")
        manifestURL = root.appendingPathComponent("usage_analytics_events_manifest.json")
    }

    var databaseURL: URL { activeDatabaseURL }

    func publishCompleteGeneration(
        sourceFingerprint: UsageAnalyticsSourceFingerprint,
        build: (UsageAnalyticsEventStore) throws -> Void
    ) throws -> Manifest {
        try queue.sync {
            try fileManager.createDirectory(
                at: activeDatabaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let generationID = UUID()
            let stagingURL = activeDatabaseURL.deletingLastPathComponent()
                .appendingPathComponent("usage_analytics_events.\(generationID.uuidString).staging.sqlite")
            defer { removeSQLiteFamily(at: stagingURL) }

            do {
                let stagingStore = try UsageAnalyticsEventStore(databaseURL: stagingURL)
                try build(stagingStore)
            } catch {
                throw error
            }

            let manifest = Manifest(
                schemaVersion: Self.manifestSchemaVersion,
                generationID: generationID,
                completedAt: nowProvider(),
                sourceFingerprint: sourceFingerprint
            )
            let manifestData = try JSONEncoder().encode(manifest)
            let stagingManifestURL = manifestURL.appendingPathExtension("staging")
            try manifestData.write(to: stagingManifestURL, options: .atomic)

            do {
                try replaceActiveDatabase(with: stagingURL)
                if fileManager.fileExists(atPath: manifestURL.path) {
                    _ = try fileManager.replaceItemAt(manifestURL, withItemAt: stagingManifestURL)
                } else {
                    try fileManager.moveItem(at: stagingManifestURL, to: manifestURL)
                }
            } catch {
                try? fileManager.removeItem(at: stagingManifestURL)
                throw LifecycleError.publishFailed
            }
            return manifest
        }
    }

    func openCompleteStore(
        matching sourceFingerprint: UsageAnalyticsSourceFingerprint? = nil
    ) throws -> UsageAnalyticsEventStore {
        try queue.sync {
            guard let manifest = loadManifest(),
                  manifest.schemaVersion == Self.manifestSchemaVersion,
                  fileManager.fileExists(atPath: activeDatabaseURL.path) else {
                throw LifecycleError.incompleteGeneration
            }
            if let sourceFingerprint,
               manifest.sourceFingerprint != sourceFingerprint {
                throw LifecycleError.staleGeneration
            }
            do {
                return try UsageAnalyticsEventStore(databaseURL: activeDatabaseURL)
            } catch {
                quarantineActiveIndex()
                throw error
            }
        }
    }

    func completeManifest() -> Manifest? {
        queue.sync { loadManifest() }
    }

    func resetDerivedAnalyticsFiles() {
        queue.sync {
            removeSQLiteFamily(at: activeDatabaseURL)
            try? fileManager.removeItem(at: manifestURL)
            let root = activeDatabaseURL.deletingLastPathComponent()
            for name in ["usage_analytics_cache.json", "usage_analytics_cache_manifest.json"] {
                try? fileManager.removeItem(at: root.appendingPathComponent(name))
            }
            guard let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { return }
            for url in contents where url.lastPathComponent.hasPrefix("usage_analytics_events.")
                && (url.lastPathComponent.contains(".staging.")
                    || url.lastPathComponent.contains(".corrupt.")) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func replaceActiveDatabase(with stagingURL: URL) throws {
        removeSQLiteSidecars(at: activeDatabaseURL)
        if fileManager.fileExists(atPath: activeDatabaseURL.path) {
            _ = try fileManager.replaceItemAt(activeDatabaseURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: activeDatabaseURL)
        }
        removeSQLiteSidecars(at: activeDatabaseURL)
    }

    private func quarantineActiveIndex() {
        let suffix = String(Int(nowProvider().timeIntervalSince1970))
        let quarantineURL = activeDatabaseURL.deletingLastPathComponent()
            .appendingPathComponent("usage_analytics_events.corrupt.\(suffix).sqlite")
        removeSQLiteSidecars(at: activeDatabaseURL)
        if fileManager.fileExists(atPath: activeDatabaseURL.path) {
            try? fileManager.moveItem(at: activeDatabaseURL, to: quarantineURL)
        }
        try? fileManager.removeItem(at: manifestURL)
    }

    private func loadManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    private func removeSQLiteFamily(at databaseURL: URL) {
        try? fileManager.removeItem(at: databaseURL)
        removeSQLiteSidecars(at: databaseURL)
    }

    private func removeSQLiteSidecars(at databaseURL: URL) {
        try? fileManager.removeItem(at: URL(fileURLWithPath: "\(databaseURL.path)-wal"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: "\(databaseURL.path)-shm"))
    }
}
