import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖统一 JSONL cursor reader、事务 event store、Codex/Kimi 累计快照格式与 Craft 单文件 scanner。
 * [OUTPUT]: 对外提供 Codex/Kimi 安全 checkpoint 增量 ingest 和 Craft changed-file replacement shadow ingest。
 * [POS]: Services analytics 批次 C2 source adapters；复用 legacy 解析口径，不接管 Repository 生产读取路径。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsStatefulJSONLIndexer {
    struct SourceConfiguration: Sendable {
        var source: UsageAnalyticsIndexedSource
        var roots: [String]
        var includeFile: @Sendable (URL) -> Bool
        var parserSchema: Int
    }

    private struct FileSnapshot: Sendable {
        var url: URL
        var identity: UsageAnalyticsFileIdentity
        var size: UInt64
        var modifiedAtRef: TimeInterval?
    }

    private struct TokenCheckpoint: Codable, Equatable, Sendable {
        var currentModel: String?
        var previousTotalTokens: Int
        var inputTokens: Int
        var outputTokens: Int
        var cacheReadTokens: Int
        var cacheWriteTokens: Int

        static let empty = TokenCheckpoint(
            currentModel: nil,
            previousTotalTokens: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
    }

    private let fileManager: FileManager
    private let reader: UsageAnalyticsJSONLCursorReader
    private let store: UsageAnalyticsEventStore

    init(
        store: UsageAnalyticsEventStore,
        fileManager: FileManager = .default,
        reader: UsageAnalyticsJSONLCursorReader = UsageAnalyticsJSONLCursorReader()
    ) {
        self.store = store
        self.fileManager = fileManager
        self.reader = reader
    }

    func ingest(_ configuration: SourceConfiguration) throws -> UsageAnalyticsIngestDiagnostics {
        precondition(configuration.source == .codex || configuration.source == .kimi)
        let files = discoverFiles(configuration)
        var diagnostics = UsageAnalyticsIngestDiagnostics(
            source: configuration.source,
            discoveredFileCount: files.count
        )

        for file in files {
            let path = file.url.standardizedFileURL.path
            let existing = try store.cursor(source: configuration.source, normalizedPath: path)
            if let existing,
               existing.identity == file.identity,
               existing.parserSchema == configuration.parserSchema,
               existing.observedSize == file.size,
               existing.observedModificationTime == file.modifiedAtRef {
                continue
            }

            diagnostics.changedFileCount += 1
            let requiresRebuild = existing == nil
                || existing?.identity != file.identity
                || existing?.parserSchema != configuration.parserSchema
                || file.size <= (existing?.observedSize ?? 0)
            let startOffset = requiresRebuild ? 0 : existing?.committedOffset ?? 0
            let initialCheckpoint = requiresRebuild ? .empty : decodeCheckpoint(existing?.checkpoint)
            let result = try reader.readCompleteLines(at: file.url, from: startOffset)
            let parsed: ([UsageAnalyticsRecord], TokenCheckpoint, Int)
            switch configuration.source {
            case .codex:
                parsed = parseCodex(lines: result.lines, fileURL: file.url, checkpoint: initialCheckpoint)
            case .kimi:
                parsed = parseKimi(lines: result.lines, fileURL: file.url, checkpoint: initialCheckpoint)
            default:
                preconditionFailure("Unsupported stateful source")
            }
            let cursor = UsageAnalyticsSourceFileCursor(
                source: configuration.source,
                normalizedPath: path,
                identity: file.identity,
                observedSize: file.size,
                observedModificationTime: file.modifiedAtRef,
                committedOffset: result.committedOffset,
                parserSchema: configuration.parserSchema,
                checkpoint: try JSONEncoder().encode(parsed.1),
                lastCompleteEventAt: parsed.0.map(\.eventAt).max() ?? existing?.lastCompleteEventAt
            )
            try store.commitFileIngest(
                cursor: cursor,
                records: parsed.0,
                replaceExistingFileRecords: requiresRebuild
            )

            diagnostics.bytesRead += result.bytesRead
            diagnostics.parsedLineCount += result.lines.count
            diagnostics.emittedRecordCount += parsed.0.count
            diagnostics.oversizedLineCount += result.oversizedLineCount
            diagnostics.invalidLineCount += result.invalidUTF8LineCount + parsed.2
            if requiresRebuild { diagnostics.rebuiltFileCount += 1 }
        }
        return diagnostics
    }

    private func parseCodex(
        lines: [String],
        fileURL: URL,
        checkpoint: TokenCheckpoint
    ) -> ([UsageAnalyticsRecord], TokenCheckpoint, Int) {
        var checkpoint = checkpoint
        var records: [UsageAnalyticsRecord] = []
        var invalidLines = 0

        for line in lines {
            guard line.contains("\"type\"") else { continue }
            guard let root = Self.object(line), let type = Self.string(root["type"]) else {
                invalidLines += 1
                continue
            }
            if type == "turn_context" {
                let payload = root["payload"] as? [String: Any]
                let info = payload?["info"] as? [String: Any]
                checkpoint.currentModel = CodexLocalUsageEventParser.normalizedModelID(
                    Self.string(payload?["model"]) ?? Self.string(info?["model"])
                )
                continue
            }
            guard type == "event_msg",
                  let payload = root["payload"] as? [String: Any],
                  Self.string(payload["type"]) == "token_count",
                  let timestamp = Self.string(root["timestamp"]),
                  let eventAt = CodexLocalUsageEventParser.parseISODate(timestamp) else { continue }

            let info = payload["info"] as? [String: Any]
            let model = CodexLocalUsageEventParser.normalizedModelID(
                Self.string(info?["model"])
                    ?? Self.string(info?["model_name"])
                    ?? Self.string(payload["model"])
                    ?? checkpoint.currentModel
            )
            let previous = Self.tokenComponents(checkpoint)
            let delta: TokenComponents
            let current: TokenComponents
            if let usage = info?["total_token_usage"] as? [String: Any],
               let snapshot = CodexLocalUsageEventParser.sessionTokenComponents(from: usage) {
                guard snapshot.totalTokens >= checkpoint.previousTotalTokens else { continue }
                let totalDelta = snapshot.totalTokens - checkpoint.previousTotalTokens
                delta = snapshot.delta(from: previous, fallbackTotal: totalDelta)
                current = snapshot
            } else if let usage = info?["last_token_usage"] as? [String: Any],
                      let last = CodexLocalUsageEventParser.sessionTokenComponents(from: usage) {
                delta = last
                current = previous.adding(last)
            } else { continue }

            checkpoint.currentModel = model
            checkpoint.previousTotalTokens = current.totalTokens
            checkpoint.inputTokens = current.inputTokens
            checkpoint.outputTokens = current.outputTokens
            checkpoint.cacheReadTokens = current.cacheReadTokens
            checkpoint.cacheWriteTokens = current.cacheWriteTokens
            guard delta.totalTokens > 0 else { continue }
            let signature = "session|\(fileURL.path)|\(timestamp)|\(delta.totalTokens)|\(model)"
            records.append(Self.localRecord(
                source: .codex,
                eventAt: eventAt,
                modelID: model,
                requestID: signature,
                input: delta.inputTokens,
                output: delta.outputTokens,
                cacheRead: delta.cacheReadTokens,
                cacheWrite: delta.cacheWriteTokens,
                fallbackTotal: delta.totalTokens
            ))
        }
        return (records, checkpoint, invalidLines)
    }

    private func parseKimi(
        lines: [String],
        fileURL: URL,
        checkpoint: TokenCheckpoint
    ) -> ([UsageAnalyticsRecord], TokenCheckpoint, Int) {
        var checkpoint = checkpoint
        var records: [UsageAnalyticsRecord] = []
        var invalidLines = 0
        let sessionID = fileURL.deletingLastPathComponent().lastPathComponent

        for line in lines {
            guard line.contains("\"StatusUpdate\""), line.contains("\"token_usage\"") else { continue }
            guard let root = Self.object(line),
                  let eventAt = Self.timestampDate(root["timestamp"]),
                  let message = root["message"] as? [String: Any],
                  Self.string(message["type"]) == "StatusUpdate",
                  let payload = message["payload"] as? [String: Any],
                  let usage = payload["token_usage"] as? [String: Any] else {
                invalidLines += 1
                continue
            }
            let snapshot = Self.kimiComponents(usage)
            let snapshotTotal = snapshot.inputTokens + snapshot.outputTokens
                + snapshot.cacheReadTokens + snapshot.cacheWriteTokens
            guard snapshotTotal >= checkpoint.previousTotalTokens else { continue }
            let deltaTotal = snapshotTotal - checkpoint.previousTotalTokens
            let previous = Self.localComponents(checkpoint)
            let delta = snapshot.delta(from: previous, fallbackTotal: deltaTotal)
            checkpoint.currentModel = Self.string(payload["model"])
                ?? Self.string(message["model"])
                ?? checkpoint.currentModel
            checkpoint.previousTotalTokens = snapshotTotal
            checkpoint.inputTokens = snapshot.inputTokens
            checkpoint.outputTokens = snapshot.outputTokens
            checkpoint.cacheReadTokens = snapshot.cacheReadTokens
            checkpoint.cacheWriteTokens = snapshot.cacheWriteTokens
            guard deltaTotal > 0 else { continue }
            let model = checkpoint.currentModel ?? "unknown"
            let messageID = Self.string(payload["message_id"]) ?? "unknown-message"
            let signature = "kimi|\(sessionID)|\(messageID)|\(Int(eventAt.timeIntervalSince1970))|\(snapshotTotal)"
            records.append(Self.localRecord(
                source: .kimi,
                eventAt: eventAt,
                modelID: model,
                requestID: signature,
                input: delta.inputTokens,
                output: delta.outputTokens,
                cacheRead: delta.cacheReadTokens,
                cacheWrite: delta.cacheWriteTokens,
                fallbackTotal: deltaTotal
            ))
        }
        return (records, checkpoint, invalidLines)
    }

    private func decodeCheckpoint(_ data: Data?) -> TokenCheckpoint {
        guard let data,
              let checkpoint = try? JSONDecoder().decode(TokenCheckpoint.self, from: data) else {
            return .empty
        }
        return checkpoint
    }

    private func discoverFiles(_ configuration: SourceConfiguration) -> [FileSnapshot] {
        var snapshots: [FileSnapshot] = []
        for rawRoot in configuration.roots {
            let root = URL(fileURLWithPath: (rawRoot as NSString).expandingTildeInPath).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if configuration.includeFile(root), let snapshot = fileSnapshot(root) { snapshots.append(snapshot) }
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where configuration.includeFile(url) {
                if let snapshot = fileSnapshot(url) { snapshots.append(snapshot) }
            }
        }
        return snapshots.sorted { $0.url.path < $1.url.path }
    }

    private func fileSnapshot(_ url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return FileSnapshot(
            url: url,
            identity: UsageAnalyticsFileIdentity(
                volumeIdentifier: (attributes?[.systemNumber] as? NSNumber)?.uint64Value,
                fileIdentifier: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
            ),
            size: UInt64(max(0, values.fileSize ?? 0)),
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
        )
    }

    private static func localRecord(
        source: UsageAnalyticsIndexedSource,
        eventAt: Date,
        modelID: String,
        requestID: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int,
        fallbackTotal: Int
    ) -> UsageAnalyticsRecord {
        let appType = source == .codex ? "codex" : "kimi"
        let name = source == .codex ? "Codex" : "Kimi"
        let componentTotal = input + output + cacheRead + cacheWrite
        return UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: eventAt,
            appType: appType,
            providerID: "ohmyusage-\(appType)-local",
            providerName: name,
            modelID: modelID,
            requestID: requestID,
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: input,
                outputTokens: componentTotal > 0 ? output : fallbackTotal,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite,
                unpricedRequestCount: 1
            )
        )
    }

    private static func tokenComponents(_ checkpoint: TokenCheckpoint) -> TokenComponents {
        TokenComponents(
            inputTokens: checkpoint.inputTokens,
            outputTokens: checkpoint.outputTokens,
            cacheReadTokens: checkpoint.cacheReadTokens,
            cacheWriteTokens: checkpoint.cacheWriteTokens,
            totalTokens: checkpoint.previousTotalTokens
        )
    }

    private static func localComponents(_ checkpoint: TokenCheckpoint) -> LocalUsageTokenComponents {
        LocalUsageTokenComponents(
            inputTokens: checkpoint.inputTokens,
            outputTokens: checkpoint.outputTokens,
            cacheReadTokens: checkpoint.cacheReadTokens,
            cacheWriteTokens: checkpoint.cacheWriteTokens
        )
    }

    private static func kimiComponents(_ usage: [String: Any]) -> LocalUsageTokenComponents {
        let components = LocalUsageTokenComponents(
            inputTokens: firstInt(usage, keys: ["input_other", "input_tokens", "input"]),
            outputTokens: firstInt(usage, keys: ["output", "output_tokens"]),
            cacheReadTokens: firstInt(usage, keys: ["input_cache_read", "cache_read_input_tokens"]),
            cacheWriteTokens: firstInt(usage, keys: ["input_cache_creation", "cache_creation_input_tokens"])
        )
        if components.totalTokens > 0 { return components }
        let total = usage.values.reduce(0) { $0 + max(0, int($1)) }
        return LocalUsageTokenComponents(outputTokens: total)
    }

    private static func firstInt(_ object: [String: Any], keys: [String]) -> Int {
        for key in keys where object[key] != nil { return int(object[key]) }
        return 0
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let raw = value as? String ?? (value as? NSNumber)?.stringValue
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let parsed = Double(value) { return max(0, Int(parsed.rounded())) }
        return 0
    }

    private static func timestampDate(_ value: Any?) -> Date? {
        if let value = value as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        if let value = value as? String, let parsed = Double(value) { return Date(timeIntervalSince1970: parsed) }
        return nil
    }
}

