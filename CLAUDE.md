# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

**How to update this file.** Describe what is true now. If a change makes a
sentence here wrong, edit that sentence — do not append a paragraph explaining
that the old one used to be right. This file was an append-only build narrative
until 2026-09-01 and grew to four times its current size, carrying claims that
later work had already contradicted. That narrative now lives in
`docs/history/BUILD_LOG.md` as a frozen record; git carries the rest. Nothing
here should be dated, and nothing should describe a sequence of events.

## Project

Ayah is a privacy-first, fully offline native macOS app (Swift/SwiftUI/AppKit).
It shows Quran verses in the MacBook notch, supports verse memorization, and
calculates Islamic prayer times offline with in-notch prayer alerts. No Hadith,
no backend, no accounts, and no network access by architecture: the App Sandbox
entitlements do not include `network.client`, and no networking API appears
anywhere in the source.

The app is Arabic-only. Every user-facing surface applies
`.environment(\.layoutDirection, .rightToLeft)` at its root. There is no English
variant and new UI should not introduce one. The single exception is
`AboutView`'s attribution block, which is intentionally English and
left-to-right.

`ARCHITECTURE.md` holds the rationale for every technical decision — minimum OS
version, notch geometry, data sourcing and licensing, prayer library,
persistence, entitlements, performance budget. Read the relevant section before
changing an architectural decision rather than re-deriving it.

Preserve dirty working-tree changes, and never commit SwiftPM `.build/` or Xcode
DerivedData output.

## Current state

The app is feature-complete for its scope: notch and menu-bar UI, Quran
display, memorization sets, prayer times, in-notch prayer alerts,
launch-at-login, last-shown replay, a non-notch fallback bar, a hardened Quran
data pipeline, and both test suites. `v1.0.1` is the latest published release;
`MARKETING_VERSION` is `1.0.2`, whose notes are in
`docs/release/RELEASE_NOTES_1.0.2.md` and which has not been packaged or
published yet.

Two things are not built and should not be started without being asked:
**themes** (white / beige-Mushaf / black), the one remaining optional product
heading; and **Developer ID signing and notarization**, relevant only if the
project joins the Apple Developer Program — Release builds are ad-hoc signed
today.

One task is outstanding rather than assumed done: the curated Arabic city-name
table (`ArabicNameOverrides.swift`) still owes a native-speaker review. Its doc
comment records what it covers and what it deliberately leaves in Latin.

## Repository layout

```
App/                     Xcode app target — AppKit/SwiftUI only
  UI/{Notch,MenuBar,Memorization,Prayer,About,Settings}/
  UI/LayoutMetrics.swift Sizes that two files must agree on
Packages/AyahKit/        Local SPM package — all business logic
  Sources/AyahKit/{Quran,Prayer,Memorization,Scheduling,Settings,Persistence,Launch,Diagnostics}/
  Tests/AyahKitTests/    Fast, headless suite (swift test)
Tests/App/               App-hosted suite (xcodebuild test)
Resources/{Quran,GeoNames,Fonts,ThirdParty}/           Committed generated data
Scripts/{import_quran,verify_quran,import_geonames}/   Independent SPM packages
docs/{history,audits,performance,release,plans}/
```

**Anything that does not need AppKit belongs in `AyahKit`**, so it stays
testable with plain `swift test`. Only window, panel, and status-item management
belongs in `App/`. When adding a module, default to `AyahKit` unless it directly
manipulates `NSWindow`/`NSPanel`/`NSScreen`.

## Commands

**Regenerate the Xcode project** after editing `project.yml` or adding any new
source file under `App/` or `Tests/App/`. XcodeGen enumerates files at generate
time, so a brand-new `.swift` file — even inside an already-referenced directory
— is silently excluded from the build, with no error explaining why, until this
is re-run:

```
xcodegen generate
```

**Build the app**:

```
xcodebuild -project Ayah.xcodeproj -scheme Ayah -destination 'platform=macOS' build
```

**Test.** There are two suites and they run differently.

```
cd Packages/AyahKit && swift test
swift test --filter AyahKitTests.QuranIntegrityTests/testChecksumMatches
```

```
xcodebuild test -project Ayah.xcodeproj -scheme Ayah -destination 'platform=macOS' -configuration Debug
```

The second runs `Tests/App` (the `AyahTests` target, covering `NotchViewModel`'s
state machine). It is app-hosted: XCTest injects it into a real `Ayah` process,
which is why `Bundle.main` inside it is the real app bundle and tests needing
real ayahs can read the bundled `quran.sqlite`. It is also why
`AppDelegate.applicationDidFinishLaunching` stands down under XCTest — without
that, the app would open its panel, start both schedulers, and write to the
user's real preferences underneath the suite. `AppLaunchGuardTests` keeps that
guard honest. Add `-only-testing:AyahTests/NotchViewModelTests/<name>` to run
one test.

