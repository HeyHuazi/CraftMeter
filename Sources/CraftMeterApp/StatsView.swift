// ============================================================================
// L3 CONTRACT — StatsView.swift
//
// INPUT:  StatsViewModel (stats / isRefreshing)
// OUTPUT: 380×500 popover：OverviewSection → ActivitySection → TopBurnSection + footer
//         overlay：SessionDetail drill-down（覆盖主视图）
// POS:    SwiftUI 视图根 · 仅 UI 编排 · 数据计算下沉到 ViewModel
// ============================================================================

import SwiftUI
import CraftMeterCore

struct StatsView: View {
    @ObservedObject var viewModel: StatsViewModel
    @State private var selectedDetail: Detail?

    var body: some View {
        ZStack {
            main
            if let detail = selectedDetail {
                SessionDetail(
                    detail: detail,
                    stats: viewModel.stats,
                    onBack: { selectedDetail = nil }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 380, height: 500)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.18), value: selectedDetail)
    }

    // MARK: - Main layout

    private var main: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    OverviewSection(stats: viewModel.stats) {
                        selectedDetail = .daySessions(today)
                    }

                    ActivitySection(stats: viewModel.stats) { date in
                        selectedDetail = .daySessions(date)
                    }

                    TopBurnSection(
                        stats: viewModel.stats,
                        onSelectSession: { selectedDetail = .session($0) },
                        onSelectWorkspace: { selectedDetail = .workspaceSessions($0) },
                        onSelectAllSessions: { selectedDetail = .allSessions }
                    )
                }
                .padding(12)
            }
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if viewModel.isRefreshing {
                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                Text("Scanning… \(cachedSuffix)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if viewModel.stats.lastScannedAtMs > 0 {
                Text("Updated \(scanTime) · \(viewModel.stats.sessionCount) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button(action: { Task { await viewModel.refresh() } }) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Quit")
            .accessibilityLabel("Quit")
        }
    }

    private var scanTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(viewModel.stats.lastScannedAtMs) / 1000)
        return date.formatted(.relative(presentation: .named))
    }

    private var cachedSuffix: String {
        guard viewModel.stats.lastScannedAtMs > 0 else { return "" }
        return "cached \(scanTime)"
    }

    private var today: Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
    }
}
