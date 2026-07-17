import SwiftUI

/**
 * [INPUT]: Observes cached UsageAnalyticsSnapshot state from AppViewModel and model brand presentation metadata.
 * [OUTPUT]: Renders natural range controls, totals, token/cost trends, dimension breakdowns, and the overlapping Craft activity insight panel.
 * [POS]: OhMyUsage Settings analytics feature; presentation orchestration only, with scanning and aggregation kept outside SwiftUI.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageAnalyticsSettingsView: View {
    @Bindable var viewModel: AppViewModel
    var theme: SettingsTheme

    @State private var hoveredBucketID: String?
    @State private var selectedStatisticsBreakdown: UsageStatisticsBreakdown = .provider
    @State private var selectedFacetKind: UsageAnalyticsFacetKind = .mcpServer

    private var snapshot: UsageAnalyticsSnapshot {
        viewModel.usageAnalyticsSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            topControls

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    overviewModule
                    trendModule
                    statisticsModule
                    facetModule
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refreshUsageAnalyticsIfNeeded(force: false)
        }
        .onChange(of: viewModel.usageAnalyticsFilter) { _, _ in
            viewModel.refreshUsageAnalyticsIfNeeded(force: false)
        }
    }

    private var topControls: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsPillSegmentedControl(
                options: timeRangeOptions.map {
                    SettingsPillSegmentOption(id: $0, title: timeRangeTitle($0))
                },
                selection: viewModel.usageAnalyticsFilter.range,
                backgroundColor: Color.white.opacity(0.15),
                selectedFillColor: Color.white.opacity(0.80),
                selectedTextColor: Color.black.opacity(0.88),
                textColor: Color.white.opacity(0.80),
                height: 24,
                segmentWidths: [
                    .today: 58,
                    .week: 58,
                    .month: 58,
                    .all: 48
                ]
            ) { range in
                viewModel.usageAnalyticsFilter.range = range
            }
            .frame(width: 228, height: 24)

            UsageAnalyticsFilterBar(
                filter: Binding(
                    get: { viewModel.usageAnalyticsFilter },
                    set: { viewModel.usageAnalyticsFilter = $0 }
                ),
                snapshot: snapshot
            )

            Button {
                viewModel.refreshUsageAnalytics()
            } label: {
                Image(systemName: viewModel.usageAnalyticsLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(usageText80)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("刷新使用统计")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewModule: some View {
        module(title: "总览", subtitle: pricingSubtitle) {
            UsageOverviewMetricsGrid(totals: snapshot.totals)
        }
    }

    private var pricingSubtitle: String {
        switch snapshot.totals.pricingState {
        case .reported:
            return "费用来自上游日志报告。"
        case .estimated:
            return "费用按 Models.dev 当前公开模型价格估算，不等同于账单。"
        case .mixed:
            return "费用同时包含上游报告与 Models.dev 公开价格估算。"
        case .partial:
            return "已知金额是下界；部分请求或 Token 类型仍无法定价。"
        case .unknown:
            return "当前记录缺少可可靠匹配的费用或模型价格。"
        }
    }

    private var trendModule: some View {
        module(title: "使用趋势", subtitle: "") {
            VStack(alignment: .leading, spacing: 16) {
                UsageTrendChartView(
                    buckets: snapshot.trendBuckets,
                    hoveredBucketID: $hoveredBucketID,
                    selectedBucketID: focusedTrendBucket?.id
                )
                .frame(height: 128)

                Rectangle()
                    .fill(theme.subtlePanelStrokeColor)
                    .frame(height: 1)

                if let bucket = focusedTrendBucket {
                    UsageHoverDetailView(bucket: bucket)
                }
            }
        }
    }

    private var statisticsModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("统计")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .frame(height: 12, alignment: .leading)

            SettingsPillSegmentedControl(
                options: UsageStatisticsBreakdown.allCases.map {
                    SettingsPillSegmentOption(id: $0, title: $0.title)
                },
                selection: selectedStatisticsBreakdown,
                backgroundColor: Color.white.opacity(0.15),
                selectedFillColor: Color.white.opacity(0.80),
                selectedTextColor: Color.black.opacity(0.88),
                textColor: Color.white.opacity(0.80),
                height: 24,
                segmentWidths: [
                    .client: 58,
                    .provider: 58,
                    .project: 48,
                    .model: 48
                ]
            ) { selection in
                selectedStatisticsBreakdown = selection
            }
            .frame(width: 212, height: 24)

            UsagePieAndTableView(
                pieItems: statisticsPieItems,
                rows: statisticsRows,
                theme: theme
            )
        }
    }

    private var statisticsPieItems: [UsagePieItem] {
        switch selectedStatisticsBreakdown {
        case .client:
            return snapshot.clientStats.map { UsagePieItem(id: $0.id, title: $0.title, share: $0.share) }
        case .provider:
            return snapshot.providerStats.map { UsagePieItem(id: $0.id, title: $0.providerName, share: $0.share) }
        case .project:
            return snapshot.projectStats.map { UsagePieItem(id: $0.id, title: $0.title, share: $0.share) }
        case .model:
            return snapshot.modelStats.map {
                UsagePieItem(
                    id: $0.id,
                    title: $0.modelID,
                    share: $0.share,
                    modelBrand: UsageAnalyticsModelBrandResolver.resolve(
                        modelID: $0.modelID,
                        providerName: $0.providerName,
                        appType: $0.appType
                    )
                )
            }
        }
    }

    private var statisticsRows: [UsageStatsTableRow] {
        switch selectedStatisticsBreakdown {
        case .client:
            return snapshot.clientStats.map { UsageStatsTableRow(id: $0.id, title: $0.title, totals: $0.totals) }
        case .provider:
            return snapshot.providerStats.map { UsageStatsTableRow(id: $0.id, title: $0.providerName, totals: $0.totals) }
        case .project:
            return snapshot.projectStats.map { UsageStatsTableRow(id: $0.id, title: $0.title, totals: $0.totals) }
        case .model:
            return snapshot.modelStats.map {
                UsageStatsTableRow(
                    id: $0.id,
                    title: $0.modelID,
                    totals: $0.totals,
                    modelBrand: UsageAnalyticsModelBrandResolver.resolve(
                        modelID: $0.modelID,
                        providerName: $0.providerName,
                        appType: $0.appType
                    )
                )
            }
        }
    }

    private var facetModule: some View {
        module(title: "Craft 活动", subtitle: "按当前筛选范围统计；同一请求可命中多个活动，因此覆盖率可以重叠。") {
            UsageFacetActivityPanel(
                groups: snapshot.facetStats,
                selectedKind: $selectedFacetKind,
                globalFilterDescription: selectedFacetFilterDescription,
                theme: theme
            )
        }
    }

    private var selectedFacetFilterDescription: String? {
        guard let kind = viewModel.usageAnalyticsFilter.selectedFacetKind else { return nil }
        guard let value = viewModel.usageAnalyticsFilter.selectedFacetValue else {
            return kind.title
        }
        let title = snapshot.availableFacetValues.first { $0.id == value }?.title ?? value
        return "\(kind.title) · \(title)"
    }

    private func module<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .frame(height: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(usageText40)
                        .lineLimit(2)
                }
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                    .fill(Color.clear)
            )
            .overlay(
                SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                    .stroke(theme.subtlePanelStrokeColor, lineWidth: 1)
            )
        }
    }

    private var hoveredBucket: UsageTrendBucket? {
        guard let hoveredBucketID else { return nil }
        return snapshot.trendBuckets.first { $0.id == hoveredBucketID }
    }

    private var focusedTrendBucket: UsageTrendBucket? {
        hoveredBucket
            ?? snapshot.trendBuckets.last(where: { $0.totals.totalTokens > 0 })
            ?? snapshot.trendBuckets.last
    }
}

private enum UsageStatisticsBreakdown: String, CaseIterable, Hashable {
    case client
    case provider
    case project
    case model

    var title: String {
        switch self {
        case .client: return "客户端"
        case .provider: return "供应商"
        case .project: return "项目"
        case .model: return "模型"
        }
    }
}

private let timeRangeOptions: [UsageAnalyticsRange] = [
    .today,
    .week,
    .month,
    .all
]

let usageText80 = Color.white.opacity(0.80)
let usageText55 = Color.white.opacity(0.55)
let usageText40 = Color.white.opacity(0.40)
private let usageText30 = Color.white.opacity(0.30)

private func timeRangeTitle(_ range: UsageAnalyticsRange) -> String {
    switch range {
    case .today: return "今天"
    case .week: return "本周"
    case .month: return "本月"
    case .all: return "全部"
    }
}

private struct UsageOverviewMetricsGrid: View {
    var totals: UsageMetricTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                UsageMetricTile(title: "总请求", value: tokenText(totals.requestCount))
                UsageMetricTile(title: "总Token", value: tokenText(totals.totalTokens))
                UsageMetricTile(title: "输入", value: tokenText(totals.inputTokens))
                UsageMetricTile(title: "输出", value: tokenText(totals.outputTokens))
            }

            HStack(spacing: 24) {
                UsageMetricTile(title: "缓存命中", value: tokenText(totals.cacheReadTokens))
                UsageMetricTile(title: "推理", value: tokenText(totals.reasoningTokens))
                UsageMetricTile(title: "费用", value: costText(totals))
                UsageMetricTile(title: "成功率", value: percentText(totals.successRate))
            }
        }
    }
}

private struct UsageMetricTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
                .lineLimit(1)
            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .semibold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageTrendChartView: View {
    var buckets: [UsageTrendBucket]
    @Binding var hoveredBucketID: String?
    var selectedBucketID: String?

    var body: some View {
        GeometryReader { proxy in
            let maxTokens = max(1, buckets.map { $0.totals.totalTokens }.max() ?? 1)
            let activeBucketID = hoveredBucketID ?? selectedBucketID
            HStack(alignment: .bottom, spacing: 6) {
                if buckets.isEmpty {
                    Text("暂无趋势数据")
                        .font(.system(size: 12))
                        .foregroundStyle(usageText55)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(buckets) { bucket in
                        let ratio = CGFloat(bucket.totals.totalTokens) / CGFloat(maxTokens)
                        let isActive = bucket.id == activeBucketID
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isActive ? usageText80 : usageText40)
                                    .frame(width: 16, height: max(4, ratio * (proxy.size.height - 18)))
                            }
                            .frame(maxWidth: .infinity)

                            Text(trendTickLabel(bucket.startAt, endAt: bucket.endAt))
                                .font(usageTrendLabelFont(isActive: isActive))
                                .foregroundStyle(isActive ? usageText80 : usageText40)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(height: 10)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !buckets.isEmpty, proxy.size.width > 0 else { return }
                    let widthPerBucket = proxy.size.width / CGFloat(buckets.count)
                    let index = min(max(0, Int(location.x / max(1, widthPerBucket))), buckets.count - 1)
                    hoveredBucketID = buckets[index].id
                case .ended:
                    hoveredBucketID = nil
                }
            }
        }
    }
}

private struct UsageHoverDetailView: View {
    var bucket: UsageTrendBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shortDate(bucket.startAt))
                .font(usagePingFangFont(size: 10, weight: .semibold))
                .foregroundStyle(usageText80)

            HStack(spacing: 24) {
                detail("总Token", tokenText(bucket.totals.totalTokens))
                detail("输入", tokenText(bucket.totals.inputTokens))
                detail("输出", tokenText(bucket.totals.outputTokens))
                detail("推理", tokenText(bucket.totals.reasoningTokens))
                detail("缓存命中", tokenText(bucket.totals.cacheReadTokens))
                detail("费用", costText(bucket.totals))
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(usagePingFangFont(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func tokenText(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

func costText(_ totals: UsageMetricTotals) -> String {
    let value = UsageAnalyticsDisplayFormatter.cost(totals)
    return value == "—" ? "未知" : value
}

func percentText(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "0%"
}

func percentTextFixed(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "0.0%"
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d  HH:mm"
    return formatter.string(from: date)
}

private func usageTrendLabelFont(isActive: Bool) -> Font {
    usagePingFangFont(size: 10, weight: isActive ? .semibold : .regular)
}

func usagePingFangFont(size: CGFloat, weight: Font.Weight) -> Font {
    switch weight {
    case .semibold, .bold, .heavy, .black:
        return .custom("PingFangSC-Semibold", size: size)
    default:
        return .custom("PingFangSC-Regular", size: size)
    }
}

private func trendTickLabel(_ date: Date, endAt: Date) -> String {
    let duration = endAt.timeIntervalSince(date)
    if duration > 40 * 24 * 60 * 60 {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let quarter = ((month - 1) / 3) + 1
        return "\(year) Q\(quarter)"
    }

    let formatter = DateFormatter()
    if duration <= 90 * 60 {
        formatter.dateFormat = "H"
    } else if duration <= 36 * 60 * 60 {
        formatter.dateFormat = "d"
    } else if duration <= 8 * 24 * 60 * 60 {
        formatter.dateFormat = "M/d"
    } else {
        formatter.dateFormat = "M月"
    }
    return formatter.string(from: date)
}

func pieColor(_ index: Int, theme: SettingsTheme) -> Color {
    let colors = [0.82, 0.56, 0.40, 0.30, 0.18, 0.08].map {
        Color.white.opacity($0)
    }
    return colors[index % colors.count]
}
