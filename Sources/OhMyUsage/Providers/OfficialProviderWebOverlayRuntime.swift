import OhMyUsageDomain
import Foundation

/**
 * [INPUT]: 依赖 CraftMeter Keychain 中已保存 Cookie 与官方 Web overlay 策略。
 * [OUTPUT]: 对外提供只读已保存 Cookie 的 Web quota header 解析及快照合并。
 * [POS]: Providers 的 Web overlay 运行时；forceRefresh 不授予浏览器访问，实时导入必须走显式协调器。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct OfficialBrowserCookieImportStrategy {
    let providerKey: String
    let hostContains: String
    let namedCookie: String?
    let autoImportMissingCredential: String
    let manualCredentialFallback: String
    let normalizeManualHeader: (String) -> String?
    let normalizeDetectedHeader: (String) -> String?
}

enum OfficialProviderWebOverlayRuntime {

    static func resolveCookieHeader(
        official: OfficialProviderConfig,
        descriptorID: String,
        keychain: KeychainService,
        browserCookieService: BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff? = nil,
        webRetryBackoffInterval: TimeInterval? = nil,
        forceRefresh: Bool,
        strategy: OfficialBrowserCookieImportStrategy
    ) async throws -> BrowserCookieHeader {
        let service = KeychainService.defaultServiceName

        if let account = official.manualCookieAccount,
           let stored = keychain.readToken(service: service, account: account),
           let header = strategy.normalizeManualHeader(stored),
           !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return BrowserCookieHeader(header: header, source: "Manual")
        }

        guard official.webMode != .manual else {
            throw ProviderError.missingCredential(official.manualCookieAccount ?? strategy.manualCredentialFallback)
        }

        guard official.webMode == .autoImport else {
            throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
        }

        _ = descriptorID
        _ = browserCookieService
        _ = webReadBackoff
        _ = webRetryBackoffInterval
        _ = forceRefresh
        throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
    }

    static func hasStoredManualCookie(
        official: OfficialProviderConfig,
        keychain: KeychainService,
        normalizeManualHeader: (String) -> String?
    ) -> Bool {
        guard let account = official.manualCookieAccount,
              let stored = keychain.readToken(service: KeychainService.defaultServiceName, account: account),
              let header = normalizeManualHeader(stored),
              !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    static func merge(primary: UsageSnapshot, overlay: UsageSnapshot, sourceLabel: String) -> UsageSnapshot {
        var merged = primary
        merged.sourceLabel = sourceLabel
        merged.accountLabel = primary.accountLabel ?? overlay.accountLabel

        var existing = Set(merged.quotaWindows.map(\.id))
        for window in overlay.quotaWindows where !existing.contains(window.id) {
            merged.quotaWindows.append(window)
            existing.insert(window.id)
        }

        for (key, value) in overlay.extras where merged.extras[key] == nil {
            merged.extras[key] = value
        }
        if merged.note.isEmpty {
            merged.note = overlay.note
        }
        return merged
    }

}