final class UsageAnalyticsCraftSessionIndexer {
    private let fileManager: FileManager
    private let store: UsageAnalyticsEventStore

    init(store: UsageAnalyticsEventStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func ingest(root: String, parserSchema: Int) throws -> UsageAnalyticsIngestDiagnostics {
        let expandedRoot = URL(fileURLWithPath: (root as NSString).expandingTildeInPath).standardizedFileURL
        let files = discoverFiles(root: expandedRoot)
        let scanner = ExtendedLocalUsageScanner(rootOverrides: [.craftAgent: expandedRoot.path])
        var diagnostics = UsageAnalyticsIngestDiagnostics(
            source: .craftAgent,
            discoveredFileCount: files.count
        )

        for file in files {
            let path = file.url.path
            let existing = try store.cursor(source: .craftAgent, normalizedPath: path)
            if let existing,
               existing.identity == file.identity,
               existing.parserSchema == parserSchema,
               existing.observedSize == file.size,
               existing.observedModificationTime == file.modifiedAtRef { continue }

            diagnostics.changedFileCount += 1
            diagnostics.rebuiltFileCount += 1
            diagnostics.bytesRead += file.size
            let record = scanner.recordForCraftSession(path: path, root: expandedRoot.path, since: .distantPast)
            let cursor = UsageAnalyticsSourceFileCursor(
                source: .craftAgent,
                normalizedPath: path,
                identity: file.identity,
                observedSize: file.size,
                observedModificationTime: file.modifiedAtRef,
                committedOffset: file.size,
                parserSchema: parserSchema,
                lastCompleteEventAt: record?.eventAt ?? existing?.lastCompleteEventAt
            )
            try store.commitFileIngest(
                cursor: cursor,
                records: record.map { [$0] } ?? [],
                replaceExistingFileRecords: true
            )
            diagnostics.emittedRecordCount += record == nil ? 0 : 1
        }
        return diagnostics
    }

    private struct FileSnapshot {
        var url: URL
        var identity: UsageAnalyticsFileIdentity
        var size: UInt64
        var modifiedAtRef: TimeInterval?
    }

    private func discoverFiles(root: URL) -> [FileSnapshot] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [FileSnapshot] = []
        for case let url as URL in enumerator where url.lastPathComponent == "session.jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            files.append(FileSnapshot(
                url: url,
                identity: UsageAnalyticsFileIdentity(
                    volumeIdentifier: (attributes?[.systemNumber] as? NSNumber)?.uint64Value,
                    fileIdentifier: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
                ),
                size: UInt64(max(0, values.fileSize ?? 0)),
                modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
            ))
        }
        return files.sorted { $0.url.path < $1.url.path }
    }
}
