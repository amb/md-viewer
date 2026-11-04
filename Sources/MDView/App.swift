import AppKit
import UniformTypeIdentifiers

final class ReadingView: NSTextView {
    var openFile: ((URL) -> Bool)?
    var openDiagram: ((NSImage, Int?) -> Void)?
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
    override func resetCursorRects() {
        guard (enclosingScrollView as? NavigationScrollView)?.modalOverlay == nil else { return }
        super.resetCursorRects()
    }
    override func cursorUpdate(with event: NSEvent) {
        if let modal = (enclosingScrollView as? NavigationScrollView)?.modalOverlay {
            modal.cursorUpdate(with: event)
        } else { super.cursorUpdate(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        if let modal = (enclosingScrollView as? NavigationScrollView)?.modalOverlay {
            modal.cursorUpdate(with: event)
        } else { super.mouseMoved(with: event) }
    }
    static func make(in scroll: NSScrollView) -> ReadingView {
        let view = ReadingView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        view.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 32, height: 24)
        view.textContainer?.lineFragmentPadding = 0
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        view.registerForDraggedTypes([.fileURL])
        scroll.registerForDraggedTypes([.fileURL])
        return view
    }
    var readingWidth: CGFloat {
        max(1, (textContainer?.size.width ?? 0) - 2 * (textContainer?.lineFragmentPadding ?? 0))
    }

    func setDocument(_ document: NSAttributedString) {
        textStorage?.setAttributedString(document)
        fitAttachments()
    }

    override func mouseDown(with event: NSEvent) {
        if let manager = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 {
            manager.ensureLayout(for: container)
            let point = convert(event.locationInWindow, from: nil)
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = manager.glyphIndex(for: local, in: container)
            if glyph < manager.numberOfGlyphs,
               manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) {
                let index = manager.characterIndexForGlyph(at: glyph)
                if let image = storage.attribute(.diagramPreview, at: index, effectiveRange: nil) as? NSImage {
                    openDiagram?(image, storage.attribute(.diagramID, at: index, effectiveRange: nil) as? Int)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard openFile != nil, sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }
    // NSTextView's default drag handling expects editable text; these drops open a document instead.
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !draggingEntered(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first else { return false }
        return openFile?(url) ?? false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitAttachments()
    }

    func fitAttachments() {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
            let bounds = NativeMarkdown.imageBounds(image.size, width: readingWidth)
            if attachment.bounds != bounds {
                attachment.bounds = bounds
                layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
        }
    }
}

final class Viewer: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation {
    var previewOutput: URL?
    var initialWidth: CGFloat = 880
    var inspectOutput: URL?
    private var window: NSWindow!
    private var text: ReadingView!
    private var status = ""
    private var file: URL?
    private var bytes: Data?
    private var fontSize: CGFloat = 15
    private var watcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private var batch: DiagramBatch?
    private var renderMermaid = true
    private var generation = 0
    private var diagramCache: [Int: NSAttributedString] = [:]
    private var diagramTheme: DiagramTheme?
    private(set) var diagramOverlay: DiagramOverlay?
    private var overlayDiagramID: Int?
    private var savedMouseMovedEvents: Bool?
    private(set) var history = NavigationHistory()
    private var navigationMonitor: Any?
    private var pendingOrigin: NSPoint?
    private var pendingFragment: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setup()
        if previewOutput == nil, inspectOutput == nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        let path = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
        if let path { open(URL(fileURLWithPath: path)) }
        else if let file { open(file) }
        else { welcome() }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else { return }
        let url = URL(fileURLWithPath: path)
        if window == nil { file = url } else { open(url) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        dismissDiagram()
        batch?.cancel(); watcher?.cancel(); fileWatcher?.cancel()
        if let navigationMonitor { NSEvent.removeMonitor(navigationMonitor) }
        navigationMonitor = nil
    }

    func setup() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MD View"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        if previewOutput != nil || inspectOutput != nil, let theme = ProcessInfo.processInfo.environment["MDVIEW_PREVIEW_APPEARANCE"] {
            window.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
        }
        let scroll = NavigationScrollView()
        window.contentView = scroll
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        text = ReadingView.make(in: scroll)
        text.delegate = self
        text.openFile = { [weak self] in self?.open($0) ?? false }
        text.openDiagram = { [weak self] image, id in self?.showDiagram(image, id: id) }
        text.appearanceChanged = { [weak self] in self?.updateDiagramTheme() }
        scroll.navigate = { [weak self] in self?.navigate($0) }
        scroll.canNavigate = { [weak self] in self?.history.target($0) != nil }
        scroll.zoom = { [weak self] in self?.changeZoom(by: $0) }
        menus()
        navigationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown, .otherMouseUp, .keyDown, .swipe]) { [weak self] event in
            guard let self, NSApp.isActive, NSApp.keyWindow === self.window,
                  self.handleNavigationEvent(event) else { return event }
            return nil
        }
        scroll.layoutSubtreeIfNeeded()
    }

    private func menus() {
        let main = NSMenu()
        NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            item.submenu = sub; main.addItem(item); return sub
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target; menu.addItem(item)
        }
        let app = menu("MD View")
        item(app, "About MD View", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        item(app, "Hide MD View", #selector(NSApplication.hide(_:)), "h")
        item(app, "Quit MD View", #selector(NSApplication.terminate(_:)), "q")
        let files = menu("File")
        item(files, "Open…", #selector(chooseFile), "o", target: self)
        item(files, "Reload", #selector(reload), "r", target: self)
        item(files, "Reveal in Finder", #selector(reveal), target: self)
        item(files, "Close", #selector(closeDocument(_:)), "w", target: self)
        let edit = menu("Edit")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        let view = menu("View")
        item(view, "Zoom In", #selector(larger), "+", target: self)
        item(view, "Zoom Out", #selector(smaller), "-", target: self)
        item(view, "Actual Size", #selector(actualSize), "0", target: self)
        item(view, "Fit Diagram to Window", #selector(fitDiagram), "9", target: self)
        item(view, "Render Mermaid Diagrams", #selector(toggleMermaid(_:)), target: self)
        view.items.last?.state = .on
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "")
        let navigation = menu("Go")
        item(navigation, "Back", #selector(goBack(_:)), "[", target: self)
        item(navigation, "Forward", #selector(goForward(_:)), "]", target: self)
        let windows = menu("Window")
        NSApp.windowsMenu = windows
        item(windows, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(windows, "Zoom", #selector(NSWindow.performZoom(_:)))
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.allowsOtherFileTypes = true
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }

    @discardableResult
    func open(_ url: URL, reportErrors: Bool = true, recordHistory: Bool = true, historyIndex: Int? = nil) -> Bool {
        do {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
            let fragment = components.fragment
            components.fragment = nil
            components.query = nil
            let target = components.url!.standardizedFileURL
            components = URLComponents(url: target, resolvingAgainstBaseURL: false)!
            components.fragment = fragment
            let location = components.url!
            let values = try target.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 4 * 1024 * 1024 else {
                throw ViewerError.message("Choose a Markdown file smaller than 4 MB.")
            }
            let data = try Data(contentsOf: target)
            guard String(data: data, encoding: .utf8) != nil else {
                throw ViewerError.message("This file is not UTF-8 text.")
            }
            dismissDiagram()
            let unchanged = file == target && bytes == data
            let origin = text.enclosingScrollView?.contentView.bounds.origin ?? .zero
            if let historyIndex {
                pendingOrigin = history.entries[historyIndex].origin
                pendingFragment = nil
                history.select(historyIndex, leaving: origin)
            } else if recordHistory {
                let duplicate = history.current?.url == location
                history.visit(location, leaving: origin)
                if duplicate, unchanged { return true }
                pendingOrigin = .zero
                pendingFragment = fragment
            } else {
                if unchanged { return true }
                pendingOrigin = origin
                pendingFragment = nil
            }
            if unchanged { restoreNavigation(final: batch == nil); reportState(); return true }
            file = target; bytes = data
            diagramCache.removeAll()
            window.title = target.lastPathComponent
            window.representedURL = target
            window.subtitle = target.deletingLastPathComponent().path
            render()
            watch(target)
            return true
        } catch {
            if reportErrors { showError(error) }
            else { status = "File unavailable · Reload to retry" }
            return false
        }
    }

    private func render() {
        guard let file, let bytes, let source = String(data: bytes, encoding: .utf8) else { return }
        let theme = DiagramTheme(appearance: text.effectiveAppearance, background: text.backgroundColor)
        if diagramTheme != theme {
            diagramTheme = theme
            diagramCache.removeAll()
        }
        if pendingOrigin == nil { pendingOrigin = text.enclosingScrollView?.contentView.bounds.origin }
        generation += 1
        let current = generation
        batch?.cancel(); batch = nil
        let document = NativeMarkdown(source: source, baseURL: file, size: fontSize)
        let jobs = document.diagrams
        if renderMermaid {
            for (id, replacement) in diagramCache {
                replaceDiagram(id, storage: document.text, replacement: replacement)
            }
        }
        if !renderMermaid {
            for job in jobs.reversed() { replaceDiagram(job.id, storage: document.text,
                replacement: NSAttributedString(string: job.source, attributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)])) }
        }
        text.setDocument(document.text)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        restoreNavigation(final: false)
        status = renderMermaid && !jobs.isEmpty ? "Rendering \(jobs.count) diagram(s)…" : "UTF-8 · Native Markdown"
        let pending = jobs.filter { diagramCache[$0.id] == nil }
        if renderMermaid, pending.isEmpty, !jobs.isEmpty { status = "\(jobs.count) diagram(s) · Renderer closed" }
        guard renderMermaid, !pending.isEmpty else { restoreNavigation(final: true); finishPreview(); reportState(); return }
        let next = DiagramBatch()
        batch = next
        do {
            try next.start(pending, theme: theme) { [weak self] folder, results in
                guard let self, self.generation == current, let storage = self.text.textStorage else { return }
                var errors = 0
                storage.beginEditing()
                for result in results {
                    let replacement: NSAttributedString
                    if result.error == nil, let image = NativeMarkdown.thumbnail(folder.appendingPathComponent("\(result.id).png"), pixelLimit: 1400) {
                        image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
                        let attachment = NSTextAttachment()
                        attachment.image = image
                        attachment.bounds = NativeMarkdown.imageBounds(image.size, width: self.text.readingWidth)
                        let rendered = NSMutableAttributedString(attachment: attachment)
                        rendered.addAttribute(.diagramID, value: result.id, range: NSRange(location: 0, length: rendered.length))
                        replacement = rendered
                        let vector = (try? Data(contentsOf: folder.appendingPathComponent("\(result.id).pdf"))).flatMap { NSImage(data: $0) } ?? image
                        rendered.addAttribute(.diagramPreview, value: vector, range: NSRange(location: 0, length: rendered.length))
                        if let fontSize = result.fontSize {
                            rendered.addAttribute(.diagramFontSize, value: fontSize, range: NSRange(location: 0, length: rendered.length))
                        }
                        if self.overlayDiagramID == result.id { self.diagramOverlay?.updateImage(vector, diagramFontSize: result.fontSize.map { CGFloat($0) }) }
                    } else {
                        errors += 1
                        let source = jobs.first { $0.id == result.id }?.source ?? ""
                        replacement = NSAttributedString(string: "Mermaid: \(result.error ?? "Image unavailable")\n\(source)",
                            attributes: [.font: NSFont.monospacedSystemFont(ofSize: self.fontSize - 2, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
                    }
                    self.diagramCache[result.id] = replacement
                    self.replaceDiagram(result.id, storage: storage, replacement: replacement)
                }
                storage.endEditing()
                self.text.fitAttachments()
                self.status = "\(results.count - errors) diagram(s) rendered" + (errors > 0 ? " · \(errors) error(s)" : " · Renderer closed")
                self.batch = nil
                self.restoreNavigation(final: true)
                self.finishPreview()
                self.reportState()
            }
        } catch { status = error.localizedDescription; batch = nil; restoreNavigation(final: true); finishPreview(); reportState() }
    }

    private func replaceDiagram(_ id: Int, storage: NSMutableAttributedString, replacement: NSAttributedString) {
        var found: NSRange?
        storage.enumerateAttribute(.diagramID, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? Int == id { found = range; stop.pointee = true }
        }
        if let found { storage.replaceCharacters(in: found, with: replacement) }
    }

    private func watch(_ url: URL) {
        watcher?.cancel()
        fileWatcher?.cancel()
        let changed = { [weak self] in
            guard let self else { return }
            self.reloadWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.file == url else { return }
                self.open(url, reportErrors: false, recordHistory: false)
            }
            self.reloadWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        func observe(_ path: String) -> DispatchSourceFileSystemObject? {
            let fd = Darwin.open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setCancelHandler { Darwin.close(fd) }
            source.setEventHandler(handler: changed)
            source.resume()
            return source
        }
        watcher = observe(url.deletingLastPathComponent().path)
        fileWatcher = observe(url.path)
    }

    @objc private func reload() { if let file { bytes = nil; open(file, recordHistory: false) } }
    @objc private func reveal() { if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
    func changeZoom(by steps: Int) {
        if let diagramOverlay { diagramOverlay.zoom(by: steps); return }
        let next = min(30, max(10, fontSize + CGFloat(steps)))
        guard next != fontSize else { return }
        fontSize = next
        render()
    }
    @objc private func larger() { changeZoom(by: 1) }
    @objc private func smaller() { changeZoom(by: -1) }
    @objc private func actualSize() {
        if let diagramOverlay { diagramOverlay.actualSize() }
        else { fontSize = 15; render() }
    }
    @objc private func fitDiagram() { diagramOverlay?.fit() }
    @objc private func closeDocument(_ sender: Any?) {
        if diagramOverlay != nil { dismissDiagram() } else { window.performClose(sender) }
    }
    @objc private func toggleMermaid(_ sender: NSMenuItem) {
        renderMermaid.toggle(); sender.state = renderMermaid ? .on : .off; render()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL else { return true }
        if url.isFileURL {
            if ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased()) { open(url) }
        } else if ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return true
    }

    func showDiagram(_ image: NSImage, id: Int? = nil) {
        dismissDiagram()
        guard let content = window.contentView else { return }
        var diagramFontSize: Double?
        if let id {
            text.textStorage?.enumerateAttribute(.diagramID, in: NSRange(location: 0, length: text.string.utf16.count)) { value, range, stop in
                if value as? Int == id {
                    diagramFontSize = text.textStorage?.attribute(.diagramFontSize, at: range.location, effectiveRange: nil) as? Double
                    stop.pointee = true
                }
            }
        }
        let overlay = DiagramOverlay(image: image, frame: content.bounds, documentFontSize: fontSize, diagramFontSize: diagramFontSize.map { CGFloat($0) })
        overlay.dismiss = { [weak self] in self?.dismissDiagram() }
        diagramOverlay = overlay
        overlayDiagramID = id
        content.addSubview(overlay, positioned: .above, relativeTo: nil)
        (content as? NavigationScrollView)?.modalOverlay = overlay
        savedMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        text.isSelectable = false
        text.discardCursorRects()
        text.updateTrackingAreas()
        overlay.needsLayout = true
        content.layoutSubtreeIfNeeded()
        window.makeFirstResponder(overlay)
        window.invalidateCursorRects(for: text)
        window.invalidateCursorRects(for: overlay)
        if window.isKeyWindow, NSApp.isActive { NSCursor.arrow.set() }
    }

    func dismissDiagram() {
        guard let overlay = diagramOverlay else { return }
        overlay.removeFromSuperview()
        (window.contentView as? NavigationScrollView)?.modalOverlay = nil
        diagramOverlay = nil
        overlayDiagramID = nil
        window.acceptsMouseMovedEvents = savedMouseMovedEvents ?? false
        savedMouseMovedEvents = nil
        text.isSelectable = true
        text.updateTrackingAreas()
        window.makeFirstResponder(text)
        window.invalidateCursorRects(for: text)
    }

    private func updateDiagramTheme() {
        guard text != nil, file != nil,
              diagramTheme != DiagramTheme(appearance: text.effectiveAppearance, background: text.backgroundColor) else { return }
        // Appearance notifications can arrive during view setup; render once it settles.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.diagramTheme != DiagramTheme(appearance: self.text.effectiveAppearance, background: self.text.backgroundColor) else { return }
            self.render()
        }
    }

    @objc func goBack(_ sender: Any?) { navigate(.back) }
    @objc func goForward(_ sender: Any?) { navigate(.forward) }

    func navigate(_ direction: NavigationDirection) {
        guard diagramOverlay == nil else { return }
        guard let index = history.target(direction) else { return }
        open(history.entries[index].url, historyIndex: index)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(goBack(_:)) { return diagramOverlay == nil && history.target(.back) != nil }
        if menuItem.action == #selector(goForward(_:)) { return diagramOverlay == nil && history.target(.forward) != nil }
        if menuItem.action == #selector(fitDiagram) { return diagramOverlay != nil }
        return true
    }

    @discardableResult
    func handleNavigationEvent(_ event: NSEvent) -> Bool {
        // Handle before subviews so image and button context menus cannot consume it.
        if event.type == .rightMouseDown, diagramOverlay != nil {
            dismissDiagram()
            return true
        }
        // Leave text-editing shortcuts alone in Find fields and file dialogs.
        if event.type == .keyDown, let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        guard let command = NavigationInput.command(for: event) else { return false }
        if diagramOverlay != nil { return true }
        if command.pressed { navigate(command.direction) }
        return true
    }

    private func restoreNavigation(final: Bool) {
        guard let container = text.textContainer, let manager = text.layoutManager,
              let scroll = text.enclosingScrollView else { return }
        manager.ensureLayout(for: container)
        if let fragment = pendingFragment {
            text.textStorage?.enumerateAttribute(.headingID, in: NSRange(location: 0, length: text.string.utf16.count)) { value, range, stop in
                if value as? String == fragment {
                    text.scrollRangeToVisible(range); stop.pointee = true
                }
            }
        } else if let origin = pendingOrigin {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if final { pendingOrigin = nil; pendingFragment = nil }
    }

    private func welcome() {
        text.textStorage?.setAttributedString(NSAttributedString(string: "MD View\n\nOpen a Markdown file with ⌘O or drop one here.\n\nSelect and copy text · Find with ⌘F · Reload with ⌘R\nFiles update automatically when saved.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.textColor]))
        status = "Markdown + Mermaid · Offline"
    }
    private func showError(_ error: Error) {
        if previewOutput != nil || inspectOutput != nil { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }

    private func reportState() {
        guard let output = inspectOutput else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            window.contentView?.layoutSubtreeIfNeeded()
            if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
            var state: [String: Any] = Diagnostics.memory()
            state["text"] = text.string
            state["status"] = status
            state["generation"] = generation
            state["rendererRunning"] = batch != nil
            state["diagramTheme"] = diagramTheme?.dark == true ? "dark" : "light"
            var vectors = 0
            text.textStorage?.enumerateAttribute(.diagramPreview, in: NSRange(location: 0, length: text.string.utf16.count)) { value, _, _ in
                if let image = value as? NSImage, image.representations.contains(where: { $0 is NSPDFImageRep }) { vectors += 1 }
            }
            state["diagramVectors"] = vectors
            state["handlesSystemKeys"] = NSApp is NavigationApplication
            state["contentIsScrollView"] = window.contentView is NSScrollView
            state["menuCommands"] = NSApp.mainMenu?.items.flatMap { $0.submenu?.items.map(\.title) ?? [] }
            state["viewportWidth"] = text.enclosingScrollView?.contentView.bounds.width
            state["documentWidth"] = text.bounds.width
            state["containerWidth"] = text.textContainer?.size.width
            state["textOriginX"] = text.textContainerOrigin.x
            if let manager = text.layoutManager, let container = text.textContainer {
                var minX = CGFloat.greatestFiniteMagnitude
                var maxX: CGFloat = 0
                manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, _, _ in
                    if used.width > 0 {
                        minX = min(minX, used.minX + self.text.textContainerOrigin.x)
                        maxX = max(maxX, used.maxX + self.text.textContainerOrigin.x)
                    }
                }
                state["renderedMinX"] = minX
                state["renderedMaxX"] = maxX
            }
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
                try? data.write(to: output, options: .atomic)
            }
        }
    }

    /// Scripted visual QA: draw native text offscreen; never activate a window.
    private func finishPreview() {
        guard let destination = previewOutput else { return }
        DispatchQueue.main.async { [self] in
            window.contentView?.layoutSubtreeIfNeeded()
            if let requested = ProcessInfo.processInfo.environment["MDVIEW_PREVIEW_DIAGRAM"], let id = Int(requested) {
                text.textStorage?.enumerateAttribute(.diagramID, in: NSRange(location: 0, length: text.string.utf16.count)) { value, range, stop in
                    if value as? Int == id,
                       let image = text.textStorage?.attribute(.diagramPreview, at: range.location, effectiveRange: nil) as? NSImage {
                        showDiagram(image, id: id); stop.pointee = true
                    }
                }
            }
            if diagramOverlay != nil, let content = window.contentView {
                content.displayIfNeeded()
                guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                do { try png.write(to: destination); exit(0) }
                catch { fputs("\(error)\n", stderr); exit(1) }
            }
            guard let container = text.textContainer, let manager = text.layoutManager else { exit(1) }
            manager.ensureLayout(for: container)
            let height = min(2000, manager.usedRect(for: container).height + 48)
            let width = text.bounds.width
            text.setFrameSize(NSSize(width: width, height: height))
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            guard let bitmap = text.bitmapImageRepForCachingDisplay(in: rect) else { exit(1) }
            text.cacheDisplay(in: rect, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: destination); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
    }
    enum ViewerError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
