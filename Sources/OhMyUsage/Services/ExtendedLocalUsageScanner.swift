import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: Reads only statistical fields from Gemini CLI, Qwen Code, and Craft Agents JSONL logs.
 * [OUTPUT]: Produces normalized UsageAnalyticsRecord facts without prompt, response, attachment, or tool-result content.
 * [POS]: OhMyUsage Services local ingestion adapter for CraftMeter-specific analytics sources.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

final class ExtendedLocalUsageScanner {
    enum Source: String, CaseIterable, Sendable {
        case gemini
        case qwen
        case craftAgent

        var rootPath: String {
            switch self {
            case .gemini: return "\(NSHomeDirectory())/.gemini/tmp"
            case .qwen: return "\(NSHomeDirectory())/.qwen/tmp"
            case .craftAgent: return "\(NSHomeDirectory())/.craft-agent/workspaces"
            }
        }
    }

    private let fileManager: FileManager
    private let rootOverrides: [Source: String]

    init(
        fileManager: FileManager = .default,
        rootOverrides: [Source: String] = [:]
    ) {
        self.fileManager = fileManager
        self.rootOverrides = rootOverrides
    }

    func records(source: Source, since: Date) -> [UsageAnalyticsRecord] {
        let root = rootOverrides[source] ?? source.rootPath
        let files = matchingFiles(source: source, root: root, since: since)
        return files.flatMap { file in
            switch source {
            case .gemini, .qwen:
                return parseGeminiLikeFile(path: file.path, root: root, source: source, since: since)
            case .craftAgent:
                return parseCraftSession(path: file.path, since: since).map { [$0] } ?? []
            }
        }
    }

    func fingerprint(source: Source) -> UsageAnalyticsFileFingerprint {
        let root = rootOverrides[source] ?? source.rootPath
        let files = matchingFiles(source: source, root: root, since: .distantPast)
        return UsageAnalyticsFileFingerprint(
            roots: [URL(fileURLWithPath: root).standardizedFileURL.path],
            fileCount: files.count,
            totalSize: files.reduce(0) { $0 + $1.size },
            latestModificationTime: files.compactMap(\.modifiedAt).max()
        )
    }

    private struct FileSnapshot {
        var path: String
        var size: UInt64
        var modifiedAt: Date?
    }

