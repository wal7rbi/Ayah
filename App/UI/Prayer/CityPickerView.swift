import AyahKit
import SwiftUI

/// A searchable list of the bundled GeoNames cities (~4,650 — see
/// `Resources/GeoNames/SOURCE.md`), too many for a plain `Picker`. Same
/// reasoning as `MemorizationSetsWindowController` for living in its own
/// window rather than the transient Settings popover.
struct CityPickerView: View {
    let onSelect: (City) -> Void

    /// Loaded in `init`, not `.onAppear` — see `MemorizationSetsView`'s
    /// doc comment for why `.onAppear` isn't reliably timed on a view
    /// hosted directly as an `NSWindow`'s `contentViewController`.
    private let cities: [City]

    @State private var query = ""

    init(locationRepository: LocationRepository, onSelect: @escaping (City) -> Void) {
        self.cities = locationRepository.cities()
        self.onSelect = onSelect
    }

    /// Matches against both `name` and `nameArabic` (when bundled) so a
    /// search works regardless of which script the user types — e.g.
    /// either "Riyadh" or "الرياض" finds the same city.
    private var filteredCities: [City] {
        guard !query.isEmpty else { return cities }
        return cities.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.nameArabic?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("بحث عن مدينة", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            if filteredCities.isEmpty {
                Spacer()
                Text("لا توجد نتائج")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                // A plain `.onTapGesture` here doesn't reliably fire on
                // macOS: `List` rows are backed by `NSTableView`, whose
                // own click-to-select handling competes with a tap
                // gesture on the row's content (confirmed by hand — the
                // gesture silently never fired). A `Button` per row goes
                // through AppKit's normal action mechanism instead and
                // is the reliable idiom for "tap a List row" on macOS.
                List(filteredCities) { city in
                    Button {
                        onSelect(city)
                    } label: {
                        HStack {
                            Text(city.displayName)
                            Spacer()
                            Text(city.countryCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
