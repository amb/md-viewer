import AppKit
import XCTest
@testable import MDView

final class DiagramOverlayTests: XCTestCase {
    func testDiagramThemeUsesAppearanceAndSurroundingBackground() {
        let dark = DiagramTheme(appearance: NSAppearance(named: .darkAqua)!, background: .black)
        let light = DiagramTheme(appearance: NSAppearance(named: .aqua)!, background: .white)
        XCTAssertTrue(dark.dark)
        XCTAssertEqual(dark.background, "#000000")
        XCTAssertEqual(dark.text, "#cdd6f4")
        XCTAssertEqual(dark.primary, "#1e1e2e")
        XCTAssertFalse(light.dark)
        XCTAssertEqual(light.background, "#ffffff")
        XCTAssertEqual(light.text, "#4c4f69")
        XCTAssertEqual(light.primary, "#eff1f5")
        XCTAssertNotEqual(light, dark)
    }

    func testAttachmentOpensSameWindowOverlayAndEscapeClosesIt() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let viewer = Viewer()
        viewer.setup()
        let window = NSApp.windows.first { $0.delegate === viewer }!
        let scroll = window.contentView as! NavigationScrollView
        let text = scroll.documentView as! ReadingView
        viewer.changeZoom(by: 5) // Normal document text is now 20 pt.
        defer {
            viewer.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            window.close()
        }
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1000))
        let vector = NSImage(data: canvas.dataWithPDF(inside: canvas.bounds))!
        XCTAssertTrue(vector.representations.contains { $0 is NSPDFImageRep })
        let attachment = NSTextAttachment()
        attachment.image = vector
        attachment.bounds = NativeMarkdown.imageBounds(vector.size)
        let content = NSMutableAttributedString(attachment: attachment)
        content.addAttributes([.diagramID: 0, .diagramPreview: vector, .diagramFontSize: 0.5], range: NSRange(location: 0, length: 1))
        text.setDocument(content)
        let windows = NSApp.windows.count
        let acceptedMouseMovement = window.acceptsMouseMovedEvents
        let manager = text.layoutManager!
        manager.ensureLayout(for: text.textContainer!)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: text.textContainer!)
        let point = text.convert(NSPoint(x: rect.midX + text.textContainerOrigin.x,
                                        y: rect.midY + text.textContainerOrigin.y), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        text.mouseDown(with: click) // Direct delivery, never posted to the desktop.
        let overlay = try! XCTUnwrap(viewer.diagramOverlay)
        XCTAssertEqual(NSApp.windows.count, windows)
        XCTAssertTrue(overlay.superview === window.contentView)
        XCTAssertTrue(window.firstResponder === overlay)
        XCTAssertFalse(text.isSelectable)
        XCTAssertTrue(window.acceptsMouseMovedEvents)
        XCTAssertTrue(overlay.trackingAreas.contains {
            $0.owner === overlay && $0.options.contains([.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect])
        })
        XCTAssertGreaterThanOrEqual(0.5 * overlay.magnification, 20)
        XCTAssertGreaterThan(overlay.magnification, 12) // Large diagrams must not hit the old zoom ceiling.
        let initial = overlay.magnification
        viewer.changeZoom(by: 2)
        XCTAssertGreaterThan(overlay.magnification, initial)
        let menu = NSApp.mainMenu!.items.first { $0.title == "View" }!.submenu!
        let actual = menu.items.first { $0.title == "Actual Size" }!
        NSApp.sendAction(actual.action!, to: viewer, from: nil)
        XCTAssertEqual(overlay.magnification, 1, accuracy: 0.001)
        let fit = menu.items.first { $0.title == "Fit Diagram to Window" }!
        NSApp.sendAction(fit.action!, to: viewer, from: nil)
        XCTAssertGreaterThanOrEqual(0.5 * overlay.magnification, 20)
        window.setContentSize(NSSize(width: 600, height: 600))
        window.contentView!.layoutSubtreeIfNeeded()
        XCTAssertEqual(overlay.bounds.width, window.contentView!.bounds.width, accuracy: 1)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        overlay.keyDown(with: escape)
        XCTAssertNil(viewer.diagramOverlay)
        XCTAssertTrue(window.firstResponder === text)
        XCTAssertTrue(text.isSelectable)
        XCTAssertEqual(window.acceptsMouseMovedEvents, acceptedMouseMovement)
        XCTAssertTrue(NSApp.windows.contains(window))
        viewer.showDiagram(vector)
        let file = NSApp.mainMenu!.items.first { $0.title == "File" }!.submenu!
        let close = file.items.first { $0.title == "Close" }!
        NSApp.sendAction(close.action!, to: viewer, from: nil)
        XCTAssertNil(viewer.diagramOverlay)
        XCTAssertTrue(NSApp.windows.contains(window))
        viewer.showDiagram(vector)
        let rightClick = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        XCTAssertTrue(viewer.handleNavigationEvent(rightClick))
        XCTAssertNil(viewer.diagramOverlay)
        XCTAssertTrue(text.isSelectable)
        XCTAssertTrue(NSApp.windows.contains(window))
        XCTAssertFalse(viewer.handleNavigationEvent(rightClick)) // Normal document context menus remain available.
    }
}
