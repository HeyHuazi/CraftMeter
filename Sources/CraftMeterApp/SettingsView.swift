// ============================================================================
// L3 CONTRACT — SettingsView.swift
//
// INPUT:  @AppStorage("menubarDisplay") 持久化偏好
// OUTPUT: 单 Picker 选择状态栏显示模式（todayCost/totalCost/todayTokens/iconOnly）
// POS:    App.body 的 Settings scene 容器 · 命令 + 逗号 唤起
// ============================================================================

import SwiftUI

struct SettingsView: View {
    @AppStorage("menubarDisplay") private var menubarDisplay: String = "todayCost"

    var body: some View {
        Form {
            Picker("Status bar display", selection: $menubarDisplay) {
                Text("Today cost").tag("todayCost")
                Text("Total cost").tag("totalCost")
                Text("Today tokens").tag("todayTokens")
                Text("Icon only").tag("iconOnly")
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 320)
    }
}
