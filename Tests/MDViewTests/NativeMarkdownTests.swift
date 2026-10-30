import AppKit
import XCTest
@testable import MDView

final class NativeMarkdownTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/docs/readme.md")

    func testReadableMarkdownAndNativeFormatting() {
        let document = NativeMarkdown(source: """
        # Heading
        A **bold** and *italic* [link](guide.md), `code`, ~~gone~~.

        3. First
           - Nested
        4. Second

        - [x] Done
        - [ ] Pending

        | Name | Value |
        | :--- | ---: |
        | One | 2 |

        > Quoted
        """, baseURL: file)
        let output = document.text.string
        for expected in ["Heading", "A bold and italic link, code, gone.", "3.\tFirst", "•\tNested", "4.\tSecond", "☑\tDone", "☐\tPending", "One", "Quoted"] {
            XCTAssertTrue(output.contains(expected), "Missing \(expected): \(output)")
        }
        let bold = (output as NSString).range(of: "bold").location
        let font = document.text.attribute(.font, at: bold, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let link = (output as NSString).range(of: "link").location
        XCTAssertEqual((document.text.attribute(.link, at: link, effectiveRange: nil) as? URL)?.path, "/tmp/docs/guide.md")
        let table = (output as NSString).range(of: "One").location
        XCTAssertTrue((document.text.attribute(.paragraphStyle, at: table, effectiveRange: nil) as! NSParagraphStyle).textBlocks.first is NSTextTableBlock)
    }

    func testMermaidIsQueuedAndCodeIsPreserved() {
        let document = NativeMarkdown(source: """
        ```mermaid
        graph LR
        A --> B
        ```
        ```swift
        let a = 1
        ```
        """, baseURL: file)
        XCTAssertEqual(document.diagrams.count, 1)
        XCTAssertTrue(document.diagrams[0].source.contains("A --> B"))
        XCTAssertTrue(document.text.string.contains("let a = 1"))
        XCTAssertFalse(document.text.string.contains("graph LR"))
    }

    func testImagePathsCannotEscapeDocumentFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("readme.md")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        XCTAssertNotNil(NativeMarkdown.localURL("image.png", relativeTo: base))
        for path in ["../secret.png", "escape/passwd", "https://example.com/image.png", "file:///etc/passwd"] {
            XCTAssertNil(NativeMarkdown.localURL(path, relativeTo: base), path)
        }
    }

    func testHTMLRemainsInertAndDangerousLinksAreNotClickable() {
        let document = NativeMarkdown(source: "<script>alert(1)</script>\n\n[run](javascript:alert)\n\n![remote](https://example.com/pixel.png)", baseURL: file)
        XCTAssertTrue(document.text.string.contains("<script>"))
        XCTAssertTrue(document.text.string.contains("[Image: remote]"))
        document.text.enumerateAttribute(.link, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            XCTAssertNil(value)
        }
    }

    func testRepeatedHeadingAnchorsAndDiagramLimit() {
        let source = "# Hello World\n# Hello World\n" + String(repeating: "```mermaid\ngraph LR; A-->B\n```\n", count: 33)
        let document = NativeMarkdown(source: source, baseURL: file)
        var ids: [String] = []
        document.text.enumerateAttribute(.headingID, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            if let id = value as? String { ids.append(id) }
        }
        XCTAssertEqual(ids, ["hello-world", "hello-world-1"])
        XCTAssertEqual(document.diagrams.count, 32)
        XCTAssertTrue(document.text.string.contains("graph LR; A-->B"))
    }

    func testBothTableColumnsFitTheReadingWidth() {
        let document = NativeMarkdown(source: "| Feature | Implementation |\n| --- | --- |\n| Text | AppKit + cmark |", baseURL: file)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.textContainer?.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        view.textStorage?.setAttributedString(document.text)
        let manager = view.layoutManager!
        manager.ensureLayout(for: view.textContainer!)
        let second = (document.text.string as NSString).range(of: "Implementation")
        let glyphs = manager.glyphRange(forCharacterRange: second, actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        XCTAssertGreaterThan(bounds.minX, 200)
        XCTAssertLessThan(bounds.maxX, 800)
    }
}
