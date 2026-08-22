import Combine
import Foundation

/// The `AppSettings` Codable struct backing `UserDefaults` (ARCHITECTURE.md
/// §7/§15) — a handful of scalars, no relational shape, no migration
/// ceremony needed. Publishes changes so other modules can react, per
/// ARCHITECTURE.md's `SettingsStore` module responsibility — there is no
/// Settings UI yet to write through it (that's its own later build
/// stage), so in practice nothing mutates `settings` until that stage
/// exists, but `VerseScheduler` already reads live values through it.
public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let storageKey = "com.ayah.appSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
