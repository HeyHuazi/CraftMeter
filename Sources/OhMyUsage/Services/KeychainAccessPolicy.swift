import Foundation
import LocalAuthentication
import OSLog
import Security

/**
 * [INPUT]: 依赖 LocalAuthentication、Security 与 OSLog 的认证查询属性和系统日志能力。
 * [OUTPUT]: 对外提供统一的 Keychain 认证属性，以及仅含操作类别、凭据类别和 OSStatus 的脱敏失败审计。
 * [POS]: Services 的 Keychain 策略单一真相源；后台请求同时禁止 LAContext 交互与 Security.framework 认证 UI，显式准备流程才允许交互。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum KeychainAccessPolicy {
    enum CredentialKind: String {
        case craftMeterVault = "craftmeter.vault"
        case browserSafeStorage = "browser.safe-storage"
        case codexExternal = "codex.external-keychain"
        case claudeExternal = "claude.external-keychain"
        case copilotExternal = "copilot.external-keychain"
        case legacyMigration = "legacy-migration"
        case externalGeneric = "external.generic"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.heyhuazi.craftmeter.app",
        category: "KeychainAccess"
    )

    static func authenticationAttributes(interactive: Bool) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        return [
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: interactive
                ? kSecUseAuthenticationUIAllow
                : kSecUseAuthenticationUIFail,
        ]
    }

    static func credentialKind(service: String) -> CredentialKind {
        switch service {
        case KeychainService.defaultServiceName:
            return .craftMeterVault
        case "Codex Auth":
            return .codexExternal
        case "Claude Code-credentials":
            return .claudeExternal
        case "copilot-cli", "gh:github.com":
            return .copilotExternal
        default:
            if service.localizedCaseInsensitiveContains("Safe Storage") {
                return .browserSafeStorage
            }
            if KeychainService.isLegacyServiceName(service) {
                return .legacyMigration
            }
            return .externalGeneric
        }
    }

    static func logFailure(
        operation: String,
        kind: CredentialKind,
        interactive: Bool,
        status: OSStatus
    ) {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        logger.error(
            "Keychain failure operation=\(operation, privacy: .public) kind=\(kind.rawValue, privacy: .public) interactive=\(interactive, privacy: .public) status=\(status, privacy: .public)"
        )
    }
}
