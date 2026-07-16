import Foundation
import os

/**
 * [INPUT]: 依赖 os signpost 与进程内单调时钟，只接收稳定阶段名，不接收用户内容或本地路径。
 * [OUTPUT]: 对外提供启动/菜单 interval 及 analytics/cache 事件埋点。
 * [POS]: App 的性能可观测性边界；用 Points of Interest 建立优化基线，不参与业务状态与控制流。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum AppPerformanceTracer {
    private static let log = OSLog(
        subsystem: "com.heyhuazi.craftmeter.app",
        category: .pointsOfInterest
    )

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let id: OSSignpostID
    }

    static func begin(_ name: StaticString) -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Interval(name: name, id: id)
    }

    static func end(_ interval: Interval) {
        os_signpost(.end, log: log, name: interval.name, signpostID: interval.id)
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
