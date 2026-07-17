import Foundation
import Security

/**
 * [INPUT]: 依赖统一 KeychainAccessPolicy 与 Security generic password API，并允许测试注入隔离的写入状态适配器。
 * [OUTPUT]: 对外提供显式导入/账户切换使用的硬失败非交互读取，以及失败不删除旧项的 update-or-add 保存能力。
 * [POS]: Services 的外部系统凭据边界；后台 Provider 不应调用本类型，XCTest 默认短路，任何失败都不会升级为 shell、认证 UI 或破坏性写入。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum SecurityCredentialReader {
    struct SecureStoreWriter: @unchecked Sendable {
        var update: (_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
        var add: (_ attributes: CFDictionary) -> OSStatus

        static let live = SecureStoreWriter(
            update: { query, attributes in
                SecItemUpdate(query, attributes)
            },
            add: { attributes in
                SecItemAdd(attributes, nil)
            }
        )
    }
    private struct CredentialCacheKey: Hashable {
        let service: String
        let account: String?
    }

    private enum CachedCredentialValue {
        case value(String)
        case missing
    }

    private struct CachedCredential {
        let value: CachedCredentialValue
        let expiresAt: Date
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var credentialCache: [CredentialCacheKey: CachedCredential] = [:]
    private static let successCacheTTL: TimeInterval = 120
    private static let failureBackoffInterval: TimeInterval = 8

    static func readGenericPassword(service: String, account: String? = nil, bypassCache: Bool = false) -> String? {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account)
        let cacheKey = CredentialCacheKey(service: normalizedService, account: normalizedAccount)
        let now = Date()

        if !bypassCache, let cached = cachedCredential(for: cacheKey, now: now) {
            switch cached {
            case .value(let value):
                return value
            case .missing:
                return nil
            }
        }

        if isRunningInXCTest {
            cache(.missing, for: cacheKey, now: now)
            return nil
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: false),
            uniquingKeysWith: { _, rhs in rhs }
        )
        if let normalizedAccount {
            query[kSecAttrAccount as String] = normalizedAccount
        } else if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            cache(.value(text), for: cacheKey, now: now)
            return text
        }
        KeychainAccessPolicy.logFailure(
            operation: "read",
            kind: KeychainAccessPolicy.credentialKind(service: normalizedService),
            interactive: false,
            status: status
        )
        cache(.missing, for: cacheKey, now: now)
        return nil
    }

    @discardableResult
    static func saveGenericPassword(
        service: String,
        account: String? = nil,
        text: String,
        secureStore: SecureStoreWriter = .live,
        allowUnderXCTest: Bool = false
    ) -> Bool {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account) ?? normalizedService
        guard allowUnderXCTest || !isRunningInXCTest else {
            return false
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecAttrAccount as String: normalizedAccount,
        ]
        query.merge(
            KeychainAccessPolicy.authenticationAttributes(interactive: false),
            uniquingKeysWith: { _, rhs in rhs }
        )
        let data = Data(text.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let didSave = KeychainGenericPasswordWriter.updateOrAdd(
            update: {
                secureStore.update(query as CFDictionary, updateAttributes as CFDictionary)
            },
            add: {
                var addAttributes: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: normalizedService,
                    kSecAttrAccount as String: normalizedAccount,
                    kSecValueData as String: data,
                ]
                addAttributes.merge(
                    KeychainAccessPolicy.authenticationAttributes(interactive: false),
                    uniquingKeysWith: { _, rhs in rhs }
                )
                return secureStore.add(addAttributes as CFDictionary)
            }
        )
        guard didSave else {
            return false
        }

        let now = Date()
        cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount), now: now)
        cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil), now: now)
        return true
    }

    private static func cachedCredential(for key: CredentialCacheKey, now: Date) -> CachedCredentialValue? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        purgeExpiredEntriesLocked(now: now)
        guard let entry = credentialCache[key] else {
            return nil
        }
        return entry.value
    }

    private static func cache(_ value: CachedCredentialValue, for key: CredentialCacheKey, now: Date) {
        let ttl: TimeInterval
        switch value {
        case .value:
            ttl = successCacheTTL
        case .missing:
            ttl = failureBackoffInterval
        }

        cacheLock.lock()
        credentialCache[key] = CachedCredential(
            value: value,
            expiresAt: now.addingTimeInterval(max(0, ttl))
        )
        purgeExpiredEntriesLocked(now: now)
        cacheLock.unlock()
    }

    private static func purgeExpiredEntriesLocked(now: Date) {
        credentialCache = credentialCache.filter { _, value in
            value.expiresAt > now
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var isRunningInXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTest_SESSION_IDENTIFIER"] != nil ||
            ProcessInfo.processInfo.processName.lowercased().contains("xctest") ||
            Bundle.main.bundlePath.lowercased().contains(".xctest")
    }

    static func nonInteractiveAuthenticationAttributesForTesting() -> [String: Any] {
        KeychainAccessPolicy.authenticationAttributes(interactive: false)
    }
}
