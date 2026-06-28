// ============================================================================
// L3 CONTRACT — main.swift (CLI executable `meter`)
//
// INPUT:  ~/.craft-agent/workspaces/ 现场扫描 + 命令行参数（filter / json）
// OUTPUT: stdout 三段格式化文本（默认）或 JSON (--json)
// POS:    独立可执行 · 无 GUI 依赖 · 复用 Core 的 Store.refresh() + aggregate()
//         退出码 0=成功 1=参数/扫描失败 2=无数据
//         全部参数可选，零参数行为向后兼容（无 filter，文本输出）
// ============================================================================

import Foundation
import CraftMeterCore

// MARK: - CLI entry

let args = CommandLine.arguments

switch parseOptions(Array(args.dropFirst())) {
case .run(let opts):
    run(opts)
case .help:
    exit(0)
case .error:
    exit(1)
}

private func run(_ opts: CLIOptions) -> Never {
    let store = Store()
    let allStats = store.refresh(scannedBy: "cli")
    let filtered = applyFilters(allStats.records, opts: opts)

    guard !filtered.isEmpty else {
        FileHandle.standardError.write("No sessions match the given filters.\n".data(using: .utf8)!)
        exit(2)
    }

    let stats = aggregate(records: filtered)
        .with(malformedCount: allStats.malformedCount, scannedBy: "cli")

    if opts.json {
        print(jsonEncode(stats))
    } else {
        print(render(stats: stats))
    }
    exit(0)
}

// MARK: - Options parsing (no third-party dep — hand-rolled)

struct CLIOptions {
    var workspace: String?
    var model: String?
    var label: String?
    var sinceMs: Int64?
    var json: Bool = false
}

enum ParseResult {
    case run(CLIOptions)
    case help
    case error
}

func parseOptions(_ args: [String]) -> ParseResult {
    var opts = CLIOptions()
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--workspace":
            guard let v = takeValue(args, &i) else { return usageError("--workspace requires a name") }
            opts.workspace = v
        case "--model":
            guard let v = takeValue(args, &i) else { return usageError("--model requires a name") }
            opts.model = v
        case "--label":
            guard let v = takeValue(args, &i) else { return usageError("--label requires a name") }
            opts.label = v
        case "--since":
            guard let v = takeValue(args, &i) else { return usageError("--since requires 7d or YYYY-MM-DD") }
            guard let ms = parseSince(v) else { return usageError("--since expects 7d or YYYY-MM-DD") }
            opts.sinceMs = ms
        case "--json":
            opts.json = true
        case "--help", "-h":
            printHelp()
            return .help
        default:
            return usageError("Unknown option: \(a)")
        }
        i += 1
    }
    return .run(opts)
}

private func takeValue(_ args: [String], _ i: inout Int) -> String? {
    guard i + 1 < args.count else { return nil }
    i += 1
    return args[i]
}

private func parseSince(_ raw: String) -> Int64? {
    if raw.hasSuffix("d"), let days = Int(raw.dropLast()) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return Int64(cutoff.timeIntervalSince1970 * 1000)
    }
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withFullDate]
    if let d = fmt.date(from: raw) {
        return Int64(d.timeIntervalSince1970 * 1000)
    }
    return nil
}

private func usageError(_ msg: String) -> ParseResult {
    FileHandle.standardError.write("\(msg)\n".data(using: .utf8)!)
    printHelp(to: FileHandle.standardError)
    return .error
}

private func printHelp(to fh: FileHandle = FileHandle.standardOutput) {
    let lines = [
        "usage: meter [options]",
        "",
        "  --workspace NAME    Filter by workspace basename",
        "  --model NAME        Filter by model id (e.g. claude-sonnet-4-6)",
        "  --label NAME        Filter by label tag",
        "  --since 7d          Filter sessions from last N days",
        "  --since YYYY-MM-DD  Filter sessions since a specific date",
        "  --json              Emit JSON instead of formatted text",
        "  -h, --help          Show this help",
        ""
    ]
    fh.write(lines.joined(separator: "\n").data(using: .utf8)!)
}

// MARK: - Filter

