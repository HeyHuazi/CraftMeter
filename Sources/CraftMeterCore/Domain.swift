// ============================================================================
// L3 CONTRACT — Domain.swift
//
// INPUT:  session.jsonl 第一行字节流（JSON），schema 见 ~/.craft-agent/docs
// OUTPUT: SessionRecord（规范化记录）+ Stats（聚合视图，含 heatmapDays 365 天网格）
// POS:    纯数据层 · 无 IO · 无副作用
//         Store.swift 唯一调用方 · UI/CLI 不直接访问
// ============================================================================

import Foundation

// MARK: - SessionRecord

public struct SessionRecord: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let workspace: String
    public let workspaceRootPath: String
    public let model: String
    public let llmConnection: String
    public let createdAt: Int64
    public let labels: [String]
    public let sessionStatus: String
    public let messageCount: Int
    public let costCents: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let contextWindow: Int

    // Drill-down detail fields (consumed by SessionDetail overlay)
    public let preview: String
    public let workingDirectory: String
    public let thinkingLevel: String
    public let permissionMode: String
    public let lastUsedAtMs: Int64

    /// Burnt tokens: input + output + cacheCreation.
    /// cacheRead excluded — cache hit is nearly free, same class as proxy costUsd=0.
    public var billableTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens
    }
}

public extension SessionRecord {
    static func from(firstLine line: [UInt8]) -> SessionRecord? {
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode(RawSessionJSON.self, from: Data(line)) else {
            return nil
        }
        return normalized(from: raw)
    }

    static func from(jsonLine: String) -> SessionRecord? {
        let bytes = [UInt8](jsonLine.utf8)
        return from(firstLine: bytes)
    }
}

private func normalized(from raw: RawSessionJSON) -> SessionRecord {
    let wsPath = raw.workspaceRootPath ?? ""
    let tu = raw.tokenUsage
    return SessionRecord(
        id: raw.id,
        name: raw.name?.isEmpty == false ? raw.name! : "Untitled",
        workspace: basename(wsPath),
        workspaceRootPath: wsPath,
        model: raw.model ?? "unknown",
        llmConnection: raw.llmConnection ?? "unknown",
        createdAt: raw.createdAt ?? 0,
        labels: raw.labels ?? [],
        sessionStatus: raw.sessionStatus ?? "unknown",
        messageCount: raw.messageCount ?? 0,
        costCents: cents(fromUSD: tu?.costUsd ?? 0),
        inputTokens: tu?.inputTokens ?? 0,
        outputTokens: tu?.outputTokens ?? 0,
        cacheReadTokens: tu?.cacheReadTokens ?? 0,
        cacheCreationTokens: tu?.cacheCreationTokens ?? 0,
        contextWindow: tu?.contextWindow ?? 0,
        preview: raw.preview ?? "",
        workingDirectory: raw.workingDirectory ?? raw.sdkCwd ?? "",
        thinkingLevel: raw.thinkingLevel ?? "",
        permissionMode: raw.permissionMode ?? "",
        lastUsedAtMs: raw.lastUsedAt ?? 0
    )
}

private func basename(_ path: String) -> String {
    let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
    guard let lastSlash = trimmed.lastIndex(of: "/") else { return trimmed }
    return String(trimmed[trimmed.index(after: lastSlash)...])
}

private func cents(fromUSD usd: Double) -> Int {
    let scaled = usd * 100.0
    return Int((scaled + 0.5).rounded(.down))
}

// MARK: - Raw JSON schema (private mirror of session.jsonl line 1)

private struct RawSessionJSON: Decodable {
    let id: String
    let name: String?
    let workspaceRootPath: String?
    let model: String?
    let llmConnection: String?
    let createdAt: Int64?
    let labels: [String]?
    let sessionStatus: String?
    let messageCount: Int?
    let tokenUsage: TokenUsage?
    let preview: String?
    let workingDirectory: String?
    let sdkCwd: String?
    let thinkingLevel: String?
    let permissionMode: String?
    let lastUsedAt: Int64?

    struct TokenUsage: Decodable {
        let costUsd: Double?
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadTokens: Int?
        let cacheCreationTokens: Int?
        let contextWindow: Int?
    }
}

// MARK: - Aggregated buckets

public struct DayBucket: Codable, Equatable, Sendable {
    public let date: Date
    public let tokens: Int          // burnt (billable) tokens for the day
    public let costCents: Int
}

