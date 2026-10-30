import AppKit

/// Catppuccin palette v1.8.0: Mocha in dark mode, Latte in light mode.
/// https://github.com/catppuccin/palette (MIT; see bundled third-party notices).
enum CodeTheme {
    static let text = adaptive("text", dark: 0xcdd6f4, light: 0x4c4f69)
    static let background = adaptive("background", dark: 0x1e1e2e, light: 0xeff1f5)
    static let surface = adaptive("surface", dark: 0x313244, light: 0xe6e9ef)
    static let comment = adaptive("comment", dark: 0x9399b2, light: 0x7c7f93)
    static let string = adaptive("string", dark: 0xa6e3a1, light: 0x40a02b)
    static let number = adaptive("number", dark: 0xfab387, light: 0xfe640b)
    static let keyword = adaptive("keyword", dark: 0xcba6f7, light: 0x8839ef)
    static let blue = adaptive("blue", dark: 0x89b4fa, light: 0x1e66f5)
    static let type = adaptive("type", dark: 0xf9e2af, light: 0xdf8e1d)
    static let removed = adaptive("removed", dark: 0xf38ba8, light: 0xd20f39)

    private static func adaptive(_ name: String, dark: UInt32, light: UInt32) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        let darkColor = rgb(dark), lightColor = rgb(light)
        return NSColor(name: NSColor.Name("MDView.code." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        }
    }
}