**Run the built app.** It is an `LSUIElement` app with no Dock icon; quit it
from the menu-bar popover's "إغلاق آية" button, not Cmd-Q.

```
open $(xcodebuild -project Ayah.xcodeproj -scheme Ayah -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Ayah.app
```

**Check entitlements** on a built app, to verify no network-client entitlement
ever creeps in:

```
codesign -d --entitlements :- <path-to>/Ayah.app
```

### Re-running the data importers

`Resources/Quran/` and `Resources/GeoNames/` are committed, generated artifacts.
Never hand-edit them; re-run the importer instead.

**Quran.** Takes the whole downloaded KFGQPC archive plus the official MD5/SHA-1
from KFGQPC's own download page, verifies the archive against those, extracts
the CSV itself, and writes `quran.sqlite`, `VERSION`, `CHECKSUM`, `SOURCE.md`,
and `MANIFEST.json` together as a matched set:

```
cd Scripts/import_quran && swift build
.build/debug/import_quran \
  --source-archive <path-to-UthmanicHafs_v2-0.zip> \
  --official-md5 <md5-from-KFGQPC-download-page> \
  --official-sha1 <sha1-from-KFGQPC-download-page> \
  --out-dir ../../Resources/Quran \
  --source-url <upstream-zip-url> \
  --source-package "<package name>" \
  --source-version "<version>" \
  --source-date <YYYY-MM-DD>
```

```
cd Scripts/verify_quran && swift build
.build/debug/verify_quran ../../Resources/Quran   # must exit 0; cross-checks MANIFEST.json
```

**GeoNames.** Download and unzip `cities1000.zip`. `--arabic-names` is optional
but needed for Arabic display names: download and unzip `alternateNamesV2.zip`
(~778 MB), then pre-filter it, since the importer does not scan the full 19M-row
world dump itself.

```
awk -F'\t' '$3=="ar"' alternateNamesV2.txt > arabic_only_worldwide.tsv
```

```
cd Scripts/import_geonames && swift build
.build/debug/import_geonames \
  --tsv <path-to-cities1000.txt> \
  --out-dir ../../Resources/GeoNames \
  --source-url https://download.geonames.org/export/dump/cities1000.zip \
  --source-date <YYYY-MM-DD> \
  --arabic-names <path-to-arabic_only_worldwide.tsv>
```

Both importers write their checksum file themselves, and both must stay
**deterministic**: two runs over the same input produce byte-identical output,
which is what makes a checksum reproducible rather than merely
corruption-detecting. Do not put a timestamp or any other per-run value into
either database; `SOURCE.md` is where a generation time belongs. `GEONAMES_CHECKSUM`
used not to be generated at all, which meant every GeoNames re-import produced a
database the app then refused to load at launch until someone regenerated the
checksum by hand.

## Rules that must not be broken

Each of these cost real debugging time at least once, and every one of them
fails silently.

**`project.yml`'s `Resources` entry needs `buildPhase: resources` explicitly.**
XcodeGen cannot infer a resource type for an extensionless file (e.g.
`Resources/Quran/CHECKSUM`), so without the override it emits only a
`PBXFileReference` and never wires the file into Copy Bundle Resources — the app
ships without it and nothing fails at build time. Resource files are also
flattened into `Contents/Resources/` with no subfolder nesting, so filenames
must be unique bundle-wide; that is why `**/SOURCE.md`, `**/VERSION`, and
`**/MANIFEST.json` are excluded from bundling rather than shipped.

**`Info.plist` is hand-written** (`GENERATE_INFOPLIST_FILE: NO`). It must keep
`CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleName`, and
`CFBundlePackageType` set explicitly. Omitting `CFBundleIdentifier` crashes App
Sandbox initialization on launch (`SIGTRAP` in `libsecinit_appsandbox`) before
any app code runs.

**Check the actual OS requirement for a permission API, not just its evident
intent.** `CurrentLocationProvider` calls `requestWhenInUseAuthorization()`,
which requires `NSLocationWhenInUseUsageDescription` specifically. With only the
legacy `NSLocationUsageDescription` present, macOS silently ignores the request —
no dialog, no delegate callback — and the `CheckedContinuation` never resumes. A
review pass once cited the wrong key as evidence this flow was correct.

**SwiftUI `List` + `.onTapGesture` does not work for row selection on macOS.**
`List` is backed by `NSTableView`/`NSOutlineView`, whose own click handling
competes with the gesture and wins: it silently never fires, even though
Accessibility confirms the click landed inside the row. Use
`Button { … } label: { row }.buttonStyle(.plain)` instead. Both sites that had
this bug (`CityPickerView`, `MemorizationSetsView.row(for:)`) are fixed; do not
reintroduce the pattern.

