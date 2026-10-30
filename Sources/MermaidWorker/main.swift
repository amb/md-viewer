import AppKit
import WebKit

struct DiagramJob: Codable { let id: Int; let source: String }
struct DiagramResult: Codable { let id: Int; let error: String?; var fontSize: Double? = nil }

/// The viewer never creates a WKWebView. This process exits after one batch.
final class DiagramWorker: NSObject, WKNavigationDelegate {
    private var view: WKWebView!
    private var window: NSWindow!
    private var ready: CheckedContinuation<Void, Error>?

    @MainActor func run(folder: URL) async -> Int32 {
        do {
            let jobs = try JSONDecoder().decode([DiagramJob].self, from: Data(contentsOf: folder.appendingPathComponent("jobs.json")))
            let theme = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("theme.json")))
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1400), configuration: config)
            view.navigationDelegate = self
            window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            guard let html = Bundle.main.url(forResource: "diagram", withExtension: "html") else {
                throw CocoaError(.fileNoSuchFile)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ready = continuation
                view.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
            }
            _ = try await view.callAsyncJavaScript("window.configureTheme(theme)",
                arguments: ["theme": theme], in: nil, contentWorld: .page)
            var results: [DiagramResult] = []
            var pixels = 0
            for job in jobs {
                do {
                    guard pixels < 8_000_000 else { throw WorkerError.message("Diagram image budget reached (8 million pixels).") }
                    let value = try await view.callAsyncJavaScript("return await window.draw(source)",
                        arguments: ["source": job.source], in: nil, contentWorld: .page)
                    guard let box = value as? [String: Any], let width = box["width"] as? Double,
                          let height = box["height"] as? Double, width > 0, height > 0,
                          width <= 1400, height <= 1400 else { throw WorkerError.message("Invalid diagram dimensions.") }
                    let snapshot = WKSnapshotConfiguration()
                    snapshot.rect = NSRect(x: 0, y: 0, width: width, height: height)
                    snapshot.snapshotWidth = NSNumber(value: width)
                    let image = try await view.takeSnapshot(configuration: snapshot)
                    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw WorkerError.message("Could not capture diagram.")
                    }
                    guard pixels + bitmap.pixelsWide * bitmap.pixelsHigh <= 8_000_000 else {
                        throw WorkerError.message("Diagram image budget reached (8 million pixels).")
                    }
                    pixels += bitmap.pixelsWide * bitmap.pixelsHigh
                    try data.write(to: folder.appendingPathComponent("\(job.id).png"))
                    let metrics = try await view.callAsyncJavaScript("return window.prepareVector()", arguments: [:], in: nil, contentWorld: .page)
                    guard let vectorBox = metrics as? [String: Any], let vectorWidth = vectorBox["width"] as? Double,
                          let vectorHeight = vectorBox["height"] as? Double,
                          vectorWidth.isFinite, vectorHeight.isFinite, vectorWidth > 0, vectorHeight > 0 else {
                        throw WorkerError.message("Invalid vector dimensions.")
                    }
                    let pdf = WKPDFConfiguration()
                    pdf.rect = NSRect(x: 0, y: 0, width: vectorWidth, height: vectorHeight)
                    let vector: Data = try await withCheckedThrowingContinuation { continuation in
                        view.createPDF(configuration: pdf) { continuation.resume(with: $0) }
                    }
                    try vector.write(to: folder.appendingPathComponent("\(job.id).pdf"))
                    let pointScale = Double(NSPDFImageRep(data: vector)?.size.width ?? CGFloat(vectorWidth)) / vectorWidth
                    let fontSize = (vectorBox["fontSize"] as? Double).map { $0 * pointScale }
                    results.append(DiagramResult(id: job.id, error: nil, fontSize: fontSize))
                } catch {
                    results.append(DiagramResult(id: job.id, error: String(error.localizedDescription.prefix(300))))
                }
            }
            try JSONEncoder().encode(results).write(to: folder.appendingPathComponent("results.json"), options: .atomic)
            return 0
        } catch {
            fputs("Diagram worker: \(error)\n", stderr)
            return 1
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready?.resume(); ready = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        ready?.resume(throwing: error); ready = nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { exit(2) }
    enum WorkerError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
guard CommandLine.arguments.count == 2 else { exit(1) }
let worker = DiagramWorker()
Task { @MainActor in
    let code = await worker.run(folder: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(code)
}
app.run()
