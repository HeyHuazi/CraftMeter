import Foundation
import OhMyUsageApplication
@testable import OhMyUsage
import XCTest

/**
 * [INPUT]: 构造临时 active/staging SQLite generations、manifest、sidecars 与 snapshot cache 文件。
 * [OUTPUT]: 验证 partial backfill 不发布、完整 generation 原子替换、corruption quarantine 和派生文件 reset。
 * [POS]: OhMyUsageTests C4 index lifecycle 回归守卫；保护 cached UI 不被半索引或损坏索引覆盖。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsIndexLifecycleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CraftMeterIndexLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedGenerationNeverReplacesCompleteActiveIndex() throws {
        enum InjectedFailure: Error { case backfill }
        let manager = UsageAnalyticsIndexLifecycleManager(baseDirectoryURL: root)
        _ = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 1)) { store in
            try self.seed(store, requestID: "complete", tokens: 10)
        }

        XCTAssertThrowsError(try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 2)) { store in
            try self.seed(store, requestID: "partial", tokens: 20)
            throw InjectedFailure.backfill
        })

        let active = try manager.openCompleteStore(matching: fingerprint(seed: 1))
        XCTAssertEqual(try active.records().map(\.requestID), ["complete"])
        XCTAssertNotNil(manager.completeManifest())
        XCTAssertFalse(try directoryNames().contains { $0.contains("staging") })
    }

    func testCompleteGenerationAtomicallyReplacesPreviousFacts() throws {
        let manager = UsageAnalyticsIndexLifecycleManager(baseDirectoryURL: root)
        let first = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 1)) { store in
            try self.seed(store, requestID: "old", tokens: 10)
        }
        let second = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 2)) { store in
            try self.seed(store, requestID: "new", tokens: 30)
        }

        XCTAssertNotEqual(first.generationID, second.generationID)
        XCTAssertEqual(try manager.openCompleteStore(matching: fingerprint(seed: 2)).records().map(\.requestID), ["new"])
        XCTAssertEqual(manager.completeManifest(), second)
        XCTAssertEqual(second.sourceFingerprint, fingerprint(seed: 2))
    }

    func testCompleteGenerationRejectsMismatchedSourceFingerprint() throws {
        let manager = UsageAnalyticsIndexLifecycleManager(baseDirectoryURL: root)
        _ = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 1)) { store in
            try self.seed(store, requestID: "complete", tokens: 10)
        }

        XCTAssertThrowsError(try manager.openCompleteStore(matching: fingerprint(seed: 2))) { error in
            XCTAssertEqual(error as? UsageAnalyticsIndexLifecycleManager.LifecycleError, .staleGeneration)
        }
        XCTAssertEqual(try manager.openCompleteStore(matching: fingerprint(seed: 1)).records().count, 1)
    }

    func testCorruptActiveIndexIsQuarantinedAndManifestRemoved() throws {
        let now = Date(timeIntervalSince1970: 1_784_300_000)
        let manager = UsageAnalyticsIndexLifecycleManager(baseDirectoryURL: root, nowProvider: { now })
        _ = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 1)) { store in
            try self.seed(store, requestID: "valid", tokens: 10)
        }
        try Data("not-sqlite".utf8).write(to: manager.databaseURL, options: .atomic)

        XCTAssertThrowsError(try manager.openCompleteStore())
        XCTAssertNil(manager.completeManifest())
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.databaseURL.path))
        XCTAssertTrue(try directoryNames().contains("usage_analytics_events.corrupt.1784300000.sqlite"))
    }

    func testResetRemovesEventFamilyManifestSnapshotAndStagingFiles() throws {
        let manager = UsageAnalyticsIndexLifecycleManager(baseDirectoryURL: root)
        _ = try manager.publishCompleteGeneration(sourceFingerprint: fingerprint(seed: 1)) { store in
            try self.seed(store, requestID: "active", tokens: 10)
        }
        let extraNames = [
            "usage_analytics_events.sqlite-wal",
            "usage_analytics_events.sqlite-shm",
            "usage_analytics_events.abcd.staging.sqlite",
            "usage_analytics_events.corrupt.1.sqlite",
            "usage_analytics_cache.json",
            "usage_analytics_cache_manifest.json"
        ]
        for name in extraNames {
            try Data("x".utf8).write(to: root.appendingPathComponent(name))
        }

        manager.resetDerivedAnalyticsFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.databaseURL.path))
        XCTAssertNil(manager.completeManifest())
        XCTAssertFalse(try directoryNames().contains { $0.hasPrefix("usage_analytics_events") })
        XCTAssertFalse(try directoryNames().contains { $0.hasPrefix("usage_analytics_cache") })
    }

    private func fingerprint(seed: Int) -> UsageAnalyticsSourceFingerprint {
        let value = UsageAnalyticsFileFingerprint(
            roots: ["/tmp/source-\(seed)"],
            fileCount: seed,
            totalSize: UInt64(seed),
            latestModificationTime: Date(timeIntervalSince1970: TimeInterval(seed))
        )
        return UsageAnalyticsSourceFingerprint(
            ccSwitch: value,
            codex: value,
            claude: value,
            kimi: value,
            gemini: value,
            qwen: value,
            craftAgent: value
        )
    }

    private func seed(_ store: UsageAnalyticsEventStore, requestID: String, tokens: Int) throws {
        let path = root.appendingPathComponent("source-\(requestID).jsonl").path
        let cursor = UsageAnalyticsSourceFileCursor(
            source: .claude,
            normalizedPath: path,
            identity: UsageAnalyticsFileIdentity(volumeIdentifier: 1, fileIdentifier: 2),
            observedSize: 1,
            observedModificationTime: 1,
            committedOffset: 1,
            parserSchema: 1
        )
        let record = UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: Date(timeIntervalSince1970: 1_784_200_000),
            appType: "claude",
            providerID: "local",
            providerName: "Local",
            modelID: "model",
            requestID: requestID,
            totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: tokens)
        )
        try store.commitFileIngest(cursor: cursor, records: [record], replaceExistingFileRecords: true)
    }

    private func directoryNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
    }
}
