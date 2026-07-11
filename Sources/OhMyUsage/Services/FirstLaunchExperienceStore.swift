/**
 * [INPUT]: 依赖 Foundation.UserDefaults 保存已完成的首次启动体验版本
 * [OUTPUT]: 对外提供 FirstLaunchExperienceStoring 协议与 FirstLaunchExperienceStore 实现
 * [POS]: Services 的轻量启动状态边界，由应用生命周期消费，不依赖 AppKit 或 SwiftUI
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation

protocol FirstLaunchExperienceStoring: AnyObject {
    func consumePresentationIfNeeded(currentVersion: Int) -> Bool
    func reset()
}

final class FirstLaunchExperienceStore: FirstLaunchExperienceStoring {
    static let currentExperienceVersion = 1

    private static let completedVersionDefaultsKey = "CraftMeter.FirstLaunchExperienceVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func consumePresentationIfNeeded(currentVersion: Int = currentExperienceVersion) -> Bool {
        guard currentVersion > 0 else { return false }

        let completedVersion = defaults.integer(forKey: Self.completedVersionDefaultsKey)
        guard completedVersion < currentVersion else { return false }

        defaults.set(currentVersion, forKey: Self.completedVersionDefaultsKey)
        return true
    }

    func reset() {
        defaults.removeObject(forKey: Self.completedVersionDefaultsKey)
    }
}
