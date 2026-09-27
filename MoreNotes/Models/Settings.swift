import Foundation

/// User-tunable settings. Persisted in UserDefaults except the API key, which
/// lives in the Keychain (see `KeychainStore`).
struct Settings: Codable, Equatable {
    /// Claude model used for chat, tutoring and quiz generation.
    var model: String = "claude-opus-5"
    /// Effort for background tutor checks. Lower = faster and cheaper.
    var tutorEffort: Effort = .medium
    /// Effort for chat and quiz generation.
    var chatEffort: Effort = .high
    /// Seconds of pen inactivity before the live tutor looks at the page.
    var tutorIdleSeconds: Double = 4
    /// Minimum seconds between two live tutor checks on the same page.
    var tutorMinInterval: Double = 20
    /// Optional proxy base URL (e.g. your own server that adds the API key). Empty = direct.
    var proxyBaseURL: String = ""
    /// Send the current page image with chat messages so Claude can "see" the page.
    var attachPageImageToChat: Bool = true
    /// Rebuild the on-device knowledge index automatically as you write.
    var autoIndex: Bool = true

    enum Effort: String, Codable, CaseIterable, Identifiable {
        case low, medium, high, xhigh, max
        var id: String { rawValue }
    }

    struct ModelOption: Identifiable {
        let id: String
        let label: String
    }

    static let availableModels: [ModelOption] = [
        ModelOption(id: "claude-opus-5", label: "Claude Opus 5 (recommended)"),
        ModelOption(id: "claude-sonnet-5", label: "Claude Sonnet 5 (faster, cheaper)"),
        ModelOption(id: "claude-fable-5-1", label: "Claude Fable 5.1 (most capable, pricier)"),
    ]

    private static let key = "MoreNotes.Settings.v1"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
