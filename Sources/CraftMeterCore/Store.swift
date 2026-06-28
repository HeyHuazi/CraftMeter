// ============================================================================
// L3 CONTRACT — Store.swift
//
// INPUT:  ~/.craft-agent/workspaces/*/sessions/*/session.jsonl (filesystem)
// OUTPUT: ScanResult (records + malformed count), cache.json 落盘
// POS:    唯一 IO 边界 · 上承 Domain 下接 UI/CLI
//         Store 是不可变 struct (Sendable)；refresh() 是单一入口
// ============================================================================

import Foundation

public struct ScanResult: Sendable {
    public let records: [SessionRecord]
    public let malformedCount: Int
}

private struct CacheEnvelope: Codable {
    let cacheVersion: Int
    let stats: Stats
}

public struct Store: Sendable {
    public static let currentCacheVersion: Int = 4

    public let workspacesRoot: URL
    public let cacheDir: URL
    public let cacheFile: URL

    public init(homeDir: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.workspacesRoot = homeDir
            .appendingPathComponent(".craft-agent", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
        self.cacheDir = homeDir.appendingPathComponent(".craft-agent-token-stats", isDirectory: true)
        self.cacheFile = cacheDir.appendingPathComponent("cache.json", isDirectory: false)
    }

    public func refresh(scannedBy: String = "app") -> Stats {
        let result = scanRoot()
        let stats = aggregate(records: result.records)
            .with(malformedCount: result.malformedCount, scannedBy: scannedBy)
        writeCache(stats)
        return stats
    }

    public func scanRoot() -> ScanResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: workspacesRoot.path) else {
            return ScanResult(records: [], malformedCount: 0)
        }
        var records: [SessionRecord] = []
        var malformed = 0
        for fileURL in enumerateSessionJSONL(root: workspacesRoot) {
            switch parseFirstLine(at: fileURL) {
            case .record(let r): records.append(r)
            case .malformed:     malformed += 1
            case .empty:         break
            }
        }
        return ScanResult(records: records, malformedCount: malformed)
    }

    public func readCache() -> Stats? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data) else {
            return nil   // legacy v1 bare-Stats JSON or corrupt → force rescan
        }
        guard envelope.cacheVersion == Store.currentCacheVersion else { return nil }
        return envelope.stats
    }

    public func writeCache(_ stats: Stats) {
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let envelope = CacheEnvelope(cacheVersion: Store.currentCacheVersion, stats: stats)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(to: cacheFile, options: .atomic)
    }
}

// MARK: - Parsing result (avoids throwing across boundary)

private enum FirstLineResult {
    case record(SessionRecord)
    case malformed
    case empty
}

private func parseFirstLine(at url: URL) -> FirstLineResult {
    guard let bytes = readFirstLine(url) else { return .empty }
    if let rec = SessionRecord.from(firstLine: bytes) { return .record(rec) }
    return .malformed
}

// MARK: - Filesystem walk: root/workspaces/*/sessions/*/session.jsonl

private func enumerateSessionJSONL(root: URL) -> [URL] {
    let fm = FileManager.default
    guard let workspaceDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
        return []
    }
    var results: [URL] = []
    results.reserveCapacity(256)
    for wsDir in workspaceDirs {
        let sessionsDir = wsDir.appendingPathComponent("sessions", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sessionsDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
        guard let sessionDirs = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else { continue }
        for sessionDir in sessionDirs {
            let jsonl = sessionDir.appendingPathComponent("session.jsonl", isDirectory: false)
            if fm.fileExists(atPath: jsonl.path) {
                results.append(jsonl)
            }
        }
    }
    return results
}

// MARK: - Read first line, cap at 64KB (metadata is ~1-2KB in practice)

private func readFirstLine(_ url: URL) -> [UInt8]? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let maxBytes = 65536
    let chunkSize = 8192
    var buffer: [UInt8] = []
    buffer.reserveCapacity(chunkSize)
    while buffer.count < maxBytes {
        let chunk = handle.readData(ofLength: chunkSize)
        if chunk.isEmpty { break }
        buffer.append(contentsOf: chunk)
        if let newlineIdx = buffer.firstIndex(of: 0x0A) {
            return Array(buffer[0..<newlineIdx])
        }
    }
    return buffer.isEmpty ? nil : buffer
}
