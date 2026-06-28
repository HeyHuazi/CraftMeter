// ============================================================================
// L3 CONTRACT — ActivitySection.swift
//
// INPUT:  Stats.dailyBuckets30d + Stats.heatmapDays + onSelectDay
// OUTPUT: ActivitySection — 30d trend + compact 365d heatmap under one evidence panel
// POS:    StatsView 时间证据层 · 连接今日结论与具体归因
// ============================================================================

import SwiftUI
import CraftMeterCore

struct ActivitySection: View {
    let stats: Stats
    let onSelectDay: (Date) -> Void

    private let chartHeight: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            trendBars
            HeatmapCalendarView(stats: stats, showsHeader: false, onSelectDay: onSelectDay)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.tokens(last7Sum))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text("· 7d")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if spikeCount > 0 {
                Text("· \(spikeCount) spike\(spikeCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.anomaly)
            }
        }
    }

    // MARK: - 30-day trend

    private var trendBars: some View {
        let buckets = stats.dailyBuckets30d
        let maxTok = buckets.map(\.tokens).max() ?? 0
        return VStack(spacing: 4) {
            GeometryReader { _ in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { idx, bucket in
                        let ratio = maxTok > 0 ? Double(bucket.tokens) / Double(maxTok) : 0
                        let height = maxTok > 0 ? chartHeight * CGFloat(ratio) : 0
                        bar(
                            bucket: bucket,
                            height: max(height, bucket.tokens > 0 ? 2 : 0),
                            ratio: ratio,
                            anomaly: isAnomaly(buckets, idx)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(height: chartHeight + 6)

            HStack {
                Text(firstDay)
                Spacer()
                Text(today)
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }

    private func bar(bucket: DayBucket, height: CGFloat, ratio: Double, anomaly: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Palette.tokens.opacity(0.24 + 0.76 * ratio))
            .frame(height: height)
            .overlay(alignment: .top) {
                if anomaly {
                    Circle()
                        .fill(Palette.anomaly)
                        .frame(width: 4, height: 4)
                        .offset(y: -3)
                }
            }
            .frame(maxHeight: chartHeight + 6, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { onSelectDay(bucket.date) }
            .help("\(bucket.date.formatted(.dateTime.month(.abbreviated).day())) · \(Format.tokens(bucket.tokens))")
            .accessibilityLabel("\(bucket.date.formatted(.dateTime.month(.abbreviated).day())), \(Format.tokens(bucket.tokens)) billable tokens")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Derivations

    private func isAnomaly(_ buckets: [DayBucket], _ idx: Int) -> Bool {
        guard idx >= 7 else { return false }
        let past7 = buckets[idx - 7 ..< idx]
        let sum = past7.reduce(0) { $0 + $1.tokens }
        let avg = Double(sum) / 7.0
        return avg > 0 && Double(buckets[idx].tokens) > 2 * avg
    }

    private var spikeCount: Int {
        let buckets = stats.dailyBuckets30d
        return buckets.indices.filter { isAnomaly(buckets, $0) }.count
    }

    private var last7Sum: Int {
        stats.dailyBuckets30d.suffix(7).reduce(0) { $0 + $1.tokens }
    }

    private var firstDay: String {
        guard let first = stats.dailyBuckets30d.first else { return "" }
        return first.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var today: String {
        guard let last = stats.dailyBuckets30d.last else { return "" }
        return last.date.formatted(.dateTime.month(.abbreviated).day())
    }
}
