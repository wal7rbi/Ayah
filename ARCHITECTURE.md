# Ayah — Architecture & Technical Design

Ayah is a lightweight, privacy-first, fully offline native macOS app that
displays Quran verses from the MacBook notch area, helps with memorization
of selected verses, and calculates Islamic prayer times entirely offline
with in-notch prayer alerts while the app is running.

Priorities, in order: **(1)** correctness of Quran data, **(2)** privacy
and security, **(3)** very low CPU/memory/wakeup/battery usage, **(4)** a
native macOS experience, **(5)** a simple, maintainable architecture,
**(6)** open-source friendliness.

This began as the research-stage design and now records both implemented
decisions and explicitly marked history. The app target, AyahKit, bundled
datasets, import/verification tools, settings, memorization, prayer-time
calculation, in-notch alerts, About/source credits, and unnotarized DMG
packaging exist. Version 1.0.1 intentionally targets Apple Silicon and does
not use Developer ID or notarization; the stable artifact remains gated on
the hardware/accessibility checklist in `docs/release/`.

---

## 1. Minimum macOS version

**macOS 13 (Ventura).**

- `SMAppService` (the modern, non-deprecated launch-at-login API) requires
  macOS 13.
- The notch-geometry APIs used for the core UI (`NSScreen.safeAreaInsets`,
  `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`) already work from macOS
  12, so targeting 13 costs nothing additional there.
- As of mid-2026, roughly 86% of active Macs run the current major macOS
  release, with negligible share below macOS 14 — the practical reach cost
  of a 13 floor is minimal.

## 2. Project architecture

**A single Xcode app target, plus one local Swift Package (`AyahKit`) for
all business logic.**

A pure SPM executable cannot produce a properly sandboxed, entitlement-
bearing, `LSUIElement` (no Dock icon) menu-bar `.app` bundle with icons and
an `Info.plist`. A bare Xcode app target, on the other hand, makes it
awkward to run fast, headless `swift test` in CI without a simulator or UI
test runner. Splitting the two solves both problems and enforces a useful
boundary: `AyahKit` contains everything that doesn't need AppKit —
`Quran`, `Memorization`, `Prayer`, `Scheduling`,
`Settings`, `Persistence` — and is fully unit-testable in isolation. Only
notch/menu-bar window management, which is inherently AppKit-bound, lives
in the app target.

```
Ayah/
  README.md  ARCHITECTURE.md  PRIVACY.md  SECURITY.md  CONTRIBUTING.md
  LICENSE  THIRD_PARTY_LICENSES.md
  .github/workflows/ci.yml
  Ayah.xcodeproj
  App/
    AyahApp.swift  AppDelegate.swift  Ayah.entitlements  Info.plist  Assets.xcassets
    UI/Notch/{NotchPanel,NotchController,NotchContentView}.swift
    UI/MenuBar/{StatusItemController,PopoverContentView}.swift
    UI/Settings/SettingsView.swift
  Packages/AyahKit/
    Package.swift
    Sources/AyahKit/
      Quran/{QuranAyah,Surah,QuranRepository,QuranIntegrityChecker}.swift
      Memorization/{MemorizationSet,MemorizationRepository}.swift
      Prayer/{PrayerCalculator,Coordinates,City,LocationRepository}.swift
      Scheduling/{VerseScheduler,PrayerAlertScheduler,PrayerAlertEvent}.swift
      Settings/{SettingsStore,AppSettings}.swift
      Persistence/ (small SQLite wrapper helpers)
    Tests/AyahKitTests/*.swift
  Resources/
    Quran/{quran.sqlite, SOURCE.md, VERSION, CHECKSUM}
    GeoNames/{cities_filtered.sqlite, GEONAMES_CHECKSUM, SOURCE.md}
    Fonts/ (KFGQPC Uthmanic Hafs)
  Scripts/
    import_quran/{main.swift, ...}
    verify_quran/{main.swift, ...}
```

## 3. Notch UI implementation

A borderless, non-activating `NSPanel` hosts SwiftUI content via
`NSHostingView`. Its geometry is computed from
`NSScreen.safeAreaInsets`/`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`
(both macOS 12+) and recomputed whenever
`NSApplication.didChangeScreenParametersNotification` fires (display
changes, resolution changes, external monitor connect/disconnect). The
panel's window level is `.statusBar` or higher so it renders above the
menu bar, with `collectionBehavior` including `.canJoinAllSpaces` and
`.fullScreenAuxiliary` so it stays visible across Spaces and full-screen
apps.

Expand/collapse is driven **purely by SwiftUI state** (`withAnimation` /
spring animations) triggered only on discrete events — a verse becoming
due, or a user click. There is never a continuous per-frame animation
loop. This is the single biggest lever on the idle-CPU target: web-shell
based notch apps have been observed sitting at 10–15% CPU continuously,
purely from render loops, versus roughly 0.1–1% for a SwiftUI
state-driven approach.

Three existing open-source notch projects were studied for proven
technique (none of their code is copied — see `THIRD_PARTY_LICENSES.md`):

