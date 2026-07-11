import SwiftUI

/**
 * [INPUT]: Receives analytics dimension options and a binding to UsageAnalyticsFilter.
 * [OUTPUT]: Renders compact composable selectors plus a single clear-filter action.
 * [POS]: Usage analytics presentation component; owns no scanning, aggregation, or cache policy.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageAnalyticsFilterBar: View {
    @Binding var filter: UsageAnalyticsFilter
    var snapshot: UsageAnalyticsSnapshot

    var body: some View {
        HStack(spacing: 8) {
            selector("客户端", selection: $filter.selectedClientID, options: snapshot.availableClients)
            selector("供应商", selection: $filter.selectedProviderID, options: snapshot.availableProviders)
            selector("项目", selection: $filter.selectedProjectID, options: snapshot.availableProjects)
            modelSelector
            facetKindSelector
            if filter.selectedFacetKind != nil {
                selector("活动值", selection: $filter.selectedFacetValue, options: snapshot.availableFacetValues)
            }
            if hasSelection {
                Button("清除筛选") {
                    filter.selectedClientID = nil
                    filter.selectedProviderID = nil
                    filter.selectedProjectID = nil
                    filter.selectedModelID = nil
                    filter.selectedFacetKind = nil
                    filter.selectedFacetValue = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }

    private var modelSelector: some View {
        let options = snapshot.availableModels.map {
            UsageAnalyticsDimensionOption(
                id: $0.id,
                title: $0.title,
                totalTokens: $0.totalTokens,
                requestCount: 0
            )
        }
        return selector("模型", selection: $filter.selectedModelID, options: options)
    }

    private var facetKindSelector: some View {
        Picker("Craft 活动", selection: Binding(
            get: { filter.selectedFacetKind },
            set: { value in
                filter.selectedFacetKind = value
                filter.selectedFacetValue = nil
            }
        )) {
            Text("全部活动").tag(UsageAnalyticsFacetKind?.none)
            ForEach(UsageAnalyticsFacetKind.allCases, id: \.self) { kind in
                Text(kind.title).tag(Optional(kind))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 126)
    }

    private func selector(
        _ title: String,
        selection: Binding<String?>,
        options: [UsageAnalyticsDimensionOption]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("全部\(title)").tag(String?.none)
            ForEach(options) { option in
                Text(option.title).tag(Optional(option.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 124)
        .disabled(options.isEmpty && selection.wrappedValue == nil)
    }

    private var hasSelection: Bool {
        filter.selectedClientID != nil
            || filter.selectedProviderID != nil
            || filter.selectedProjectID != nil
            || filter.selectedModelID != nil
            || filter.selectedFacetKind != nil
            || filter.selectedFacetValue != nil
    }
}

extension UsageAnalyticsFacetKind {
    var title: String {
        switch self {
        case .mcpServer: return "MCP"
        case .skill: return "Skill"
        case .craftSource: return "Source"
        case .craftTool: return "Tool"
        case .craftCategory: return "Category"
        case .craftStatus: return "Status"
        case .permissionMode: return "权限模式"
        case .thinkingLevel: return "思考等级"
        }
    }
}
