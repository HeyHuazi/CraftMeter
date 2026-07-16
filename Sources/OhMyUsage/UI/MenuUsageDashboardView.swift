import SwiftUI
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 MenuUsageDashboardPresentation、自然周期选择、共享菜单视口约束以及指标/维度/趋势柱交互回调。
 * [OUTPUT]: 对外提供填满固定菜单视口的历史用量 Dashboard、趋势柱旁 Token 提示和紧凑卡片组件。
 * [POS]: UI 的菜单历史统计渲染层；只消费纯展示模型，页面内容变化仅在自身 ScrollView 内消化。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct MenuUsageDashboardView: View {
    var presentation: MenuUsageDashboardPresentation
    var language: AppLanguage
    var range: UsageAnalyticsRange
    var metric: MenuUsageMetricMode
    var breakdown: MenuUsageBreakdown
    var isLoading: Bool
    var onSelectRange: (UsageAnalyticsRange) -> Void
    var onSelectMetric: (MenuUsageMetricMode) -> Void
    var onSelectBreakdown: (MenuUsageBreakdown) -> Void
    var onOpenFullAnalytics: () -> Void

    @State private var selectedTrendID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsVisualTokens.Menu.dashboardSectionSpacing) {
                rangeControl
                summaryGrid
                trendCard
                rankingCard
                footer
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rangeControl: some View {
        menuSegmentedRow(
            values: UsageAnalyticsRange.allCases,
            selection: range,
            title: { MenuUsageDashboardPresenter.rangeTitle($0, language: language) },
            onSelect: onSelectRange
        )
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
            spacing: 6
        ) {
            ForEach(presentation.summaryItems) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsVisualTokens.Text.muted)
                    Text(item.value)
                        .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(cardBackground)
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(text("趋势", "Trend"))
                Spacer()
                compactMetricControl
            }

            if let emptyMessage = presentation.emptyMessage {
                emptyState(emptyMessage)
            } else {
                MenuUsageCompactTrendView(
                    items: presentation.trendItems,
                    selectedID: selectedTrendID,
                    onSelect: { item in
                        selectedTrendID = item.id
                    }
                )
                .frame(height: 108)
            }
        }
        .padding(10)
        .background(cardBackground)
        .onChange(of: presentation.trendItems.map(\.id)) { _, ids in
            guard let selectedTrendID, !ids.contains(selectedTrendID) else { return }
            self.selectedTrendID = nil
        }
    }

    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(text("排行", "Breakdown"))
                Spacer()
                compactBreakdownControl
            }

            if presentation.rankingItems.isEmpty {
                emptyState(text("暂无维度数据", "No breakdown data"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(presentation.rankingItems.enumerated()), id: \.element.id) { index, item in
                        rankingRow(item)
                        if index < presentation.rankingItems.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                }
                Text(presentation.pricingMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(SettingsVisualTokens.Text.muted)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Button(action: onOpenFullAnalytics) {
                HStack {
                    Text(text("查看完整统计", "Open full analytics"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(cardBackground)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactBreakdownControl: some View {
        HStack(spacing: 2) {
            ForEach(MenuUsageBreakdown.allCases, id: \.self) { item in
                Button {
                    onSelectBreakdown(item)
                } label: {
                    Text(MenuUsageDashboardPresenter.breakdownTitle(item, language: language))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(breakdown == item ? Color.black.opacity(0.88) : SettingsVisualTokens.Text.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(breakdown == item ? Color.white.opacity(0.82) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private var compactMetricControl: some View {
        HStack(spacing: 2) {
            ForEach(MenuUsageMetricMode.allCases, id: \.self) { item in
                Button {
                    onSelectMetric(item)
                } label: {
                    Text(MenuUsageDashboardPresenter.metricTitle(item, language: language))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(metric == item ? Color.black.opacity(0.88) : SettingsVisualTokens.Text.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(metric == item ? Color.white.opacity(0.82) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private func rankingRow(_ item: MenuUsageRankingItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let brand = item.modelBrand {
                    UsageAnalyticsModelBrandIcon(presentation: brand, size: 13)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(SettingsVisualTokens.Text.muted)
                    }
                }
                Spacer(minLength: 8)
                Text(item.value)
                    .font(AppFonts.numeric(size: 11, fallbackWeight: .semibold))
                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                if let share = item.share {
                    Text(UsageAnalyticsDisplayFormatter.percent(share))
                        .font(AppFonts.numeric(size: 9, fallbackWeight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Text.muted)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            if let share = item.share {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.58))
                                .frame(width: max(2, proxy.size.width * min(max(share, 0), 1)))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 8)
    }

    private func menuSegmentedRow<Value: Hashable>(
        values: [Value],
        selection: Value,
        title: @escaping (Value) -> String,
        onSelect: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text(title(value))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selection == value ? Color.black.opacity(0.88) : SettingsVisualTokens.Text.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(selection == value ? Color.white.opacity(0.82) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private var cardBackground: some View {
        SettingsSmoothedRoundedRectangle(cornerRadius: 10)
            .fill(SettingsVisualTokens.Menu.cardBackground)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsVisualTokens.Text.primary)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(SettingsVisualTokens.Text.muted)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
    }

    private func text(_ zhHans: String, _ english: String) -> String {
        language == .zhHans ? zhHans : english
    }
}

private struct MenuUsageCompactTrendView: View {
    var items: [MenuUsageTrendItem]
    var selectedID: String?
    var onSelect: (MenuUsageTrendItem) -> Void
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(1, items.map(\.value).max() ?? 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(items) { item in
                    let active = item.id == hoveredID || item.id == selectedID
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(spacing: 4) {
                            Spacer().frame(height: 19)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(active ? Color.white.opacity(0.85) : Color.white.opacity(0.38))
                                .frame(height: max(3, CGFloat(item.value / maxValue) * (proxy.size.height - 40)))
                            Text(item.label)
                                .font(.system(size: 7, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? SettingsVisualTokens.Text.primary : SettingsVisualTokens.Text.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .overlay(alignment: .top) {
                            if active {
                                Text(item.tokensText)
                                    .font(AppFonts.numeric(size: 11, fallbackWeight: .bold))
                                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.18)))
                                    .shadow(color: Color.black.opacity(0.24), radius: 3, y: 1)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                    .onHover { hovering in
                        hoveredID = hovering ? item.id : nil
                    }
                }
            }
        }
    }
}
