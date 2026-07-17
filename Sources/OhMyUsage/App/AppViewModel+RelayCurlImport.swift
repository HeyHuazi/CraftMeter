/**
 * [INPUT]: 依赖 RelayCurlImportCoordinator、RelayDescriptorPreviewBuilder、配置仓储与 Keychain 凭据边界
 * [OUTPUT]: 对外提供 NewAPI cURL 先验证后提交命令，失败时回滚配置与新写凭据
 * [POS]: App 的 NewAPI 高级导入事务边界；将秘密结果立即落入 Keychain，不进入可观察草稿
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import Foundation
import OhMyUsageDomain

@MainActor
extension AppViewModel {
    func importNewAPISiteFromCurl(_ command: String) async -> RelayCurlImportDisplayResult {
        switch await relayCurlImportCoordinator.validate(command) {
        case let .failure(display):
            return display
        case let .success(payload):
            return commitVerifiedCurlImport(payload)
        }
    }

    private func commitVerifiedCurlImport(
        _ payload: RelayCurlImportVerifiedPayload
    ) -> RelayCurlImportDisplayResult {
        let previousConfig = config
        let credentialLabel = payload.credentialKind == .cookie ? "Cookie" : "Bearer"
        let providerName = payload.host
        let baseProvider = ProviderDescriptor.makeOpenRelay(
            name: providerName,
            baseURL: payload.baseURL,
            preferredAdapterID: "generic-newapi"
        )
        var draft = RelaySettingsDraft(provider: baseProvider, preferredAdapterID: "generic-newapi")
        draft.name = providerName
        draft.baseURL = payload.baseURL
        draft.balanceCredentialMode = .manualPreferred
        draft.userID = payload.userID
        draft.authHeader = payload.credentialKind == .cookie ? "Cookie" : "Authorization"
        draft.authScheme = payload.credentialKind == .cookie ? "" : "Bearer"
        draft.quotaDisplayMode = .remaining

        guard let provider = relayDescriptorPreviewBuilder.build(
            draft: draft,
            providers: config.providers + [baseProvider]
        ), let balanceAuth = provider.relayConfig?.balanceAuth,
        let service = balanceAuth.keychainService,
        let account = balanceAuth.keychainAccount else {
            return failure(payload, message: "无法创建 NewAPI 配置")
        }

        config.providers.append(provider)
        if config.statusBarProviderID == nil {
            config.statusBarProviderID = provider.id
        }
        guard credentialAccessService.saveCredential(payload.credential, service: service, account: account) else {
            config = previousConfig
            return failure(payload, message: "凭据验证成功，但无法写入安全存储")
        }
        credentialLookupVersion &+= 1

        guard persistConfiguration(showFeedback: true) else {
            config = previousConfig
            _ = keychain.deleteToken(service: service, account: account)
            credentialLookupVersion &+= 1
            return failure(payload, message: "凭据验证成功，但无法保存站点配置")
        }

        restartPolling()
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
        return RelayCurlImportDisplayResult(
            success: true,
            host: payload.host,
            credentialKind: payload.credentialKind,
            message: "已通过 \(credentialLabel) 验证并保存",
            providerID: provider.id
        )
    }

    private func failure(
        _ payload: RelayCurlImportVerifiedPayload,
        message: String
    ) -> RelayCurlImportDisplayResult {
        RelayCurlImportDisplayResult(
            success: false,
            host: payload.host,
            credentialKind: payload.credentialKind,
            message: message,
            providerID: nil
        )
    }
}
