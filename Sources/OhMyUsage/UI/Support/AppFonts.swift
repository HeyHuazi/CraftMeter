import AppKit
import CoreText
import SwiftUI

/**
 * [INPUT]: 依赖 AppKit/CoreText 与 bundle 中 AnonymousPro-Bold 字体资源。
 * [OUTPUT]: 对外提供一次注册后的 SwiftUI/NSFont 数字字体与系统等宽回退。
 * [POS]: UI Support 的字体注册边界；以锁保护 once 状态，避免视图重绘重复探测和注册资源。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

enum AppFonts {
    private static let numericFontName = "AnonymousPro-Bold"
    private static let registrationLock = NSLock()
    nonisolated(unsafe) private static var didAttemptRegistration = false
    nonisolated(unsafe) private static var numericFontAvailable = false

    static func registerBundledFonts() {
        registerNumericFontIfNeeded()
    }

    static func numeric(size: CGFloat, fallbackWeight: Font.Weight = .semibold) -> Font {
        registerNumericFontIfNeeded()

        guard numericFontAvailable else {
            return .system(size: size, weight: fallbackWeight, design: .monospaced)
        }

        return .custom(numericFontName, size: size)
    }

    static func numericNSFont(size: CGFloat, fallbackWeight: NSFont.Weight = .semibold) -> NSFont {
        registerNumericFontIfNeeded()

        guard numericFontAvailable,
              let font = NSFont(name: numericFontName, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: fallbackWeight)
        }

        return font
    }

    private static func registerNumericFontIfNeeded() {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard !didAttemptRegistration else { return }
        didAttemptRegistration = true

        if NSFont(name: numericFontName, size: 12) != nil {
            numericFontAvailable = true
            return
        }
        guard let fontURL = Bundle.module.url(forResource: "AnonymousPro-Bold", withExtension: "ttf") else {
            return
        }

        var registrationError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
        registrationError?.release()
        numericFontAvailable = NSFont(name: numericFontName, size: 12) != nil
    }
}
