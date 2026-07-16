import SwiftUI

/**
 * [INPUT]: 依赖 UsageMetricTotals、SettingsTheme、模型品牌展示元数据与统计页共享格式化函数。
 * [OUTPUT]: 对外提供 UsagePieItem、UsageStatsTableRow、UsagePieAndTableView，以及包含模型费用/定价状态的环形图和明细行。
 * [POS]: Settings 使用统计的维度可视化组件；承载紧凑图例、环形图和明细行，不负责选择统计维度。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsagePieItem: Identifiable {
    var id: String
    var title: String
    var share: Double
    var modelBrand: UsageAnalyticsModelBrandPresentation?

    init(
        id: String,
        title: String,
        share: Double,
        modelBrand: UsageAnalyticsModelBrandPresentation? = nil
    ) {
        self.id = id
        self.title = title
        self.share = share
        self.modelBrand = modelBrand
    }
}

struct UsageStatsTableRow: Identifiable {
    var id: String
    var title: String
    var totals: UsageMetricTotals
    var modelBrand: UsageAnalyticsModelBrandPresentation?

    init(
        id: String,
        title: String,
        totals: UsageMetricTotals,
        modelBrand: UsageAnalyticsModelBrandPresentation? = nil
    ) {
        self.id = id
        self.title = title
        self.totals = totals
        self.modelBrand = modelBrand
    }
}

struct UsagePieAndTableView: View {
    var pieItems: [UsagePieItem]
    var rows: [UsageStatsTableRow]
    var theme: SettingsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 40) {
                Spacer(minLength: 0)

                UsagePieChartView(items: pieItems, theme: theme)
                    .frame(width: 160, height: 160)

                legend
                    .frame(width: 260, alignment: .leading)

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(theme.subtlePanelStrokeColor)
                .frame(height: 1)

            UsageStatsTableView(rows: rows, theme: theme)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .stroke(theme.subtlePanelStrokeColor, lineWidth: 1)
        )
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pieItems.prefix(6).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(pieColor(index, theme: theme))
                        .frame(width: 6, height: 6)
                    if let modelBrand = item.modelBrand {
                        UsageAnalyticsModelBrandIcon(presentation: modelBrand, size: 12)
                    }
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(usageText55)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(percentText(item.share))
                        .font(AppFonts.numeric(size: 12, fallbackWeight: .semibold))
                        .foregroundStyle(usageText55)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct UsagePieChartView: View {
    var items: [UsagePieItem]
    var theme: SettingsTheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ringFrame = max(28, side - 6)
            let innerRatio = 0.62
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                if items.isEmpty {
                    Circle()
                        .stroke(
                            theme.subtlePanelStrokeColor.opacity(0.60),
                            style: StrokeStyle(lineWidth: max(16, side * 0.24), lineCap: .butt)
                        )
                        .frame(width: ringFrame, height: ringFrame)
                        .position(center)
                } else {
                    let segments = ringSegments
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        UsageDonutSegmentShape(
                            start: Angle(degrees: segment.startDegrees),
                            end: Angle(degrees: segment.endDegrees),
                            innerRatio: innerRatio
                        )
                        .fill(pieColor(index, theme: theme))
                        .frame(width: ringFrame, height: ringFrame)
                        .position(center)
                    }

                    Circle()
                        .fill(theme.sectionFillColor)
                        .frame(
                            width: ringFrame * innerRatio + 2,
                            height: ringFrame * innerRatio + 2
                        )
                        .position(center)
                }
            }
        }
    }

    private var ringSegments: [UsageRingSegment] {
        let visibleItems = items.filter { $0.share > 0 }
        guard !visibleItems.isEmpty else { return [] }

        let gap = visibleItems.count == 1 ? 0 : 1.5
        let totalGap = min(Double(visibleItems.count) * gap, 24)
        let availableDegrees = max(0, 360 - totalGap)
        let totalShare = max(visibleItems.reduce(0) { $0 + max(0, $1.share) }, 0.0001)
        let rawSegments = visibleItems.map { item in
            (item: item, degrees: max(0, item.share / totalShare) * availableDegrees)
        }
        let minimumDegrees = visibleItems.count == 1 ? 0 : 4.0
        let fixedDegrees = rawSegments.reduce(0) { partial, raw in
            partial + (raw.degrees > 0 && raw.degrees < minimumDegrees ? minimumDegrees : 0)
        }
        let flexibleRawDegrees = rawSegments.reduce(0) { partial, raw in
            partial + (raw.degrees >= minimumDegrees ? raw.degrees : 0)
        }
        let flexibleDegrees = max(0, availableDegrees - fixedDegrees)

        var cursor = -90.0
        return rawSegments.map { raw in
            let degrees: Double
            if raw.degrees > 0 && raw.degrees < minimumDegrees {
                degrees = minimumDegrees
            } else if flexibleRawDegrees > 0 {
                degrees = raw.degrees / flexibleRawDegrees * flexibleDegrees
            } else {
                degrees = raw.degrees
            }
            let startDegrees = cursor + gap / 2
            let endDegrees = startDegrees + degrees
            cursor += degrees + gap
            return UsageRingSegment(
                id: raw.item.id,
                startDegrees: startDegrees,
                endDegrees: endDegrees
            )
        }
    }
}

private struct UsageRingSegment: Identifiable {
    var id: String
    var startDegrees: Double
    var endDegrees: Double
}

private struct UsageDonutSegmentShape: Shape {
    var start: Angle
    var end: Angle
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let startRadians = start.radians
        let endRadians = end.radians

        var path = Path()
        path.move(to: point(center: center, radius: outerRadius, radians: startRadians))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: innerRadius, radians: endRadians))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: end,
            endAngle: start,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, radians: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

private struct UsageStatsTableView: View {
    var rows: [UsageStatsTableRow]
    var theme: SettingsTheme
    private let rateColumnWidth: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                tableRow(row)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(theme.subtlePanelStrokeColor)
                        .frame(height: 1)
                }
            }
            if rows.isEmpty {
                Text("暂无匹配的使用数据")
                    .font(.system(size: 12))
                    .foregroundStyle(usageText55)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            }
        }
    }

    private func tableRow(_ row: UsageStatsTableRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let modelBrand = row.modelBrand {
                    UsageAnalyticsModelBrandIcon(presentation: modelBrand, size: 12)
                }
                Text(row.title)
                    .font(usagePingFangFont(size: 12, weight: .semibold))
                    .foregroundStyle(usageText80)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 24) {
                compactMetric(title: "总Token", tokenText(row.totals.totalTokens))
                compactMetric(title: "输入", tokenText(row.totals.inputTokens))
                compactMetric(title: "输出", tokenText(row.totals.outputTokens))
                compactMetric(title: "推理", tokenText(row.totals.reasoningTokens))
                compactMetric(title: "缓存命中", tokenText(row.totals.cacheReadTokens))
                compactMetric(title: "缓存写入", tokenText(row.totals.cacheWriteTokens))
                compactMetric(title: "费用", costText(row.totals))
                compactMetric(title: "价格", pricingStateText(row.totals.pricingState))
                compactMetric(title: "缓存率", percentTextFixed(row.totals.cacheRate), fixedWidth: rateColumnWidth)
                compactMetric(title: "成功率", percentTextFixed(row.totals.successRate), fixedWidth: rateColumnWidth)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(
        title: String,
        _ value: String,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(usagePingFangFont(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
                .lineLimit(1)
            Text(value)
                .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
    }

    private func pricingStateText(_ state: UsagePricingState) -> String {
        switch state {
        case .reported: return "日志报告"
        case .estimated: return "Models.dev"
        case .mixed: return "混合"
        case .partial: return "部分定价"
        case .unknown: return "未知"
        }
    }
}

