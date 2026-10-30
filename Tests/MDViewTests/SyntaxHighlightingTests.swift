import AppKit
import XCTest
@testable import MDView

final class SyntaxHighlightingTests: XCTestCase {
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.textColor, .backgroundColor: NSColor.quaternaryLabelColor
    ]

    func testCatppuccinColorsResolveForBothAppearances() {
        let result = SyntaxHighlighter.highlight("let value = 42", language: "swift", attributes: attributes)
        let keyword = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        for (appearance, colors): (NSAppearance.Name, [(NSColor, UInt32)]) in [
            (.darkAqua, [(keyword, 0xcba6f7), (CodeTheme.text, 0xcdd6f4),
                         (CodeTheme.background, 0x1e1e2e), (CodeTheme.string, 0xa6e3a1)]),
            (.aqua, [(keyword, 0x8839ef), (CodeTheme.text, 0x4c4f69),
                     (CodeTheme.background, 0xeff1f5), (CodeTheme.string, 0x40a02b)])
        ] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                for (color, hex) in colors {
                    let rgb = color.usingColorSpace(.sRGB)!
                    XCTAssertEqual(rgb.redComponent, CGFloat((hex >> 16) & 255) / 255, accuracy: 0.0001)
                    XCTAssertEqual(rgb.greenComponent, CGFloat((hex >> 8) & 255) / 255, accuracy: 0.0001)
                    XCTAssertEqual(rgb.blueComponent, CGFloat(hex & 255) / 255, accuracy: 0.0001)
                }
            }
        }
    }

    func testSwiftStringsCommentsUnicodeAndSourcePreservation() {
        let code = "let greeting = \"Hello 👋 // not a comment\"\n// let count = 42\nprint(greeting)\nlet count = 42\n"
        let result = SyntaxHighlighter.highlight(code, language: "Swift", attributes: attributes)
        XCTAssertEqual(result.string, code)
        assertColor(CodeTheme.keyword, on: "let", in: result)
        assertColor(CodeTheme.string, on: "// not a comment", in: result)
        assertColor(CodeTheme.comment, on: "// let count = 42", in: result)
        assertColor(CodeTheme.blue, on: "print", in: result)
        let lastNumber = (code as NSString).range(of: "42", options: .backwards)
        XCTAssertEqual(result.attribute(.foregroundColor, at: lastNumber.location, effectiveRange: nil) as? NSColor, CodeTheme.number)
        XCTAssertEqual(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, attributes[.font] as? NSFont)
        XCTAssertEqual(result.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor, .quaternaryLabelColor)
    }

    func testCommonLanguageGrammarsAndAliases() {
        let samples: [(String, String, String, NSColor)] = [
            ("swift", "let n = 1", "let", CodeTheme.keyword),
            ("py", "def hello(): # comment", "def", CodeTheme.keyword),
            ("typescript", "interface Item { value: number }", "interface", CodeTheme.keyword),
            ("rs", "pub fn main() {}", "fn", CodeTheme.keyword),
            ("c++", "#include <stdio.h>\nint main() {}", "int", CodeTheme.keyword),
            ("java", "public class Example {}", "class", CodeTheme.keyword),
            ("cs", "using System;", "using", CodeTheme.keyword),
            ("golang", "func main() {}", "func", CodeTheme.keyword),
            ("bash", "if test -n \"$HOME\"; then echo yes; fi", "if", CodeTheme.keyword),
            ("rb", "def hello; true; end", "def", CodeTheme.keyword),
            ("sql", "SELECT * FROM users WHERE active = true", "SELECT", CodeTheme.keyword),
            ("json", "{\"name\": \"value\", \"enabled\": true}", "\"name\"", CodeTheme.blue),
            ("yml", "enabled: true # comment", "enabled", CodeTheme.blue),
            ("toml", "enabled = true", "enabled", CodeTheme.blue),
            ("xml", "<root name=\"value\">Text</root>", "<root", CodeTheme.blue),
            ("css", "body { color: #aabbcc; }", "color", CodeTheme.blue),
            ("diff", "--- a/file\n+++ b/file\n+added\n-removed\n", "+added", CodeTheme.string)
        ]
        for (language, code, token, color) in samples {
            let result = SyntaxHighlighter.highlight(code, language: language, attributes: attributes)
            XCTAssertEqual(result.string, code, language)
            assertColor(color, on: token, in: result)
        }
    }

    func testMultilineAndRawStringsHideKeywordsAndComments() {
        let python = "text = \"\"\"First\n# still a string\nTrue\n\"\"\"\n# actual comment\n"
        let result = SyntaxHighlighter.highlight(python, language: "python", attributes: attributes)
        assertColor(CodeTheme.string, on: "# still a string", in: result)
        assertColor(CodeTheme.string, on: "True", in: result)
        assertColor(CodeTheme.comment, on: "# actual comment", in: result)
        let swift = "let text = #\"literal \"quote\" // content\"#\n"
        assertColor(CodeTheme.string, on: "// content", in: SyntaxHighlighter.highlight(swift, language: "swift", attributes: attributes))
        let rust = "fn borrow<'a>(s: &'a str) -> &'a str { s }\nlet text = r#\"literal \"quote\" // content\"#;"
        let highlighted = SyntaxHighlighter.highlight(rust, language: "rust", attributes: attributes)
        assertColor(.textColor, on: "'a", in: highlighted)
        assertColor(CodeTheme.string, on: "// content", in: highlighted)
    }

    func testUnlabeledUnknownAndHugeBlocksStayPlain() {
        for language in [nil, "text", "unknown-language"] {
            let result = SyntaxHighlighter.highlight("let x = 42\n", language: language, attributes: attributes)
            assertColor(.textColor, on: "let", in: result)
        }
        let large = String(repeating: "let x = 1\n", count: 25_000)
        let result = SyntaxHighlighter.highlight(large, language: "swift", attributes: attributes)
        XCTAssertEqual(result.string, large)
        assertColor(.textColor, on: "let", in: result)
    }

    func testNativeMarkdownIntegrationPreservesBlankLinesAndDoesNotColorProse() {
        let code = "\nlet café = \"Hello 👋\"\n\n"
        let document = NativeMarkdown(source: "let stays plain.\n\n~~~swift\n" + code + "~~~\n",
                                      baseURL: URL(fileURLWithPath: "/tmp/readme.md"))
        XCTAssertTrue(document.text.string.contains(code))
        assertColor(.textColor, on: "let stays plain", in: document.text)
        assertColor(CodeTheme.keyword, on: "let café", in: document.text)
        assertColor(CodeTheme.string, on: "\"Hello 👋\"", in: document.text)
    }

    private func assertColor(_ color: NSColor, on token: String, in text: NSAttributedString,
                             file: StaticString = #filePath, line: UInt = #line) {
        let range = (text.string as NSString).range(of: token)
        XCTAssertNotEqual(range.location, NSNotFound, token, file: file, line: line)
        guard range.location != NSNotFound else { return }
        XCTAssertEqual(text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                       color, token, file: file, line: line)
    }
}
