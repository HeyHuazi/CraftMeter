import Foundation

/**
 * [INPUT]: 依赖 UsageAnalyticsRepository loader、可延迟恢复的快照 cache store、当前 filter 与 Claude 配置目录集合。
 * [OUTPUT]: 对外提供 cache-first、single-generation 的完整历史统计刷新，并以 MainActor 回调提交 loading/snapshot 状态。
 * [POS]: App 的设置/菜单历史统计刷新编排器；磁盘恢复、源指纹、扫描和持久化不得阻塞 MainActor。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

@MainActor
final class UsageAnalyticsRefreshCoordinator {
    typealias SourceFingerprintLoader = @Sendable (_ claudeAllConfigDirs: [String]) -> UsageAnalyticsSourceFingerprint
    typealias SnapshotLoader = @Sendable (
        _ filter: UsageAnalyticsFilter,
        _ claudeAllConfigDirs: [String],
        _ sourceFingerprint: UsageAnalyticsSourceFingerprint
    ) -> UsageAnalyticsSnapshot

    private let sourceFingerprintLoader: SourceFingerprintLoader
    private let snapshotLoader: SnapshotLoader
    private let cacheStore: UsageAnalyticsSnapshotCacheStore
    private let nowProvider: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        repository: UsageAnalyticsRepository = UsageAnalyticsRepository(),
        cacheStore: UsageAnalyticsSnapshotCacheStore = UsageAnalyticsSnapshotCacheStore(
            restoreImmediately: false
        ),
        nowProvider: @escaping () -> Date = Date.init,
        sourceFingerprintLoader: SourceFingerprintLoader? = nil,
        snapshotLoader: SnapshotLoader? = nil
    ) {
        self.cacheStore = cacheStore
        self.nowProvider = nowProvider
        self.sourceFingerprintLoader = sourceFingerprintLoader ?? { claudeAllConfigDirs in
            repository.sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs)
        }
        self.snapshotLoader = snapshotLoader ?? { filter, claudeAllConfigDirs, fingerprint in
            repository.snapshot(
                filter: filter,
                claudeAllConfigDirs: claudeAllConfigDirs,
                sourceFingerprint: fingerprint
            )
        }
    }

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        cacheStore.reset()
    }

    func refreshUsageAnalyticsIfNeeded(
        filter: UsageAnalyticsFilter,
        currentSnapshotFilter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String],
        force: Bool = false,
        onSnapshotChange: @escaping @MainActor (UsageAnalyticsSnapshot) -> Void,
        onLoadingChange: @escaping @MainActor (Bool) -> Void
    ) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let cacheStore = cacheStore
        let sourceFingerprintLoader = sourceFingerprintLoader
        let snapshotLoader = snapshotLoader
        let nowProvider = nowProvider
        let cacheWasRestored = cacheStore.isRestored
        let initialLoadingState = force || !cacheWasRestored
        onLoadingChange(initialLoadingState)

        refreshTask = Task { @MainActor [weak self] in
            await Task.detached(priority: .utility) {
                cacheStore.restoreIfNeeded()
            }.value

            guard !Task.isCancelled else { return }
            guard let self, generation == self.refreshGeneration else { return }

            let cachedEntry = cacheStore.entry(for: filter)
            let hasCachedSnapshot = cachedEntry?.snapshot != nil
            if let snapshot = cachedEntry?.snapshot {
                onSnapshotChange(snapshot)
            } else if currentSnapshotFilter != filter {
                onSnapshotChange(UsageAnalyticsSnapshot.empty(filter: filter))
            }
            let restoredLoadingState = force || !hasCachedSnapshot
            if restoredLoadingState != initialLoadingState {
                onLoadingChange(restoredLoadingState)
            }

            let fingerprint = await Task.detached(priority: .utility) {
                sourceFingerprintLoader(claudeAllConfigDirs)
            }.value

            guard !Task.isCancelled else { return }
            guard generation == self.refreshGeneration else { return }

            let validationDate = nowProvider()
            if !force,
               let entry = cacheStore.entry(for: filter),
               entry.sourceFingerprint == fingerprint,
               cacheStore.isEntryTemporallyFresh(
                   for: filter,
                   now: validationDate,
                   calendar: .current
               ) {
                cacheStore.markValidatedInBackground(
                    filter: filter,
                    sourceFingerprint: fingerprint,
                    at: validationDate
                )
                onLoadingChange(false)
                self.refreshTask = nil
                return
            }

            if !hasCachedSnapshot {
                onLoadingChange(true)
            }

            let snapshot = await Task.detached(priority: .utility) {
                snapshotLoader(filter, claudeAllConfigDirs, fingerprint)
            }.value

            guard !Task.isCancelled else { return }
            guard generation == self.refreshGeneration else { return }

            cacheStore.saveInBackground(snapshot: snapshot, sourceFingerprint: fingerprint)
            onSnapshotChange(snapshot)
            onLoadingChange(false)
            self.refreshTask = nil
        }
    }
}
