import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖统一 JSONL cursor reader、事务 event store 与 Claude/Gemini/Qwen 统计字段格式。
 * [OUTPUT]: 对外提供无状态 JSONL source 的 shadow ingest、按文件 append/rebuild 与 source 级读取诊断。
 * [POS]: Services analytics 增量索引 adapter；首批只写派生事实库，不切换 Repository 生产读取路径。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class UsageAnalyticsStatelessJSONLIndexer {
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
            let result = try reader.readCompleteLines(at: file.url, from: startOffset)
            let parsed = parse(
                lines: result.lines,
                source: configuration.source,
                fileURL: file.url,
                roots: configuration.roots
            )
            let cursor = UsageAnalyticsSourceFileCursor(
                source: configuration.source,
                normalizedPath: path,
                identity: file.identity,
                observedSize: file.size,
                observedModificationTime: file.modifiedAtRef,
                committedOffset: result.committedOffset,
                parserSchema: configuration.parserSchema,
                lastCompleteEventAt: parsed.compactMap(\.eventAt).max()
                    ?? existing?.lastCompleteEventAt
            )
            try store.commitFileIngest(
                cursor: cursor,
                records: parsed,
                replaceExistingFileRecords: requiresRebuild
            )

            diagnostics.bytesRead += result.bytesRead
            diagnostics.parsedLineCount += result.lines.count
            diagnostics.emittedRecordCount += parsed.count
            diagnostics.oversizedLineCount += result.oversizedLineCount
            diagnostics.invalidLineCount += result.invalidUTF8LineCount
            if requiresRebuild { diagnostics.rebuiltFileCount += 1 }
        }
        return diagnostics
    }

    private func discoverFiles(_ configuration: SourceConfiguration) -> [FileSnapshot] {
        var snapshots: [FileSnapshot] = []
        for rawRoot in configuration.roots {
            let root = URL(fileURLWithPath: (rawRoot as NSString).expandingTildeInPath).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if configuration.includeFile(root), let snapshot = fileSnapshot(root) {
                    snapshots.append(snapshot)
                }
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                    .volumeIdentifierKey, .fileResourceIdentifierKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where configuration.includeFile(url) {
                if let snapshot = fileSnapshot(url) { snapshots.append(snapshot) }
            }
        }
        return snapshots.sorted { $0.url.path < $1.url.path }
    }

    private func fileSnapshot(_ url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .volumeIdentifierKey, .fileResourceIdentifierKey
        ]), values.isRegularFile == true else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let device = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        return FileSnapshot(
            url: url,
            identity: UsageAnalyticsFileIdentity(
                volumeIdentifier: device,
                fileIdentifier: inode
            ),
            size: UInt64(max(0, values.fileSize ?? 0)),
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
        )
    }

    private func parse(
        lines: [String],
        source: UsageAnalyticsIndexedSource,
        fileURL: URL,
        roots: [String]
    ) -> [UsageAnalyticsRecord] {
        switch source {
        case .claude:
            return lines.compactMap(parseClaudeLine)
        case .gemini, .qwen:
            return lines.compactMap { parseGeminiLikeLine(
                $0,
                source: source,
                fileURL: fileURL,
                roots: roots
            ) }
        case .codex, .kimi, .craftAgent, .ccSwitch:
            return []
        }
    }

    private func parseClaudeLine(_ line: String) -> UsageAnalyticsRecord? {
        guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else { return nil }
        guard line.contains("\"usage\""), let root = Self.object(line),
              Self.string(root["type"]) == "assistant",
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let eventAt = Self.date(root["timestamp"]) else { return nil }

        let input = Self.int(usage["input_tokens"])
        let output = Self.int(usage["output_tokens"])
            + Self.int(usage["reasoning_output_tokens"])
            + Self.int(usage["tool_tokens"])
        let cacheRead = Self.int(usage["cache_read_input_tokens"])
        let cacheWrite = Self.int(usage["cache_creation_input_tokens"])
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }
        let sessionID = Self.string(root["sessionId"]) ?? "unknown-session"
        let requestID = Self.string(message["id"])
            ?? Self.string(root["uuid"])
            ?? Self.string(root["parentUuid"])
            ?? "hash=\(Self.stableHash(line))"

        return UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: eventAt,
            appType: "claude",
            providerID: "ohmyusage-claude-local",
            providerName: "Claude",
            modelID: Self.string(message["model"]) ?? "unknown",
            sessionID: sessionID,
            requestID: "claude|\(sessionID)|\(requestID)",
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite,
                unpricedRequestCount: 1
            )
        )
    }

    private func parseGeminiLikeLine(
        _ line: String,
        source: UsageAnalyticsIndexedSource,
        fileURL: URL,
        roots: [String]
    ) -> UsageAnalyticsRecord? {
        guard line.contains("\"usageMetadata\""), let object = Self.object(line),
              Self.string(object["type"]) == "assistant",
              let eventAt = Self.date(object["timestamp"]),
              let usage = object["usageMetadata"] as? [String: Any] else { return nil }

        let cacheRead = Self.int(usage["cachedContentTokenCount"])
        let reasoning = Self.int(usage["thoughtsTokenCount"])
        let input = max(0, Self.int(usage["promptTokenCount"]) - cacheRead)
        let output = max(0, Self.int(usage["candidatesTokenCount"]) - reasoning)
        guard input + cacheRead + output + reasoning > 0 else { return nil }

        let sessionID = fileURL.deletingPathExtension().lastPathComponent
        let isGemini = source == .gemini
        let clientID = isGemini ? "gemini-cli" : "qwen-code"
        let clientName = isGemini ? "Gemini CLI" : "Qwen Code"
        let requestID = Self.string(object["uuid"])
            ?? "\(clientID):\(sessionID):\(Int(eventAt.timeIntervalSince1970 * 1000))"
        let project = Self.projectName(
            cwd: Self.string(object["cwd"]),
            fileURL: fileURL,
            roots: roots
        )

        return UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: eventAt,
            appType: clientID,
            clientID: clientID,
            clientName: clientName,
            providerID: "craftmeter-\(clientID)-local",
            providerName: clientName,
            providerCategory: isGemini ? "Google" : "Qwen",
            modelID: Self.string(object["model"]) ?? "unknown",
            projectID: project,
            projectName: project,
            sessionID: sessionID,
            requestID: requestID,
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                reasoningTokens: reasoning,
                unpricedRequestCount: 1
            )
        )
    }

    private static func projectName(cwd: String?, fileURL: URL, roots: [String]) -> String {
        if let cwd {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty { return name }
        }
        let pathComponents = fileURL.standardizedFileURL.pathComponents
        for rawRoot in roots {
            let rootComponents = URL(fileURLWithPath: rawRoot).standardizedFileURL.pathComponents
            guard pathComponents.starts(with: rootComponents) else { continue }
            if let relative = pathComponents.dropFirst(rootComponents.count).first, !relative.isEmpty {
                return relative
            }
        }
        return "unknown"
    }

    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let raw: String?
        if let string = value as? String { raw = string }
        else if let number = value as? NSNumber { raw = number.stringValue }
        else { raw = nil }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let number = Double(value) { return max(0, Int(number.rounded())) }
        return 0
    }

    private static func date(_ value: Any?) -> Date? {
        if let value = value as? NSNumber {
            let raw = value.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        guard let raw = string(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
