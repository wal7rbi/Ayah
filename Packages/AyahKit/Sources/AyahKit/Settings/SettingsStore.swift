import Combine
import Foundation

/// Observable local settings with field-wise migration and recoverable decode errors.
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
    @Published public private(set) var lastSaveError: Error?
    /// A malformed top-level settings blob is observable instead of
    /// looking indistinguishable from a first launch with no stored data.
    @Published public private(set) var lastLoadError: Error?

    private let defaults: UserDefaults
    private static let storageKey = "com.ayah.appSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                self.settings = try JSONDecoder().decode(AppSettings.self, from: data)
                self.lastLoadError = nil
            } catch {
                // Preserve the original before a subsequent edit replaces the active key.
                if defaults.data(forKey: Self.storageKey + ".recovery") == nil {
                    defaults.set(data, forKey: Self.storageKey + ".recovery")
                }
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
