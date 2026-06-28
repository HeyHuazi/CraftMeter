// ============================================================================
// L3 CONTRACT — HeatmapCalendarView.swift
//
// INPUT:  Stats.heatmapDays ([DayBucket], 365 天), Palette.tokens, Format.tokens()
// OUTPUT: HeatmapCalendarView 组件 — 365 天 GitHub 风格使用热力图
//         头部 HStack + 月名标签行 + 7 行 × ~53 列网格 + 日名标签列
// POS:    Components 热力图模块 · 与 TrendChart 并列展示时间维度
//         每格 Button → onSelectDay(Date) → StatsView drill-down
// ============================================================================

import SwiftUI
import CraftMeterCore

private struct HeatmapLayout {
    let cell: CGFloat
    let gap: CGFloat
}

struct HeatmapCalendarView: View {
    let stats: Stats
    let showsHeader: Bool
    let onSelectDay: (Date) -> Void

    private static let maxCellSize: CGFloat = 5
    private static let minCellSize: CGFloat = 3.8
    private static let maxCellGap: CGFloat = 1.5
    private static let minCellGap: CGFloat = 0.8
    private static let labelWidth: CGFloat = 24
    private static let labelGap: CGFloat = 4
    private static let maxGridHeight: CGFloat = 54

    private static let dayLabels = ["", "Mon", "", "Wed", "", "Fri", ""]

    init(stats: Stats, showsHeader: Bool = true, onSelectDay: @escaping (Date) -> Void) {
        self.stats = stats
        self.showsHeader = showsHeader
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 6 : 0) {
            if showsHeader {
                header
            }
            monthAndGrid
        }
    }

    // MARK: - Header

    private var header: some View {
        let total30 = stats.dailyBuckets30d.reduce(0) { $0 + $1.tokens }
        return HStack(alignment: .firstTextBaseline) {
            Text("Activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Format.tokens(total30)) · 30d")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Month labels + grid with day labels

    @ViewBuilder
    private var monthAndGrid: some View {
        let buckets = stats.heatmapDays
        if buckets.isEmpty {
            EmptyView()
        } else {
            GeometryReader { proxy in
                monthAndGridContent(buckets: buckets, width: proxy.size.width)
            }
            .frame(height: Self.maxGridHeight)
        }
    }

    private func monthAndGridContent(buckets: [DayBucket], width: CGFloat) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let (grid, weeks) = gridData(from: buckets, calendar: cal)
        let thresholds = percentileThresholds(buckets)
        let layout = layoutMetrics(width: width, weeks: weeks)

        return VStack(alignment: .leading, spacing: 0) {
            monthLabels(buckets: buckets, weeks: weeks, calendar: cal, layout: layout)
                .padding(.leading, Self.labelWidth + Self.labelGap)

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: layout.gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(Self.dayLabels[row])
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(width: Self.labelWidth, height: layout.cell, alignment: .trailing)
                    }
                }
                .padding(.trailing, Self.labelGap)

                HStack(alignment: .top, spacing: layout.gap) {
                    ForEach(0..<weeks, id: \.self) { col in
                        VStack(spacing: layout.gap) {
                            ForEach(0..<7, id: \.self) { row in
                                cellView(grid[row][col], thresholds: thresholds, cell: layout.cell)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Single cell

    @ViewBuilder
    private func cellView(_ bucket: DayBucket?, thresholds: (q25: Int, q50: Int, q75: Int), cell: CGFloat) -> some View {
        let tokens = bucket?.tokens ?? 0
        let color = heatmapColor(tokens: tokens, thresholds: thresholds)
        let tip = bucket.map {
            "\($0.date.formatted(.dateTime.month(.abbreviated).day())) · \(Format.tokens($0.tokens)) tokens"
        } ?? ""

        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: cell, height: cell)
            .help(tip)
            .onTapGesture {
                if let bucket, bucket.tokens > 0 {
                    onSelectDay(bucket.date)
                }
            }
    }

    // MARK: - Month labels row

    @ViewBuilder
    private func monthLabels(buckets: [DayBucket], weeks: Int, calendar: Calendar, layout: HeatmapLayout) -> some View {
        let monthStarts = computeMonthStarts(buckets: buckets, weeks: weeks, calendar: calendar)

        ZStack(alignment: .topLeading) {
            ForEach(monthStarts.indices, id: \.self) { i in
                let (col, name) = monthStarts[i]
                Text(name)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .offset(x: CGFloat(col) * (layout.cell + layout.gap))
            }
        }
        .frame(height: 10)
    }

    private func computeMonthStarts(buckets: [DayBucket], weeks: Int, calendar: Calendar) -> [(Int, String)] {
        var monthStarts: [(Int, String)] = []
        var seenMonths: Set<Int> = []
        for col in 0..<weeks {
            let weekStart = calendar.date(byAdding: .day, value: col * 7, to: buckets[0].date)!
            let month = calendar.component(.month, from: weekStart)
            if seenMonths.insert(month).inserted {
                monthStarts.append((col, weekStart.formatted(.dateTime.month(.abbreviated))))
            }
        }
        return monthStarts
    }

    // MARK: - Adaptive layout

    private func layoutMetrics(width: CGFloat, weeks: Int) -> HeatmapLayout {
        let columns = max(weeks, 1)
        let gridWidth = max(0, width - Self.labelWidth - Self.labelGap)
        let fluidGap = gridWidth / 260
        let gap = min(Self.maxCellGap, max(Self.minCellGap, fluidGap))
        let gapsWidth = CGFloat(max(columns - 1, 0)) * gap
        let rawCell = (gridWidth - gapsWidth) / CGFloat(columns)
        let cell = min(Self.maxCellSize, max(Self.minCellSize, rawCell))
        return HeatmapLayout(cell: cell, gap: gap)
    }

    // MARK: - Color mapping

    private func heatmapColor(tokens: Int, thresholds: (q25: Int, q50: Int, q75: Int)) -> Color {
        guard tokens > 0 else { return Color.primary.opacity(0.04) }
        let opacity: Double
        if tokens < thresholds.q25 { opacity = 0.2 }
        else if tokens < thresholds.q50 { opacity = 0.4 }
        else if tokens < thresholds.q75 { opacity = 0.7 }
        else { opacity = 1.0 }
        return Palette.tokens.opacity(opacity)
    }

    // MARK: - Percentile thresholds (exclude zeros)

    private func percentileThresholds(_ buckets: [DayBucket]) -> (q25: Int, q50: Int, q75: Int) {
        let sorted = buckets.map(\.tokens).filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0) }
        func pct(_ p: Double) -> Int {
            let idx = min(Int(Double(sorted.count - 1) * p), sorted.count - 1)
            return sorted[idx]
        }
        return (pct(0.25), pct(0.50), pct(0.75))
    }

    // MARK: - Grid construction: 7 rows (Sun..Sat) × N weeks

    private func gridData(from buckets: [DayBucket], calendar: Calendar) -> (grid: [[DayBucket?]], weeks: Int) {
        let weekday = calendar.component(.weekday, from: buckets[0].date)
        guard weekday == 1 else { return ([], 0) }  // must start on Sunday

        let weeks = (buckets.count + 6) / 7
        var grid: [[DayBucket?]] = Array(repeating: Array(repeating: nil, count: weeks), count: 7)
        for (i, bucket) in buckets.enumerated() {
            let row = i % 7
            let col = i / 7
            grid[row][col] = bucket
        }
        return (grid, weeks)
    }
}
