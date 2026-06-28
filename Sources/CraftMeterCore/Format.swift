// ============================================================================
// L3 CONTRACT — Format.swift
//
// INPUT:  Int tokens / Int cents / Double ratio
// OUTPUT: 显示层字符串（tokens 缩写 · cost $xx.xx · percent 0-100%）
// POS:    Core 工具层 · 纯函数无副作用 · 被 meter CLI 与 App UI 共用
//         消除 SummaryCards / TopSessions / WorkspaceList / meter/main.swift
//         各自维护格式化函数的冗余（DRY）
// ============================================================================

import Foundation

public enum Format {
    /// Compact token formatter: 1_234_567 → "1.2M", 23_456 → "23.5K", 234 → "234"
    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }

    /// USD cost from Int cents: 1234 → "$12.34"
    public static func cost(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }

    /// Percentage from ratio: 0.123 → "12%"
    public static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }
}