| Project | License | Notes |
|---|---|---|
| [NotchDrop](https://github.com/Lakr233/NotchDrop) | MIT | Borderless NSPanel over the notch rect; safe to reference |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch) | GPL-3.0 | Copyleft — studied for the general windowing approach only, **never to be copied from** |
| NotchNook | Closed source | Nothing to reference |

## 4. Fallback for Macs without a notch

Two separate things are both true on a Mac without a notch, and this
section covers both.

**Settings** always go through a standard `NSStatusItem` with an
`NSPopover` (`StatusItemController`/`PopoverContentView`) — the universal,
well-understood macOS menu-bar utility pattern. This is not just a fallback
for non-notch hardware (older MacBooks, Mac mini/Studio, iMac, or a notched
MacBook driving only an external display): it is also the **default entry
point for Settings** on every Mac, notch or not, so there's only one
interaction pattern to maintain rather than two divergent UIs.

**Verse display and prayer alerts** get their own fallback, reusing the
same view stack as the physical notch rather than going unimplemented or
duplicating it. `NotchController.attachToNotchIfAvailable()` picks one of
two paths once, at attach time: `attachPhysicalNotch(on:)` (today's
existing behavior — a panel sized to the real notch cutout, always visible
as a small collapsed pill) or `attachFallbackBar()` when
`notchedScreen()` finds no notch. The fallback reuses the exact same
`NotchPanel`/`NotchViewModel`/`NotchContentView` — same Uthmanic-font verse
card, same prayer-alert card, same expand/auto-collapse timing — as a
borderless floating panel pinned to the top-center of the primary screen,
positioned via `screen.visibleFrame.maxY` (which excludes the menu bar
strip) so it sits flush below the menu bar rather than overlapping it.
Two differences from the physical-notch path, both driven by a
`NotchContentView.isPhysicalNotch` flag threaded down from `NotchPanel`:
- **Shape**: a plain flat-topped, rounded-bottom `UnevenRoundedRectangle`
  instead of `NotchShape`'s concave top flare — there's no physical camera
  housing here for a concave flare to read as growing out of.
- **Visibility**: hidden entirely while idle (`NotchController` subscribes
  to `viewModel.$isExpanded` and orders the panel front/out accordingly)
  rather than left as an always-visible collapsed pill — there's nothing
  for a permanent floating pill to visually blend into on this class of
  Mac the way the physical notch pill blends into the camera housing.

Both `VerseScheduler.start(...)` and `PrayerAlertScheduler.start(...)` are
called from both paths identically — before this, they were only ever
started from the physical-notch path, so verse display and prayer alerts
silently never ran at all on a non-notch Mac (see §13's own note on this,
now superseded). Switching modes while already running (e.g. a notched
MacBook entering clamshell mode with only an external display attached) is
out of scope — the same scope boundary the physical-notch path's own
`screenParametersChanged()` already had (it only re-positions/hides within
whichever mode was picked at attach time, not switches between them).

## 5. Quran text source & licensing

**Source: the official King Fahd Glorious Quran Printing Complex (KFGQPC)
Software Developers Platform — https://qurancomplex.gov.sa/quran-dev/.**

This platform is confirmed real, current, and official (copyright notice
"All rights reserved © 2026 King Fahd Complex for Printing the Holy
Quran"). It offers the Hafs-narration, Uthmanic-script, Madinah
Mushaf-compatible Quran text — along with the matching Uthmanic Hafs font
— for free download with no registration, in multiple formats (SQL, JSON,
XML, CSV, Excel, PDF, TXT, Word).

**Licensing caveat, documented deliberately and not glossed over:** the
platform publishes no terms-of-use or license page anywhere for the *text*
(verified directly, including every footer link — only a privacy policy
and an unrelated printed-Mushaf sales policy exist; re-verified 2026-08-22
going further still — the downloaded package's own `read.me` and its raw
CSV/SQL/JSON/XML exports carry no license text either, same conclusion).
"Freely downloadable for developers" is not the same as "licensed for
redistribution" in an open-source GitHub repository and a distributed app
binary. After this gap was surfaced, the decision was made to proceed
using this official KFGQPC data anyway, accepting the residual legal risk
— reaffirmed 2026-08-22 after the deeper check above — see
`THIRD_PARTY_LICENSES.md` for the full reasoning, the mitigation path
(pursuing written permission from KFGQPC), and the fallback source
(Tanzil.net, which has an explicit, unambiguous redistribution license for
the same Uthmani Hafs text) that the import pipeline is designed to be
able to swap to later without an architecture rewrite.

## 6. Quran font & licensing

**Different from §5's conclusion, not the same caveat.** The KFGQPC
Uthmanic Hafs TrueType font (`Resources/Fonts/uthmanic_hafs_v20.ttf`,
bundled from the same developer platform and package as the text) carries
an End-User License Agreement embedded directly in its own font metadata
— readable via `strings` on the file, not present anywhere on the download
webpage, which is why an earlier check of the website alone missed it.
Confirmed 2026-08-22 to be byte-for-byte identical (SHA-256) to the font
inside a freshly re-downloaded copy of `UthmanicHafs_v2-0.zip`. The
embedded EULA grants free "Use, Copy, Distribute" rights, prohibiting only
selling, modifying, or reverse-engineering the font — Ayah bundles it
unmodified and only registers it at runtime, squarely within that grant.
See `THIRD_PARTY_LICENSES.md` for the full quoted text.

## 7. Quran SQLite import strategy

`Scripts/import_quran` takes the whole downloaded KFGQPC archive (the
"Hafs Narration (Standard)" package, `UthmanicHafs_v2-0.zip` — chosen over
the "Smart Devices" package because the latter encodes `aya_text` in
private-use-area glyph codepoints tied to its own font rather than
portable Unicode), not a pre-extracted CSV. Before parsing anything, it
computes the archive's MD5 and SHA-1 and compares them against the values
KFGQPC publishes on the same download page (`--official-md5`/
`--official-sha1`, operator-supplied since the importer has no network
access of its own) — a hard failure on either mismatch, no silent
continue. MD5/SHA-1 are used here only because they're what KFGQPC
publishes as an upstream identity check, not because Ayah considers them
security primitives; the importer separately computes its own SHA-256 of
the archive as the long-term integrity identifier. Once verified, it
extracts `hafsData_v2-0.csv` from the archive itself (shelling out to
`/usr/bin/unzip -p`, no new dependency) and parses that. This is official
Madinah Mushaf data and was confirmed, by actually downloading and
inspecting the export, to contain accurate surah names (transliterated),
juz numbers, and page numbers matching the standard 604-page Mushaf
pagination, plus a ready-made simplified-spelling column
(`aya_text_emlaey`, documented by KFGQPC as "used for search purpose")
that is used directly as `searchable_text` rather than being derived by
stripping diacritics ourselves.

**Confirmed gap, resolved rather than silently assumed:** the KFGQPC
export does **not** include `hizb_quarter`, `ruku_number`,
`manzil_number`, `sajda` markers, translated (as opposed to
transliterated) English surah names, or `revelation_place`/
`revelation_order`. This was the exact risk flagged when this document
was first written. Decision: since no currently-scoped feature
(Memorization, Prayer, Themes, Notifications) needs any of those fields,
Stage 3 ships without them rather than pulling in a second data source
pre-emptively. If a future stage needs them, `Scripts/import_quran` is
the only place that changes — merge in a secondary, separately-license-
checked source (Tanzil.net's `quran-data`, already named in
`THIRD_PARTY_LICENSES.md` as the fallback source, is the natural
candidate) and re-run the importer; the bundled schema simply gains
columns, no architecture rewrite. See `Resources/Quran/SOURCE.md` for the
exact export version and date used.

The importer produces `Resources/Quran/quran.sqlite`.

### Data model

```sql
-- Immutable, read-only, shipped inside the app bundle.
CREATE TABLE surahs (
  number              INTEGER PRIMARY KEY,      -- 1..114
  name_arabic         TEXT NOT NULL,
  name_transliterated TEXT NOT NULL,
  ayah_count          INTEGER NOT NULL
);

CREATE TABLE ayahs (
  id               INTEGER PRIMARY KEY,         -- global 1..6236
  surah_number     INTEGER NOT NULL REFERENCES surahs(number),
  ayah_number      INTEGER NOT NULL,            -- 1-based within surah
  juz_number       INTEGER NOT NULL,            -- 1..30
  page_number      INTEGER NOT NULL,            -- 1..604 (Madani mushaf)
  uthmanic_text    TEXT NOT NULL,                -- never programmatically modified
  searchable_text  TEXT NOT NULL,                -- diacritic-stripped, for search only
  UNIQUE (surah_number, ayah_number)
);
CREATE INDEX idx_ayahs_juz  ON ayahs(juz_number);
CREATE INDEX idx_ayahs_page ON ayahs(page_number);

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);  -- source_url, source_package, source_version, source_date,
    -- source_sha256, content_version, checksum
```

`meta` deliberately carries no wall-clock timestamp (no `generated_at`
row) — that was the one identified obstacle to deterministic output (see
§8's reproducibility note); an import timestamp is recorded only in the
generated, unhashed `SOURCE.md`, never inside the database itself. Nothing
in the app reads `meta` at runtime; it exists for provenance inspection
only.

`name_english`, `revelation_place`, `revelation_order`, `hizb_quarter`,
`ruku_number`, `manzil_number`, and `sajda` are deliberately not columns
yet — see the gap note above.

`uthmanic_text` is stored and displayed exactly as supplied by the source
— never normalized, never stripped of diacritics or waqf marks, never
otherwise altered. `searchable_text` is a separate, explicitly
diacritic-stripped column used only for search, so the displayed Quran
text is never derived from a lossy transformation.

**Mutable user data is stored entirely separately**, in different files,
so the immutable Quran data can never be accidentally touched by app code:

```sql
-- ayah_user.sqlite — small, local, user-editable.
CREATE TABLE memorization_sets (
  id                  TEXT PRIMARY KEY,          -- UUID
  surah_number        INTEGER NOT NULL,
  start_ayah          INTEGER NOT NULL,
  end_ayah            INTEGER NOT NULL,
  is_enabled          INTEGER NOT NULL DEFAULT 1,
  repetition_mode     TEXT NOT NULL DEFAULT 'sequential', -- 'sequential' | 'random'
  cursor_ayah         INTEGER,                    -- for sequential mode
  created_at          TEXT NOT NULL,
  -- Placeholders for a future spaced-repetition mode (v2+). Nullable now
  -- so activating spaced repetition later means writing values, not an
  -- ALTER TABLE migration.
  last_shown_at       TEXT,
  ease_factor         REAL,
  review_interval_days INTEGER
);
```

`AppSettings` (calculation method, Asr method, city, verse display
interval, verses per display, memorization weight percentage, toggles) is
a small `Codable` struct persisted via `UserDefaults` — not SwiftData
(which requires macOS 14+, above our 13 floor) and not worth a relational
schema for a handful of scalar values.

## 8. Quran integrity strategy

`Scripts/verify_quran` (added alongside the importer) asserts, at minimum:

- Exactly 114 surahs
- Exactly 6236 total ayahs
- Per-surah ayah counts match a canonical reference table
- `ayah_number` is contiguous from 1 with no gaps or duplicates within
  each surah; the global `id` is contiguous 1..6236
- `juz_number` and `page_number` are monotonically non-decreasing across
  the whole Quran and cover the full expected range (1–30 juz, 1–604
  pages)
- No empty/null text fields
- A recomputed content checksum (SHA-256 over canonically-sorted row data,
  not raw file bytes, so it's stable across SQLite vacuum/header
  differences) matches `Resources/Quran/CHECKSUM`
- If `Resources/Quran/MANIFEST.json` exists, its `dataset.*` fields
  cross-check against the same recomputed checksum, the 114/6236 counts,
  and a freshly computed SHA-256 of the actual `quran.sqlite` file bytes

The app performs the same checksum/row-count verification **at runtime on
launch**. If it fails, Ayah refuses to silently display unverified text
and surfaces a visible error instead of continuing. `SOURCE.md` records
the exact upstream export used and its date; `VERSION` is a single
content-version line; `CHECKSUM` is `sha256:<hex>`.

**`Resources/Quran/MANIFEST.json`** is a machine-readable provenance
record, additive alongside the three files above (nothing reads it at
runtime — it's a build/CI/documentation artifact, excluded from the app
bundle the same way `SOURCE.md`/`VERSION` are): the authority/narration/
script, the source archive's official MD5/SHA-1 (KFGQPC's own published
values) plus Ayah's own computed SHA-256, the importer's own version, and
the dataset's canonical content checksum plus the raw `quran.sqlite`
file-bytes SHA-256. It carries no timestamp field — every value is a
property of the source or the output, not of when the importer happened
to run, so the manifest stays reproducible across re-imports of the
identical source.

**Reproducibility, precisely scoped (two tiers, not conflated):**
"Source integrity" is the archive being byte-identified by KFGQPC's own
MD5/SHA-1 plus Ayah's SHA-256 — a property of the *download*.  "Semantic
Quran integrity" is `canonical_content_sha256` (the existing checksum
above), computed over sorted in-memory row data — reproducible given the
same CSV regardless of SQLite internals, and the guarantee actually
enforced by tests and CI. The raw `quran.sqlite` file-bytes SHA-256 is
recorded for convenience/runtime-corruption-detection but is not asserted
stable across SQLite library version changes. In practice, removing the
one identified non-determinism source (a `generated_at` timestamp
previously written into the database's own `meta` table) was verified
empirically to make `quran.sqlite` byte-for-byte reproducible run-to-run
against the same archive on the current toolchain — but that's an
observed property, not a tested/enforced invariant, since nothing here
depends on it holding forever.

**Tampering-detection tests** (`Packages/AyahKit/Tests/AyahKitTests/
QuranTamperingTests.swift`) prove the runtime check above actually rejects
corrupted data — a byte-tampered copy, a truncated file, and a
structurally-valid-but-wrong-size replacement all fail through the real
`QuranRepository.init`/`QuranIntegrityChecker.verify` code paths, never a
reimplemented check, and never against the real bundled file (always a
throwaway temp copy). A separate defense-in-depth test opens a copy with
the same `SQLITE_OPEN_READONLY` flag production uses and confirms a raw
`UPDATE` fails at the SQLite level, not just by app-logic convention.

**CI** (`.github/workflows/quran-integrity.yml`) runs `verify_quran` and
the full `swift test` suite on every push/PR, plus a provenance guard that
fails a PR which changes `quran.sqlite` without also updating `VERSION`/
`CHECKSUM`/`MANIFEST.json` together. It cannot prove a PR's claimed
official MD5/SHA-1 genuinely came from KFGQPC (that needs a human to check
the live page) and does not re-run the full import from the original
source on every run (would add an external network dependency to CI) —
both documented as trust-sensitive in `SECURITY.md`, not silently assumed
solved. The **Release build gate** (`project.yml`'s `preBuildScripts`,
gated on `$CONFIGURATION = Release` only, so Debug iteration is never
slowed) runs the same `verify_quran` + `swift test` pair before compiling
a Release build, failing the build outright on any Quran-integrity
failure. See `SECURITY.md`'s trust-model section for the full chain,
including how this relates to macOS code signing (a different, later
protection layer — see there for the distinction) and the deliberately
deferred future step of attesting the final distributable artifact.

## 9. Prayer time library

**[Adhan Swift](https://github.com/batoulapps/adhan-swift)** —
actively maintained (commits as recent as the day this research was
performed), MIT license, zero external dependencies, supports macOS
10.13+ (well below our 13 floor). Its `CalculationMethod` enum includes
`.ummAlQura` among many other methods (Muslim World League, Egyptian,
Karachi, Dubai, Moonsighting Committee, North America, Kuwait, Qatar,
Singapore, Tehran, Turkey, and others), so the calculation-method setting
can expose supported named presets, defaulting to Umm al-Qura. Adhan's
`.other` is deliberately excluded because it is a 0°/0° custom-parameter
template and Ayah does not expose custom-angle inputs.

**Update: `PrayerCalculator.prayerTimes(...)` now takes a required
`timeZone: TimeZone` parameter — a bug fix, not a new feature.** Adhan
Swift's own source (`PrayerTimes.swift`) interprets the `date:
DateComponents` it's handed through a UTC-based calendar internally, so
the caller must supply year/month/day as experienced *at the target
location*, not wherever the calling process happens to be. The original
implementation extracted those components via
`Calendar(identifier: .gregorian).dateComponents(...)`, whose implicit
timezone is `TimeZone.current` — the Mac's own system timezone — rather
than the selected city's (`City.timeZoneIdentifier`, already known via
`LocationRepository`, was never threaded through). Any user whose
system timezone differed from their selected prayer city — precisely
the diaspora/travel use case §12's bundled ~4,650-city dataset exists
for — could get prayer times, and prayer-alert firing times, computed
for the wrong calendar day, for several hours around either timezone's
midnight. The same implicit-system-TZ bug also affected §10's Ramadan
detection (`isRamadan`), fixed the same way. `PrayerCalculatorTests.swift`
gained a regression test that overrides `NSTimeZone.default` to a
far-away zone for its duration and confirms the result is unchanged —
confirmed to actually fail against the pre-fix implementation before
being folded into the passing suite, not just plausible-looking.
`PopoverContentView.todaysPrayerTimes` and `PrayerAlertScheduler`
(`resolveLocation()`/`armNextTimer()`) now resolve and pass the correct
zone (the selected city's, or the system IANA identifier cached alongside
a one-shot current-location fix; `TimeZone.current` is retained only as a
backward-compatible fallback for legacy settings).

## 10. Umm al-Qura implementation details

Umm al-Qura uses a Fajr angle of 18.5°, standard sunset-based Maghrib, and
a **fixed 90-minute Isha interval** after Maghrib. Adhan Swift implements
exactly this — but it has **no Hijri calendar awareness**, so it does not
know when Ramadan is and cannot apply the correct **120-minute** Isha
interval (90 + 30) that Umm al-Qura calls for during Ramadan. `PrayerCalculator`
must independently detect Ramadan (via `Calendar(identifier:
.islamicUmmAlQura)`) and apply a +30-minute adjustment to Isha through
Adhan Swift's `CalculationParameters.adjustments` API itself — this is not
optional or automatic in the library.

## 11. Asr calculation: Majority vs. Hanafi

Adhan Swift models this narrowly as a `Madhab` enum with two cases:
`.shafi` (shadow length = object length; the enum's own doc comment notes
this also covers Maliki, Hanbali, and Ja'fari views — i.e. the majority
position) and `.hanafi` (shadow length = 2× object length, giving a later
Asr time). Because this only ever affects the Asr calculation and nothing
else, **the app's UI must label this control specifically as "Asr
calculation"** (e.g. "Standard" vs. "Hanafi"), not as a whole-application
"Madhhab" setting — matching the actual scope of what it controls.
Default: Majority (Shafi'i/Maliki/Hanbali).

## 12. Offline location dataset

**[GeoNames](https://www.geonames.org)**, licensed CC BY 4.0 (attribution
required, redistribution explicitly permitted). Its city dumps include
name, lat/lon, country code, admin codes, population, and IANA timezone —
directly usable without further lookup. Ayah bundles a **filtered
subset** (Saudi Arabia and other Muslim-majority countries initially, not
the full world dump) targeting tens to low hundreds of KB, expandable
later. SimpleMaps' flagship "Basic" world-cities database is excluded — its
license prohibits redistribution. Adhan Swift itself ships no location
data; it purely accepts `Coordinates`, so location lookup is entirely
Ayah's own responsibility via `LocationRepository`.

Location Services are never required by default — coordinates come from a
manually selected city (or manually entered lat/lon), matching the privacy
priority. Location Services could be added later as an explicit, opt-in
convenience feature.

**Update: this opt-in convenience feature has since been built.**
`AppSettings.prayerLocationSource` (`.city` default, or `.currentLocation`)
picks between the bundled-city flow above and a one-shot
`CurrentLocationProvider` (`Prayer/CurrentLocationProvider.swift`) fetch
triggered only by an explicit tap of "استخدام الموقع الحالي" in the
Settings popover — never automatically, never on a recurring timer (§18's
no-continuous-background-work priority: this is a single `CLLocationManager
.requestLocation()` call per tap, not a live subscription). The fetched
coordinates are cached in `AppSettings.currentLocationCoordinates` /
`currentLocationFetchedAt` and `currentLocationTimeZoneIdentifier` and
reused until the user taps again; there is
no reverse-geocoding (no `CLGeocoder`, which is itself not offline), so a
current-location fix has no city name or reverse-geocoded timezone — the
system IANA identifier at fetch time is cached rather than looking one up.

**This is the one place in Ayah where "fully offline" needs a caveat, and
it must stay disclosed, not quietly glossed over.** Macs ship no GPS chip,
so `CLLocationManager` resolves position via nearby Wi-Fi access points
through macOS's own `locationd`, which can involve network traffic
initiated by the *system*, entirely outside Ayah's sandboxed process.
Ayah's own entitlements still never gain `network.client` (§16) — the
guarantee that Ayah's process itself cannot open an outbound connection is
unaffected — but the location *fix* it requests may not be fully offline
at the OS level. The Settings popover's current-location section carries
this disclosure in its own caption text; don't remove it when touching
that UI.

## 13. Prayer alerts (originally designed as OS notifications; superseded by an in-notch design — see below)

`UNUserNotificationCenter`, scheduled with `UNCalendarNotificationTrigger`
using explicit `DateComponents` (including an explicit `timeZone` when a
specific city's timezone must be honored) — **not**
`UNTimeIntervalNotificationTrigger`, because prayer times differ every
day and calendar-based triggers self-adjust correctly across DST within a
timezone, whereas interval-based triggers would drift.

Once scheduled, notifications are OS-owned and fire even if the Ayah
process isn't running. Because the system has historically capped pending
local notifications (around 64), and because prayer times must be
recomputed daily anyway, `PrayerNotificationScheduler` follows a single
`rescheduleToday()` pattern: cancel only Ayah's own previously-scheduled
requests, compute today's remaining and tomorrow's prayer times, and
schedule fresh notifications — never scheduling weeks ahead. This runs on:
app launch (safety net for sleep/restart/timezone changes that may have
happened while not running), a local-midnight rollover timer, and any
relevant settings change (calculation method, Asr method, city,
notification toggles).

**Update: this was built as described**, in `Packages/AyahKit/Sources/AyahKit/Notifications/PrayerNotificationScheduler.swift`.
`AppSettings.arePrayerNotificationsEnabled` (off by default — turning it
on is what triggered the `UNUserNotificationCenter` authorization prompt,
matching `prayerLocationSource`'s "explicit opt-in" precedent in §12) and
`AppSettings.prayerNotificationReminderMinutes` (0/5/10/15 in the Settings
UI; `0` means "at the exact prayer time") backed one notification per
prayer — Fajr, Dhuhr, Asr, Maghrib, Isha; sunrise excluded since it isn't
a prayer. `notificationRequests(for:coordinates:...)` was a pure,
synchronous, fully unit-tested function (the "what to schedule" half,
mirroring `VerseScheduler.selectNextVerses()`'s split from its timer
layer); `rescheduleToday()` was the thin `UNUserNotificationCenter` side
effect on top, untestable the same way `VerseScheduler`'s
`DispatchSourceTimer` firing is. All three of this section's triggers
were wired through a single mechanism: `PrayerNotificationScheduler.start()`
subscribed to `settingsStore.$settings`, whose `@Published` publisher
replays its current value to a brand-new subscriber — covering "app
launch" for free — and fired again on every later settings change; a
self-rearming `DispatchSourceTimer` (same style as `VerseScheduler`'s
display timer) covered the local-midnight rollover.

**Update: superseded — prayer alerts now render in the notch itself,
not as OS notifications.** `PrayerNotificationScheduler` and its tests
were deleted outright; `Packages/AyahKit/Sources/AyahKit/Scheduling/
{PrayerAlertEvent,PrayerAlertScheduler}.swift` replace them, colocated
with `VerseScheduler` as a peer scheduler rather than kept in a
`Notifications/` folder that no longer applies. This was a deliberate
product decision, not a bug fix, made while diagnosing why alerts
weren't firing: `UNUserNotificationCenter` permission for Ayah was Off
at the OS level, and separately, the actually-desired behavior turned
out to be a notch popup like the verse display, not a system banner —
so the fix was to stop depending on OS notification permission at all.

Because there is no OS handoff left to fire anything while Ayah isn't
running, `PrayerAlertScheduler` must self-time every individual
reminder/at-time moment rather than delegating to
`UNCalendarNotificationTrigger`: `armNextTimer()` computes today's and
tomorrow's reminder/at-time events fresh on every arm (via
`prayerAlertEvents(...)`, the same pure "what to show" split
`notificationRequests(...)` used, now returning a `PrayerAlertEvent`
rather than pre-baked notification text — no identifier or per-day
dedupe key is needed either, since nothing is registered with the OS to
dedupe against), takes the single soonest one across both days, and
arms exactly one `DispatchSourceTimer` for it; firing invokes the
callback and immediately rearms for the next event. There is no
dedicated midnight-rollover timer any more — recomputing fresh on every
arm naturally rolls into tomorrow once today's events are exhausted.
The one gap that leaves — an already-armed deadline silently passing
while the Mac is asleep — is covered by `NotchController` calling
`PrayerAlertScheduler.rearm()` on `NSWorkspace.didWakeNotification`,
not a periodic timer.

`AppSettings.arePrayerNotificationsEnabled`/`prayerNotificationReminderMinutes`
are reused unchanged (same toggle/picker in the Settings popover), but
turning the toggle on no longer triggers any OS permission prompt —
alerts are shown entirely in-process. Each fired alert (reminder and
at-time alike) carries the prayer name, a short Arabic message, and a
Quran ayah containing "الصلاة" that rotates every firing —
`QuranRepository.randomAyah(searchableTextContains:)` filters
`searchable_text` (never `uthmanic_text`, which can't substring-match a
plain-spelled word like this — see the Architecture section of
`CLAUDE.md` for why) and returns that row's `uthmanic_text` for display,
per this project's display-text rule. `PrayerAlertScheduler` resolves
the ayah at fire time and bundles it with the `PrayerAlertEvent` into a
`PrayerAlertDisplay` handed to its callback, matching the existing split
where schedulers own "what to show" and the view model just republishes.
`NotchViewModel` represents this alongside verse display through a
single `@Published content: NotchDisplayContent` enum (`.none`/
`.verses`/`.prayerAlert`) rather than a second parallel optional —
`VerseScheduler` and `PrayerAlertScheduler` are two independent timers
that can each fire while the notch is already expanded showing the
other's content, and the enum makes "exactly one active kind" true by
construction. Both card types share the same top safe-zone padding (see
§3) and 12-second auto-collapse.

Non-notch Macs get the same prayer alerts as notched ones — see §4's
floating-bar fallback, which starts `PrayerAlertScheduler` (and
`VerseScheduler`) exactly the same way the physical-notch path does. This
supersedes an earlier gap where `PrayerAlertScheduler` was only ever
started from the physical-notch path and so structurally never ran at all
without a notch. Location resolution still reuses
`prayerLocationSource`/`selectedCityID`/`currentLocationCoordinates`
directly (§12), the same way it backed the deleted scheduler and still
backs the Settings popover's live prayer-time preview.

## 14. Launch at login

**`SMAppService.mainApp`** (ServiceManagement framework, macOS 13+),
which replaces the deprecated `SMLoginItemSetEnabled`/`SMJobBless`
approach. It registers the login item directly from the main app bundle —
no separate helper app target is needed — and works the same whether or
not the app is sandboxed.

## 15. Persistence choices

| Data | Mechanism | Why |
|---|---|---|
| Quran text (`quran.sqlite`) | Read-only bundled SQLite | Immutable, large enough to want indexed lookup/search, never mutated |
| Location data (`cities_filtered.sqlite`) | Read-only bundled SQLite | Same reasoning, small |
| App settings | `UserDefaults` (Codable struct) | Handful of scalars, no relational shape, no migration ceremony needed |
| Last shown item | Dedicated `UserDefaults` key (versioned Codable record) | Exactly one compact record; Quran ayah IDs rather than duplicated Quran text |
| Memorization sets | Small local SQLite (`ayah_user.sqlite`) | Genuinely list-like, relational, user-editable over time |

SwiftData was considered and rejected for v1: it requires macOS 14+, above
the project's macOS 13 floor, for no benefit over a lightweight SQLite
table here.

## 16. App Sandbox & entitlements

App Sandbox is adopted as defense-in-depth, not only because it's required
for Mac App Store distribution. Current entitlements are base
`com.apple.security.app-sandbox`, and nothing else beyond what's strictly
needed — reading bundled resources requires no entitlement and local
`UserDefaults`/small SQLite user-data writes require no entitlement.
Prayer alerts are in-process UI and request no notification permission.
**`com.apple.security.network.client` is deliberately never requested.**
This omission is real, kernel-level (`sandboxd`) enforcement of "this
process cannot open an outbound connection" — not merely an App Review
policy check — which is what makes Ayah's "no network calls during normal
use" claim an architectural guarantee rather than a promise. Accessibility,
Screen Recording, Microphone, Camera, Contacts, and broad filesystem
access are never requested; none are needed for any v1 feature.

`com.apple.security.personal-information.location` **is** requested, as
of the "current location" prayer-time convenience feature (§12) — the one
addition beyond the base sandbox entitlement. It's opt-in at the UI level
(a city remains the default, per §12) and doesn't touch `network.client`
or any other entitlement; verify with `codesign -d --entitlements :-` on
the built app after touching anything here, same as before.

The 1.0.1 Release configuration is arm64-only and disables Xcode's base
entitlement injection. Release packaging requires an ad-hoc signature with
hardened runtime and exactly the sandbox/location entitlement pair; a
`get-task-allow` or network entitlement is a hard failure. Because there is
no Apple Developer account, users must approve the downloaded app through
macOS's per-app Open Anyway flow.

## 17. Network independence

Falls directly out of §16 plus dependency hygiene: no network entitlement,
zero networking code anywhere in the app's own logic, and a single
third-party dependency (Adhan Swift) that itself has zero dependencies and
performs no networking. No analytics, crash-reporting, or advertising SDK
is present anywhere in the project, by design.

## 18. Expected CPU / RAM / energy characteristics

- **Idle CPU target: ~0.1–1%.** Supported structurally by never running a continuous
  animation loop (see §3) and by using event-driven scheduling exclusively
  (see below) rather than any polling loop.
- **Scheduling**: a single self-rearming `DispatchSourceTimer`, armed only
  for the *next* verse display event — never a `while true { check() }`-
  style loop. Originally given roughly 10% tolerance/leeway per Apple's
  Energy Efficiency Guide (letting the system coalesce wakeups); switched
  to zero leeway once `displayInterval` became a user-chosen 15min-3hr
  preset (see "Settings UI" below) — at that cadence a single wakeup's
  coalescing benefit is negligible, while 10% drift is up to 18 minutes
  late on the 3-hour preset, which defeats the point of picking an exact
  interval. Prayer alerts (§13) follow the same one-timer-armed-for-the-
  next-event pattern, recomputed fresh on every arm rather than polled.
- **Memory**: dominated by the bundled SQLite files, expected to total a
  low tens-of-MB process footprint.
- **Disk writes**: limited to occasional `UserDefaults`/memorization-set
  changes when the user actually changes something — no continuous or
  periodic disk activity while idle.

**Measured release-candidate evidence (2026-08-23, Apple M4 MacBook Air,
16GB, macOS 26.5.2)** is recorded in
`docs/performance/2026-08-23-release-candidate-baseline-v1.md`. Three
Release XCTest runs established stable baselines for Quran/GeoNames
initialization, bilingual city search, prayer calculation, memorization,
and verse selection. A sanitized launch trace measured the internal
`LaunchInitialization` interval at 52.65ms and repository initialization
at 1.44–7.19ms. A 30-second Time Profiler trace recorded no running-thread
samples after 15 seconds, but that is not a substitute for the required
30-minute energy/wakeup run. A sanitized Allocations trace exists. On
2026-08-24, an isolated profiling build performed five warm-up cycles and
200 measured real-popover cycles; the canonical full run's settled RSS
changed from 120.40MiB to 103.58MiB (−16.82MiB), passing the provisional
5MiB trend guardrail. A separate 30-minute isolated idle run captured 180
samples: CPU median/p95 0.000%, mean 0.023%, memory 30→21MiB, and
power-impact median/p95 0.000. This is repeatable trend evidence, not an
independent proof of zero leaks or per-process wakeup attribution.

The verse timer therefore remains at zero leeway: the approved change
gate requires two comparable long idle traces attributing at least 10% of
Ayah's wakeups to that timer, and this measurement pass did not establish
that. Historical 2026-08-22 manual measurements (13.5MB steady-state /
16.2MB peak physical footprint, four threads) remain useful context but
were not silently promoted to current release-candidate results. The
repeatable workflow is documented in `docs/performance/README.md`.

## 19. Major implementation risks

In priority order:

1. **KFGQPC data licensing ambiguity** (§5/§6) — documented and knowingly
   accepted; revisit if KFGQPC ever publishes explicit terms, or objects.
2. **Notch geometry APIs are relatively new** (macOS 12+) and
   hardware-dependent — needs real-device testing across notched and
   non-notched Macs, and Macs driving only an external display.
3. **Bundled-data provenance anchors** remain reviewer-controlled files in
   the same source tree as their datasets. Checksums detect accidental or
   post-approval changes but do not independently attest upstream truth.
4. **In-process alert behavior across sleep/restart/clock/time-zone
   changes** needs continued real-hardware testing. The scheduler rearms on
   wake, settings changes, system clock changes, and time-zone changes.

## 20. Repository structure

See §2 above for the full tree. Top-level docs (this file, `README.md`,
`PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `LICENSE`,
`THIRD_PARTY_LICENSES.md`) and the implementation under `App/`, `Packages/`,
`Resources/`, and `Scripts/` all exist. `Ayah.xcodeproj` is regenerated
from `project.yml` with XcodeGen.

---

## Module responsibilities

Kept intentionally minimal — no speculative abstraction beyond what v1
needs.

- **`NotchController`** (App target, AppKit) — owns the `NotchPanel`
  (`NSPanel`) lifecycle, geometry, and expand/collapse state; when no
  physical notch is detected, attaches the same panel as a floating bar
  below the menu bar instead (see §4) rather than leaving verse
  display/prayer alerts unstarted — `StatusItemController` remains the
  app's one Settings surface either way.
- **`QuranRepository`** — opens `quran.sqlite` read-only; runs the
  integrity check once at init and surfaces failure as a visible error
  state rather than continuing silently; exposes `ayah(surah:ayah:)`,
  `ayah(id:)`, `randomAyah()`, `surahs()`.
- **`MemorizationRepository`** — CRUD over `memorization_sets`.
- **`VerseScheduler`** — a single self-rearming timer, armed only for the
  next event; on fire, weighted-selects a starting ayah (memorization sets
  vs. general pool, per the configurable percentage — default 70/30) and
  returns it plus up to `versesPerDisplay - 1` following consecutive
  ayahs within the same surah (or within the memorization set's own
  range), so a display never spills across a surah boundary. See
  "Verses per display" below.
- **`PrayerCalculator`** — wraps Adhan Swift, applies the Ramadan Isha
  adjustment (§10), and pairs with `LocationRepository` for the bundled
  city dataset.
- **`PrayerAlertScheduler`** — computes the next in-notch prayer event,
  arms one timer, and rearms after firing, wake, clock, time-zone, or
  relevant settings changes (§13).
- **`SettingsStore`** — the `AppSettings` Codable struct backing
  `UserDefaults`, publishing changes so other modules can react (e.g. a
  city or alert-setting change triggers scheduler rearming).
- **`LastShownStore`** — the separate, shared, observable source of truth
  for exactly one latest verse batch or prayer alert. It persists ordered
  ayah IDs, prayer timing fields, and the original display timestamp, never
  Quran text. `NotchDisplayContent.resolve` re-fetches those identifiers
  through `QuranRepository` for both the menu-bar card and popup replay;
  invalid references hide the card and make replay a no-op.

The Settings popover renders “آخر ما ظهر” above the existing settings when
that shared record resolves successfully. “إعادة العرض” closes the transient
popover and invokes `NotchViewModel`'s existing expand-and-12-second-collapse
path. On physical-notch Macs this expands the existing notch panel; in
fallback mode the existing `isExpanded` subscription shows the top-center
panel. Restoring a record at launch supplies collapsed content only: it never
auto-opens, and replay never rewrites the original `shownAt` timestamp. No
history beyond the single replacement record is retained.

### Verses per display

The notch display is not limited to exactly one ayah per appearance. A
**"verses per display"** setting (default **2**, adjustable e.g. 1–5) is a
first-class part of `AppSettings`, exposed in the Quran settings section
alongside "Enable verse display" and "Display interval." `VerseScheduler`
selects a starting ayah and shows it plus the next `versesPerDisplay - 1`
consecutive ayahs, clamped to the current surah (or the active
memorization set's range) rather than spilling into the next surah — if
fewer ayahs remain than requested, it simply shows what's left. The notch
layout and Arabic typography must accommodate multiple lines gracefully
rather than assuming a single short ayah.

## Weighted verse selection

`VerseScheduler` draws from the flattened pool of all `is_enabled`
memorization sets with probability `memorizationWeightPercent` (default
70%, user-configurable — the architecture treats this as data, not a
constant, so it can be tuned without a code change), honoring each set's
`repetition_mode` (`sequential` walks `cursor_ayah` forward;
`random` picks uniformly within the set's range). Otherwise it draws
uniformly from the full 6236-ayah general pool. No exclusion logic is
needed between the two pools for v1. The `memorization_sets` schema (§7)
already carries nullable `last_shown_at` / `ease_factor` /
`review_interval_days` columns so a future spaced-repetition mode can be
added by writing values to existing columns, not by an `ALTER TABLE`
migration.

---

## Phased build order

Following the project's own incremental-development instruction: build in
small, reviewable stages, never the whole application at once. Only the
next few stages are detailed; later ones are listed as headings to be
designed when reached.

- **Stage 1 — Repo scaffold + design docs.** *(This stage.)* All
  top-level docs with real content (this file and its siblings), no
  Xcode project or code yet.
- **Stage 2 — Minimal app shell.** Empty `Ayah.xcodeproj` (App target,
  `LSUIElement`, sandbox entitlement, no network client) + empty
  `AyahKit` package. `App/UI/Notch/*` with static placeholder text and
  spring expand/collapse; `App/UI/MenuBar/*` status-item + popover
  fallback. Exit criterion: the app builds, launches, shows a
  placeholder notch panel that expands/collapses via animation on a
  notched Mac and a working popover on a non-notched Mac, with idle CPU
  in the ~0.1–1% range over a short manual measurement window.
- **Stage 3 — Quran import pipeline.** `Scripts/import_quran`,
  `Scripts/verify_quran`, a committed `Resources/Quran/{quran.sqlite,
  SOURCE.md, VERSION, CHECKSUM, MANIFEST.json}`, the `QuranAyah`/`Surah`
  models, and integrity tests. Exit criterion: `verify_quran` exits 0 and
  `swift test` passes the 114-surah/6236-ayah/ordering/checksum
  assertions.
- **Stage 4 — QuranRepository wired into the notch UI.**
  `QuranRepository`, `QuranIntegrityChecker`, repository tests, and a
  minimal fixed-interval timer showing a real ayah (KFGQPC Uthmanic Hafs
  font) in the notch. Exit criterion: real Arabic text renders correctly
  in the notch on launch and refreshes on interval; no network
  entitlement present; repository tests pass.
- **Stage 5 — Memorization sets + weighted `VerseScheduler`.**
  `Persistence/SQLiteConnection` (a small read-write wrapper, distinct
  from `QuranRepository`'s read-only bundled-data access),
  `MemorizationRepository` (CRUD over `memorization_sets` in the local
  `ayah_user.sqlite`), a minimal `Settings` module (`AppSettings`/
  `SettingsStore`, scoped to just the Quran-display fields this stage
  needs — display interval, verses per display, memorization weight —
  not the Prayer/Notification/Theme settings later stages will add), and
  `VerseScheduler` itself (weighted selection per "Weighted verse
  selection" below, plus the self-rearming `DispatchSourceTimer` from
  §18). `NotchViewModel`/`NotchContentView` now show a batch of up to
  `versesPerDisplay` ayahs instead of always exactly one. Exit criterion:
  `VerseScheduler`'s selection logic (weighting, sequential cursor
  advance/wrap, random-mode range, surah/set-boundary clamping) is
  covered by fully deterministic unit tests (randomness injected, no
  timer sleeps); the notch visibly renders a multi-ayah batch end-to-end
  in a running build.

- **Stage 6 — Prayer time calculation.** `Scripts/import_geonames`, a
  committed `Resources/GeoNames/{cities_filtered.sqlite, SOURCE.md}`
  (GeoNames `cities1000` filtered to a documented Muslim-majority-country
  list, population ≥ 15,000 or a national capital), the
  `Coordinates`/`City`/`LocationRepository` models (mirroring
  `QuranRepository`'s raw-SQLite read-only pattern and verifying a bundled
  `GEONAMES_CHECKSUM`), and `PrayerCalculator` wrapping Adhan Swift with the Umm
  al-Qura Ramadan Isha adjustment (§10) applied via Hijri-calendar
  detection. Deliberately scoped to calculation only, matching this
  heading's own boundary from "Local notification scheduling" and
  "Settings UI" below — `PrayerCalculator` is a pure function taking
  method/madhab/coordinates as parameters rather than reading
  `AppSettings`, and nothing here is wired into notifications or any UI
  yet. Exit criterion: `PrayerCalculator`'s Ramadan-adjustment and
  Asr-madhab logic and `LocationRepository`'s bundled-data lookups are
  covered by unit tests; `swift test` passes.

**Local notification scheduling, Settings UI, launch-at-login, an
initial performance measurement pass, and a first security review have
all since been built/run** — see the "Prayer notifications", "Settings
UI", "Launch at login", "Performance measurement", and "First security
review" narrative sections of `CLAUDE.md`'s "Build order / current
stage"; §13 above for the notification architecture, §14 for
launch-at-login, §18 above (with its "Measured" addendum) for the
performance numbers, and `SECURITY.md`'s "Security posture (verified
2026-08-22)" section for the security review's findings and evidence.

**Later stages (headings only, to be detailed when reached):**
Themes (white / beige-Mushaf / black) · Developer ID/notarization if the
project later joins the Apple Developer Program.

## Continuous integration

**Quran-specific CI is implemented**: `.github/workflows/quran-integrity.yml`
(`runs-on: macos-14`), scoped exactly to the two items originally planned
here plus the full AyahKit suite:

- **quran-integrity**: builds and runs `Scripts/verify_quran` against the
  committed `Resources/Quran` (structural checks, checksum, and the
  `MANIFEST.json` cross-check — see §8), and runs `cd Packages/AyahKit &&
  swift test` (including the tampering-detection tests). Fails on any
  violation. Runs on every push/PR, not path-filtered — both are fast
  enough that there's no benefit to filtering, and a filter is itself a
  footgun.
- **quran-provenance-guard** (pull requests only): diffs
  `Resources/Quran/` against the PR's base branch; if `quran.sqlite`
  changed, asserts the diff also touches `VERSION`, `CHECKSUM`, and
  `MANIFEST.json` together, failing with an explicit message otherwise —
  making an unexplained Quran-data change hard to merge by accident. This
  cannot prove a claimed source hash is genuinely KFGQPC's (that needs a
  human reviewer checking the live page) and does not itself re-run the
  import from the original source — both documented as trust-sensitive in
  `SECURITY.md`, not silently assumed solved.

The same job now builds the Release app with automatic package resolution
disabled, using the reviewed workspace `Package.resolved`. Hosted CI still
requires an observed GitHub run before it can be claimed operational; the
repository files alone prove configuration, not remote execution.
