import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()

        let statusBar = StatusBarController()
        statusBar.onOpenSettings = { SettingsWindowController.show() }
        statusBar.onOpenAbout = { AboutWindowController.show() }
        self.statusBar = statusBar
        statusBar.start()

        // First launch has nothing to show, so open Settings once instead of
        // leaving a bare whale in the menu bar.
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: "deepseek.hasLaunchedBefore")
        defaults.set(true, forKey: "deepseek.hasLaunchedBefore")
        if isFirstLaunch && !SettingsStore.shared.hasAPIKey {
            SettingsWindowController.show()
        }

        NotificationCenter.default.addObserver(
            forName: .deepSeekSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak statusBar] _ in
            MainActor.assumeIsolated {
                statusBar?.restartTimer()
                statusBar?.refresh()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

}
