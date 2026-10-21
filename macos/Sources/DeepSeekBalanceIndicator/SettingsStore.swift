import Foundation

extension Notification.Name {
    static let deepSeekSettingsDidChange = Notification.Name("DeepSeekSettingsDidChange")
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let defaultPollInterval: Double = 30
    static let minPollInterval: Double = 5
    static let maxPollInterval: Double = 3600

    private enum Key {
        static let apiKey = "deepseek.apiKey"
        static let pollInterval = "deepseek.pollInterval"
    }

    @Published private(set) var apiKey: String
    @Published private(set) var pollInterval: Double

    private init() {
        let defaults = UserDefaults.standard
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        let stored = defaults.double(forKey: Key.pollInterval)
        pollInterval = stored > 0 ? stored : Self.defaultPollInterval
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(apiKey: String, pollInterval: Double) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let clamped = min(max(pollInterval, Self.minPollInterval), Self.maxPollInterval)
        let changed = trimmed != self.apiKey || clamped != self.pollInterval

        self.apiKey = trimmed
        self.pollInterval = clamped

        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: Key.apiKey)
        defaults.set(clamped, forKey: Key.pollInterval)

        guard changed else { return }
        NotificationCenter.default.post(name: .deepSeekSettingsDidChange, object: nil)
    }
}
