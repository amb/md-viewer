import AppKit
import XCTest
@testable import MDView

final class FileDropTests: XCTestCase {
    func testFinderFileDropsOpenFromDocumentAndEmptyWindowArea() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewer = Viewer()
        viewer.setup()
        let window = NSApp.windows.first { $0.delegate === viewer }!
        let scroll = window.contentView as! NavigationScrollView
        let text = scroll.documentView as! ReadingView
        defer {
            viewer.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            window.close()
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let drag = FileDrag(pasteboard: pasteboard, window: window)
        XCTAssertFalse(text.isEditable)
        for (index, destination) in [text as NSView, scroll].enumerated() {
            let file = folder.appendingPathComponent("Finder drop \(index) café.md")
            let content = "Document opened from Finder \(index)"
            try content.write(to: file, atomically: true, encoding: .utf8)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
            XCTAssertTrue(destination.registeredDraggedTypes.contains(.fileURL))
            XCTAssertEqual(destination.draggingEntered(drag), .copy)
            XCTAssertEqual(destination.draggingUpdated(drag), .copy)
            XCTAssertTrue(destination.prepareForDragOperation(drag))
            XCTAssertTrue(destination.performDragOperation(drag))
            XCTAssertTrue(text.string.contains(content))
            XCTAssertEqual(viewer.history.current?.url, file)
            XCTAssertEqual(window.representedURL, file)
            XCTAssertFalse(text.isEditable)
        }
    }

    func testNonFileDropsAreRejected() {
        let scroll = NavigationScrollView()
        let text = ReadingView.make(in: scroll)
        var opened = false
        text.openFile = { _ in opened = true; return true }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let drag = FileDrag(pasteboard: pasteboard)
        for value: NSPasteboardWriting in ["plain text" as NSString, NSURL(string: "https://example.com/readme.md")!] {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([value]))
            for destination in [text as NSView, scroll] {
                XCTAssertEqual(destination.draggingEntered(drag), [])
                XCTAssertEqual(destination.draggingUpdated(drag), [])
                XCTAssertFalse(destination.prepareForDragOperation(drag))
                XCTAssertFalse(destination.performDragOperation(drag))
            }
        }
        XCTAssertFalse(opened)
    }

    func testDropReportsWhetherDocumentWasOpened() {
        let scroll = NavigationScrollView()
        let text = ReadingView.make(in: scroll)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/readme.md") as NSURL]))
        let drag = FileDrag(pasteboard: pasteboard)
        XCTAssertEqual(text.draggingEntered(drag), [])
        XCTAssertFalse(text.performDragOperation(drag))
        text.openFile = { _ in false }
        XCTAssertFalse(text.performDragOperation(drag))
    }
}

/// Finder-style pasteboard data delivered in process, without dragging on the desktop.
private final class FileDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    init(pasteboard: NSPasteboard, window: NSWindow? = nil) {
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
    }
    let draggingSourceOperationMask: NSDragOperation = .copy
    let draggingLocation: NSPoint = .zero
    let draggedImageLocation: NSPoint = .zero
    let draggedImage: NSImage? = nil
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 0
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
