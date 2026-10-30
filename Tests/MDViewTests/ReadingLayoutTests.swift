import AppKit
import XCTest
@testable import MDView

final class ReadingLayoutTests: XCTestCase {
    func testAutoLayoutViewportDoesNotAddToTheInitialDocumentWidth() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        window.contentView = root
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        // The production window attaches its reader before Auto Layout sizes the scroll view.
        let view = ReadingView.make(in: scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        for width: CGFloat in [400, 1200, 600] {
            window.setContentSize(NSSize(width: width, height: 600))
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.frame.width, width, accuracy: 1)
            XCTAssertEqual(view.frame.width, scroll.contentView.bounds.width, accuracy: 1)
        }
    }
    func testContentReflowsWithMarginsWhenViewportChanges() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 880, height: 600))
        scroll.hasVerticalScroller = true
        let view = ReadingView.make(in: scroll)
        let source = """
        # Responsive document
        \(String(repeating: "Words should wrap inside the reading margins. ", count: 20))

        | Feature | Implementation |
        | --- | --- |
        | Text | Native Markdown rendering |

        ![Wide image](image.png)
        """
        let document = NativeMarkdown(source: source, baseURL: URL(fileURLWithPath: "/tmp/readme.md"))
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: 1400, height: 400))
        attachment.bounds = NativeMarkdown.imageBounds(attachment.image!.size)
        document.text.append(NSAttributedString(attachment: attachment))
        view.setDocument(document.text)
        for width: CGFloat in [400, 1200, 600, 400] {
            scroll.setFrameSize(NSSize(width: width, height: 600))
            scroll.tile()
            let container = view.textContainer!
            let manager = view.layoutManager!
            manager.ensureLayout(for: container)
            let viewportWidth = scroll.contentView.bounds.width
            XCTAssertEqual(view.frame.width, viewportWidth, accuracy: 1)
            XCTAssertGreaterThanOrEqual(view.textContainerOrigin.x, 24)
            XCTAssertLessThanOrEqual(container.size.width + 2 * view.textContainerOrigin.x, viewportWidth + 1)
            XCTAssertLessThanOrEqual(attachment.bounds.width, container.size.width - 2 * container.lineFragmentPadding)
            view.scrollRangeToVisible(NSRange(location: document.text.length - 1, length: 1))
            XCTAssertEqual(scroll.contentView.bounds.origin.x, 0, accuracy: 1)
            let range = manager.glyphRange(for: container)
            var lineCount = 0
            manager.enumerateLineFragments(forGlyphRange: range) { _, used, _, _, _ in
                if used.width > 0 {
                    XCTAssertGreaterThanOrEqual(used.minX + view.textContainerOrigin.x, 24)
                    XCTAssertLessThanOrEqual(used.maxX + view.textContainerOrigin.x, viewportWidth - 24)
                    lineCount += 1
                }
            }
            XCTAssertGreaterThan(lineCount, 10)
        }
    }

    func testImageFitsWhenLoadedIntoAnAlreadyNarrowWindow() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let view = ReadingView.make(in: scroll)
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: 1400, height: 400))
        attachment.bounds = NativeMarkdown.imageBounds(attachment.image!.size)
        view.setDocument(NSAttributedString(attachment: attachment))
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        XCTAssertLessThanOrEqual(attachment.bounds.width, view.textContainer!.size.width - 2 * view.textContainer!.lineFragmentPadding)
    }
}
