// ============================================================================
// L3 CONTRACT — TopBurnSection.swift
//
// INPUT:  Stats.top5ByBillable + Stats.workspaceBreakdown + drill-down callbacks
// OUTPUT: TopBurnSection — Sessions/Workspaces segmented attribution panel
// POS:    StatsView 归因层 · 单一区域承载“谁在燃烧”，避免双列表竞争
// ============================================================================

import SwiftUI
import CraftMeterCore

struct TopBurnSection: View {
    let stats: Stats
    let onSelectSession: (SessionRecord) -> Void
    let onSelectWorkspace: (String) -> Void
    let onSelectAllSessions: () -> Void

    @State private var dimension: BurnDimension = .sessions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.18), value: dimension)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Top burn")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if dimension == .sessions && stats.records.count > 5 {
                    Button("View all", action: onSelectAllSessions)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Burn dimension", selection: $dimension) {
                Text("Sessions").tag(BurnDimension.sessions)
                Text("Models").tag(BurnDimension.models)
                Text("Workspaces").tag(BurnDimension.workspaces)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .controlSize(.small)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch dimension {
        case .sessions:
            sessionList
        case .models:
            modelList
        case .workspaces:
            workspaceList
        }
    }

    @ViewBuilder
    private var modelList: some View {
        VStack(spacing: 2) {
            if stats.modelBreakdown.isEmpty {
                emptyText("No models yet")
            } else {
                ForEach(Array(stats.modelBreakdown.prefix(5)), id: \.model) { ms in
                    BurnModelRow(ms: ms, total: stats.totalBillableTokens)
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(spacing: 2) {
            if stats.top5ByBillable.isEmpty {
                emptyText("No sessions yet")
            } else {
                ForEach(Array(stats.top5ByBillable.prefix(5)), id: \.id) { record in
                    BurnSessionRow(record: record) { onSelectSession(record) }
                }
            }
        }
    }

    private var workspaceList: some View {
        VStack(spacing: 2) {
            if stats.workspaceBreakdown.isEmpty {
                emptyText("No workspaces yet")
            } else {
                ForEach(Array(stats.workspaceBreakdown.prefix(5)), id: \.workspace) { ws in
                    BurnWorkspaceRow(ws: ws, total: stats.totalBillableTokens) {
                        onSelectWorkspace(ws.workspace)
                    }
                }
            }
        }
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}

private enum BurnDimension: String {
    case sessions
    case models
    case workspaces
}

// MARK: - Session row

private struct BurnSessionRow: View {
    let record: SessionRecord
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                dateBadge
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(record.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.cost(cents: record.costCents))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(Format.tokens(record.billableTokens))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 58, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hover ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private var dateBadge: some View {
        let date = Date(timeIntervalSince1970: TimeInterval(record.createdAt) / 1000)
        return VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 8, weight: .semibold))
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 30, height: 30)
        .foregroundStyle(.secondary)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private var accessibilityLabel: String {
        "Session \(record.name), model \(record.model), cost \(Format.cost(cents: record.costCents)), \(Format.tokens(record.billableTokens)) billable tokens."
    }
}

// MARK: - Workspace row

// MARK: - Model row

private struct BurnModelRow: View {
    let ms: ModelStat
    let total: Int
    @State private var hover = false

    var body: some View {
        let ratio = total > 0 ? Double(ms.billableTokens) / Double(total) : 0
        let color = Color(hue: ms.tier.hueFraction, saturation: 0.6, brightness: 0.75)
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(ms.model)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Bar(ratio: ratio, color: color)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.percent(ratio))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(Format.cost(cents: ms.costCents))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hover = $0 }
        .accessibilityLabel("Model \(ms.model), \(Format.percent(ratio)) of billable tokens, \(Format.cost(cents: ms.costCents)).")
    }
}

private struct BurnWorkspaceRow: View {
    let ws: WorkspaceStat
    let total: Int
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        let ratio = total > 0 ? Double(ws.billableTokens) / Double(total) : 0
        let color = Palette.workspace(ws.workspace)
        return Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ws.workspace)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Bar(ratio: ratio, color: color)
                }
                Spacer(minLength: 4)
                Text(Format.percent(ratio))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                Text(Format.cost(cents: ws.costCents))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hover ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Workspace \(ws.workspace), \(Format.percent(ratio)) of billable tokens, cost \(Format.cost(cents: ws.costCents)).")
    }
}

private struct Bar: View {
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(1, max(0, ratio)))
            }
        }
        .frame(height: 4)
    }
}
