// ============================================================================
// L3 CONTRACT — ViewModel.swift
//
// INPUT:  timer tick (5min) / Refresh button / app 启动
// OUTPUT: @Published stats 给 StatsView 消费；cache.json 持久化
// POS:    @MainActor · 唯一持有 Store · 唯一调度后台 refresh
// ============================================================================

import Foundation
import SwiftUI
import CraftMeterCore

@MainActor
final class StatsViewModel: ObservableObject {
    @Published private(set) var stats: Stats = .empty
    @Published private(set) var isRefreshing: Bool = false

    private let store = Store()
    private var timer: Timer?

    init() {
        if let cached = store.readCache() {
            self.stats = cached
        }
        Task { await refresh() }
        startBackgroundTimer()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let next = await Task.detached(priority: .utility) { [store] in
            store.refresh()
        }.value
        self.stats = next
    }

    private func startBackgroundTimer() {
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
}
