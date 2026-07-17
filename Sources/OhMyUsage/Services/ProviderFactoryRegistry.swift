import Foundation
import OhMyUsageDomain

/**
 * [INPUT]: 依赖 ProviderDescriptor 与共享 Keychain/浏览器服务依赖集合。
 * [OUTPUT]: 对外提供覆盖全部 ProviderType 的构造注册表。
 * [POS]: Services 的 Provider composition root；向后台 Provider 注入 CraftMeter vault，外部凭据访问不在工厂内升级。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct ProviderFactoryRegistry {
    struct Dependencies {
        let keychain: KeychainService
        let kimiCookieService: KimiBrowserCookieService
        let browserCookieService: BrowserCookieService
        let browserCredentialService: BrowserCredentialService
    }

    typealias Maker = (ProviderDescriptor, Dependencies) -> UsageProvider

    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(
            Set(makers.keys) == Set(ProviderType.allCases),
            "ProviderFactoryRegistry must register every ProviderType"
        )
    }

    var registeredProviderTypes: Set<ProviderType> {
        Set(makers.keys)
    }

    func makeProvider(
        for descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        guard let maker = makers[descriptor.type] else {
            preconditionFailure("Missing provider maker for \(descriptor.type)")
        }
        return maker(descriptor, dependencies)
    }

    private static func makeDefaultMakers() -> [ProviderType: Maker] {
        [
            .codex: { descriptor, dependencies in
                CodexProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .claude: { descriptor, dependencies in
                ClaudeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .gemini: { descriptor, _ in
                GeminiProvider(descriptor: descriptor)
            },
            .copilot: { descriptor, _ in
                CopilotProvider(descriptor: descriptor)
            },
            .microsoftCopilot: { descriptor, dependencies in
                MicrosoftCopilotProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain
                )
            },
            .zai: { descriptor, _ in
                ZaiProvider(descriptor: descriptor)
            },
            .amp: { descriptor, _ in
                AmpProvider(descriptor: descriptor)
            },
            .cursor: { descriptor, _ in
                CursorProvider(descriptor: descriptor)
            },
            .jetbrains: { descriptor, _ in
                JetBrainsProvider(descriptor: descriptor)
            },
            .kiro: { descriptor, _ in
                KiroProvider(descriptor: descriptor)
            },
            .windsurf: { descriptor, _ in
                WindsurfProvider(descriptor: descriptor)
            },
            .trae: { descriptor, dependencies in
                TraeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCredentialService: dependencies.browserCredentialService
                )
            },
            .openrouterCredits: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .openrouterAPI: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .ollamaCloud: { descriptor, dependencies in
                OllamaCloudProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .opencodeGo: { descriptor, dependencies in
                OpenCodeGoProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .relay: ProviderFactoryRegistry.makeRelayProvider,
            .open: ProviderFactoryRegistry.makeRelayProvider,
            .dragon: ProviderFactoryRegistry.makeRelayProvider,
            .kimi: { descriptor, dependencies in
                KimiSmartProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.kimiCookieService
                )
            }
        ]
    }

    private static func makeRelayProvider(
        descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        RelayProvider(
            descriptor: descriptor,
            keychain: dependencies.keychain,
            browserCredentialService: dependencies.browserCredentialService
        )
    }
}
