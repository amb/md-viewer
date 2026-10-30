import AppKit

struct DiagramTheme: Codable, Equatable {
    let dark: Bool
    let background: String
    let text: String
    let primary: String
    let secondary: String
    let accent: String
    let line: String

    init(appearance: NSAppearance, background: NSColor = .textBackgroundColor) {
        dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var colors: [String] = []
        appearance.performAsCurrentDrawingAppearance {
            for color in [background, CodeTheme.text, CodeTheme.background, CodeTheme.surface, CodeTheme.blue, CodeTheme.comment] {
                let rgb = color.usingColorSpace(.sRGB)!
                colors.append(String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()),
                                     Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded())))
            }
        }
        self.background = colors[0]; text = colors[1]; primary = colors[2]
        secondary = colors[3]; accent = colors[4]; line = colors[5]
    }
}
