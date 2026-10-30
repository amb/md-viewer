import AppKit

let app = NavigationApplication.shared
let preview = (4...5).contains(CommandLine.arguments.count) && CommandLine.arguments[1] == "--preview"
let inspect = (4...5).contains(CommandLine.arguments.count) && CommandLine.arguments[1] == "--inspect"
app.setActivationPolicy(preview || inspect ? .prohibited : .regular)
let viewer = Viewer()
if preview { viewer.previewOutput = URL(fileURLWithPath: CommandLine.arguments[3]) }
if preview || inspect, CommandLine.arguments.count == 5 {
    guard let width = Double(CommandLine.arguments[4]), (400...3000).contains(width) else {
        fputs("Window width must be between 400 and 3000 points.\n", stderr); exit(1)
    }
    viewer.initialWidth = CGFloat(width)
}
if inspect { viewer.inspectOutput = URL(fileURLWithPath: CommandLine.arguments[3]) }
app.delegate = viewer
app.run()
