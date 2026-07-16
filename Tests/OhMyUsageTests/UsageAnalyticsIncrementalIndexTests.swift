import Foundation
import OhMyUsageApplication
import SQLite3
@testable import OhMyUsage
import XCTest

/**
 * [INPUT]: 构造临时 JSONL 与 SQLite 派生事实库，模拟 append、partial tail、truncate 和事务失败。
 * [OUTPUT]: 验证 cursor reader、event store 原子性、无状态/有状态/CCSwitch source parity、changed-file replacement 与隐私 sentinel 不落盘。
 * [POS]: OhMyUsageTests 批次 C0-C3 回归守卫；生产 Repository 仍使用 legacy scanner，本组只验证 shadow index。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsIncrementalIndexTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CraftMeterIncrementalIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        databaseURL = temporaryDirectory.appendingPathComponent("usage_analytics_events.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCursorReaderCommitsOnlyCompleteLinesAndResumesPartialTailOnce() throws {
        let file = temporaryDirectory.appendingPathComponent("session.jsonl")
        try Data("one\ntwo\npartial".utf8).write(to: file)
        let reader = UsageAnalyticsJSONLCursorReader(chunkSize: 3, maxLineBytes: 64)

        let first = try reader.readCompleteLines(at: file, from: 0)
        XCTAssertEqual(first.lines, ["one", "two"])
        XCTAssertEqual(first.committedOffset, 8)
        XCTAssertTrue(first.hasIncompleteTail)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("-done\nthree\n".utf8))
        try handle.close()

        let second = try reader.readCompleteLines(at: file, from: first.committedOffset)
        XCTAssertEqual(second.lines, ["partial-done", "three"])
        XCTAssertFalse(second.hasIncompleteTail)
        XCTAssertEqual(second.committedOffset, try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init))
    }

    func testCursorReaderDropsOversizedLineAndKeepsFollowingLine() throws {
        let file = temporaryDirectory.appendingPathComponent("oversized.jsonl")
        try Data((String(repeating: "x", count: 80) + "\nok\n").utf8).write(to: file)
        let result = try UsageAnalyticsJSONLCursorReader(chunkSize: 7, maxLineBytes: 32)
            .readCompleteLines(at: file, from: 0)

        XCTAssertEqual(result.lines, ["ok"])
        XCTAssertEqual(result.oversizedLineCount, 1)
        XCTAssertFalse(result.hasIncompleteTail)
    }

    func testEventStoreCommitsCursorAndFactsTogetherAndReplacesOneFileOnly() throws {
        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let pathA = temporaryDirectory.appendingPathComponent("a.jsonl").path
        let pathB = temporaryDirectory.appendingPathComponent("b.jsonl").path
        try store.commitFileIngest(
            cursor: cursor(path: pathA, size: 10, offset: 10),
            records: [record(requestID: "a1", tokens: 10)],
            replaceExistingFileRecords: true
        )
        try store.commitFileIngest(
            cursor: cursor(path: pathB, size: 10, offset: 10),
            records: [record(requestID: "b1", tokens: 20)],
            replaceExistingFileRecords: true
        )
        try store.commitFileIngest(
            cursor: cursor(path: pathA, size: 12, offset: 12),
            records: [record(requestID: "a2", tokens: 30)],
            replaceExistingFileRecords: true
        )

        let records = try store.records()
        XCTAssertEqual(Set(records.map(\.requestID)), ["a2", "b1"])
        XCTAssertEqual(records.reduce(0) { $0 + $1.totals.totalTokens }, 50)
        XCTAssertEqual(try store.cursor(source: .claude, normalizedPath: pathA)?.committedOffset, 12)
    }

    func testEventStoreRollsBackFactsWhenCursorWriteFails() throws {
        enum InjectedFailure: Error { case beforeCursor }
        let store = try UsageAnalyticsEventStore(
            databaseURL: databaseURL,
            beforeCursorCommit: { throw InjectedFailure.beforeCursor }
        )
        let path = temporaryDirectory.appendingPathComponent("rollback.jsonl").path

        XCTAssertThrowsError(try store.commitFileIngest(
            cursor: cursor(path: path, size: 1, offset: 1),
            records: [record(requestID: "must-rollback", tokens: 99)],
            replaceExistingFileRecords: true
        ))
        XCTAssertTrue(try store.records().isEmpty)
        XCTAssertNil(try store.cursor(source: .claude, normalizedPath: path))
    }

    func testGeminiShadowIndexMatchesLegacyScannerAndDoesNotPersistPrivateContent() throws {
        let root = temporaryDirectory.appendingPathComponent("gemini", isDirectory: true)
        let chats = root.appendingPathComponent("workspace/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let file = chats.appendingPathComponent("session.jsonl")
        let privateSentinel = "PRIVATE_RESPONSE_MUST_NOT_SURVIVE_INDEX"
        let line = """
        {"type":"assistant","timestamp":"2026-07-10T16:00:00.000Z","uuid":"request-1","model":"model-x","cwd":"/tmp/MyProject","usageMetadata":{"promptTokenCount":100,"cachedContentTokenCount":30,"candidatesTokenCount":50,"thoughtsTokenCount":20},"content":"\(privateSentinel)"}
        """
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatelessJSONLIndexer(store: store)
        let diagnostics = try indexer.ingest(.init(
            source: .gemini,
            roots: [root.path],
            includeFile: { $0.pathExtension.lowercased() == "jsonl" && $0.pathComponents.contains("chats") },
            parserSchema: 1
        ))
        let indexed = try store.records(sources: [.gemini])
        let legacy = ExtendedLocalUsageScanner(rootOverrides: [.gemini: root.path])
            .records(source: .gemini, since: .distantPast)

        XCTAssertEqual(indexed, legacy)
        XCTAssertEqual(diagnostics.emittedRecordCount, 1)
        XCTAssertEqual(diagnostics.rebuiltFileCount, 1)
        XCTAssertFalse(try databaseContains(privateSentinel))
    }

    func testClaudeShadowIndexMatchesLegacyAndAppendReadsOnlyNewBytes() throws {
        let root = temporaryDirectory.appendingPathComponent("claude-projects", isDirectory: true)
        let file = root.appendingPathComponent("workspace/session.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let firstLine = claudeLine(messageID: "m1", timestamp: "2026-07-10T16:00:00Z", input: 10, output: 5)
        try (firstLine + "\n").write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatelessJSONLIndexer(store: store)
        let configuration = UsageAnalyticsStatelessJSONLIndexer.SourceConfiguration(
            source: .claude,
            roots: [root.path],
            includeFile: { $0.pathExtension.lowercased() == "jsonl" },
            parserSchema: 1
        )
        let first = try indexer.ingest(configuration)
        let initialSize = UInt64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)

        let secondLine = claudeLine(messageID: "m2", timestamp: "2026-07-10T16:05:00Z", input: 3, output: 2)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((secondLine + "\n").utf8))
        try handle.close()
        let second = try indexer.ingest(configuration)

        let indexed = try store.records(sources: [.claude])
        let legacyEvents = try ClaudeLocalUsageService(defaultClaudeRootPath: root.path)
            .fetchEvents(since: .distantPast)
        let legacyTokens = legacyEvents.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(indexed.reduce(0) { $0 + $1.totals.totalTokens }, legacyTokens)
        XCTAssertEqual(indexed.count, legacyEvents.count)
        XCTAssertEqual(first.bytesRead, initialSize)
        XCTAssertEqual(second.bytesRead, UInt64((secondLine + "\n").utf8.count))
        XCTAssertEqual(second.rebuiltFileCount, 0)
    }

    func testSameSizeRewriteRebuildsOnlyChangedFile() throws {
        let root = temporaryDirectory.appendingPathComponent("rewrite", isDirectory: true)
        let chats = root.appendingPathComponent("workspace/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let file = chats.appendingPathComponent("session.jsonl")
        let first = "{\"type\":\"assistant\",\"timestamp\":\"2026-07-10T16:00:00Z\",\"uuid\":\"request-a\",\"model\":\"model-x\",\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5}}\n"
        let second = first.replacingOccurrences(of: "request-a", with: "request-b")
        XCTAssertEqual(first.utf8.count, second.utf8.count)
        try first.write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatelessJSONLIndexer(store: store)
        let configuration = UsageAnalyticsStatelessJSONLIndexer.SourceConfiguration(
            source: .gemini,
            roots: [root.path],
            includeFile: { $0.pathExtension.lowercased() == "jsonl" },
            parserSchema: 1
        )
        _ = try indexer.ingest(configuration)
        try second.write(to: file, atomically: true, encoding: .utf8)
        let diagnostics = try indexer.ingest(configuration)

        XCTAssertEqual(try store.records(sources: [.gemini]).map(\.requestID), ["request-b"])
        XCTAssertEqual(diagnostics.rebuiltFileCount, 1)
    }

    func testClaudeDuplicateSignatureAcrossFilesMatchesLegacyBestEvent() throws {
        let root = temporaryDirectory.appendingPathComponent("claude-duplicates", isDirectory: true)
        let firstFile = root.appendingPathComponent("workspace-a/first.jsonl")
        let secondFile = root.appendingPathComponent("workspace-b/second.jsonl")
        try FileManager.default.createDirectory(at: firstFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (claudeLine(messageID: "same", timestamp: "2026-07-10T16:00:00Z", input: 10, output: 5) + "\n")
            .write(to: firstFile, atomically: true, encoding: .utf8)
        try (claudeLine(messageID: "same", timestamp: "2026-07-10T16:05:00Z", input: 10, output: 7) + "\n")
            .write(to: secondFile, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatelessJSONLIndexer(store: store)
        _ = try indexer.ingest(.init(
            source: .claude,
            roots: [root.path],
            includeFile: { $0.pathExtension.lowercased() == "jsonl" },
            parserSchema: 1
        ))

        let indexed = try store.records(sources: [.claude])
        let legacy = try ClaudeLocalUsageService(defaultClaudeRootPath: root.path).fetchEvents(since: .distantPast)
        XCTAssertEqual(indexed.count, 1)
        XCTAssertEqual(legacy.count, 1)
        XCTAssertEqual(indexed.first?.totals.totalTokens, legacy.first?.totalTokens)
        XCTAssertEqual(indexed.first?.eventAt, legacy.first?.eventAt)
    }

    func testCodexCheckpointMatchesLegacyAndAppendReadsOnlyNewSnapshot() throws {
        let root = temporaryDirectory.appendingPathComponent("codex", isDirectory: true)
        let file = root.appendingPathComponent("sessions/2026/07/16/rollout.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = jsonLine([
            "timestamp": "2026-07-16T15:00:00Z",
            "type": "turn_context",
            "payload": ["model": "gpt-5.6"]
        ])
        let firstUsage = codexTotalLine(timestamp: "2026-07-16T15:01:00Z", input: 100, output: 20)
        try ([context, firstUsage].joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatefulJSONLIndexer(store: store)
        let configuration = UsageAnalyticsStatefulJSONLIndexer.SourceConfiguration(
            source: .codex,
            roots: [root.appendingPathComponent("sessions").path],
            includeFile: { $0.pathExtension.lowercased() == "jsonl" },
            parserSchema: 1
        )
        let first = try indexer.ingest(configuration)
        let secondUsage = codexTotalLine(timestamp: "2026-07-16T15:02:00Z", input: 130, output: 30)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((secondUsage + "\n").utf8))
        try handle.close()
        let second = try indexer.ingest(configuration)

        let indexed = try store.records(sources: [.codex])
        let legacy = CodexSessionTokenEventScanner.parse(filePath: file.standardizedFileURL.path)
        XCTAssertEqual(indexed.map(\.totals.totalTokens), legacy.map(\.totalTokens))
        XCTAssertEqual(indexed.map(\.eventAt), legacy.map(\.eventAt))
        XCTAssertEqual(indexed.map(\.modelID), legacy.map(\.modelID))
        XCTAssertEqual(first.emittedRecordCount, 1)
        XCTAssertEqual(second.emittedRecordCount, 1)
        XCTAssertEqual(second.bytesRead, UInt64((secondUsage + "\n").utf8.count))
        XCTAssertEqual(second.rebuiltFileCount, 0)
        XCTAssertNotNil(try store.cursor(source: .codex, normalizedPath: file.path)?.checkpoint)
    }

    func testKimiCheckpointMatchesLegacyAndAppendUsesPreviousSnapshot() throws {
        let root = temporaryDirectory.appendingPathComponent("kimi", isDirectory: true)
        let file = root.appendingPathComponent("tenant/session-a/wire.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let firstLine = kimiLine(timestamp: 1_784_214_000, input: 100, output: 20, messageID: "m1")
        try (firstLine + "\n").write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsStatefulJSONLIndexer(store: store)
        let configuration = UsageAnalyticsStatefulJSONLIndexer.SourceConfiguration(
            source: .kimi,
            roots: [root.path],
            includeFile: { $0.lastPathComponent == "wire.jsonl" },
            parserSchema: 1
        )
        _ = try indexer.ingest(configuration)
        let secondLine = kimiLine(timestamp: 1_784_214_060, input: 130, output: 25, messageID: "m2")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((secondLine + "\n").utf8))
        try handle.close()
        let diagnostics = try indexer.ingest(configuration)

        let indexed = try store.records(sources: [.kimi])
        let legacyEvents = try KimiLocalUsageService(defaultSessionsRootPath: root.path)
            .fetchEvents(sessionsRootPath: root.path, since: .distantPast)
        XCTAssertEqual(indexed.map(\.requestID), legacyEvents.map(\.signature))
        XCTAssertEqual(indexed.map(\.totals.totalTokens), legacyEvents.map(\.totalTokens))
        XCTAssertEqual(diagnostics.bytesRead, UInt64((secondLine + "\n").utf8.count))
        XCTAssertEqual(indexed.last?.totals.inputTokens, 30)
        XCTAssertEqual(indexed.last?.totals.outputTokens, 5)
    }

    func testCraftChangedFileReplacementMatchesLegacyAndDropsRemovedFacets() throws {
        let root = temporaryDirectory.appendingPathComponent("craft", isDirectory: true)
        let file = root.appendingPathComponent("workspace/sessions/session-1/session.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let privateSentinel = "PRIVATE_TOOL_RESULT_MUST_NOT_ENTER_EVENT_DB"
        let initial = """
        {"id":"session-1","model":"claude-opus","createdAt":1784214000000,"workingDirectory":"/tmp/CraftMeter","enabledSourceSlugs":["github"],"tokenUsage":{"inputTokens":100,"outputTokens":20}}
        {"type":"tool","toolName":"mcp__github__search","toolStatus":"completed","toolDisplayMeta":{"category":"research"},"toolResult":"\(privateSentinel)"}
        """
        try (initial + "\n").write(to: file, atomically: true, encoding: .utf8)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsCraftSessionIndexer(store: store)
        _ = try indexer.ingest(root: root.path, parserSchema: 1)
        let legacyInitial = ExtendedLocalUsageScanner(rootOverrides: [.craftAgent: root.path])
            .records(source: .craftAgent, since: .distantPast)
        XCTAssertEqual(try store.records(sources: [.craftAgent]), legacyInitial)
        XCTAssertFalse(try databaseContains(privateSentinel))

        let rewritten = """
        {"id":"session-1","model":"claude-opus","createdAt":1784214000000,"workingDirectory":"/tmp/CraftMeter","enabledSourceSlugs":["notion"],"tokenUsage":{"inputTokens":140,"outputTokens":30}}
        """
        try (rewritten + "\n").write(to: file, atomically: true, encoding: .utf8)
        let diagnostics = try indexer.ingest(root: root.path, parserSchema: 1)
        let indexed = try store.records(sources: [.craftAgent])
        let legacyRewritten = ExtendedLocalUsageScanner(rootOverrides: [.craftAgent: root.path])
            .records(source: .craftAgent, since: .distantPast)

        XCTAssertEqual(indexed, legacyRewritten)
        XCTAssertEqual(diagnostics.rebuiltFileCount, 1)
        XCTAssertEqual(indexed.count, 1)
        XCTAssertFalse(indexed[0].facets.contains { $0.value == "github" })
        XCTAssertTrue(indexed[0].facets.contains { $0.value == "notion" })
    }

    func testCCSwitchInitialIndexMatchesLegacyReader() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("cc-switch.db")
        try createCCSwitchDatabase(at: sourceURL)
        let proxyAt = Date(timeIntervalSince1970: 1_784_214_000)
        try executeSQLite(sourceURL, """
            INSERT INTO providers (id, app_type, name) VALUES ('relay-a', 'codex', 'Relay A');
            INSERT INTO proxy_request_logs VALUES
              ('proxy-1', 'relay-a', 'codex', 'gpt-5.6', 100, 30, 20, 5, 200, \(Int(proxyAt.timeIntervalSince1970)), NULL),
              ('session-1', '_codex_session', 'codex', 'gpt-5.5', 50, 10, 5, 0, 500, \(Int(proxyAt.timeIntervalSince1970 + 60)), 'session');
            INSERT INTO usage_daily_rollups VALUES
              ('2026-07-15', 'claude', 'relay-a', 'claude-sonnet', 4, 3, 400, 100, 50, 10);
            """)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsCCSwitchIndexer(store: store)
        let now = Date(timeIntervalSince1970: 1_784_300_000)
        let diagnostics = try indexer.ingest(.init(
            databasePath: sourceURL.path,
            parserSchema: 1,
            initialSince: Date(timeIntervalSince1970: 1_784_000_000),
            now: now
        ))
        let indexed = try store.records(sources: [.ccSwitch])
        let legacy = CCSwitchUsageLogReader(databasePath: sourceURL.path)
            .readUsageLogs(since: Date(timeIntervalSince1970: 1_784_000_000), until: now.addingTimeInterval(1))
            .records.map(\.analyticsRecord)
            .sorted { $0.requestID < $1.requestID }

        XCTAssertEqual(indexed.sorted { $0.requestID < $1.requestID }, legacy)
        XCTAssertEqual(diagnostics.rebuiltFileCount, 1)
        XCTAssertEqual(Set(indexed.map(\.source)), [.ccswitchProxy, .ccswitchSession, .ccswitchDailyRollup])
    }

    func testCCSwitchOverlapUpsertsCorrectedProxyAndReplacesBoundedRollups() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("cc-switch-overlap.db")
        try createCCSwitchDatabase(at: sourceURL)
        let firstNow = Date(timeIntervalSince1970: 1_784_300_000)
        let firstProxyAt = firstNow.addingTimeInterval(-120)
        try executeSQLite(sourceURL, """
            INSERT INTO proxy_request_logs VALUES
              ('proxy-1', 'relay-a', 'codex', 'gpt-5.6', 100, 20, 0, 0, 200, \(Int(firstProxyAt.timeIntervalSince1970)), NULL);
            INSERT INTO usage_daily_rollups VALUES
              ('2026-07-12', 'codex', 'relay-a', 'old-model', 2, 2, 20, 10, 0, 0),
              ('2026-07-16', 'codex', 'relay-a', 'gpt-5.6', 3, 3, 30, 10, 0, 0);
            """)

        let store = try UsageAnalyticsEventStore(databaseURL: databaseURL)
        let indexer = UsageAnalyticsCCSwitchIndexer(store: store)
        let configuration = UsageAnalyticsCCSwitchIndexer.Configuration(
            databasePath: sourceURL.path,
            parserSchema: 1,
            initialSince: Date(timeIntervalSince1970: 1_783_000_000),
            overlap: 10 * 60,
            rollupRefreshDays: 3,
            now: firstNow
        )
        _ = try indexer.ingest(configuration)

        let secondProxyAt = firstNow.addingTimeInterval(60)
        try executeSQLite(sourceURL, """
            UPDATE proxy_request_logs SET input_tokens = 140, output_tokens = 30 WHERE request_id = 'proxy-1';
            INSERT INTO proxy_request_logs VALUES
              ('proxy-2', 'relay-a', 'codex', 'gpt-5.6', 50, 10, 0, 0, 200, \(Int(secondProxyAt.timeIntervalSince1970)), NULL);
            DELETE FROM usage_daily_rollups WHERE date = '2026-07-16';
            INSERT INTO usage_daily_rollups VALUES
              ('2026-07-17', 'codex', 'relay-a', 'gpt-5.6', 5, 5, 70, 20, 0, 0);
            """)
        var secondConfiguration = configuration
        secondConfiguration.now = firstNow.addingTimeInterval(120)
        let diagnostics = try indexer.ingest(secondConfiguration)
        let indexed = try store.records(sources: [.ccSwitch])

        XCTAssertEqual(indexed.first { $0.requestID == "proxy-1" }?.totals.inputTokens, 140)
        XCTAssertNotNil(indexed.first { $0.requestID == "proxy-2" })
        XCTAssertNotNil(indexed.first { $0.requestID.contains("2026-07-12") }, "rollups older than bounded refresh remain indexed")
        XCTAssertNil(indexed.first { $0.requestID.contains("2026-07-16") })
        XCTAssertNotNil(indexed.first { $0.requestID.contains("2026-07-17") })
        XCTAssertEqual(diagnostics.rebuiltFileCount, 0)
        XCTAssertNotNil(try store.cursor(source: .ccSwitch, normalizedPath: sourceURL.path)?.checkpoint)
    }

    private func cursor(path: String, size: UInt64, offset: UInt64) -> UsageAnalyticsSourceFileCursor {
        UsageAnalyticsSourceFileCursor(
            source: .claude,
            normalizedPath: path,
            identity: UsageAnalyticsFileIdentity(volumeIdentifier: 1, fileIdentifier: 2),
            observedSize: size,
            observedModificationTime: 1,
            committedOffset: offset,
            parserSchema: 1
        )
    }

    private func record(requestID: String, tokens: Int) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: Date(timeIntervalSince1970: 1_783_700_100),
            appType: "claude",
            providerID: "local",
            providerName: "Local",
            modelID: "model",
            requestID: requestID,
            totals: UsageMetricTotals(requestCount: 1, successCount: 1, inputTokens: tokens)
        )
    }

    private func claudeLine(messageID: String, timestamp: String, input: Int, output: Int) -> String {
        let payload: [String: Any] = [
            "timestamp": timestamp,
            "sessionId": "session",
            "uuid": "uuid-\(messageID)",
            "type": "assistant",
            "message": [
                "id": messageID,
                "model": "claude-sonnet",
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func codexTotalLine(timestamp: String, input: Int, output: Int) -> String {
        jsonLine([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": input,
                        "cached_input_tokens": 0,
                        "output_tokens": output,
                        "reasoning_output_tokens": 0,
                        "total_tokens": input + output
                    ]
                ]
            ]
        ])
    }

    private func kimiLine(timestamp: Double, input: Int, output: Int, messageID: String) -> String {
        jsonLine([
            "timestamp": timestamp,
            "message": [
                "type": "StatusUpdate",
                "payload": [
                    "model": "kimi-k2",
                    "message_id": messageID,
                    "token_usage": [
                        "input_other": input,
                        "output": output,
                        "input_cache_read": 0,
                        "input_cache_creation": 0
                    ]
                ]
            ]
        ])
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func createCCSwitchDatabase(at url: URL) throws {
        try executeSQLite(url, """
            CREATE TABLE providers (id TEXT PRIMARY KEY, app_type TEXT, name TEXT);
            CREATE TABLE proxy_request_logs (
                request_id TEXT PRIMARY KEY,
                provider_id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                model TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER,
                status_code INTEGER,
                created_at INTEGER,
                data_source TEXT
            );
            CREATE TABLE usage_daily_rollups (
                date TEXT,
                app_type TEXT,
                provider_id TEXT,
                model TEXT,
                request_count INTEGER,
                success_count INTEGER,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER
            );
            """)
    }

    private func executeSQLite(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "UsageAnalyticsIncrementalIndexTests", code: 10)
        }
        defer { sqlite3_close(database) }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "SQLite failure"
            sqlite3_free(error)
            throw NSError(domain: "UsageAnalyticsIncrementalIndexTests", code: 11, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func databaseContains(_ sentinel: String) throws -> Bool {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            if data.range(of: Data(sentinel.utf8)) != nil { return true }
        }
        return false
    }
}
