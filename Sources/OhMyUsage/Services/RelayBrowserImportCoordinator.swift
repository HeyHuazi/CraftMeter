/**
 * [INPUT]: 依赖 BrowserCredentialService 发现浏览器 Cookie/Bearer，依赖 Relay manifest 声明认证策略与必填字段
 * [OUTPUT]: 对外提供 Relay 浏览器导入预检结果，只暴露脱敏来源与下一步动作
 * [POS]: Services 的 Relay 导入发现边界；不发网络请求、不写配置或 Keychain，验证与提交由 App 层编排
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import OhMyUsageDomain

enum RelayBrowserImportNextAction: String, Equatable {
    case verify
    case enterUserID
    case manualFallback
}

struct RelayBrowserImportDiscovery: Equatable {
    var host: String
    var adapterID: String
    var credentialSource: String?
    var credentialKind: String?
    var nextAction: RelayBrowserImportNextAction
    var message: String
}

struct RelayBrowserImportCoordinator {
    let browserCredentialService: BrowserCredentialService

    func discover(draft: RelaySettingsDraft, manifest: RelayAdapterManifest) -> RelayBrowserImportDiscovery {
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(draft.baseURL)
        guard let host = URL(string: normalizedBaseURL)?.host?.lowercased(), !host.isEmpty else {
            return RelayBrowserImportDiscovery(
                host: "",
                adapterID: manifest.id,
                credentialSource: nil,
                credentialKind: nil,
                nextAction: .manualFallback,
                message: "invalid relay base URL"
            )
        }

        let strategies = Set(manifest.authStrategies.map(\.kind))
        let bearer = strategies.contains(.browserBearer)
            ? browserCredentialService.detectBearerTokenCandidates(host: host, accessIntent: .interactiveImport).first
            : nil
        let cookie = strategies.contains(.browserCookieHeader)
            ? browserCredentialService.detectCookieHeader(host: host, accessIntent: .interactiveImport)
            : nil

        let detected = bearer.map { ($0.source, "Bearer") } ?? cookie.map { ($0.source, "Cookie") }
        guard let detected else {
            return RelayBrowserImportDiscovery(
                host: host,
                adapterID: manifest.id,
                credentialSource: nil,
                credentialKind: nil,
                nextAction: .manualFallback,
                message: "no browser login credential found"
            )
        }

        let requiresUserID = manifest.setup?.requiredInputs.contains(.userID) == true || (
            manifest.balanceRequest.userID == nil &&
            !(manifest.balanceRequest.userIDHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
        if requiresUserID && draft.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RelayBrowserImportDiscovery(
                host: host,
                adapterID: manifest.id,
                credentialSource: detected.0,
                credentialKind: detected.1,
                nextAction: .enterUserID,
                message: "browser credential found; user ID is required"
            )
        }

        return RelayBrowserImportDiscovery(
            host: host,
            adapterID: manifest.id,
            credentialSource: detected.0,
            credentialKind: detected.1,
            nextAction: .verify,
            message: "browser credential found"
        )
    }
}
