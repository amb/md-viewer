import AppKit

/// Clip inline-code backgrounds to the code on each visual row, including hanging indents.
final class MarkdownLayoutManager: NSLayoutManager {
    private var backgroundOrigin = NSPoint.zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let previousOrigin = backgroundOrigin
        backgroundOrigin = origin
        defer { backgroundOrigin = previousOrigin }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        guard let storage = textStorage, charRange.length > 0,
              charRange.location != NSNotFound, NSMaxRange(charRange) <= storage.length,
              storage.attribute(.inlineCode, at: charRange.location, effectiveRange: nil) as? Bool == true,
              storage.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? NSColor == color else {
            // Preserve native selection highlights, fenced code, and table backgrounds.
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }

        // Layout queries reuse AppKit's rectangle buffer, so preserve it before querying glyph bounds.
        let backgrounds = Array(UnsafeBufferPointer(start: rectArray, count: rectCount))
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var clippedRects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
            let code = NSIntersectionRange(glyphs, lineGlyphs)
            guard code.length > 0 else { return }
            let bounds = self.boundingRect(forGlyphRange: code, in: container)
            let row = NSRect(x: bounds.minX + self.backgroundOrigin.x,
                             y: line.minY + self.backgroundOrigin.y,
                             width: bounds.width, height: line.height)
            for background in backgrounds {
                let clipped = background.intersection(row)
                if !clipped.isEmpty { clippedRects.append(clipped) }
            }
        }
        guard !clippedRects.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        color.setFill()
        clippedRects.withUnsafeBufferPointer {
            super.fillBackgroundRectArray($0.baseAddress!, count: $0.count, forCharacterRange: charRange, color: color)
        }
    }
}
