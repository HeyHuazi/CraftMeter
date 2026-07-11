import Foundation
import OhMyUsageApplication

/**
 * [INPUT]: 依赖 UsageAnalyticsRepository 的源指纹与自然周期摘要加载能力。
 * [OUTPUT]: 对外提供按源变化和自然周期边界去重的菜单栏摘要刷新。
 * [POS]: App 的轻量历史统计协调器，与设置页完整 analytics 刷新链路相互独立。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

@MainActor
final class MenuBarUsageAnalyticsCoordinator {
    typealias SourceFingerprintLoader = @Sendable ([String]) -> UsageAnalyticsSourceFingerprint
    typealias SummaryLoader = @Sendable ([String]) -> UsageAnalyticsMenuBarSummary

    private let sourceFingerprintLoader: SourceFingerprintLoader
    private let summaryLoader: SummaryLoader
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private var refreshTask: Task<Void, Never>?
    private var lastFingerprint: UsageAnalyticsSourceFingerprint?
    private var lastPeriodAnchor: Date?
    private var lastValidationAt: Date?
    private let validationInterval: TimeInterval = 60

    init(
        repository: UsageAnalyticsRepository = UsageAnalyticsRepository(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        sourceFingerprintLoader: SourceFingerprintLoader? = nil,
        summaryLoader: SummaryLoader? = nil
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.sourceFingerprintLoader = sourceFingerprintLoader ?? { directories in
            repository.sourceFingerprint(claudeAllConfigDirs: directories)
        }
        self.summaryLoader = summaryLoader ?? { directories in
            repository.menuBarSummary(claudeAllConfigDirs: directories)
        }
    }

    func refreshIfNeeded(
        enabled: Bool,
        claudeAllConfigDirs: [String],
        force: Bool = false,
        onSummaryChange: @escaping @MainActor (UsageAnalyticsMenuBarSummary) -> Void
    ) {
        guard enabled else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }
        guard refreshTask == nil else { return }

        let sourceFingerprintLoader = sourceFingerprintLoader
        let summaryLoader = summaryLoader
        let now = nowProvider()
        let periodAnchor = calendar.startOfDay(for: now)
        let shouldForceForPeriodChange = lastPeriodAnchor != periodAnchor
        if !force,
           !shouldForceForPeriodChange,
           let lastValidationAt,
           now.timeIntervalSince(lastValidationAt) < validationInterval {
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            let fingerprint = await Task.detached(priority: .utility) {
                sourceFingerprintLoader(claudeAllConfigDirs)
            }.value
            guard !Task.isCancelled, let self else { return }
            lastValidationAt = now

            if !force,
               !shouldForceForPeriodChange,
               fingerprint == lastFingerprint {
                refreshTask = nil
                return
            }

            let summary = await Task.detached(priority: .utility) {
                summaryLoader(claudeAllConfigDirs)
            }.value
            guard !Task.isCancelled else { return }

            lastFingerprint = fingerprint
            lastPeriodAnchor = periodAnchor
            refreshTask = nil
            onSummaryChange(summary)
        }
    }
}