public struct WorkspaceStat: Codable, Equatable, Sendable, Comparable {
    public let workspace: String
    public let billableTokens: Int
    public let costCents: Int
    public let sessionCount: Int

    public static func < (lhs: WorkspaceStat, rhs: WorkspaceStat) -> Bool {
        lhs.billableTokens == rhs.billableTokens
            ? lhs.workspace < rhs.workspace
            : lhs.billableTokens > rhs.billableTokens
    }
}

// MARK: - Model tier

/// Inference model cost tier derived from model ID string pattern.
/// Used for semantic coloring in UI (red=opus, amber=sonnet, green=haiku) and
/// cost-per-token grouping. Falls back to .other for unrecognized models.
public enum ModelTier: String, Codable, Sendable {
    case opus, sonnet, haiku, other

    public init(_ modelID: String) {
        let id = modelID.lowercased()
        if id.contains("opus") { self = .opus; return }
        if id.contains("sonnet") { self = .sonnet; return }
        if id.contains("haiku") { self = .haiku; return }
        self = .other
    }

    /// Named hue fractions for semantic coloring:
    ///   opus:   0.0   (red family)
    ///   sonnet: 0.12  (amber)
    ///   haiku:  0.33  (green)
    ///   other:  0.6   (blue)
    public var hueFraction: Double {
        switch self {
        case .opus:   return 0.0
        case .sonnet: return 0.12
        case .haiku:  return 0.33
        case .other:  return 0.6
        }
    }
}

// MARK: - ModelStat

public struct ModelStat: Codable, Equatable, Sendable, Comparable {
    public let model: String
    public let billableTokens: Int
    public let costCents: Int
    public let sessionCount: Int
    public let avgTokensPerSession: Int
    public let tier: ModelTier

    public static func < (lhs: ModelStat, rhs: ModelStat) -> Bool {
        lhs.billableTokens == rhs.billableTokens
            ? lhs.model < rhs.model
            : lhs.billableTokens > rhs.billableTokens
    }
}

// MARK: - Stats (final aggregate view consumed by UI/CLI)

public struct Stats: Codable, Equatable, Sendable {
    public let totalCostCents: Int
    public let totalBillableTokens: Int
    public let sessionCount: Int
    public let malformedCount: Int
    public let records: [SessionRecord]
    public let top5ByBillable: [SessionRecord]
    public let dailyBuckets30d: [DayBucket]
    public let heatmapDays: [DayBucket]
    public let workspaceBreakdown: [WorkspaceStat]
    public let modelBreakdown: [ModelStat]
    public let lastScannedAtMs: Int64
    public let scannedBy: String

    public var totalCostUSD: Double { Double(totalCostCents) / 100.0 }
    public var workspaceCount: Int { workspaceBreakdown.count }

        public static let empty = Stats(
        totalCostCents: 0,
        totalBillableTokens: 0,
        sessionCount: 0,
        malformedCount: 0,
        records: [],
        top5ByBillable: [],
        dailyBuckets30d: [],
        heatmapDays: [],
        workspaceBreakdown: [],
        modelBreakdown: [],
        lastScannedAtMs: 0,
        scannedBy: "unknown"
    )

    public func with(malformedCount: Int, scannedBy: String) -> Stats {
        Stats(
            totalCostCents: totalCostCents,
            totalBillableTokens: totalBillableTokens,
            sessionCount: sessionCount,
            malformedCount: malformedCount,
            records: records,
            top5ByBillable: top5ByBillable,
            dailyBuckets30d: dailyBuckets30d,
            heatmapDays: heatmapDays,
            workspaceBreakdown: workspaceBreakdown,
            modelBreakdown: modelBreakdown,
            lastScannedAtMs: lastScannedAtMs,
            scannedBy: scannedBy
        )
    }
}

// MARK: - aggregate() — single pass, pure

public func aggregate(records: [SessionRecord], now: Date = Date()) -> Stats {
    guard !records.isEmpty else { return .empty }

    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: now)
    let cutoffMs = msStartOf(calendarDayBefore(today, days: 364))

    let (totals, wsStats, modelStats, daily) = scanAll(records, cutoffMs: cutoffMs, calendar: cal, today: today)
    let top5 = records.sorted { $0.billableTokens > $1.billableTokens }.prefix(5)
    let dailyArr = build30DayBuckets(from: daily, today: today, calendar: cal)
    let heatmapArr = buildHeatmapBuckets(from: daily, today: today, calendar: cal)

    return Stats(
        totalCostCents: totals.costCents,
        totalBillableTokens: totals.billableTokens,
        sessionCount: records.count,
        malformedCount: 0,
        records: records,
        top5ByBillable: Array(top5),
        dailyBuckets30d: dailyArr,
        heatmapDays: heatmapArr,
        workspaceBreakdown: wsStats,
        modelBreakdown: modelStats,
        lastScannedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
        scannedBy: "unknown"   // Store.refresh overrides via with(scannedBy:)
    )
}

