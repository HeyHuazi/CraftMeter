import Foundation
import Security

/**
 * [INPUT]: 依赖 KeychainAccessPolicy、Security.framework 与 KeychainGenericPasswordWriter。
 * [OUTPUT]: 为 KeychainService 提供 live generic-password read/read-all/update-or-add/delete 适配实现；所有 delete 同样硬禁止认证 UI。
 * [POS]: Services 的 CraftMeter vault 系统适配层；后台查询硬禁止认证 UI，显式准备流程可交互，失败仅输出脱敏状态。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

extension KeychainService {
    static func liveReadData(service: String, account: String, interactive: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: interactive),
            uniquingKeysWith: { _, rhs in rhs }
        )

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              !data.isEmpty else {
            KeychainAccessPolicy.logFailure(
                operation: "read",
                kind: KeychainAccessPolicy.credentialKind(service: service),
                interactive: interactive,
                status: status
            )
            return nil
        }
        return data
    }

    static func liveReadAll(service: String, interactive: Bool) -> [String: String]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: interactive),
            uniquingKeysWith: { _, rhs in rhs }
        )

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            KeychainAccessPolicy.logFailure(
                operation: "read-all",
                kind: KeychainAccessPolicy.credentialKind(service: service),
                interactive: interactive,
                status: status
            )
            return nil
        }

        return tokensFromEnumeratedKeychainRows(item)
    }

    static func liveSaveData(_ data: Data, service: String, account: String, interactive: Bool) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: interactive),
            uniquingKeysWith: { _, rhs in rhs }
        )

        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        return KeychainGenericPasswordWriter.updateOrAdd(
            update: {
                let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
                KeychainAccessPolicy.logFailure(
                    operation: "update",
                    kind: KeychainAccessPolicy.credentialKind(service: service),
                    interactive: interactive,
                    status: status
                )
                return status
            },
            add: {
                var addAttributes: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]
                addAttributes.merge(
                    KeychainAccessPolicy.authenticationAttributes(interactive: interactive),
                    uniquingKeysWith: { _, rhs in rhs }
                )
                let status = SecItemAdd(addAttributes as CFDictionary, nil)
                KeychainAccessPolicy.logFailure(
                    operation: "add",
                    kind: KeychainAccessPolicy.credentialKind(service: service),
                    interactive: interactive,
                    status: status
                )
                return status
            }
        )
    }

    static func liveDeleteItem(service: String, account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: false),
            uniquingKeysWith: { _, rhs in rhs }
        )
        let status = SecItemDelete(query as CFDictionary)
        KeychainAccessPolicy.logFailure(
            operation: "delete",
            kind: KeychainAccessPolicy.credentialKind(service: service),
            interactive: false,
            status: status
        )
    }

    static func liveDeleteAll(service: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: false),
            uniquingKeysWith: { _, rhs in rhs }
        )
        let status = SecItemDelete(query as CFDictionary)
        KeychainAccessPolicy.logFailure(
            operation: "delete-all",
            kind: KeychainAccessPolicy.credentialKind(service: service),
            interactive: false,
            status: status
        )
    }
}
