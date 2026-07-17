/**
 * [INPUT]: 依赖 XCTest、隔离 UserDefaults suite 与 FirstLaunchExperienceStore
 * [OUTPUT]: 验证首次启动体验的单次消费、版本升级和重置语义
 * [POS]: CraftMeterTests 的启动状态回归测试，防止菜单栏应用重新出现无反馈启动
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import XCTest
@testable import OhMyUsage

final class FirstLaunchExperienceStoreTests: XCTestCase {
    func testFirstLaunchPresentsOnlyOnceForCurrentExperienceVersion() {
        let defaults = makeDefaults()
        let store = FirstLaunchExperienceStore(defaults: defaults)

        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 1))
        XCTAssertFalse(store.consumePresentationIfNeeded(currentVersion: 1))
    }

    func testNewerExperienceVersionPresentsAgain() {
        let defaults = makeDefaults()
        let store = FirstLaunchExperienceStore(defaults: defaults)

        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 1))
        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 2))
        XCTAssertFalse(store.consumePresentationIfNeeded(currentVersion: 2))
    }

    func testOlderOrInvalidExperienceVersionDoesNotPresent() {
        let defaults = makeDefaults()
        let store = FirstLaunchExperienceStore(defaults: defaults)

        XCTAssertFalse(store.consumePresentationIfNeeded(currentVersion: 0))
        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 2))
        XCTAssertFalse(store.consumePresentationIfNeeded(currentVersion: 1))
    }

    func testResetAllowsPresentationAgain() {
        let defaults = makeDefaults()
        let store = FirstLaunchExperienceStore(defaults: defaults)

        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 1))
        store.reset()
        XCTAssertTrue(store.consumePresentationIfNeeded(currentVersion: 1))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FirstLaunchExperienceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
