import Foundation
import Security

/**
 * [INPUT]: 依赖调用方提供的 Security.framework update/add 操作及其 OSStatus。
 * [OUTPUT]: 对外提供严格的 generic-password update-or-add 状态机；仅 item-not-found 才允许新增。
 * [POS]: Services 的 Keychain 写入策略内核，被 CraftMeter vault 与外部桌面凭据写入共同复用，禁止权限失败后删除旧项。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum KeychainGenericPasswordWriter {
    static func updateOrAdd(
        update: () -> OSStatus,
        add: () -> OSStatus
    ) -> Bool {
        let updateStatus = update()
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return add() == errSecSuccess
        default:
            return false
        }
    }
}
