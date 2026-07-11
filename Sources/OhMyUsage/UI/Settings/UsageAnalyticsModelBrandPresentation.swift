import SwiftUI

/**
 * [INPUT]: 依赖 analytics 模型的 modelID、providerName、appType 展示事实，以及 BundledIconView 的资源加载能力。
 * [OUTPUT]: 对外提供 UsageAnalyticsModelBrandPresentation、UsageAnalyticsModelBrandResolver 与紧凑品牌图标视图。
 * [POS]: Settings 使用统计的模型品牌展示边界；集中消化命名差异，避免 SwiftUI 页面散落字符串判断。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

struct UsageAnalyticsModelBrandPresentation: Equatable {
    var iconName: String
    var fallbackSystemIcon: String
}

enum UsageAnalyticsModelBrandResolver {
    private static let generic = UsageAnalyticsModelBrandPresentation(
        iconName: "menu_relay_icon",
        fallbackSystemIcon: "cpu"
    )

    static func resolve(
        modelID: String,
        providerName: String,
        appType: String
    ) -> UsageAnalyticsModelBrandPresentation {
        let model = normalized(modelID)
        let provider = normalized(providerName)
        let app = normalized(appType)

        if let presentation = presentationForModel(model) {
            return presentation
        }
        if provider != "多个来源", provider != "mixed",
           let presentation = presentationForProvider(provider) {
            return presentation
        }
        if let presentation = presentationForProvider(app) {
            return presentation
        }
        return generic
    }

    private static func presentationForModel(
        _ value: String
    ) -> UsageAnalyticsModelBrandPresentation? {
        if hasAnyPrefix(value, ["gpt", "chatgpt", "codex", "o1", "o3", "o4"]) {
            return presentation(icon: "menu_codex_icon", fallback: "brain.head.profile")
        }
        if value.contains("claude") {
            return presentation(icon: "menu_claude_icon", fallback: "sparkles")
        }
        if value.contains("gemini") {
            return presentation(icon: "menu_gemini_icon", fallback: "diamond.fill")
        }
        if value.contains("deepseek") {
            return presentation(icon: "menu_deepseek_icon", fallback: "waveform")
        }
        if value.contains("kimi") || value.contains("moonshot") {
            return presentation(icon: "menu_kimi_icon", fallback: "moon.stars.fill")
        }
        if value.contains("minimax") {
            return presentation(icon: "menu_minimax_icon", fallback: "m.square.fill")
        }
        if value.contains("mimo") {
            return presentation(icon: "menu_mimo_icon", fallback: "m.circle.fill")
        }
        if value.contains("qwen") {
            return presentation(icon: "menu_qwen_icon", fallback: "q.circle.fill")
        }
        if value.contains("glm") || value.contains("zhipu") {
            return presentation(icon: "menu_zai_icon", fallback: "z.square.fill")
        }
        return nil
    }

    private static func presentationForProvider(
        _ value: String
    ) -> UsageAnalyticsModelBrandPresentation? {
        if containsAny(value, ["openai", "chatgpt", "codex"]) {
            return presentation(icon: "menu_codex_icon", fallback: "brain.head.profile")
        }
        if containsAny(value, ["anthropic", "claude"]) {
            return presentation(icon: "menu_claude_icon", fallback: "sparkles")
        }
        if containsAny(value, ["google", "gemini"]) {
            return presentation(icon: "menu_gemini_icon", fallback: "diamond.fill")
        }
        if value.contains("deepseek") {
            return presentation(icon: "menu_deepseek_icon", fallback: "waveform")
        }
        if containsAny(value, ["kimi", "moonshot"]) {
            return presentation(icon: "menu_kimi_icon", fallback: "moon.stars.fill")
        }
        if value.contains("minimax") {
            return presentation(icon: "menu_minimax_icon", fallback: "m.square.fill")
        }
        if value.contains("mimo") {
            return presentation(icon: "menu_mimo_icon", fallback: "m.circle.fill")
        }
        if containsAny(value, ["openrouter", "open router"]) {
            return presentation(icon: "menu_openrouter_icon", fallback: "arrow.triangle.branch")
        }
        if value.contains("qwen") {
            return presentation(icon: "menu_qwen_icon", fallback: "q.circle.fill")
        }
        if containsAny(value, ["z.ai", "zhipu", "bigmodel"]) {
            return presentation(icon: "menu_zai_icon", fallback: "z.square.fill")
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func hasAnyPrefix(_ value: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { value.hasPrefix($0) }
    }

    private static func containsAny(_ value: String, _ fragments: [String]) -> Bool {
        fragments.contains { value.contains($0) }
    }

    private static func presentation(
        icon: String,
        fallback: String
    ) -> UsageAnalyticsModelBrandPresentation {
        UsageAnalyticsModelBrandPresentation(iconName: icon, fallbackSystemIcon: fallback)
    }
}

struct UsageAnalyticsModelBrandIcon: View {
    var presentation: UsageAnalyticsModelBrandPresentation
    var size: CGFloat = 12

    var body: some View {
        BundledIconView(
            name: presentation.iconName,
            fallback: presentation.fallbackSystemIcon,
            size: size,
            iconOpacity: 0.80
        )
        .frame(width: size + 4, height: size + 4)
    }
}
