import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--check-resources") {
    print("menu bar icon : \(MenuBarIcon.debugDescription)")
    exit(MenuBarIcon.load() == nil ? 1 : 0)
}

if let index = arguments.firstIndex(of: "--capture"), index + 1 < arguments.count {
    Capture.run(directory: arguments[index + 1], arguments: arguments)
}

if arguments.contains("--self-test") {
    SelfTest.run(arguments: arguments)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    // Held for the lifetime of the run loop: NSApplication.delegate is weak.
    let delegate = AppDelegate()
    application.delegate = delegate
    // Menu bar only: no Dock icon, no main window.
    application.setActivationPolicy(.accessory)
    application.run()
}