private func scanAll(
    _ records: [SessionRecord],
    cutoffMs: Int64,
    calendar: Calendar,
    today: Date
) -> (Totals, [WorkspaceStat], [ModelStat], [Date: DayAccum]) {
    var totals = Totals()
    var ws: [String: WorkspaceAccum] = [:]
    var models: [String: ModelAccum] = [:]
    var daily: [Date: DayAccum] = [:]

    for r in records {
        totals.billableTokens += r.billableTokens
        totals.costCents += r.costCents
        ws[r.workspace, default: WorkspaceAccum()].add(r)
        models[r.model, default: ModelAccum()].add(r)
        if r.createdAt >= cutoffMs {
            let day = calendar.startOfDay(for: dateFromMs(r.createdAt))
            daily[day, default: DayAccum()].add(r)
        }
    }
    let wsStats = ws.map { (k, v) in
        WorkspaceStat(
            workspace: k,
            billableTokens: v.billableTokens,
            costCents: v.costCents,
            sessionCount: v.sessionCount
        )
    }.sorted()
    let modelStats = models.map { (k, v) in
        ModelStat(
            model: k,
            billableTokens: v.billableTokens,
            costCents: v.costCents,
            sessionCount: v.sessionCount,
            avgTokensPerSession: v.sessionCount > 0 ? v.billableTokens / v.sessionCount : 0,
            tier: ModelTier(k)
        )
    }.sorted()
    return (totals, wsStats, modelStats, daily)
}

private func build30DayBuckets(from daily: [Date: DayAccum], today: Date, calendar: Calendar) -> [DayBucket] {
    var out: [DayBucket] = []
    out.reserveCapacity(30)
    for offset in stride(from: 29, through: 0, by: -1) {
        let day = calendar.date(byAdding: .day, value: -offset, to: today)!
        let a = daily[day] ?? DayAccum()
        out.append(DayBucket(date: day, tokens: a.billableTokens, costCents: a.costCents))
    }
    return out
}

/// 365-day heatmap grid aligned to Sunday-start weeks.
/// Returns a flat array of DayBuckets from the first Sunday in range through today.
private func buildHeatmapBuckets(from daily: [Date: DayAccum], today: Date, calendar: Calendar) -> [DayBucket] {
    let startDate = calendar.date(byAdding: .day, value: -364, to: today)!
    let weekday = calendar.component(.weekday, from: startDate)  // 1=Sun
    let gridStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: startDate)!
    let daysBetween = calendar.dateComponents([.day], from: gridStart, to: today).day!
    var out: [DayBucket] = []
    out.reserveCapacity(daysBetween + 1)
    for offset in 0...daysBetween {
        let day = calendar.date(byAdding: .day, value: offset, to: gridStart)!
        let dayStart = calendar.startOfDay(for: day)
        let a = daily[dayStart] ?? DayAccum()
        out.append(DayBucket(date: dayStart, tokens: a.billableTokens, costCents: a.costCents))
    }
    return out
}

// MARK: - private accumulators

private struct Totals {
    var billableTokens: Int = 0
    var costCents: Int = 0
}

private struct WorkspaceAccum {
    var billableTokens: Int = 0
    var costCents: Int = 0
    var sessionCount: Int = 0

    mutating func add(_ r: SessionRecord) {
        billableTokens += r.billableTokens
        costCents += r.costCents
        sessionCount += 1
    }
}

private struct DayAccum {
    var billableTokens: Int = 0
    var costCents: Int = 0

    mutating func add(_ r: SessionRecord) {
        billableTokens += r.billableTokens
        costCents += r.costCents
    }
}

private struct ModelAccum {
    var billableTokens: Int = 0
    var costCents: Int = 0
    var sessionCount: Int = 0

    mutating func add(_ r: SessionRecord) {
        billableTokens += r.billableTokens
        costCents += r.costCents
        sessionCount += 1
    }
}

// MARK: - date helpers

private func calendarDayBefore(_ date: Date, days: Int) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: date)!
}

private func msStartOf(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func dateFromMs(_ ms: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
}
