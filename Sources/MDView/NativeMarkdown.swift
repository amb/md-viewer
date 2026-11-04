import AppKit
import ImageIO
import Markdown

extension NSAttributedString.Key {
    static let diagramID = Self("MDView.diagram")
    static let diagramPreview = Self("MDView.diagramPreview")
    static let diagramFontSize = Self("MDView.diagramFontSize")
    static let headingID = Self("MDView.heading")
    static let inlineCode = Self("MDView.inlineCode")
}

struct DiagramJob: Codable {
    let id: Int
    let source: String
}

/// Native text storage is the only retained document representation.
final class NativeMarkdown {
    let text = NSMutableAttributedString()
    var diagrams: [DiagramJob] = []
    let baseURL: URL
    let size: CGFloat
    private var imagePixels = 0
    private var headingCounts: [String: Int] = [:]

    init(source: String, baseURL: URL, size: CGFloat = 15) {
        self.baseURL = baseURL
        self.size = size
        render(Document(parsing: source), attributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.textColor
        ])
    }

    private func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
        text.append(NSAttributedString(string: string, attributes: attributes))
    }

    private func paragraph(_ depth: Int = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 9
        style.headIndent = CGFloat(depth) * 22
        style.firstLineHeadIndent = style.headIndent
        return style
    }

    private func render(_ node: Markup, attributes: [NSAttributedString.Key: Any], depth: Int = 0) {
        var a = attributes
        if a[.paragraphStyle] == nil { a[.paragraphStyle] = paragraph(depth) }
        let start = text.length
        switch node {
        case let n as Markdown.Text: append(n.string, a)
        case _ as SoftBreak: append(" ", a)
        case _ as LineBreak: append("\n", a)
        case let n as InlineCode:
            a[.font] = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
            a[.backgroundColor] = NSColor.quaternaryLabelColor
            a[.inlineCode] = true
            append(n.code, a)
        case let n as CodeBlock:
            a[.font] = NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            a[.foregroundColor] = CodeTheme.text
            a[.backgroundColor] = CodeTheme.background
            let style = paragraph(depth)
            style.paragraphSpacing = 2
            style.lineSpacing = 0
            a[.paragraphStyle] = style
            if n.language?.lowercased() == "mermaid", diagrams.count < 32 {
                a.removeValue(forKey: .backgroundColor)
                let id = diagrams.count
                diagrams.append(DiagramJob(id: id, source: n.code))
                a[.diagramID] = id
                append("Rendering diagram…", a)
                a.removeValue(forKey: .diagramID)
                append("\n", a)
            } else {
                let code = n.code.hasSuffix("\n") ? n.code : n.code + "\n"
                text.append(SyntaxHighlighter.highlight(code, language: n.language, attributes: a))
                // Keep code rows compact, with normal paragraph spacing after the block.
                let endingStyle = style.mutableCopy() as! NSMutableParagraphStyle
                endingStyle.paragraphSpacing = paragraph(depth).paragraphSpacing
                let lastLine = text.mutableString.paragraphRange(for: NSRange(location: text.length - 1, length: 1))
                text.addAttribute(.paragraphStyle, value: endingStyle, range: lastLine)
            }
        case let n as Heading:
            a[.font] = NSFont.systemFont(ofSize: size + CGFloat(max(0, 7 - n.level)) * 2, weight: .semibold)
            let slug = Self.slug(n.plainText)
            let count = headingCounts[slug, default: 0]
            headingCounts[slug] = count + 1
            a[.headingID] = count == 0 ? slug : "\(slug)-\(count)"
            children(n, a, depth)
            append("\n", a)
        case let n as Strong:
            let font = a[.font] as? NSFont ?? .systemFont(ofSize: size)
            a[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            children(n, a, depth)
        case let n as Emphasis:
            let font = a[.font] as? NSFont ?? .systemFont(ofSize: size)
            a[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            children(n, a, depth)
        case _ as Strikethrough:
            a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            children(node, a, depth)
        case let n as Markdown.Link:
            if let destination = n.destination,
               let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL,
               ["http", "https", "mailto", "file"].contains(url.scheme ?? "") { a[.link] = url }
            children(n, a, depth)
        case let n as Markdown.Image:
            if let source = n.source, let url = Self.localURL(source, relativeTo: baseURL),
               imagePixels < 8_000_000, let image = Self.thumbnail(url, pixelLimit: 1_400),
               imagePixels + Int(image.size.width * image.size.height) <= 8_000_000 {
                imagePixels += Int(image.size.width * image.size.height)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = Self.imageBounds(image.size)
                text.append(NSAttributedString(attachment: attachment))
            } else { append("[Image: \(n.plainText)]", a) }
        case let n as OrderedList:
            for (index, item) in n.children.enumerated() {
                listItem(item, prefix: "\(Int(n.startIndex) + index).", a, depth)
            }
        case let n as UnorderedList:
            for item in n.children { listItem(item, prefix: "•", a, depth) }
        case let n as BlockQuote:
            a[.foregroundColor] = NSColor.secondaryLabelColor
            a[.paragraphStyle] = paragraph(depth + 1)
            children(n, a, depth + 1)
        case let n as Table:
            renderTable(n, a, depth)
        case _ as ThematicBreak:
            a[.foregroundColor] = NSColor.separatorColor
            append("────────────────────────\n", a)
        case let n as HTMLBlock:
            a[.font] = NSFont.monospacedSystemFont(ofSize: size - 2, weight: .regular)
            append(n.rawHTML + "\n", a)
        case let n as InlineHTML: append(n.rawHTML, a)
        default:
            children(node, a, depth)
            if node is Paragraph { append("\n", a) }
        }
        if node is BlockMarkup, !(node is ListItem), text.length > start,
           !text.string.hasSuffix("\n") { append("\n", a) }
    }

    private func children(_ node: Markup, _ attributes: [NSAttributedString.Key: Any], _ depth: Int) {
        for child in node.children { render(child, attributes: attributes, depth: depth) }
    }

    private func listItem(_ item: Markup, prefix: String, _ attributes: [NSAttributedString.Key: Any], _ depth: Int) {
        var a = attributes
        let style = paragraph(depth + 1)
        style.firstLineHeadIndent = CGFloat(depth) * 22
        style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
        a[.paragraphStyle] = style
        let check = (item as? ListItem)?.checkbox
        append("\(check.map { $0 == .checked ? "☑" : "☐" } ?? prefix)\t", a)
        children(item, a, depth + 1)
    }

    private func renderTable(_ node: Table, _ attributes: [NSAttributedString.Key: Any], _ depth: Int) {
        let table = NSTextTable()
        table.numberOfColumns = node.maxColumnCount
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        let rows: [Markup] = [node.head] + Array(node.body.children)
        for (rowIndex, row) in rows.enumerated() {
            for (column, cell) in row.children.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1,
                                             startingColumn: column, columnSpan: 1)
                block.setValue(100 / CGFloat(max(1, node.maxColumnCount)), type: .percentageValueType, for: .width)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 { block.backgroundColor = .quaternaryLabelColor }
                let style = paragraph(depth)
                style.textBlocks = [block]
                if column < node.columnAlignments.count {
                    switch node.columnAlignments[column] {
                    case .center: style.alignment = .center
                    case .right: style.alignment = .right
                    default: break
                    }
                }
                var a = attributes
                a[.paragraphStyle] = style
                if rowIndex == 0 { a[.font] = NSFont.systemFont(ofSize: size, weight: .semibold) }
                children(cell, a, depth)
                append("\n", a)
            }
        }
    }

    static func slug(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" })
            .replacingOccurrences(of: " ", with: "-")
    }

    /// Only read images inside the document folder, including after resolving symlinks.
    static func localURL(_ path: String, relativeTo base: URL) -> URL? {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL, url.isFileURL else { return nil }
        let root = base.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return resolved.path.hasPrefix(root) ? resolved : nil
    }

    static func thumbnail(_ url: URL, pixelLimit: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func imageBounds(_ size: NSSize, width: CGFloat = 680) -> NSRect {
        let scale = min(1, width / max(1, size.width))
        return NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }
}
