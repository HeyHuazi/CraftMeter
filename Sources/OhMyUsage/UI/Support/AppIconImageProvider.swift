import AppKit

/**
 * [INPUT]: 依赖 AppKit 与应用 bundle 中的 AppIcon/app_icon_source 资源。
 * [OUTPUT]: 对外提供按尺寸复制的非模板应用图标，并可应用到 NSApplication。
 * [POS]: UI Support 的图标解码边界；原始 bundle 图像只加载一次，调用方始终获得独立副本。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

@MainActor
enum AppIconImageProvider {
    private static var cachedSourceImage: NSImage?

    static func image(size: CGFloat? = nil) -> NSImage? {
        guard let source = sourceImage(),
              let image = source.copy() as? NSImage else {
            return nil
        }
        if let size {
            image.size = NSSize(width: size, height: size)
        }
        image.isTemplate = false
        return image
    }

    static func applyApplicationIcon(size: CGFloat = 256) {
        guard let image = image(size: size) else { return }
        NSApp.applicationIconImage = image
    }

    private static func sourceImage() -> NSImage? {
        if let cachedSourceImage {
            return cachedSourceImage
        }
        let image = bundledImage() ?? applicationIconImage()
        cachedSourceImage = image
        return image
    }

    private static func bundledImage() -> NSImage? {
        let candidates: [(Bundle, String, String)] = [
            (.main, "AppIcon", "icns"),
            (.module, "AppIcon", "icns"),
            (.module, "app_icon_source", "png")
        ]

        for (bundle, name, ext) in candidates {
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  let image = NSImage(contentsOf: url),
                  image.isValid else {
                continue
            }
            return image
        }

        return nil
    }

    private static func applicationIconImage() -> NSImage? {
        guard let image = NSApp.applicationIconImage?.copy() as? NSImage,
              image.isValid else {
            return nil
        }
        return image
    }
}