**SwiftUI `.onAppear` is not reliably timed on a view hosted directly as an
`NSWindow`'s `contentViewController`** — that is, with no SwiftUI `App`/`Scene`
driving it. `MemorizationSetsView` loading its surah list in `.onAppear` produced
an empty picker the first time the window opened. Load initial data in the
view's `init` for any view hosted this way. This does not apply to
`PopoverContentView`, which uses live bindings rather than a one-time load.

**Sizes that two files must agree on live in `App/UI/LayoutMetrics.swift`.**
`NotchMetrics.expandedSize` is read by both `NotchController` (panel size) and
`NotchContentView` (content sizing); `PopoverMetrics.contentSize` by both
`StatusItemController` and `PopoverContentView`. Each pair was once two literals
kept in sync by hand, which silently clips content against the smaller of the
two — no build error, and for the popover no scroll indicator warning the user
there is more below. Put any future window/view size pair here.

**The notch expanded card reserves top clearance of at least
`viewModel.collapsedSize.height`** before any text. On real notched hardware
that band is physically occluded by the camera housing, and tall Arabic
diacritics get clipped under it. Growing `NotchMetrics.expandedSize.height` is
safe; shrinking it is not, and text space must never be reclaimed by trimming
this clearance.

**Never match `uthmanic_text` with a plain-spelled substring, and never
normalize it.** Uthmani orthography interleaves diacritics between consonants,
so `LIKE '%صلاة%'` against `uthmanic_text` returns zero rows while the same query
against `searchable_text` returns 63. Filter on `searchable_text` — a column
KFGQPC ships pre-simplified, not one derived by mutating the Uthmani text — and
display `uthmanic_text`. No diacritic stripping, no character substitution,
ever.

**Always display `City.displayName`, never `City.name`.** Well under half of
bundled cities have an Arabic name, and a place with no Arabic exonym is meant to
stay Latin. `displayName` is the single `nameArabic ?? name` fallback rule; do
not reimplement the `??` at a call site.

**Prayer times must be computed in the target location's own timezone.**
`PrayerCalculator.prayerTimes(...)` takes a required `timeZone:`; Adhan Swift
interprets the passed date components via a UTC-based calendar internally, so the
caller must supply the year/month/day as experienced at that location. Using
`TimeZone.current` instead produced a shipped wrong-day bug for anyone whose
system timezone differed from their selected city — the diaspora and travel case
the bundled city dataset exists for. `PrayerLocationResolver.resolve` is the one
place that decides coordinates and timezone; both the Settings popover and
`PrayerAlertScheduler` go through it, because when those two disagree the user
sees one set of times and gets alerts at another.

**One shared instance of `SettingsStore`, `MemorizationRepository`, and
`LastShownStore`**, constructed once in
`AppDelegate.applicationDidFinishLaunching` and injected. Two `SettingsStore`
instances over the same `UserDefaults` key do not observe each other, so a
settings UI writing to one would never live-update the other.

**Launch-at-login state has no `AppSettings` field, deliberately.**
`SMAppService.mainApp.status` is macOS's own Login Items list, independently
editable from System Settings, and is the source of truth. Mirroring it into
`UserDefaults` would create a second copy that drifts.
`LaunchAtLoginViewModel.refresh()` re-reads it on demand.

**Third-party enums can be given `Sendable` retroactively** when they are
genuinely simple immutable value types — e.g.
`extension CalculationMethod: @unchecked @retroactive Sendable {}` for Adhan
Swift's `CalculationMethod`/`Madhab`, which `AppSettings: Sendable` stores
directly. Reach for this instead of wrapping a third-party type in a parallel
local enum, but only after actually checking it holds no mutable or reference
state.

**`AyahKit.swift`'s `public enum AyahKit` marker shadows the module name.** A
file importing both `Adhan` and `AyahKit` cannot disambiguate `Coordinates` by
writing `AyahKit.Coordinates` — that resolves to the marker enum and fails to
compile. Resolve it by argument-position type inference (construct
`Coordinates(...)` directly where a parameter's declared type picks the
overload), as `PrayerCalculatorTests` does. A stored or computed *property* has
no call site to infer from, so the fix there is to wrap the value in a type that
exists in one module only: `PrayerLocationResolver`'s `ResolvedPrayerLocation`
does this, and its doc comment records why.

**Classes touching AppKit directly are explicitly `@MainActor`** —
`NotchController`, `StatusItemController`, and the schedulers that drive them.
Swift 6 rejects AppKit object construction in a non-isolated context; do not
remove these annotations to "simplify" a class.

