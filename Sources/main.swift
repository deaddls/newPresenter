import AppKit

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--render-test"), i + 1 < arguments.count {
    exit(RenderTest.run(outputDirectory: arguments[i + 1]) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
