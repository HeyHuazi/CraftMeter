import Foundation

/**
 * [INPUT]: 依赖 JWTInspector 解析官方 OAuth ID token 的显示身份。
 * [OUTPUT]: 为 CodexProvider 与 ClaudeProvider 提供文件/环境凭据载体及来源标记。
 * [POS]: Providers 的官方凭据值模型；只在 Provider 调用栈内承载秘密，不负责 Keychain、持久化或日志。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct CodexCredentials {
    var accessToken: String
    var refreshToken: String?
    var accountId: String?
    var idToken: String?
    var lastRefresh: Date?
    var source: CodexCredentialSource

    var accountLabel: String? {
        guard let idToken else { return nil }
        return JWTInspector.email(idToken)
    }

    var accountSubject: String? {
        guard let idToken else { return nil }
        return JWTInspector.subject(idToken)
    }
}

enum CodexCredentialSource {
    case file(String)
}

struct ClaudeCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var scopes: [String]
    var source: ClaudeCredentialSource
    var inferenceOnly: Bool

    var accountLabel: String? { nil }
}

enum ClaudeCredentialSource {
    case file(String)
    case environment
}
