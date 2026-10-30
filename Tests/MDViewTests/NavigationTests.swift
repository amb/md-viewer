import AppKit
import XCTest
@testable import MDView

final class NavigationTests: XCTestCase {
    func testHistoryBranchesAndStaysBounded() {
        var history = NavigationHistory()
        let a = URL(fileURLWithPath: "/tmp/a.md")
        let b = URL(fileURLWithPath: "/tmp/b.md")
        let c = URL(fileURLWithPath: "/tmp/c.md")
        XCTAssertNil(history.target(.back))
        history.visit(a, leaving: .zero)
        history.visit(b, leaving: NSPoint(x: 0, y: 120))
        history.select(history.target(.back)!, leaving: NSPoint(x: 0, y: 300))
        XCTAssertEqual(history.current?.origin.y, 120)
        history.visit(c, leaving: NSPoint(x: 0, y: 150))
        XCTAssertEqual(history.entries.map(\.url), [a, c])
        XCTAssertNil(history.target(.forward))
        history.visit(c, leaving: .zero)
        XCTAssertEqual(history.entries.count, 2)
        for i in 0..<200 { history.visit(URL(fileURLWithPath: "/tmp/\(i).md"), leaving: .zero) }
        XCTAssertEqual(history.entries.count, 128)
        XCTAssertEqual(history.index, 127)
    }

    func testCommonKeyboardPatternsAndRepeatSuppression() {
        for (code, characters, flags, direction): (UInt16, String, NSEvent.ModifierFlags, NavigationDirection) in [
            (33, "[", .command, .back), (30, "]", .command, .forward),
            (123, "\u{f702}", .command, .back), (124, "\u{f703}", .command, .forward),
            (123, "\u{f702}", .option, .back), (124, "\u{f703}", .option, .forward),
            (51, "\u{7f}", [], .back), (51, "\u{7f}", .shift, .forward)
        ] {
            XCTAssertEqual(NavigationInput.command(for: key(code, characters, flags))?.direction, direction)
            XCTAssertEqual(NavigationInput.command(for: key(code, characters, flags, repeatKey: true))?.pressed, false)
        }
        XCTAssertNil(NavigationInput.command(for: key(123, "\u{f702}", [])))
        XCTAssertNil(NavigationInput.command(for: key(123, "\u{f702}", [.command, .shift])))
        XCTAssertNil(NavigationInput.command(for: key(8, "c", .command)))
    }

    func testMouseButtonsAndMediaKeysTriggerOnlyOnPress() {
        for (button, direction): (UInt32, NavigationDirection) in [(3, .back), (4, .forward)] {
            XCTAssertEqual(NavigationInput.command(for: mouse(button))?.direction, direction)
            XCTAssertEqual(NavigationInput.command(for: mouse(button, up: true))?.pressed, false)
        }
        XCTAssertNil(NavigationInput.command(for: mouse(2))) // middle-click remains available
        for (code, direction) in [(18, NavigationDirection.back), (20, .back), (17, .forward), (19, .forward)] {
            XCTAssertEqual(NavigationInput.command(for: media(code))?.direction, direction)
            XCTAssertEqual(NavigationInput.command(for: media(code, up: true))?.pressed, false)
            XCTAssertEqual(NavigationInput.command(for: media(code, repeatKey: true))?.pressed, false)
        }
        XCTAssertNil(NavigationInput.command(for: media(16))) // leave Play/Pause alone
        XCTAssertNil(NavigationInput.command(for: media(0))) // leave volume alone
        let legacyMouse = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 7, data1: 1 << 3, data2: 1 << 3)!
        XCTAssertEqual(NavigationInput.command(for: legacyMouse)?.direction, .back)
    }

    func testLinkNavigationInputsAnchorsAndScrollRestoration() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.md")
        let b = root.appendingPathComponent("b.md")
        let c = root.appendingPathComponent("c.md")
        let paragraphs = String(repeating: "A paragraph with native text.\n\n", count: 100)
        try ("# First\n" + paragraphs).write(to: a, atomically: true, encoding: .utf8)
        try ("# Second\n" + paragraphs + "\n## Target\nEnd.\n").write(to: b, atomically: true, encoding: .utf8)
        try "# Branch\n".write(to: c, atomically: true, encoding: .utf8)
        let viewer = Viewer()
        viewer.setup()
        let window = NSApp.windows.first { $0.delegate === viewer }!
        let scroll = window.contentView as! NavigationScrollView
        let text = scroll.documentView as! ReadingView
        defer {
            viewer.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            window.close()
        }
        XCTAssertTrue(viewer.open(a))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        let originalY = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(originalY, 200)
        let destination = URL(string: b.absoluteString + "#target")!
        XCTAssertTrue(viewer.textView(text, clickedOnLink: destination, at: 0))
        XCTAssertEqual(viewer.history.current?.url, destination)
        let anchorY = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(anchorY, 1000)
        XCTAssertTrue(viewer.handleNavigationEvent(mouse(3)))
        XCTAssertEqual(viewer.history.current?.url, a)
        XCTAssertEqual(scroll.contentView.bounds.minY, originalY, accuracy: 1)
        XCTAssertTrue(viewer.handleNavigationEvent(mouse(4)))
        XCTAssertEqual(viewer.history.current?.url, destination)
        XCTAssertEqual(scroll.contentView.bounds.minY, anchorY, accuracy: 1)
        viewer.handleNavigationEvent(media(18))
        XCTAssertEqual(viewer.history.current?.url, a)
        viewer.handleNavigationEvent(media(18, up: true))
        XCTAssertEqual(viewer.history.current?.url, a)
        viewer.handleNavigationEvent(key(30, "]", .command))
        XCTAssertEqual(viewer.history.current?.url, destination)
        // Standard menu actions use the same history.
        let go = NSApp.mainMenu!.items.first { $0.title == "Go" }!.submenu!
        XCTAssertTrue(NSApp.sendAction(go.items[0].action!, to: viewer, from: nil))
        XCTAssertEqual(viewer.history.current?.url, a)
        XCTAssertTrue(viewer.open(c))
        XCTAssertNil(viewer.history.target(.forward))
        XCTAssertFalse(viewer.validateMenuItem(go.items[1]))
        let count = viewer.history.entries.count
        XCTAssertTrue(viewer.open(c, recordHistory: false))
        XCTAssertEqual(viewer.history.entries.count, count)
        XCTAssertFalse(viewer.open(root.appendingPathComponent("missing.md"), reportErrors: false))
        XCTAssertEqual(viewer.history.current?.url, c)
        try FileManager.default.removeItem(at: a)
        let previous = viewer.history.target(.back)!
        XCTAssertFalse(viewer.open(a, reportErrors: false, historyIndex: previous))
        XCTAssertEqual(viewer.history.current?.url, c)
        // Find-field editing must keep its own word-navigation and deletion keys.
        let field = NSTextView()
        field.isEditable = true
        scroll.addSubview(field)
        window.makeFirstResponder(field)
        XCTAssertFalse(viewer.handleNavigationEvent(key(123, "\u{f702}", .option)))
    }

    private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeatKey, keyCode: code)!
    }
    private func mouse(_ button: UInt32, up: Bool = false) -> NSEvent {
        NSEvent(cgEvent: CGEvent(mouseEventSource: nil, mouseType: up ? .otherMouseUp : .otherMouseDown,
            mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: button)!)!)!
    }
    private func media(_ code: Int, up: Bool = false, repeatKey: Bool = false) -> NSEvent {
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8,
            data1: (code << 16) | (up ? 0x0b00 : 0x0a00) | (repeatKey ? 1 : 0), data2: 0)!
    }
}
