// ============================================================================
// L3 CONTRACT — Palette.swift
//
// INPUT:  workspace name (String) / 信号类别（today/total/tokens/anomaly）
// OUTPUT: Color（语义色 · workspace 稳定 hash 色）
// POS:    Components 共享色彩字典 · 消除各组件 4 档 if/else 色彩分支
//         色彩承担分类信号，让"看一眼就懂"成为可能
// ============================================================================

import SwiftUI
import CraftMeterCore

enum Palette {
    static let today    = Color.orange
    static let total    = Color.green
    static let tokens   = Color.purple
    static let anomaly  = Color.red

    /// 8-color palette for workspace dots. Stable hash guarantees the same
    /// workspace name always maps to the same color across launches —
    /// Swift's String.hashValue is randomized per-process, would flicker.
    private static let workspaceColors: [Color] = [
        .blue, .orange, .purple, .pink, .teal, .yellow, .brown, .cyan
    ]

    static func workspace(_ name: String) -> Color {
        workspaceColors[abs(stableHash(name)) % workspaceColors.count]
    }

    /// djb2 — classic string hash, deterministic and well-distributed for
    /// short workspace names. Avoids hashValue's per-launch randomization.
    private static func stableHash(_ s: String) -> Int {
        var h: Int = 5381
        for scalar in s.unicodeScalars {
            h = (h &* 33) &+ Int(scalar.value)
        }
        return h
    }
}

// MARK: - Drill-down navigation target

/// Drill-down routing. Self-managed via @State in StatsView (NOT NavigationStack
/// — its behavior inside MenuBarExtra popover is unstable across macOS versions).
/// List-like targets are normalized inside SessionDetail by its private SessionQuery.
enum Detail: Equatable {
    case session(SessionRecord)
    case daySessions(Date)
    case workspaceSessions(String)
    case allSessions
}
