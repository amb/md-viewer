import AppKit

struct DiagramResult: Codable {
    let id: Int
    let error: String?
    var fontSize: Double? = nil
}

final class DiagramBatch {
    private let process = Process()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("md-view-\(UUID().uuidString)")
    private var timeout: DispatchWorkItem?
    private var cancelled = false

    func start(_ jobs: [DiagramJob], theme: DiagramTheme, completion: @escaping (URL, [DiagramResult]) -> Void) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(jobs).write(to: folder.appendingPathComponent("jobs.json"))
        try JSONEncoder().encode(theme).write(to: folder.appendingPathComponent("theme.json"))
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MermaidWorker")
        process.arguments = [folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [self] _ in
            DispatchQueue.main.async { [self] in
                process.terminationHandler = nil
                timeout?.cancel()
                defer { try? FileManager.default.removeItem(at: folder) }
                guard !cancelled else { return }
                let results = (try? Data(contentsOf: folder.appendingPathComponent("results.json")))
                    .flatMap { try? JSONDecoder().decode([DiagramResult].self, from: $0) }
                completion(folder, results ?? jobs.map {
                    DiagramResult(id: $0.id, error: "Diagram renderer stopped or timed out. Reload to retry.")
                })
            }
        }
        do { try process.run() }
        catch { process.terminationHandler = nil; try? FileManager.default.removeItem(at: folder); throw error }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: deadline)
    }

    func cancel() {
        cancelled = true
        timeout?.cancel()
        if process.isRunning { process.terminate() }
    }
}
