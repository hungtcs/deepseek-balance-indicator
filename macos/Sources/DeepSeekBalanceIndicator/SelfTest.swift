import AppKit

/// Headless verification used to check the packaged app without a display grab.
/// Boots the status item, runs one real refresh, opens both windows, and
/// exercises the ⌘V path, then exits.
enum SelfTest {
    static func run(arguments: [String]) -> Never {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)

            // Same Edit menu the real app installs, so the ⌘V check is meaningful.
            MainMenu.install()

            let statusBar = StatusBarController()
            if let index = arguments.firstIndex(of: "--endpoint"), index + 1 < arguments.count,
               let url = URL(string: arguments[index + 1]) {
                statusBar.endpoint = url
            }
            statusBar.start()
            RunLoop.main.run(until: Date().addingTimeInterval(4))
            print(statusBar.diagnosticsDescription())

            SettingsWindowController.show()
            AboutWindowController.show()
            RunLoop.main.run(until: Date().addingTimeInterval(2))

            print("windows:")
            for window in NSApp.windows where window.isVisible {
                print("  \"\(window.title)\" \(Int(window.frame.width))x\(Int(window.frame.height))")
            }

            reportEditingShortcuts()
            reportPasteIntoKeyField()

            exit(0)
        }
    }

    /// Confirms ⌘X/⌘C/⌘V/⌘A are registered against the standard selectors.
    private static func reportEditingShortcuts() {
        print("main menu shortcuts:")
        guard let mainMenu = NSApp.mainMenu else {
            print("  (no main menu — standard editing shortcuts will not work)")
            return
        }
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            for entry in submenu.items where !entry.keyEquivalent.isEmpty {
                var modifiers = "⌘"
                if entry.keyEquivalentModifierMask.contains(.shift) { modifiers = "⇧⌘" }
                let action = entry.action.map(NSStringFromSelector) ?? "nil"
                print("  \(modifiers)\(entry.keyEquivalent.uppercased())  \(entry.title)  ->  \(action)")
            }
        }
    }

    /// Drives a real paste through the responder chain and reports the result.
    private static func reportPasteIntoKeyField() {
        guard let window = NSApp.windows.first(where: { $0.title == "设置" }) else {
            print("paste test: settings window not found")
            return
        }
        window.makeKeyAndOrderFront(nil)
        guard let field = firstTextField(in: window.contentView) else {
            print("paste test: no NSTextField in the settings hierarchy")
            return
        }
        window.makeFirstResponder(field)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let responder = window.firstResponder
        let canPaste = responder?.responds(to: #selector(NSText.paste(_:))) ?? false
        print("paste test:")
        print("  field class      : \(type(of: field))")
        print("  first responder  : \(responder.map { String(describing: type(of: $0)) } ?? "nil")")
        print("  responds to paste: \(canPaste)")

        let sentinel = "sk-pasted-from-clipboard"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentinel, forType: .string)

        print("  app active       : \(NSApp.isActive), window key: \(window.isKeyWindow)")
        // The real ⌘V path: NSApplication walks from the key window's responder.
        let viaMenuPath = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        // Falls back to the focused responder so the check still means something
        // when this headless process cannot take keyboard focus.
        let viaResponder = viaMenuPath || (responder?.tryToPerform(#selector(NSText.paste(_:)), with: nil) ?? false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        print("  menu path        : \(viaMenuPath)")
        print("  responder path   : \(viaResponder)")
        print("  field value      : \"\(field.stringValue)\"")
        print("  VERDICT          : \(field.stringValue == sentinel ? "paste reaches the field" : "paste did NOT land")")
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }
}
