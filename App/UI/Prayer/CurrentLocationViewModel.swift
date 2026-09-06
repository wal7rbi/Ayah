import AyahKit
import Foundation

/// Bridges the Settings popover's "current location" button to
/// `CurrentLocationProvider` (AyahKit) and `AppSettings`. Deliberately a
/// one-shot fetch per tap, cached into
/// `AppSettings.currentLocationCoordinates` until the user taps again —
/// there is no live location subscription here, matching ARCHITECTURE.md
/// §18's no-continuous-background-work priority and the pattern already
/// used for the bundled city dataset (fetch/pick once, reuse until
/// changed).
@MainActor
final class CurrentLocationViewModel: ObservableObject {
    @Published private(set) var isFetching = false
    @Published var errorMessage: String?

    private let provider: LocationProviding
    private let settingsStore: SettingsStore

    init(provider: LocationProviding? = nil, settingsStore: SettingsStore) {
        self.provider = provider ?? CurrentLocationProvider()
        self.settingsStore = settingsStore
    }

    func fetchCurrentLocation() async {
        errorMessage = nil
        isFetching = true
        defer { isFetching = false }
        do {
            let coordinates = try await provider.requestOneShotLocation()
            var settings = settingsStore.settings
            settings.currentLocationCoordinates = coordinates
            settings.currentLocationTimeZoneIdentifier = TimeZone.current.identifier
            settings.currentLocationFetchedAt = Date()
            settings.prayerLocationSource = .currentLocation
            settingsStore.settings = settings
        } catch LocationProviderError.authorizationDenied {
            errorMessage = "لم يتم منح إذن الموقع لآية. يمكنك تفعيله من إعدادات النظام > الخصوصية والأمان > خدمات الموقع."
        } catch {
            errorMessage = "تعذر الحصول على الموقع الحالي. حاول مرة أخرى."
        }
    }
}