**A `@MainActor` class conforming to a plain system delegate protocol needs an
isolated conformance**, not a `@MainActor`-annotated extension. That annotation
isolates the extension's *members*, not the conformance, which the compiler
tracks separately. Write
`extension CurrentLocationProvider: @MainActor CLLocationManagerDelegate { … }`.

**`QuranIntegrityTests` locates `Resources/Quran/` via `#filePath`, not SPM
package resources.** That directory is outside every SPM target's source tree.
An earlier attempt symlinked the files in and declared them as `.copy()`
resources, but SPM preserves symlinks rather than dereferencing them, so the
relative target broke once copied into the differently-nested bundle
(`sqlite3_open` failing with `SQLITE_CANTOPEN`).

**A local build is weak evidence for CI: the toolchains are far apart.** This
Mac runs Xcode 26.3 / Swift 6.2; the `macos-15` runner selects Xcode 16.4 /
Swift 6.1. Swift 6.2 infers actor isolation for an XCTest override, so a
`@MainActor` test class whose nonisolated `tearDown()` touches isolated
properties compiles here and fails on CI. That exact mistake has already
cost one red run. When a change leans on recent concurrency behaviour, treat
CI as the authority and expect to iterate there; the properties in
`NotchViewModelTests` are `nonisolated(unsafe)` for this reason, which is
sound because XCTest runs setUp, the test, and tearDown serially.

**AyahKit is linked into `AyahTests` with `link: false`.** It builds as a static
library, so linking it into the test bundle as well as the host app would give
the two modules separate, mutually incompatible copies of every AyahKit type,
and `@testable import Ayah` would hand `NotchViewModel.init` the wrong
`SettingsStore`.

## Deliberate decisions — do not "fix" these

- **The KFGQPC Quran text carries no published redistribution license.** A
  documented, re-confirmed, accepted product risk in `THIRD_PARTY_LICENSES.md`.
  Do not resolve it by quietly swapping the data source. The bundled **font** is
  a separate and settled question: its EULA is embedded in the file's own
  metadata and permits Ayah's unmodified bundling.
- **The Quran checksum algorithm exists in three independent copies** across
  `import_quran`, `verify_quran`, and `QuranIntegrityTests`. Belt-and-suspenders
  for integrity-critical data. Do not consolidate.
- **`Scripts/import_quran` and `Scripts/verify_quran` are separate SPM
  packages** with their own `Package.swift`, linking only system SQLite3 and
  CryptoKit. Same reasoning.
- **The Release build runs `verify_quran` plus the full AyahKit suite as a
  pre-build script.** Slow and unconventional, and it couples building to
  testing. It is also what makes shipping a Release binary against unverified
  Quran data impossible. Keep it. It is gated on `$CONFIGURATION = Release`, so
  Debug builds skip it.
- **`MemorizationSet.RepetitionMode.random` is not offered in the editor.** It
  exists and is tested, but shuffling away the order a user is memorizing in is
  not a useful option to expose.
- **The Quran schema omits `hizb_quarter`, `ruku_number`, `manzil_number`,
  `sajda`, translated surah names, `revelation_place`, and `revelation_order`.**
  KFGQPC's real export does not include them and no in-scope feature needs them;
  they were dropped rather than pulling in a second data source. See
  `ARCHITECTURE.md` §7 and `Resources/Quran/SOURCE.md`.
- **Release builds are arm64-only.** This means the non-notch fallback bar
  cannot reach Intel Macs, so its real audience is Apple Silicon machines
  without a notch. Note the interaction; it is not a defect.
- **`AboutWindowController`'s 480×520 against `AboutView`'s `minWidth`/
  `minHeight`** is not the `LayoutMetrics` hazard: it is a minimum against a
  resizable window, so a divergence degrades gracefully instead of clipping.
- **Switching notch/fallback mode while running is out of scope** — e.g. a
  notched MacBook entering clamshell with only an external display attached. The
  mode is picked once, at attach time.

## Verification expectations

A claim here is backed by something that was actually run, and **a new test is
seen to fail before it is trusted** — by inverting its assertion or disabling
the guard it covers. The timezone regression test, the Quran tampering tests,
every `NotchViewModel` test, and the GeoNames checksum fix were all confirmed
this way.

UI work is verified by running the built app and inspecting it through
Accessibility or a screenshot, not by reading the diff. Two practical notes: the
menu-bar popover's content lives under `pop over 1 of menu bar 2`, not
`window 1`; and `entire contents` of a SwiftUI scroll area often returns
nothing, so address elements directly by index instead.

Any change touching `AppSettings`, entitlements, or data handling carries an
implicit obligation to re-check `PRIVACY.md` and `SECURITY.md` for staleness. A
privacy document falling out of sync with the code is a bug, not a matter of
opinion.