    private func matchingFiles(source: Source, root: String, since: Date) -> [FileSnapshot] {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [FileSnapshot] = []
        for case let url as URL in enumerator {
            guard matches(source: source, url: url),
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                  ),
                  values.isRegularFile == true else {
                continue
            }
            if let modifiedAt = values.contentModificationDate, modifiedAt < since {
                continue
            }
            files.append(FileSnapshot(
                path: url.path,
                size: UInt64(max(0, values.fileSize ?? 0)),
                modifiedAt: values.contentModificationDate
            ))
        }
        return files.sorted { $0.path < $1.path }
    }

    private func matches(source: Source, url: URL) -> Bool {
        switch source {
        case .gemini, .qwen:
            return url.pathExtension.lowercased() == "jsonl"
                && url.pathComponents.contains("chats")
        case .craftAgent:
            return url.lastPathComponent == "session.jsonl"
        }
    }

    private func parseGeminiLikeFile(
        path: String,
        root: String,
        source: Source,
        since: Date
    ) -> [UsageAnalyticsRecord] {
        var records: [UsageAnalyticsRecord] = []
        scanJSONLLines(path: path) { line in
            guard line.contains("\"usageMetadata\"") else { return }
            guard let object = Self.object(from: line),
                  Self.string(object["type"]) == "assistant",
                  let eventAt = Self.date(object["timestamp"]),
                  eventAt >= since,
                  let usage = object["usageMetadata"] as? [String: Any] else {
                return
            }

            let cacheRead = Self.int(usage["cachedContentTokenCount"])
            let reasoning = Self.int(usage["thoughtsTokenCount"])
            let input = max(0, Self.int(usage["promptTokenCount"]) - cacheRead)
            let output = max(0, Self.int(usage["candidatesTokenCount"]) - reasoning)
            guard input + cacheRead + output + reasoning > 0 else { return }

            let sessionID = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let clientID = source == .gemini ? "gemini-cli" : "qwen-code"
            let clientName = source == .gemini ? "Gemini CLI" : "Qwen Code"
            let requestID = Self.string(object["uuid"])
                ?? "\(clientID):\(sessionID):\(Int(eventAt.timeIntervalSince1970 * 1000))"
            let project = Self.projectName(
                cwd: Self.string(object["cwd"]),
                filePath: path,
                root: root
            )

            records.append(UsageAnalyticsRecord(
                source: .ohMyUsageLocal,
                eventAt: eventAt,
                appType: clientID,
                clientID: clientID,
                clientName: clientName,
                providerID: "craftmeter-\(clientID)-local",
                providerName: clientName,
                providerCategory: source == .gemini ? "Google" : "Qwen",
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
            ))
        }
        return records
    }

    private func parseCraftSession(path: String, since: Date) -> UsageAnalyticsRecord? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first,
              let meta = Self.object(from: String(first)),
              let sessionID = Self.string(meta["id"]),
              let eventAt = Self.date(meta["createdAt"]),
              eventAt >= since else {
            return nil
        }

        let usage = meta["tokenUsage"] as? [String: Any] ?? [:]
        var facets = sessionFacets(meta: meta)
        for line in lines.dropFirst() {
            guard let event = Self.object(from: String(line)),
                  Self.string(event["type"]) == "tool" else {
                continue
            }
            facets.append(contentsOf: toolFacets(event: event))
        }

        let project = Self.projectName(
            cwd: Self.string(meta["workingDirectory"]) ?? Self.string(meta["cwd"]),
            filePath: path,
            root: rootOverrides[.craftAgent] ?? Source.craftAgent.rootPath
        )
        let costCents = Self.double(meta["costCents"])
        return UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: eventAt,
            appType: "craft-agent",
            clientID: "craft-agent",
            clientName: "Craft Agents",
            providerID: "craftmeter-craft-agent-local",
            providerName: "Craft Agents",
            providerCategory: "Craft",
            modelID: Self.string(meta["model"]) ?? "unknown",
            projectID: project,
            projectName: project,
            sessionID: sessionID,
            requestID: sessionID,
            totals: UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: Self.int(usage["inputTokens"]),
                outputTokens: Self.int(usage["outputTokens"]),
                cacheReadTokens: Self.int(usage["cacheReadTokens"]),
                cacheWriteTokens: Self.int(usage["cacheCreationTokens"]),
                reasoningTokens: Self.int(usage["reasoningTokens"]),
                estimatedCostUSD: costCents / 100,
                reportedCostRequestCount: costCents > 0 ? 1 : 0,
                unpricedRequestCount: costCents > 0 ? 0 : 1
            ),
            facets: facets
        )
    }

    private func sessionFacets(meta: [String: Any]) -> [UsageAnalyticsFacetEvent] {
        var facets: [UsageAnalyticsFacetEvent] = []
        if let values = meta["enabledSourceSlugs"] as? [Any] {
            facets += values.compactMap(Self.string).map {
                UsageAnalyticsFacetEvent(kind: .craftSource, value: $0)
            }
        }
        if let permission = Self.string(meta["permissionMode"]) {
            facets.append(UsageAnalyticsFacetEvent(kind: .permissionMode, value: permission))
        }
        if let thinking = Self.string(meta["thinkingLevel"]) {
            facets.append(UsageAnalyticsFacetEvent(kind: .thinkingLevel, value: thinking))
        }
        return facets
    }

    private func toolFacets(event: [String: Any]) -> [UsageAnalyticsFacetEvent] {
        let name = Self.string(event["toolName"]) ?? "unknown"
        let displayName = Self.string(event["toolDisplayName"]) ?? name
        let status = Self.string(event["toolStatus"]) ?? "unknown"
        let isError = (event["isError"] as? Bool) ?? false
        let meta = event["toolDisplayMeta"] as? [String: Any]
        let category = Self.string(meta?["category"]) ?? "unknown"
        var facets = [
            UsageAnalyticsFacetEvent(
                kind: .craftTool,
                value: name,
                displayName: displayName,
                status: status,
                isError: isError
            ),
            UsageAnalyticsFacetEvent(
                kind: .craftCategory,
                value: category,
                status: status,
                isError: isError
            ),
            UsageAnalyticsFacetEvent(kind: .craftStatus, value: status)
        ]
        if name.hasPrefix("mcp__") {
            let server = name.dropFirst("mcp__".count).split(separator: "__").first.map(String.init) ?? ""
            if !server.isEmpty {
                facets.append(UsageAnalyticsFacetEvent(kind: .mcpServer, value: server))
            }
        } else if name == "Skill",
                  let input = event["toolInput"] as? [String: Any],
                  let skill = Self.string(input["skill"]) {
            facets.append(UsageAnalyticsFacetEvent(kind: .skill, value: skill))
        }
        return facets
    }

    private func scanJSONLLines(path: String, onLine: (String) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        var buffer = Data()
        let newline = Data([0x0A])
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            while let range = buffer.range(of: newline) {
                let line = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                if line.count <= RuntimeDiagnosticsLimits.jsonlMaxLineBytes,
                   let text = String(data: line, encoding: .utf8) {
                    onLine(text)
                }
            }
            if buffer.count > RuntimeDiagnosticsLimits.jsonlMaxLineBytes {
                buffer.removeAll(keepingCapacity: false)
            }
        }
        if !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8) {
            onLine(text)
        }
    }

    private static func object(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let number = Double(value) { return max(0, Int(number.rounded())) }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.doubleValue) }
        if let value = value as? String, let number = Double(value) { return max(0, number) }
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

    private static func projectName(cwd: String?, filePath: String, root: String) -> String {
        if let cwd {
            let value = URL(fileURLWithPath: cwd).lastPathComponent
            if !value.isEmpty { return value }
        }
        let file = URL(fileURLWithPath: filePath).standardizedFileURL
        let root = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        let relative = file.pathComponents.dropFirst(root.count).first
        return relative.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
    }
}