func applyFilters(_ records: [SessionRecord], opts: CLIOptions) -> [SessionRecord] {
    records.filter { r in
        if let ws = opts.workspace, r.workspace != ws { return false }
        if let m  = opts.model, r.model != m { return false }
        if let l  = opts.label, !r.labels.contains(l) { return false }
        if let cutoff = opts.sinceMs, r.createdAt < cutoff { return false }
        return true
    }
}

// MARK: - Text renderer

func render(stats: Stats) -> String {
    var out: [String] = []
    out.append("")
    out.append("CraftMeter  —  Craft Agent 用量仪表盘")
    out.append(String(repeating: "═", count: 56))

    let costStr = Format.cost(cents: stats.totalCostCents)
    let tokStr  = Format.tokens(stats.totalBillableTokens)
    let scanDate = Date(timeIntervalSince1970: TimeInterval(stats.lastScannedAtMs) / 1000)
    let scanStr  = scanDate.formatted(date: .abbreviated, time: .shortened)

    out.append("  Total reported cost   \(costStr)")
    out.append("  Total tokens          \(tokStr)")
    out.append("  Sessions              \(stats.sessionCount)\(stats.malformedCount > 0 ? " (\(stats.malformedCount) malformed skipped)" : "")")
    out.append("  Workspaces            \(stats.workspaceCount)")
    out.append("  Last scan             \(scanStr)")
    out.append("")
    if !stats.modelBreakdown.isEmpty {
        out.append("Model breakdown")
        for ms in stats.modelBreakdown.prefix(6) {
            let cost = Format.cost(cents: ms.costCents)
            let tokens = Format.tokens(ms.billableTokens)
            out.append("  \(ms.model)")
            out.append("     \(tokens) tokens · \(cost) · \(ms.sessionCount) sessions")
        }
        out.append("")
    }
    out.append("Top 5 sessions (by billable tokens)")
    for (i, r) in stats.top5ByBillable.prefix(5).enumerated() {
        let cost = Format.cost(cents: r.costCents)
        let labels = r.labels.isEmpty ? "" : "  [\(r.labels.joined(separator: ", "))]"
        out.append("  \(i + 1). \(r.name)\(labels)")
        out.append("     \(Format.tokens(r.billableTokens)) · \(cost) · \(r.model) · \(r.workspace)/\(r.id)")
    }

    out.append("")
    out.append("30-day token trend")
    let maxTok = stats.dailyBuckets30d.map(\.tokens).max() ?? 1
    for bucket in stats.dailyBuckets30d {
        let date = bucket.date.formatted(.dateTime.month(.abbreviated).day())
        let bar = barChart(value: bucket.tokens, max: maxTok)
        out.append("  \(date) \(bar) \(Format.tokens(bucket.tokens))")
    }
    out.append("")
    return out.joined(separator: "\n")
}

func barChart(value: Int, max: Int) -> String {
    let count = 8
    guard max > 0 else { return String(repeating: " ", count: count) }
    let filled = Int((Double(value) / Double(max) * Double(count)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: " ", count: count - filled)
}

// MARK: - JSON renderer

private struct CLIStatsJSON: Codable {
    let totalCostCents: Int
    let totalBillableTokens: Int
    let sessionCount: Int
    let workspaces: [WorkspaceStat]
    let modelBreakdown: [ModelStat]
    let top5: [SessionRecord]
    let dailyBuckets30d: [DayBucket]
    let heatmapDays: [DayBucket]
    let lastScannedAtMs: Int64
}

func jsonEncode(_ stats: Stats) -> String {
    let payload = CLIStatsJSON(
        totalCostCents: stats.totalCostCents,
        totalBillableTokens: stats.totalBillableTokens,
        sessionCount: stats.sessionCount,
        workspaces: stats.workspaceBreakdown,
        modelBreakdown: stats.modelBreakdown,
        top5: Array(stats.top5ByBillable.prefix(5)),
        dailyBuckets30d: stats.dailyBuckets30d,
        heatmapDays: stats.heatmapDays,
        lastScannedAtMs: stats.lastScannedAtMs
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = (try? encoder.encode(payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}
