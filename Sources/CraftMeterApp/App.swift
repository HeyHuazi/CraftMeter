// ============================================================================
// L3 CONTRACT — App.swift (menubar executable `CraftMeterApp`)
//
// INPUT:  用户点击状态栏图标 / 5min 自动 timer / 手动 Refresh 按钮 / 命令+逗号 Settings
// OUTPUT: MenuBarExtra popover (380×500) · 实时状态栏数字 · cache.json 落盘
// POS:    唯一 GUI 入口 · @main · 持有 StatsViewModel 单例 · 调度后台 refresh
// ============================================================================

import SwiftUI
import CraftMeterCore

@main
struct CraftMeterApp: App {
    @StateObject private var viewModel = StatsViewModel()
    @AppStorage("menubarDisplay") private var menubarDisplay: String = "todayCost"

    var body: some Scene {
        MenuBarExtra {
            StatsView(viewModel: viewModel)
        } label: {
            labelView
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    // MARK: - Status bar label

    @ViewBuilder
    private var labelView: some View {
        if menubarDisplay == "iconOnly" {
            Image(systemName: "dollarsign.circle.fill")
        } else {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle.fill")
                Text(displayText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var displayText: String {
        switch menubarDisplay {
        case "totalCost":   return Format.cost(cents: viewModel.stats.totalCostCents)
        case "todayTokens": return Format.tokens(todayBucket?.tokens ?? 0)
        default:            return Format.cost(cents: todayBucket?.costCents ?? 0)
        }
    }

    private var todayBucket: DayBucket? { viewModel.stats.dailyBuckets30d.last }
}
