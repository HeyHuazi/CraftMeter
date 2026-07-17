import SwiftUI

/**
 * [INPUT]: 依赖 typed facet 统计、当前浏览维度、全局活动筛选描述与 Settings 主题令牌。
 * [OUTPUT]: 对外提供 UsageFacetPanelPresentation 纯展示模型与 UsageFacetActivityPanel 活动洞察面板。
 * [POS]: Settings 使用统计的 Craft 活动展示边界；负责维度导航、安全摘要和覆盖率排行，不汇总可重叠 facet、不承载扫描或聚合策略。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageFacetPanelPresentation {
    static let visibleLimit = 12

    let availableGroups: [UsageAnalyticsFacetStatsGroup]
    let selectedKind: UsageAnalyticsFacetKind?
    let selectedItems: [UsageAnalyticsDimensionStats]

    init(
        groups: [UsageAnalyticsFacetStatsGroup],
        requestedKind: UsageAnalyticsFacetKind?
    ) {
        let groupsByKind = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0) })
        availableGroups = UsageAnalyticsFacetKind.allCases.compactMap { groupsByKind[$0] }
        selectedKind = requestedKind.flatMap { groupsByKind[$0] != nil ? $0 : nil }
            ?? availableGroups.first?.kind
        selectedItems = selectedKind.flatMap { groupsByKind[$0]?.items } ?? []
    }

    var topItem: UsageAnalyticsDimensionStats? {
        selectedItems.first
    }

    var visibleItems: [UsageAnalyticsDimensionStats] {
        Array(selectedItems.prefix(Self.visibleLimit))
    }

    var hiddenItemCount: Int {
        max(0, selectedItems.count - visibleItems.count)
    }
}

struct UsageFacetActivityPanel: View {
    var groups: [UsageAnalyticsFacetStatsGroup]
    @Binding var selectedKind: UsageAnalyticsFacetKind
    var globalFilterDescription: String?
    var theme: SettingsTheme

    private var presentation: UsageFacetPanelPresentation {
        UsageFacetPanelPresentation(groups: groups, requestedKind: selectedKind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dimensionNavigation

            if let globalFilterDescription {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("全局筛选：\(globalFilterDescription)")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(usageText55)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .accessibilityLabel("全局活动筛选，\(globalFilterDescription)")
            }

            if presentation.selectedItems.isEmpty {
                emptyState
            } else {
                summary

                Rectangle()
                    .fill(theme.subtlePanelStrokeColor)
                    .frame(height: 1)

                UsageFacetCoverageList(
                    items: presentation.visibleItems,
                    totalItemCount: presentation.selectedItems.count,
                    theme: theme
                )
            }
        }
        .onAppear(perform: repairSelectionIfNeeded)
        .onChange(of: presentation.availableGroups.map(\.kind)) { _, _ in
            repairSelectionIfNeeded()
        }
    }

    private var dimensionNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("浏览活动维度")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(usageText40)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(presentation.availableGroups) { group in
                        let isSelected = group.kind == presentation.selectedKind
                        Button {
                            selectedKind = group.kind
                        } label: {
                            HStack(spacing: 6) {
                                Text(group.kind.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                Text("\(group.items.count)")
                                    .font(AppFonts.numeric(size: 10, fallbackWeight: .semibold))
                                    .foregroundStyle(isSelected ? Color.black.opacity(0.58) : usageText40)
                            }
                            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : usageText80)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(group.kind.title)，\(group.items.count) 个活动项")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            UsageFacetSummaryTile(
                title: "已识别",
                value: "\(presentation.selectedItems.count) 项",
                detail: presentation.selectedKind?.title ?? "—"
            )
            UsageFacetSummaryTile(
                title: "覆盖最高",
                value: presentation.topItem?.title ?? "—",
                detail: presentation.topItem.map { percentText($0.share) } ?? "—"
            )
            UsageFacetSummaryTile(
                title: "Top 活动 Token",
                value: presentation.topItem.map { tokenText($0.totals.totalTokens) } ?? "—",
                detail: presentation.topItem.map { "\(tokenText($0.totals.requestCount)) 次请求" } ?? "—"
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(usageText40)
            Text("当前筛选范围内暂无 Craft 活动")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText55)
            Text("顶部筛选会作用于整张统计快照；这里仅切换活动维度。")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func repairSelectionIfNeeded() {
        guard let resolvedKind = presentation.selectedKind, resolvedKind != selectedKind else { return }
        selectedKind = resolvedKind
    }
}

private struct UsageFacetSummaryTile: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(AppFonts.numeric(size: 10, fallbackWeight: .semibold))
                .foregroundStyle(usageText55)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }
}

struct UsageFacetCoverageList: View {
    var items: [UsageAnalyticsDimensionStats]
    var totalItemCount: Int
    var theme: SettingsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("活动覆盖排行")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(usageText55)
                Spacer()
                Text("覆盖率按 Token 计算")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(usageText40)
            }
            .padding(.bottom, 4)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                coverageRow(item, rank: index + 1)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(theme.subtlePanelStrokeColor)
                        .frame(height: 1)
                }
            }

            if totalItemCount > items.count {
                Text("仅展示前 \(items.count) 项 · 共 \(totalItemCount) 项")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(usageText40)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("仅展示前 \(items.count) 项，共 \(totalItemCount) 项")
            }
        }
    }

    private func coverageRow(_ item: UsageAnalyticsDimensionStats, rank: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(AppFonts.numeric(size: 10, fallbackWeight: .bold))
                .foregroundStyle(rank <= 3 ? usageText80 : usageText40)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(rank <= 3 ? Color.white.opacity(0.10) : Color.clear)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(usageText80)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(percentText(item.share))
                        .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                        .foregroundStyle(usageText80)
                }

                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(theme.subtlePanelStrokeColor)
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(rank <= 3 ? 0.72 : 0.48))
                                .frame(width: proxy.size.width * min(1, max(0, item.share)))
                        }
                }
                .frame(height: 4)

                HStack(spacing: 16) {
                    compactMetric("Token", tokenText(item.totals.totalTokens))
                    compactMetric("请求", tokenText(item.totals.requestCount))
                    compactMetric("成功率", percentTextFixed(item.totals.successRate))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(item.title)")
        .accessibilityValue(
            "Token 覆盖率 \(percentText(item.share))，Token \(tokenText(item.totals.totalTokens))，请求 \(tokenText(item.totals.requestCount))，成功率 \(percentTextFixed(item.totals.successRate))"
        )
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(usageText40)
            Text(value)
                .font(AppFonts.numeric(size: 10, fallbackWeight: .semibold))
                .foregroundStyle(usageText55)
        }
    }
}
