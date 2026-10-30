import AppKit
import XCTest
@testable import MDView

final class WheelZoomTests: XCTestCase {
    func testWheelZoomUsesPhysicalDirectionAndRequiresCommand() {
        let scroll = NavigationScrollView()
        var steps: [Int] = []
        scroll.zoom = { steps.append($0) }
        scroll.scrollWheel(with: WheelEvent(delta: 1))
        scroll.scrollWheel(with: WheelEvent(delta: -1))
        scroll.scrollWheel(with: WheelEvent(delta: -1, inverted: true))
        scroll.scrollWheel(with: WheelEvent(delta: 1, inverted: true))
        scroll.scrollWheel(with: WheelEvent(delta: 0))
        scroll.scrollWheel(with: WheelEvent(delta: 1, command: false))
        XCTAssertEqual(steps, [1, -1, 1, -1])
    }

    func testPreciseScrollingAccumulatesAndIgnoresMomentum() {
        let scroll = NavigationScrollView()
        var steps: [Int] = []
        scroll.zoom = { steps.append($0) }
        for _ in 0..<10 { scroll.scrollWheel(with: WheelEvent(delta: 2, precise: true)) }
        XCTAssertEqual(steps, [1])
        scroll.scrollWheel(with: WheelEvent(delta: -40, precise: true))
        XCTAssertEqual(steps, [1, -2])
        scroll.scrollWheel(with: WheelEvent(delta: 100, precise: true, momentum: .changed))
        XCTAssertEqual(steps, [1, -2])
    }

    func testWheelChangesNativeTextSizeWithinLimitsAndPreservesPosition() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zoom-\(UUID().uuidString).md")
        try String(repeating: "Native text should zoom.\n\n", count: 100).write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let viewer = Viewer()
        viewer.setup()
        let window = NSApp.windows.first { $0.delegate === viewer }!
        let scroll = window.contentView as! NavigationScrollView
        let text = scroll.documentView as! ReadingView
        defer {
            viewer.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            window.close()
        }
        XCTAssertTrue(viewer.open(file))
        func size() -> CGFloat { (text.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        XCTAssertEqual(size(), 15)
        scroll.scrollWheel(with: WheelEvent(delta: 1))
        XCTAssertEqual(size(), 16)
        XCTAssertEqual(scroll.contentView.bounds.minY, 300, accuracy: 1)
        scroll.scrollWheel(with: WheelEvent(delta: -1))
        XCTAssertEqual(size(), 15)
        for _ in 0..<40 { scroll.scrollWheel(with: WheelEvent(delta: 1)) }
        XCTAssertEqual(size(), 30)
        for _ in 0..<40 { scroll.scrollWheel(with: WheelEvent(delta: -1)) }
        XCTAssertEqual(size(), 10)
        XCTAssertEqual(viewer.history.entries.count, 1)
    }
}

/// In-process events only: no posting to the desktop or reliance on device settings.
private final class WheelEvent: NSEvent {
    let delta: CGFloat
    let command: Bool
    let inverted: Bool
    let precise: Bool
    let momentum: NSEvent.Phase
    init(delta: CGFloat, command: Bool = true, inverted: Bool = false,
         precise: Bool = false, momentum: NSEvent.Phase = []) {
        self.delta = delta; self.command = command; self.inverted = inverted
        self.precise = precise; self.momentum = momentum
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not used for synthetic events") }
    override var type: NSEvent.EventType { .scrollWheel }
    override var modifierFlags: NSEvent.ModifierFlags { command ? .command : [] }
    override var scrollingDeltaY: CGFloat { delta }
    override var scrollingDeltaX: CGFloat { 0 }
    override var isDirectionInvertedFromDevice: Bool { inverted }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var phase: NSEvent.Phase { [] }
}
