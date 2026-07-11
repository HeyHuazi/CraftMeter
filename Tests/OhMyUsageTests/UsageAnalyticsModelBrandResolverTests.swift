import XCTest
@testable import OhMyUsage

final class UsageAnalyticsModelBrandResolverTests: XCTestCase {
    func testOpenAIModelFamiliesUseExistingCodexIcon() {
        for modelID in ["gpt-5", "GPT-4.1-mini", "o3", "o4-mini", "codex-mini-latest"] {
            XCTAssertEqual(
                resolve(modelID: modelID).iconName,
                "menu_codex_icon",
                modelID
            )
        }
    }

    func testKnownModelFamiliesUseExistingBundledIcons() {
        let expectations = [
            "claude-opus-4-1": "menu_claude_icon",
            "gemini-2.5-pro": "menu_gemini_icon",
            "deepseek-r1": "menu_deepseek_icon",
            "moonshot-v1-128k": "menu_kimi_icon",
            "MiniMax-M2": "menu_minimax_icon",
            "mimo-v2": "menu_mimo_icon",
            "qwen3-coder-plus": "menu_qwen_icon",
            "glm-4.5": "menu_zai_icon"
        ]

        for (modelID, iconName) in expectations {
            XCTAssertEqual(resolve(modelID: modelID).iconName, iconName, modelID)
        }
    }

    func testProviderIdentifiesOpaqueModelID() {
        XCTAssertEqual(
            resolve(modelID: "custom-model", providerName: "OpenRouter").iconName,
            "menu_openrouter_icon"
        )
        XCTAssertEqual(
            resolve(modelID: "enterprise-alias", providerName: "Anthropic").iconName,
            "menu_claude_icon"
        )
    }

    func testModelIdentityWinsOverRelayProvider() {
        XCTAssertEqual(
            resolve(modelID: "gpt-5", providerName: "OpenRouter").iconName,
            "menu_codex_icon"
        )
    }

    func testMultipleSourcesOnlyUseBrandWhenModelIsRecognizable() {
        XCTAssertEqual(
            resolve(modelID: "claude-sonnet-4", providerName: "多个来源").iconName,
            "menu_claude_icon"
        )
        XCTAssertEqual(
            resolve(modelID: "internal-alias", providerName: "多个来源").fallbackSystemIcon,
            "cpu"
        )
    }

    func testAppTypeProvidesLastReliableFallback() {
        XCTAssertEqual(
            resolve(modelID: "internal-alias", providerName: "多个来源", appType: "gemini-cli").iconName,
            "menu_gemini_icon"
        )
    }

    private func resolve(
        modelID: String,
        providerName: String = "",
        appType: String = ""
    ) -> UsageAnalyticsModelBrandPresentation {
        UsageAnalyticsModelBrandResolver.resolve(
            modelID: modelID,
            providerName: providerName,
            appType: appType
        )
    }
}
