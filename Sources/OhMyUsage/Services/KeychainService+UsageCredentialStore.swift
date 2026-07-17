import OhMyUsageDomain
import OhMyUsageInfrastructure

/**
 * [INPUT]: 依赖 KeychainService 的 CraftMeter vault 读写能力、Domain 的 provider identity 与 Infrastructure 的 UsageCredentialStore 协议。
 * [OUTPUT]: 让 KeychainService 作为 Provider 身份凭据存储注入 Application/Provider 运行时。
 * [POS]: Services 的领域协议适配层；不定义 Keychain 策略，只把 providerID 映射到默认 service account。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

extension KeychainService: UsageCredentialStore {
    func credential(for providerID: UsageProviderIdentity) async throws -> String? {
        readToken(service: Self.defaultServiceName, account: providerID.rawValue)
    }

    func saveCredential(_ credential: String, for providerID: UsageProviderIdentity) async throws {
        _ = saveToken(credential, service: Self.defaultServiceName, account: providerID.rawValue)
    }

    func removeCredential(for providerID: UsageProviderIdentity) async throws {
        _ = deleteToken(service: Self.defaultServiceName, account: providerID.rawValue)
    }
}
