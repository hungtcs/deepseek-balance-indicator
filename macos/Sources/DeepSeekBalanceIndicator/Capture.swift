import AppKit

/// Dev-only (`--capture <dir>`): renders the app's own views to PNG for the README.
///
/// Uses `cacheDisplay(in:to:)`, which draws the view hierarchy in-process, so it
/// needs no Screen Recording permission. Menu-bar backgrounds are not part of
/// any view we own, so the status item is written with a transparent background
/// and composited onto a menu bar strip by `scripts/make-screenshots.sh`.
enum Capture {
    static func run(directory: String, arguments: [String]) -> Never {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            MainMenu.install()

            let directory = URL(fileURLWithPath: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let statusBar = StatusBarController()
            if let index = arguments.firstIndex(of: "--endpoint"), index + 1 < arguments.count,
               let url = URL(string: arguments[index + 1]) {
                statusBar.endpoint = url
            }
            statusBar.start()
            RunLoop.main.run(until: Date().addingTimeInterval(3))

            if let button = statusBar.statusBarButton {
                report("menubar", write(button, to: directory.appendingPathComponent("menubar.png")))
            }
            report("menu", captureMenu(statusBar.statusMenu, to: directory.appendingPathComponent("menu.png")))

            SettingsWindowController.show()
            AboutWindowController.show()
            RunLoop.main.run(until: Date().addingTimeInterval(2))

            for (title, name) in [("设置", "settings"), ("关于", "about")] {
                guard let window = NSApp.windows.first(where: { $0.title == title }) else {
                    report(name, false)
                    continue
                }
                // The theme frame includes the title bar; the content view does not.
                let view = window.contentView?.superview ?? window.contentView
                report(name, view.map { write($0, to: directory.appendingPathComponent("\(name).png")) } ?? false)
            }

            exit(0)
        }
    }

    /// Pops the menu up, grabs its window mid-tracking, then dismisses it.
    private static func captureMenu(_ menu: NSMenu, to url: URL) -> Bool {
        var captured = false
        let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
            let candidates = NSApp.windows.filter {
                String(describing: type(of: $0)).localizedCaseInsensitiveContains("menu")
            }
            print("  menu window candidates: \(candidates.map { String(describing: type(of: $0)) })")
            if let window = candidates.first {
                // The menu is composited by the window server, so neither
                // cacheDisplay nor layer.render can see it — but the window
                // belongs to this process, so a direct window capture is allowed.
                captured = writeWindowServerImage(window, to: url)
                    || window.contentView.map { write($0, to: url) } == true
            }
            menu.cancelTrackingWithoutAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 240, y: 420), in: nil)
        return captured
    }

    /// `cacheDisplay` draws through the view hierarchy, which produces a blank
    /// image for the layer-backed menu window. Falls back to rendering the layer
    /// tree directly when the first pass comes back empty.
    private static func write(_ view: NSView, to url: URL) -> Bool {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return false }

        if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: representation)
            if !isBlank(representation),
               let data = representation.representation(using: .png, properties: [:]) {
                return (try? data.write(to: url)) != nil
            }
        }

        view.displayIfNeeded()
        guard let layer = view.layer?.presentation() ?? view.layer,
              let context = CGContext(
                data: nil,
                width: Int(view.bounds.width * (view.window?.backingScaleFactor ?? 2)),
                height: Int(view.bounds.height * (view.window?.backingScaleFactor ?? 2)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { return false }
        context.scaleBy(x: view.window?.backingScaleFactor ?? 2, y: view.window?.backingScaleFactor ?? 2)
        layer.render(in: context)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Captures a window through the window server. Restricted to windows owned
    /// by this process, which is why it needs no Screen Recording permission.
    private static func writeWindowServerImage(_ window: NSWindow, to url: URL) -> Bool {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), options
        ) else { return false }
        let representation = NSBitmapImageRep(cgImage: image)
        guard !isBlank(representation),
              let data = representation.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// True when every sampled pixel matches, i.e. nothing actually drew.
    private static func isBlank(_ representation: NSBitmapImageRep) -> Bool {
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        guard width > 1, height > 1, let reference = representation.colorAt(x: 0, y: 0) else { return true }
        let stepX = max(1, width / 16)
        let stepY = max(1, height / 16)
        for x in stride(from: 0, to: width, by: stepX) {
            for y in stride(from: 0, to: height, by: stepY) {
                guard let sample = representation.colorAt(x: x, y: y) else { continue }
                if abs(sample.redComponent - reference.redComponent) > 0.02
                    || abs(sample.greenComponent - reference.greenComponent) > 0.02
                    || abs(sample.blueComponent - reference.blueComponent) > 0.02
                    || abs(sample.alphaComponent - reference.alphaComponent) > 0.02 {
                    return false
                }
            }
        }
        return true
    }

    private static func report(_ name: String, _ ok: Bool) {
        print("  \(ok ? "✓" : "✗") \(name)")
    }
}
