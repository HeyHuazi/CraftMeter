// ============================================================================
// L3 CONTRACT — SessionDetail.swift
//
// INPUT:  Detail enum case + Stats（用于 day/workspace 聚合切片）+ onBack
// OUTPUT: overlay 全屏详情视图（single session / day sessions / workspace / all）
// POS:    StatsView 的覆盖层 · drill-down 终点 · 不依赖 NavigationStack
// ============================================================================

import SwiftUI
import CraftMeterCore

struct SessionDetail: View {
    let detail: Detail
    let stats: Stats
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            Spacer()
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            // Invisible mirror to balance the leading Back button
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch detail {
        case .session(let r):           return r.name
        case .daySessions(let d):       return d.formatted(.dateTime.month(.abbreviated).day().year())
        case .workspaceSessions(let n): return n
        case .allSessions:              return "All sessions"
        }
    }

    // MARK: - Content per Detail case

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .session(let r):
            sessionDetail(r)
        case .daySessions(let d):
            sessionList(sessions(matching: .day(d)), placeholder: "No sessions on this day")
        case .workspaceSessions(let n):
            sessionList(sessions(matching: .workspace(n)), placeholder: "No sessions in this workspace")
        case .allSessions:
            sessionList(sessions(matching: .all), placeholder: "No sessions")
        }
    }

    // MARK: - Single session

    private func sessionDetail(_ r: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !r.preview.isEmpty {
                Text(r.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                    .lineLimit(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                metaRow("Model", r.model)
                metaRow("Workspace", r.workspace)
                if !r.workingDirectory.isEmpty {
                    metaRow("Working dir", r.workingDirectory)
                }
                if !r.thinkingLevel.isEmpty {
                    metaRow("Thinking", r.thinkingLevel)
                }
                if !r.permissionMode.isEmpty {
                    metaRow("Permission", r.permissionMode)
                }
                metaRow("Labels", r.labels.isEmpty ? "—" : r.labels.joined(separator: ", "))
                metaRow("Created", formatMs(r.createdAt))
                if r.lastUsedAtMs > 0 {
                    metaRow("Last used", formatMs(r.lastUsedAtMs))
                }
                metaRow("Messages", "\(r.messageCount)")
                metaRow("Session ID", r.id)
            }
            .font(.system(size: 11))

            Divider()

            tokenBreakdown(r)

            Divider()

            HStack {
                Text("Reported cost")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(Format.cost(cents: r.costCents))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func tokenBreakdown(_ r: SessionRecord) -> some View {
        let total = max(r.billableTokens, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Token breakdown")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            tokenBar("Input", r.inputTokens, color: .blue, total: total)
            tokenBar("Output", r.outputTokens, color: .green, total: total)
            tokenBar("Cache read", r.cacheReadTokens, color: .orange, total: total)
            tokenBar("Cache write", r.cacheCreationTokens, color: .purple, total: total)
            HStack {
                Text("Billable total")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(Format.tokens(r.billableTokens))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.top, 2)
        }
    }

    private func tokenBar(_ label: String, _ value: Int, color: Color, total: Int) -> some View {
        let ratio = total > 0 ? Double(value) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.tokens(value))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(1, max(0, ratio)))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Session list (day / workspace / all)

    @ViewBuilder
    private func sessionList(_ records: [SessionRecord], placeholder: String) -> some View {
        if records.isEmpty {
            Text(placeholder)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            VStack(spacing: 2) {
                ForEach(records.prefix(100), id: \.id) { r in
                    SimpleRow(r: r)
                }
                if records.count > 100 {
                    Text("+ \(records.count - 100) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: - Record filtering helpers

    private enum SessionQuery {
        case all
        case day(Date)
        case workspace(String)
    }

    private func sessions(matching query: SessionQuery) -> [SessionRecord] {
        let filtered: [SessionRecord]
        switch query {
        case .all:
            filtered = stats.records
        case .day(let date):
            let cal = Calendar(identifier: .gregorian)
            filtered = stats.records.filter {
                cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.createdAt) / 1000), inSameDayAs: date)
            }
        case .workspace(let name):
            filtered = stats.records.filter { $0.workspace == name }
        }
        return filtered.sorted { $0.billableTokens > $1.billableTokens }
    }

    private func formatMs(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Compact row for list views (no date badge — context already known)

private struct SimpleRow: View {
    let r: SessionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(r.model)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.tokens(r.billableTokens))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Format.cost(cents: r.costCents))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
