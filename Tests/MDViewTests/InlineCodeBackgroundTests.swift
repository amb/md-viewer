import AppKit
import XCTest
@testable import MDView

final class InlineCodeBackgroundTests: XCTestCase {
    private let drawingOrigin = NSPoint(x: 32, y: 24)
    private func reader(width: CGFloat, nativeBackgrounds: Bool = false) throws -> ReadingView {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/wrapped-inline-code.md")
        let document = NativeMarkdown(source: try String(contentsOf: fixture, encoding: .utf8), baseURL: fixture)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        let view = ReadingView.make(in: scroll)
        if nativeBackgrounds { view.textContainer!.replaceLayoutManager(NSLayoutManager()) }
        view.setDocument(document.text)
        return view
    }

    func testWrappedInlineBackgroundLeavesRightEdgeAndListGutterClear() throws {
        for width: CGFloat in [685, 400] {
            let view = try reader(width: width)
            let manager = view.layoutManager!
            let container = view.textContainer!
            manager.ensureLayout(for: container)
            let code = (view.string as NSString).range(of: "if args.backend == \"file\"")
            let glyphs = manager.glyphRange(forCharacterRange: code, actualCharacterRange: nil)
            let bitmap = renderBackgrounds(view)
            for token in ["--backend", "main()", "inline code"] {
                let range = (view.string as NSString).range(of: token)
                let bounds = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
                XCTAssertGreaterThan(alpha(bitmap, at: NSPoint(x: bounds.midX, y: bounds.midY)), 0.01,
                                     "Single-line code lost its background: \(token)")
            }
            var rows = 0
            manager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, range, _ in
                let bounds = manager.boundingRect(forGlyphRange: NSIntersectionRange(range, glyphs), in: container)
                let middle = NSPoint(x: bounds.midX, y: line.midY)
                XCTAssertGreaterThan(self.alpha(bitmap, at: middle), 0.01, "Code lost its background")
                if range.location > glyphs.location {
                    XCTAssertEqual(self.alpha(bitmap, at: NSPoint(x: 10, y: line.midY)), 0,
                                   "Background leaked into the hanging-indent gutter")
                }
                if NSMaxRange(range) < NSMaxRange(glyphs), bounds.maxX < container.size.width - 2 {
                    let blank = NSPoint(x: (bounds.maxX + container.size.width) / 2, y: line.midY)
                    XCTAssertEqual(self.alpha(bitmap, at: blank), 0,
                                   "Background continued past the wrapped text")
                }
                rows += 1
            }
            XCTAssertGreaterThan(rows, 1, "Fixture must reproduce a wrapped inline span")
            let fenced = (view.string as NSString).range(of: "use_file_backend(args)\n")
            let fencedGlyph = manager.glyphRange(forCharacterRange: fenced, actualCharacterRange: nil)
            let row = manager.lineFragmentRect(forGlyphAt: fencedGlyph.location, effectiveRange: nil)
            XCTAssertGreaterThan(alpha(bitmap, at: NSPoint(x: container.size.width - 2, y: row.midY)), 0.01,
                                 "Fenced code should keep its full-width background")
        }
    }

    func testTextLayoutAndTemporaryHighlightsMatchNativeRendering() throws {
        let view = try reader(width: 685)
        let native = try reader(width: 685, nativeBackgrounds: true)
        for reader in [view, native] { reader.layoutManager!.ensureLayout(for: reader.textContainer!) }
        XCTAssertEqual(view.string, native.string)
        XCTAssertEqual(view.textContainerInset, native.textContainerInset)
        let manager = view.layoutManager!
        let nativeManager = native.layoutManager!
        XCTAssertEqual(manager.numberOfGlyphs, nativeManager.numberOfGlyphs)
        for glyph in 0..<manager.numberOfGlyphs {
            XCTAssertEqual(manager.location(forGlyphAt: glyph), nativeManager.location(forGlyphAt: glyph))
            XCTAssertEqual(manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
                           nativeManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
        }
        // Temporary backgrounds are used by native highlighting; retain their native geometry.
        let range = NSRange(location: 0, length: view.textStorage!.length)
        for reader in [view, native] {
            reader.layoutManager!.addTemporaryAttribute(.backgroundColor, value: NSColor.magenta, forCharacterRange: range)
        }
        let actual = renderBackgrounds(view)
        let expected = renderBackgrounds(native)
        XCTAssertEqual(actual.tiffRepresentation, expected.tiffRepresentation)
    }

    private func renderBackgrounds(_ view: ReadingView) -> NSBitmapImageRep {
        let manager = view.layoutManager!
        let container = view.textContainer!
        manager.ensureLayout(for: container)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(container.size.width + 2 * drawingOrigin.x)),
            pixelsHigh: Int(ceil(manager.usedRect(for: container).maxY + 2 * drawingOrigin.y)) + 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill(using: .copy)
        manager.drawBackground(forGlyphRange: manager.glyphRange(for: container), at: drawingOrigin)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(_ bitmap: NSBitmapImageRep, at point: NSPoint) -> CGFloat {
        bitmap.colorAt(x: Int(point.x + drawingOrigin.x),
                       y: bitmap.pixelsHigh - 1 - Int(point.y + drawingOrigin.y))!.alphaComponent
    }
}
