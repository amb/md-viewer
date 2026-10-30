import AppKit

/// A document-local modal viewer. PDF-backed images remain sharp at any zoom.
final class DiagramOverlay: NSView {
    let scroll = NavigationScrollView()
    private let imageView = PannableDiagramView()
    private let caption = NSTextField(labelWithString: "Diagram")
    private let controls = NSView()
    private var fitted = false
    private let documentFontSize: CGFloat
    private var diagramFontSize: CGFloat?
    var minimumReadableMagnification: CGFloat {
        guard let diagramFontSize, diagramFontSize.isFinite, diagramFontSize > 0 else { return 0.1 }
        return documentFontSize / diagramFontSize
    }
    var dismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var magnification: CGFloat { scroll.magnification }

    init(image: NSImage, frame: NSRect, documentFontSize: CGFloat = 15, diagramFontSize: CGFloat? = nil) {
        self.documentFontSize = documentFontSize
        self.diagramFontSize = diagramFontSize
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        imageView.image = image
        image.cacheMode = .never
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setFrameSize(image.size)
        scroll.contentView = CenteredDiagramClipView()
        scroll.documentView = imageView
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1
        scroll.maxMagnification = max(12, minimumReadableMagnification * 4)
        scroll.zoom = { [weak self] in self?.zoom(by: $0) }
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        for (title, action) in [("−", #selector(zoomOut)), ("+", #selector(zoomIn)),
                                ("Fit", #selector(fit)), ("Close", #selector(cancelOperation(_:)))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            controls.addSubview(button)
        }
        addSubview(scroll); addSubview(caption); addSubview(controls)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    override func resetCursorRects() { addCursorRect(visibleRect, cursor: .arrow) }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) { updateCursor() }
    private func updateCursor() {
        if window?.isKeyWindow == true, NSApp.isActive { NSCursor.arrow.set() }
    }

    override func layout() {
        super.layout()
        let panel = bounds.insetBy(dx: 24, dy: 24)
        let bar = NSRect(x: panel.minX + 16, y: panel.minY + 12, width: panel.width - 32, height: 28)
        controls.frame = NSRect(x: bar.maxX - 250, y: bar.minY, width: 250, height: 28)
        var x: CGFloat = 0
        for (button, width) in zip(controls.subviews, [36.0, 36.0, 56.0, 72.0]) {
            button.frame = NSRect(x: x, y: 0, width: width, height: 28)
            x += width + 8
        }
        caption.frame = NSRect(x: bar.minX, y: bar.minY + 5, width: max(0, bar.width - 260), height: 20)
        scroll.frame = NSRect(x: panel.minX + 12, y: bar.maxY + 12,
                              width: max(1, panel.width - 24), height: max(1, panel.maxY - bar.maxY - 24))
        if !fitted, scroll.contentSize.width > 0 { fitted = true; fit() }
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.65).setFill()
        bounds.fill()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 24, dy: 24), xRadius: 12, yRadius: 12).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if !bounds.insetBy(dx: 24, dy: 24).contains(convert(event.locationInWindow, from: nil)) { dismiss?() }
    }
    override func rightMouseDown(with event: NSEvent) { dismiss?() }
    override func scrollWheel(with event: NSEvent) { scroll.scrollWheel(with: event) }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss?() } else { interpretKeyEvents([event]) }
    }

    func updateImage(_ image: NSImage, diagramFontSize: CGFloat? = nil) {
        self.diagramFontSize = diagramFontSize
        scroll.maxMagnification = max(12, minimumReadableMagnification * 4)
        image.cacheMode = .never
        imageView.image = image
        imageView.setFrameSize(image.size)
        imageView.needsDisplay = true
    }
    func zoom(by steps: Int) { setZoom(scroll.magnification * pow(1.2, CGFloat(steps))) }
    func actualSize() { setZoom(1) }
    @objc private func zoomIn() { zoom(by: 1) }
    @objc private func zoomOut() { zoom(by: -1) }
    @objc func fit() {
        guard let image = imageView.image else { return }
        let wholeDiagram = min(scroll.contentSize.width / max(1, image.size.width), scroll.contentSize.height / max(1, image.size.height))
        setZoom(max(wholeDiagram, minimumReadableMagnification))
    }
    private func setZoom(_ amount: CGFloat) {
        let visible = scroll.documentVisibleRect
        scroll.setMagnification(min(scroll.maxMagnification, max(0.1, amount)), centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        caption.stringValue = "Diagram · \(Int((scroll.magnification * 100).rounded()))%"
    }
}

private final class CenteredDiagramClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if documentView.frame.width < rect.width { rect.origin.x = (documentView.frame.width - rect.width) / 2 }
        if documentView.frame.height < rect.height { rect.origin.y = (documentView.frame.height - rect.height) / 2 }
        return rect
    }
}

private final class PannableDiagramView: NSImageView {
    private var grab: (point: NSPoint, origin: NSPoint)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if let scroll = enclosingScrollView { grab = (event.locationInWindow, scroll.contentView.bounds.origin) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let grab, let scroll = enclosingScrollView else { return }
        let point = event.locationInWindow
        let scale = scroll.magnification
        scroll.contentView.scroll(to: NSPoint(x: grab.origin.x - (point.x - grab.point.x) / scale,
                                              y: grab.origin.y + (point.y - grab.point.y) / scale))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    override func mouseUp(with event: NSEvent) { grab = nil }
}
