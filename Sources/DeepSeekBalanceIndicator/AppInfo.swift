import AppKit
import Foundation

enum AppInfo {
    static let name = "DeepSeek 余额指示器"
    static let bundleIdentifier = "com.hungtcs.deepseek-balance-indicator"
    static let apiKeysURL = URL(string: "https://platform.deepseek.com/api_keys")!
    static let platformURL = URL(string: "https://platform.deepseek.com")!

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Loads the DeepSeek whale that ships in the target's `Resources` folder.
///
/// Deliberately avoids `Bundle.module`: its generated accessor looks for the
/// resource bundle at `Bundle.main.bundleURL` (the `.app` root, not
/// `Contents/Resources`) and calls `fatalError` when it misses, which would
/// crash the app as soon as the `.build` directory is gone.
enum MenuBarIcon {
    /// Point size the 39x28 px bitmap is displayed at (exact 2x, keeps the 63x46.4 artwork ratio).
    static let pointSize = NSSize(width: 19.5, height: 14)

    private static var resourceURL: URL? {
        // Inside the .app: Contents/Resources/icon.png
        if let url = Bundle.main.url(forResource: "icon", withExtension: "png") {
            return url
        }
        // `swift run` / raw binary: the SwiftPM bundle sits next to the executable.
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        let bundled = executableDir
            .appendingPathComponent("DeepSeekBalanceIndicator_DeepSeekBalanceIndicator.bundle")
            .appendingPathComponent("Resources/icon.png")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled : nil
    }

    static func load() -> NSImage? {
        guard let url = resourceURL, let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data) else { return nil }
        representation.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(representation)
        // Template = AppKit draws only the alpha channel in the system colour, so
        // the whale matches every other status item (white on a dark menu bar,
        // black on a light one). No colour needs to be baked into the artwork.
        image.isTemplate = true
        return image
    }

    static var debugDescription: String {
        guard let url = resourceURL else { return "not found in Bundle.module" }
        return "\(url.path) -> \(load() == nil ? "failed to decode" : "ok")"
    }
}
