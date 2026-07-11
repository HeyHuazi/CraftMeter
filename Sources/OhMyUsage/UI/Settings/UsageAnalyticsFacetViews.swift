import SwiftUI

/**
 * [INPUT]: Receives overlapping typed-facet statistics and Settings theme tokens.
 * [OUTPUT]: Renders a ranked coverage list without implying mutually exclusive attribution.
 * [POS]: Usage analytics facet presentation component; separated from page orchestration to keep the feature decomposed.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageFacetCoverageList: View {
    var items: [UsageAnalyticsDimensionStats]
    var theme: SettingsTheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.prefix(12)) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(1)
                        Spacer()
                        Text("\(usageFacetTokenText(item.totals.totalTokens)) · \(usageFacetPercentText(item.share))")
                            .font(AppFonts.numeric(size: 11, fallbackWeight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(theme.subtlePanelStrokeColor)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.62))
                                    .frame(width: proxy.size.width * min(1, max(0, item.share)))
                            }
                    }
                    .frame(height: 4)
                }
                .padding(.vertical, 10)
            }
        }
    }
}

private func usageFacetTokenText(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func usageFacetPercentText(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "0%"
}
