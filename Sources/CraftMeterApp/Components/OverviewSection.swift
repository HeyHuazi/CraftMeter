// ============================================================================
// L3 CONTRACT — OverviewSection.swift
//
// INPUT:  Stats (today bucket / 7d average / total cost / total billable tokens)
// OUTPUT: OverviewSection — Today burn hero + secondary metric strip
// POS:    StatsView 首屏判断层 · 让今日消耗成为主视觉，Total/Tokens 退为背景信息
// ============================================================================

import SwiftUI
import CraftMeterCore

struct OverviewSection: View {
    let stats: Stats
    let onSelectToday: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            todayHero
            metricStrip
        }
    }

    // MARK: - Today hero

    private var todayHero: some View {
        Button(action: onSelectToday) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: heroIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(heroColor)
                        Text("TODAY BURN")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                    }

                    Text(Format.cost(cents: todayCost))
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(deltaLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(heroColor.opacity(isQuiet ? 0.75 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                sparkline(stats.dailyBuckets30d.suffix(7), color: heroColor)
                    .frame(width: 96, height: 42)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(heroColor.opacity(isQuiet ? 0.12 : 0.36), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("View today's sessions")
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Metric strip

    private var metricStrip: some View {
        HStack(spacing: 8) {
            metricCell(
                title: "TOTAL COST",
                value: Format.cost(cents: stats.totalCostCents),
                icon: "chart.line.uptrend.xyaxis",
                color: Palette.total
            )
            metricCell(
                title: "BILLABLE",
                value: Format.tokens(stats.totalBillableTokens),
                icon: "bolt.circle.fill",
                color: Palette.tokens
            )
        }
    }

    private func metricCell(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.45)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sparkline

    private func sparkline(_ buckets: ArraySlice<DayBucket>, color: Color) -> some View {
        let peak = buckets.map(\.tokens).max() ?? 1
        return GeometryReader { _ in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    let ratio = peak > 0 ? Double(bucket.tokens) / Double(peak) : 0
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(0.22 + 0.78 * ratio))
                        .frame(width: 8, height: max(3, 40 * ratio))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    // MARK: - Derived data

    private var todayBucket: DayBucket? { stats.dailyBuckets30d.last }
    private var todayCost: Int { todayBucket?.costCents ?? 0 }
    private var todayTokens: Int { todayBucket?.tokens ?? 0 }

    private var baselineBuckets: ArraySlice<DayBucket> {
        stats.dailyBuckets30d.dropLast().suffix(7)
    }

    private var baselineCostAverage: Double {
        guard !baselineBuckets.isEmpty else { return 0 }
        let sum = baselineBuckets.reduce(0) { $0 + $1.costCents }
        return Double(sum) / Double(baselineBuckets.count)
    }

    private var baselineTokenAverage: Double {
        guard !baselineBuckets.isEmpty else { return 0 }
        let sum = baselineBuckets.reduce(0) { $0 + $1.tokens }
        return Double(sum) / Double(baselineBuckets.count)
    }

    private var deltaRatio: Double {
        if baselineCostAverage > 0 {
            return (Double(todayCost) - baselineCostAverage) / baselineCostAverage
        }
        if baselineTokenAverage > 0 {
            return (Double(todayTokens) - baselineTokenAverage) / baselineTokenAverage
        }
        return 0
    }

    private var isQuiet: Bool { todayCost == 0 && todayTokens == 0 }
    private var isAnomaly: Bool { deltaRatio >= 1.0 && (todayCost > 0 || todayTokens > 0) }
    private var heroColor: Color { isAnomaly ? Palette.anomaly : Palette.today }
    private var heroIcon: String { isAnomaly ? "exclamationmark.triangle.fill" : "dollarsign.circle.fill" }

    private var deltaLabel: String {
        if isQuiet { return "No usage today" }
        guard baselineCostAverage > 0 || baselineTokenAverage > 0 else { return "No 7d baseline yet" }
        let sign = deltaRatio >= 0 ? "+" : ""
        return "\(sign)\(Format.percent(deltaRatio)) vs 7d avg"
    }

    private var heroAccessibilityLabel: String {
        "Today burn, \(Format.cost(cents: todayCost)), \(Format.tokens(todayTokens)) billable tokens, \(deltaLabel). Opens today's sessions."
    }
}
