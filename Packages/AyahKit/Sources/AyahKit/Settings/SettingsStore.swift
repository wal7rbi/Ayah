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

    /// The error from the most recent `save()` attempt, or `nil` if it
    /// succeeded. `didSet` can't throw, so there's no caller to propagate
    /// a failure to synchronously — but it must stay observable rather
    /// than fully silent: a save failure means a settings change applied
    /// in memory but was never persisted, and would silently revert on
    /// the next launch.
    public private(set) var lastSaveError: Error?
    /// A malformed top-level settings blob is observable instead of
    /// looking indistinguishable from a first launch with no stored data.
    public private(set) var lastLoadError: Error?

    private let defaults: UserDefaults
    private static let storageKey = "com.ayah.appSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                self.settings = try JSONDecoder().decode(AppSettings.self, from: data)
                self.lastLoadError = nil
            } catch {
                self.settings = AppSettings()
                self.lastLoadError = error
            }
        } else {
            self.settings = AppSettings()
            self.lastLoadError = nil
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.storageKey)
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }
}
