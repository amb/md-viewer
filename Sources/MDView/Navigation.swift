import AppKit

final class NavigationApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .systemDefined, isActive, let viewer = keyWindow?.delegate as? Viewer,
           viewer.handleNavigationEvent(event) { return }
        super.sendEvent(event)
    }
}

enum NavigationDirection: Int { case back = -1, forward = 1 }

/// History retains URLs and scroll positions, never document contents or images.
struct NavigationHistory {
    struct Entry {
        let url: URL
        var origin: NSPoint = .zero
    }
    private(set) var entries: [Entry] = []
    private(set) var index = -1
    var current: Entry? { entries.indices.contains(index) ? entries[index] : nil }

    func target(_ direction: NavigationDirection) -> Int? {
        let next = index + direction.rawValue
        return entries.indices.contains(next) ? next : nil
    }

    mutating func visit(_ url: URL, leaving origin: NSPoint) {
        if entries.indices.contains(index) { entries[index].origin = origin }
        guard current?.url != url else { return }
        entries.removeSubrange((index + 1)..<entries.count)
        entries.append(Entry(url: url))
        if entries.count > 128 { entries.removeFirst() }
        index = entries.count - 1
    }

    mutating func select(_ next: Int, leaving origin: NSPoint) {
        if entries.indices.contains(index) { entries[index].origin = origin }
        index = next
    }
}

enum NavigationInput {
    struct Command {
        let direction: NavigationDirection
        let pressed: Bool
    }

    static func command(for event: NSEvent) -> Command? {
        switch event.type {
        case .otherMouseDown, .otherMouseUp:
            guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return nil }
            return Command(direction: event.buttonNumber == 3 ? .back : .forward, pressed: event.type == .otherMouseDown)
        case .keyDown:
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            var direction: NavigationDirection?
            if flags == .command {
                switch event.charactersIgnoringModifiers {
                case "[": direction = .back
                case "]": direction = .forward
                default: break
                }
            }
            if flags == .command || flags == .option, event.keyCode == 123 || event.keyCode == 124 {
                direction = event.keyCode == 123 ? .back : .forward
            }
            if event.keyCode == 51, flags.isEmpty || flags == .shift {
                direction = flags.isEmpty ? .back : .forward
            }
            return direction.map { Command(direction: $0, pressed: !event.isARepeat) }
        case .systemDefined:
            // Legacy NX_SUBTYPE_AUX_MOUSE_BUTTONS: changed buttons and current state.
            if event.subtype.rawValue == 7 {
                for (mask, direction) in [(1 << 3, NavigationDirection.back), (1 << 4, .forward)] {
                    if event.data1 & mask != 0 {
                        return Command(direction: direction, pressed: event.data2 & mask != 0)
                    }
                }
                return nil
            }
            // NX_SUBTYPE_AUX_CONTROL_BUTTONS; NX_KEYTYPE_NEXT/PREVIOUS/FAST/REWIND.
            guard event.subtype.rawValue == 8 else { return nil }
            let key = (event.data1 >> 16) & 0xffff
            guard [17, 18, 19, 20].contains(key) else { return nil }
            let isDown = ((event.data1 >> 8) & 0xff) == 0x0a
            return Command(direction: key == 18 || key == 20 ? .back : .forward,
                           pressed: isDown && event.data1 & 1 == 0)
        case .swipe:
            guard abs(event.deltaX) > abs(event.deltaY) else { return nil }
            return Command(direction: event.deltaX > 0 ? .back : .forward, pressed: true)
        default: return nil
        }
    }
}

final class NavigationScrollView: NSScrollView {
    var modalOverlay: NSView?
    var navigate: ((NavigationDirection) -> Void)?
    var canNavigate: ((NavigationDirection) -> Bool)?
    var zoom: ((Int) -> Void)?
    private var zoomRemainder: CGFloat = 0

    // The scroll view receives drops over empty space outside the text view.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (documentView as? ReadingView)?.draggingEntered(sender) ?? []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (documentView as? ReadingView)?.draggingUpdated(sender) ?? []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (documentView as? ReadingView)?.prepareForDragOperation(sender) ?? false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (documentView as? ReadingView)?.performDragOperation(sender) ?? false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        modalOverlay?.frame = bounds
        modalOverlay?.needsLayout = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            guard event.momentumPhase.isEmpty else { return }
            let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
            if event.hasPreciseScrollingDeltas {
                if event.phase == .began { zoomRemainder = 0 }
                zoomRemainder += delta
                let steps = Int(zoomRemainder / 20)
                zoomRemainder -= CGFloat(steps) * 20
                if steps != 0 { zoom?(steps) }
                if event.phase == .ended || event.phase == .cancelled { zoomRemainder = 0 }
            } else if delta != 0 { zoom?(delta > 0 ? 1 : -1) }
            return
        }
        zoomRemainder = 0
        if NSEvent.isSwipeTrackingFromScrollEventsEnabled, event.hasPreciseScrollingDeltas,
           event.phase == .began || event.phase == .changed,
           abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
           canNavigate?(event.scrollingDeltaX > 0 ? .back : .forward) == true {
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: canNavigate?(.forward) == true ? -1 : 0,
                max: canNavigate?(.back) == true ? 1 : 0) { [weak self] amount, _, complete, _ in
                    if complete, abs(amount) > 0.5 { self?.navigate?(amount > 0 ? .back : .forward) }
                }
        } else { super.scrollWheel(with: event) }
    }
}
