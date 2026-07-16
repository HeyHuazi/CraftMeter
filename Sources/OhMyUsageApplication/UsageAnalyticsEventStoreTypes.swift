import Foundation

/**
 * [INPUT]: 接收 Services 层发现的本地 usage 文件身份、解析游标和安全 checkpoint。
 * [OUTPUT]: 对外提供增量读取、事务 ingest、source 状态与性能诊断的纯数据契约。
 * [POS]: OhMyUsageApplication analytics ingestion contract；隔离文件/SQLite 实现与 Repository/Aggregator 语义。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

public enum UsageAnalyticsIndexedSource: String, Codable, CaseIterable, Sendable {
    case claude
    case gemini
    case qwen
    case codex
    case kimi
    case craftAgent
    case ccSwitch
}

public struct UsageAnalyticsFileIdentity: Codable, Equatable, Hashable, Sendable {
    public var volumeIdentifier: UInt64?
    public var fileIdentifier: UInt64?

    public init(volumeIdentifier: UInt64?, fileIdentifier: UInt64?) {
        self.volumeIdentifier = volumeIdentifier
        self.fileIdentifier = fileIdentifier
    }
}

public struct UsageAnalyticsSourceFileCursor: Codable, Equatable, Sendable {
    public var source: UsageAnalyticsIndexedSource
    public var normalizedPath: String
    public var identity: UsageAnalyticsFileIdentity
    public var observedSize: UInt64
    public var observedModificationTime: TimeInterval?
    public var committedOffset: UInt64
    public var parserSchema: Int
    public var checkpoint: Data?
    public var lastCompleteEventAt: Date?

    public init(
        source: UsageAnalyticsIndexedSource,
        normalizedPath: String,
        identity: UsageAnalyticsFileIdentity,
        observedSize: UInt64,
        observedModificationTime: TimeInterval?,
        committedOffset: UInt64,
        parserSchema: Int,
        checkpoint: Data? = nil,
        lastCompleteEventAt: Date? = nil
    ) {
        self.source = source
        self.normalizedPath = normalizedPath
        self.identity = identity
        self.observedSize = observedSize
        self.observedModificationTime = observedModificationTime
        self.committedOffset = committedOffset
        self.parserSchema = parserSchema
        self.checkpoint = checkpoint
        self.lastCompleteEventAt = lastCompleteEventAt
    }
}

public struct UsageAnalyticsJSONLReadResult: Equatable, Sendable {
    public var lines: [String]
    public var committedOffset: UInt64
    public var bytesRead: UInt64
    public var oversizedLineCount: Int
    public var invalidUTF8LineCount: Int
    public var hasIncompleteTail: Bool

    public init(
        lines: [String],
        committedOffset: UInt64,
        bytesRead: UInt64,
        oversizedLineCount: Int,
        invalidUTF8LineCount: Int,
        hasIncompleteTail: Bool
    ) {
        self.lines = lines
        self.committedOffset = committedOffset
        self.bytesRead = bytesRead
        self.oversizedLineCount = oversizedLineCount
        self.invalidUTF8LineCount = invalidUTF8LineCount
        self.hasIncompleteTail = hasIncompleteTail
    }
}

public struct UsageAnalyticsIngestDiagnostics: Equatable, Sendable {
    public var source: UsageAnalyticsIndexedSource
    public var discoveredFileCount: Int
    public var changedFileCount: Int
    public var bytesRead: UInt64
    public var parsedLineCount: Int
    public var emittedRecordCount: Int
    public var rebuiltFileCount: Int
    public var oversizedLineCount: Int
    public var invalidLineCount: Int

    public init(
        source: UsageAnalyticsIndexedSource,
        discoveredFileCount: Int = 0,
        changedFileCount: Int = 0,
        bytesRead: UInt64 = 0,
        parsedLineCount: Int = 0,
        emittedRecordCount: Int = 0,
        rebuiltFileCount: Int = 0,
        oversizedLineCount: Int = 0,
        invalidLineCount: Int = 0
    ) {
        self.source = source
        self.discoveredFileCount = discoveredFileCount
        self.changedFileCount = changedFileCount
        self.bytesRead = bytesRead
        self.parsedLineCount = parsedLineCount
        self.emittedRecordCount = emittedRecordCount
        self.rebuiltFileCount = rebuiltFileCount
        self.oversizedLineCount = oversizedLineCount
        self.invalidLineCount = invalidLineCount
    }
}
