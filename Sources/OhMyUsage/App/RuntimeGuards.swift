/**
 * [INPUT]: 依赖 AppKit 应用生命周期、StatusBarController、首次启动状态与更新说明状态存储
 * [OUTPUT]: 对外提供单实例锁与 AppLifecycleDelegate，完成菜单栏运行时启动及首次可见反馈
 * [POS]: App 模块的进程入口守卫，连接系统生命周期与 CraftMeter 窗口/菜单栏控制器
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import Foundation

private enum SingleInstanceActivationBridge {
    static let distributedNotificationName = Notification.Name("com.heyhuazi.craftmeter.activate-existing-instance")

    @MainActor
    static func notifyExistingInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            distributedNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fd: Int32 = -1
    private let lockPath = "/tmp/com.heyhuazi.craftmeter.app.lock"

    private init() {}

    func acquire() -> Bool {
        if fd != -1 {
            return true
        }

        fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd != -1 else {
            return false
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        close(fd)
        fd = -1
        return false
    }

    deinit {
        if fd != -1 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var activationObserver: NSObjectProtocol?
    private let postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore()
    private let firstLaunchExperienceStore: any FirstLaunchExperienceStoring = FirstLaunchExperienceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchInterval = AppPerformanceTracer.begin("ApplicationLaunch")
        defer { AppPerformanceTracer.end(launchInterval) }
        // Ensure app stays menu-bar only even if started from terminal context.
        applyBundledAppIcon()
        AppFonts.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)

        if !SingleInstanceLock.shared.acquire() {
            SingleInstanceActivationBridge.notifyExistingInstance()
            NSApp.terminate(nil)
            return
        }

        startActivationBridgeObservation()
        let viewModel = AppViewModel()
        AppPerformanceTracer.event("ViewModelEssentialReady")
        statusBarController = StatusBarController(viewModel: viewModel)
        AppPerformanceTracer.event("StatusBarReady")
        if !presentPostUpdateReleaseNotesIfNeeded(currentVersion: viewModel.currentAppVersion) {
            presentFirstLaunchExperienceIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopActivationBridgeObservation()
    }

    @MainActor
    private func applyBundledAppIcon() {
        AppIconImageProvider.applyApplicationIcon(size: 256)
    }

    @MainActor
    private func startActivationBridgeObservation() {
        stopActivationBridgeObservation()
        let center = DistributedNotificationCenter.default()
        activationObserver = center.addObserver(
            forName: SingleInstanceActivationBridge.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                NSRunningApplication.current.activate(options: [])
                self.statusBarController?.showSettingsWindow()
            }
        }
    }

    @MainActor
    private func stopActivationBridgeObservation() {
        guard let activationObserver else { return }
        DistributedNotificationCenter.default().removeObserver(activationObserver)
        self.activationObserver = nil
    }

    @MainActor
    @discardableResult
    private func presentPostUpdateReleaseNotesIfNeeded(currentVersion: String) -> Bool {
        guard let releaseNotes = postUpdateReleaseNotesStore.consumePresentationIfNeeded(
            currentVersion: currentVersion
        ) else {
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            ReleaseNotesWindowController.shared.show(releaseNotes: releaseNotes)
        }
        return true
    }

    @MainActor
    private func presentFirstLaunchExperienceIfNeeded() {
        guard firstLaunchExperienceStore.consumePresentationIfNeeded(
            currentVersion: FirstLaunchExperienceStore.currentExperienceVersion
        ) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.statusBarController?.showSettingsWindow()
        }
    }
}
