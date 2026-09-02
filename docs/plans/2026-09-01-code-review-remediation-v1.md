# Ayah — Code Review Remediation Plan (v1)

**Created**: 2026-09-01
**Source**: repository-wide review of the working tree at `d9ff06e` (Ayah 1.0.1),
covering `App/`, `Packages/AyahKit/`, `Scripts/`, `Resources/`, `project.yml`,
and CI. Baseline at time of review: 107 AyahKit tests passing, clean package
build, zero TODO/FIXME, zero force unwraps, zero `try!`/`as!`.
**Status**: complete. All six items landed 2026-09-01/02.

This plan fixes six findings. None is a shipped-correctness emergency: 1.0.1 is
sound. These are the places where the next silent bug is most likely to come
from, ordered so that the cheapest risk reduction happens early and the most
tedious work happens once, at the end, when its inputs have stopped moving.

## How to use this document

Work top to bottom. Each item is independent and separately shippable, so
stopping after any one of them leaves the repository in a better state than it
started, never a half-migrated one.

**Working convention while P1–P5 are in flight**: do *not* append a new
narrative paragraph to `CLAUDE.md` for each change, which is the convention the
file has used until now. Keep a short running note in this document's
"Completion log" instead. P6 folds everything into the restructured
documentation in one pass. Following the old convention during P1–P5 means
writing the same prose twice and makes P6 larger than it needs to be.

**After any new file under `App/`**: run `xcodegen generate`. XcodeGen
enumerates files at generate time, so a new `.swift` file is silently excluded
from the build with no error until the project is regenerated. P2 and P4 both
add files.

## Priority summary

| # | Item | Why it ranks here | Effort |
|---|---|---|---|
| P1 | Unify prayer-location resolution | Only correctness item. This exact duplication already produced one shipped wrong-day bug | 1–2 h |
| P2 | Collapse duplicated layout constants | Removes a hazard that already caused clipped UI once. Cheapest risk reduction in the plan | 20 min |
| P3 | Arabic launch alerts | User-visible defect at the worst possible moment, trivial fix | 15 min |
| P4 | App-layer tests for the notch state machine | Largest structural gap. Roughly 1,900 lines currently verified only by hand | 4–6 h |
| P5 | Arabic city names, plus the GeoNames importer checksum gap | Visible product wart for the primary audience. Includes a real re-import trap | 3–5 h |
| P6 | Documentation restructure | Largest maintenance win, but zero functional risk, and doing it last avoids rewriting it after every item above | 4–8 h |

---

## P1 — Unify prayer-location resolution

### Why

The rule "use the selected city's coordinates and IANA timezone, or the cached
one-shot coordinates and captured system timezone" is implemented twice:

- `PrayerAlertScheduler.resolveLocation()` in AyahKit, which decides when
  prayer alerts fire.
- `PopoverContentView.activeTimeZoneIdentifier` plus
  `PopoverContentView.todaysPrayerTimes` in the app target, which decides what
  prayer times the user is shown.

These must agree. When they disagree, the popover shows one set of times and
the notch fires alerts at another, which is the single most damaging failure
this app can have short of wrong Quran text.

This is not hypothetical. The wrong-day timezone bug found in the 2026-08-23
audit lived in this exact logic and had to be fixed in both places
independently. The duplication is currently defended in a code comment saying
it matches an earlier file's precedent. That is a description of how it
happened, not a reason to keep it.

`PopoverContentView` also duplicates the `PrayerCalculator.prayerTimes` call
itself once per location source, where the only difference between the two
branches is where `coordinates` comes from.

### How

1. **Add `Packages/AyahKit/Sources/AyahKit/Prayer/PrayerLocationResolver.swift`.**
   Introduce a named result type rather than returning a bare tuple:

   ```swift
   public struct ResolvedPrayerLocation: Equatable, Sendable {
       public let coordinates: Coordinates
       public let timeZone: TimeZone
   }

   public enum PrayerLocationResolver {
       public static func resolve(
           settings: AppSettings,
           locationRepository: LocationRepository?
       ) -> ResolvedPrayerLocation?
   }
   ```

   Take `AppSettings` by value, not `SettingsStore`. That keeps the function
   pure and testable with no Combine or persistence involved, matching how
   `VerseScheduler.selectNextVerses` and
   `PrayerAlertScheduler.prayerAlertEvents` are already split.

   The named struct is deliberate and solves a real problem. `PopoverContentView`
   imports both `Adhan` and `AyahKit`, so the bare name `Coordinates` is
   ambiguous there and cannot be module-qualified, because `AyahKit.swift`'s
   marker enum shadows the module name. A computed property in Swift requires an
   explicit type annotation, so returning a tuple would force that file to spell
   the ambiguous name and fail to compile. `ResolvedPrayerLocation` exists in
   only one module, so it is always spellable, and `.coordinates` is reached
   through it without ever naming the ambiguous type. This retires the workaround
   comment currently sitting above `todaysPrayerTimes`.

2. **Move the body of `PrayerAlertScheduler.resolveLocation()` into the
   resolver** unchanged, then delete the private method and call the resolver
   from `armNextTimer()`.

3. **Rewrite `PopoverContentView`** to hold one
   `private var resolvedLocation: ResolvedPrayerLocation?` computed from the
   resolver, and collapse `todaysPrayerTimes` from two near-identical switch
   branches into a single `PrayerCalculator.prayerTimes` call. Keep a display
   fallback of `TimeZone.current` for the time-formatting path only, so the
   prayer-times block renders nothing rather than the wrong thing when the
   location cannot be resolved.

4. **Add `PrayerLocationResolverTests.swift`** to AyahKit covering: city source
   with a valid city; city source with `selectedCityID` set to an id that is not
   in the database; city source with a city whose `timeZoneIdentifier` does not
   parse; current-location source with cached coordinates; current-location
   source with no cached coordinates; current-location source with a nil cached
   timezone identifier falling back to the system zone.

### Behaviour change to accept deliberately

Today `PopoverContentView` falls back to `TimeZone.current` when a selected
city has an unparseable identifier, while `PrayerAlertScheduler` returns nil and
schedules nothing. After unification the resolver returns nil in that case, so
the popover will show no prayer times instead of times computed in the Mac's
own timezone.

This is the correct direction. Showing nothing is a visible prompt to re-pick a
city. Showing times silently computed for the wrong location is indistinguishable
from correct output. Record this in the release notes for whatever version ships
it.

### Verify

- `cd Packages/AyahKit && swift test` passes, including the new tests.
- `xcodebuild -project Ayah.xcodeproj -scheme Ayah -destination 'platform=macOS' build` succeeds.
- Run the app, pick a city in a far-away timezone, and confirm the popover's
  five prayer times match what `PrayerAlertScheduler` would compute. The
  existing `PrayerCalculatorTests` regression test that overrides
  `NSTimeZone.default` still passes.

---

## P2 — Collapse duplicated layout constants

### Why

Two constants are each defined twice, in files that must agree but have no
mechanism forcing them to:

| Constant | Defined in | And in |
|---|---|---|
| Expanded notch size, 480 by 220 | `NotchController.expandedSize` | `NotchContentView.expandedSize` |
| Popover content size, 320 by 620 | `StatusItemController`, popover setup | `PopoverContentView`, `.frame` |

Both pairs are already documented in `CLAUDE.md` as manual-sync hazards, and
the popover pair has already caused a real defect: content clipped against the
smaller of the two values with no scroll indicator to reveal that anything was
missing. Divergence in the notch pair produces either a clipped verse card or a
transparent margin around it, and Arabic diacritics are exactly the kind of
tall glyph that gets silently cut.

Documenting a footgun is strictly weaker than deleting it. This is the highest
value per minute in the plan.

### How

1. **Add `App/UI/LayoutMetrics.swift`** with one enum per surface:

   ```swift
   enum NotchMetrics {
       static let expandedSize = CGSize(width: 480, height: 220)
   }

   enum PopoverMetrics {
       static let contentSize = CGSize(width: 320, height: 620)
   }
   ```

   One file rather than two, because the entire point is that there is one
   place to look. Add a comment stating that the notch card's top clearance
   must remain at least the live collapsed notch height, so a future height
   reduction does not silently reintroduce occlusion under the camera housing.

2. **Delete** the four literal definitions and point all call sites at the new
   constants. In `StatusItemController` that means
   `popover.contentSize = NSSize(width: PopoverMetrics.contentSize.width, height: PopoverMetrics.contentSize.height)`
   or storing the metric as an `NSSize` directly.

3. **Run `xcodegen generate`.** This is a new file under `App/`.

4. **Update `CLAUDE.md`'s Architecture section** to say these are now single
   constants, replacing the two "keep them in sync manually" warnings. Note this
   in the Completion log rather than as a new narrative paragraph; P6 will place
   it properly.

### Verify

- Debug build succeeds.
- Run the app, open the popover, confirm the general section and Quit button
  are still reachable without clipping.
- Trigger a verse display and confirm the expanded card is unchanged. On this
  dev Mac that is the fallback bar below the menu bar, since it has no physical
  notch.

---

## P3 — Arabic launch alerts

### Why

`AppDelegate` presents three startup failure alerts. Two are in English and one
is in Arabic:

| Failure | Current language |
|---|---|
| Quran data missing from bundle | English |
| Quran data failed integrity check | English |
| Memorization database unavailable | English |
| City data missing or unloadable | Arabic |

Every settings, memorization, city-picker, and notch surface in this app is
Arabic-only by an explicit project convention. These alerts are the first thing
a user sees when something has gone wrong, which is the worst moment to switch
languages on them. The city alert already shows the intended tone and wording.

**In scope**: the three English alerts in `AppDelegate` only.

**Explicitly not in scope**: `AboutView.englishSummary`. That block is
intentionally English and carries an explicit
`.environment(\.layoutDirection, .leftToRight)`. It is a source-attribution and
non-endorsement statement about KFGQPC, Adhan Swift, and GeoNames, which is
exactly the kind of text that should stay in the language its upstream terms
are written in. Leave it alone.

### How

1. Replace the three English title and message pairs in `AppDelegate`, matching
   the register of the existing city alert. Suggested wording, to be reviewed by
   a native speaker before committing:

   - Quran missing: title `آية: بيانات القرآن غير متوفرة`, message
     `لم يتم العثور على ملفات بيانات القرآن ضمن حزمة التطبيق.`
   - Quran integrity failure: same title, message
     `فشل التحقق من سلامة بيانات القرآن، ولن يتم عرض النص.` followed by the
     underlying error, as today.
   - Memorization: title `آية: بيانات الحفظ غير متوفرة`, message
     `تعذر تحميل بيانات الحفظ، وسيتم تعطيل عرض الآيات في هذه الجلسة.`

2. Change `presentErrorAlert`'s button title from `OK` to `موافق`.

3. Keep the interpolated `\(error)` on the two alerts that carry it. It is
   English and untranslatable, and it is the only diagnostic a user can paste
   into an issue.

### Verify

Temporarily rename `quran.sqlite` in a built app bundle, launch it, confirm the
Arabic critical alert appears, then restore the file. Repeat for
`cities_filtered.sqlite` to confirm the existing alert is unchanged.

---

## P4 — App-layer tests for the notch state machine

### Why

The App target is roughly 1,900 lines of AppKit and SwiftUI with no automated
test coverage at all. Every verification of it in this project's history has
been manual: screenshots, Accessibility inspection, AppleScript driving. That
process is genuinely rigorous and has caught real bugs, including the
`.onTapGesture` row-selection failure. It is also unrepeatable, so nothing
catches a regression on the next change.

The evidence that this already constrains design is `LazySingleton`, which was
pushed down into AyahKit specifically so its reuse logic could be tested, with a
doc comment stating that `App/` has no test target of its own.

`NotchViewModel` is the type that most deserves coverage. It is not really UI
code, it is a state machine, and it holds three interacting pieces of state
where the failure modes are silent:

- `shouldSkipInitialScheduledVerses`, which suppresses exactly one scheduler
  emission at launch so a restored last-shown card survives. Off by one in
  either direction either discards the restored card or permanently swallows a
  real verse display.
- `autoCollapseTask`, a cancellable 12-second task. If a manual tap fails to
  cancel it, the notch collapses under the user mid-read.
- The `isVerseDisplayEnabled` sink, which must clear verse content but must not
  disturb an in-progress prayer alert.

None of this touches AppKit meaningfully. Its only framework dependencies are
`NSWorkspace.accessibilityDisplayShouldReduceMotion` and SwiftUI's
`withAnimation`, both of which work fine inside a test process.

### How

1. **Make the auto-collapse delay injectable.** `NotchViewModel.autoCollapseDelay`
   is currently a `private static let` of 12 seconds. Move it to an init
   parameter defaulting to `.seconds(12)` and store it as an instance property.
   Without this, every auto-collapse test costs 12 seconds of wall clock. Pass
   the default from `NotchController`; no behaviour changes.

2. **Add a unit-test target to `project.yml`:**

   ```yaml
     AyahTests:
       type: bundle.unit-test
       platform: macOS
       deploymentTarget: "13.0"
       sources:
         - path: Tests/App
       dependencies:
         - target: Ayah
       settings:
         base:
           SWIFT_VERSION: "6.0"
   ```

   Then `xcodegen generate`. Note that this suite runs under
   `xcodebuild test -project Ayah.xcodeproj -scheme Ayah -destination 'platform=macOS'`,
   not `swift test`. AyahKit's suite stays where it is. This adds a second test
   command to the project rather than replacing the first.

3. **Write `Tests/App/NotchViewModelTests.swift`** covering, at minimum:

   - Launch restoration populates `content` from a saved record without setting
     `isExpanded`.
   - With a restored record, the first scheduler emission is ignored and the
     second is displayed.
   - With no restored record, the first emission is displayed.
   - Showing verses writes a record to `LastShownStore` holding only ayah ids.
   - The notch collapses after the injected delay elapses.
   - `toggleExpanded` during the auto-collapse window cancels it, and the notch
     is still expanded after the original delay would have passed.
   - Disabling verse display while verses are showing clears content and
     collapses.
   - Disabling verse display while a prayer alert is showing leaves the alert
     content and expansion untouched.
   - `replayLastShown` re-resolves content without mutating the stored
     `shownAt`.

   Construct the view model with `quranRepository: nil` where the test does not
   need real ayahs, and inject `SettingsStore(defaults:)` and
   `LastShownStore(defaults:)` backed by a scratch `UserDefaults(suiteName:)`,
   copying the pattern already in `SettingsStoreTests`. Both stores already take
   an injectable `UserDefaults`, so no production change is needed for this.

4. **Add the new suite to CI** in `.github/workflows/quran-integrity.yml`. A
   Release `xcodebuild` step already runs there, so add a `test` action against
   the Debug configuration next to it.

### Verify

`xcodebuild test` passes locally and in CI. Confirm each new test genuinely
fails against the pre-change behaviour before trusting it, by temporarily
inverting the assertion or disabling the guard it covers. That is the standard
this repository already set when adding the timezone regression test and the
Quran tampering tests, and a test that has never been seen to fail is not yet
evidence of anything.

---

## P5 — Arabic city names, and the GeoNames importer checksum gap

### Why

`City.displayName` falls back to GeoNames' primary Latin field when no
Arabic-tagged alternate name exists. Overall that is about a third of the
bundled dataset, which sounds worse than it is, because coverage is concentrated
in the largest cities. The gap is much narrower but far more visible where this
app's primary audience actually lives:

| Scope | Cities carrying an Arabic name |
|---|---|
| All bundled cities | 1,529 of 4,654 |
| Top 100 by population | 85 of 100 |
| Arabic-speaking countries | 915 of 1,329 |
| Saudi Arabia | 72 of 98 |

The result is a city list that is mostly Arabic with Latin transliterations
scattered through it, carrying diacritics that appear nowhere else in the
interface. Sultanah, with a population near 950,000, and Unaizah, near 183,000,
both render as Latin text inside an otherwise fully Arabic, right-to-left list.

Missing entries in Arabic-speaking countries, by country:

| Country | Missing | Country | Missing |
|---|---|---|---|
| Morocco | 138 | Libya | 14 |
| Tunisia | 71 | Mauritania | 10 |
| Sudan | 42 | Iraq | 8 |
| Egypt | 41 | Palestine | 5 |
| UAE | 27 | Oman | 4 |
| Saudi Arabia | 26 | Jordan | 2 |
| Somalia | 23 | Lebanon, Qatar, Yemen | 1 each |

### The trap that must be fixed first

`Scripts/import_geonames` does **not** write `Resources/GeoNames/GEONAMES_CHECKSUM`.
Nothing does. It is a plain `sha256:<hex>` of the database file bytes that was
produced by hand, and `LocationRepository.verifyFileChecksum` fails closed
against it at every launch.

This means re-running the GeoNames importer today produces a database that the
app refuses to load, surfacing as the Arabic "city data unavailable" warning,
until someone remembers to regenerate the checksum manually. This is an
asymmetry with `Scripts/import_quran`, which writes `VERSION`, `CHECKSUM`,
`SOURCE.md`, and `MANIFEST.json` together as a matched set.

Fix this before doing the data work, not after.

### How

1. **Teach `import_geonames` to emit `GEONAMES_CHECKSUM`.** After
   `SQLiteWriter` finishes, compute `SHA256` over the written database's bytes
   and write `sha256:<hex>` to `GEONAMES_CHECKSUM` in the output directory,
   alongside the `SOURCE.md` it already writes. Match `import_quran`'s existing
   format exactly, since `LocationRepository` parses it.

2. **Add a curated Arabic-name override table** as
   `Scripts/import_geonames/Sources/import_geonames/ArabicNameOverrides.swift`,
   a `[Int: String]` keyed by GeoNames id. Merge it over the loaded dump at the
   single existing lookup site in `main.swift`, where `nameArabic:` is currently
   assigned from `arabicNames[geonameID]`, so an override always wins:

   ```swift
   nameArabic: ArabicNameOverrides.table[geonameID] ?? arabicNames[geonameID],
   ```

   Put the table in the importer, not in AyahKit. The generated database stays
   the one source of truth for display names, `City.displayName` keeps its
   single fallback rule, and `Resources/GeoNames/` is never hand-edited, which
   is an existing project rule.

3. **Scope the table honestly.** Only add names for cities that genuinely have
   an Arabic name. Do not invent Arabic transliterations for Indonesian,
   Nigerian, Pakistani, or Turkish cities that have no Arabic exonym; leaving
   those in Latin is correct, not a gap. Note that the same reasoning applies to
   the existing documented Dari and Pashto mistagging for Afghan cities.

   Suggested staging by audience proximity:

   - **Phase A**, about 75 entries: Saudi Arabia, UAE, Qatar, Oman, Kuwait,
     Bahrain, Iraq, Jordan, Lebanon, Palestine, Yemen. Appendix A below is a
     starting draft for the 26 Saudi entries.
   - **Phase B**, 41 entries: Egypt.
   - **Phase C**, about 298 entries: Morocco, Tunisia, Libya, Sudan,
     Mauritania, Somalia. Largest and lowest urgency.

   Phase A alone closes the gap a Gulf user will actually notice.

4. **Re-run the importer.** This requires re-downloading both GeoNames dumps,
   `cities1000.zip` and `alternateNamesV2.zip`, and re-running the `awk`
   pre-filter for Arabic-tagged rows. The exact commands are in `CLAUDE.md`.
   Budget for the roughly 778 MB alternate-names download. The importer is the
   only supported way to regenerate this data.

5. **Verify the regenerated database is otherwise unchanged.** City count should
   stay at 4,654, and every `name_arabic` that was previously populated should
   still hold the same value. Only nulls should have become non-null. Confirm
   with a query against a copy of the old database before replacing it.

6. **Update `Resources/GeoNames/SOURCE.md`** to state that a curated override
   table supplements the dump, and record the resulting coverage figure.

### Verify

- `LocationRepository` loads the regenerated database at launch with no warning
  alert, proving step 1 worked.
- `LocationRepositoryTests` still pass, including the existing checksum test.
- Open the city picker and confirm the previously Latin entries now render in
  Arabic and sort sensibly in a right-to-left list.

---

## P6 — Documentation restructure

### Why

Documentation now outweighs source, and it is the most likely origin of the next
inconsistency in this project.

| Artifact | Size |
|---|---|
| All Markdown | 231,852 bytes |
| `CLAUDE.md` | 67,217 bytes |
| `ARCHITECTURE.md` | 52,622 bytes |
| Swift source, all targets | 6,089 lines |

`CLAUDE.md` alone is larger than the entire App layer's source. Its "Build order
/ current stage" section is a chronological build narrative made of 43
bold-led paragraphs, most describing decisions that later work superseded. The
file already carries its own corrections, including passages noting that an
earlier note is now stale and has been removed.

The problem is structural, not stylistic. A narrative organised by *when*
something was done cannot be updated in place when the thing changes; it can
only be appended to. So every change obliges an author to either grow the file
or leave a stale claim behind, and both have already happened.

Do this last. Every item above changes something `CLAUDE.md` describes. Doing
the restructure first means writing the final state twice.

### How

1. **Split by purpose, not chronology.**

   - `CLAUDE.md` becomes current state and invariants only. Target under
     15,000 bytes. It should answer: what this project is, what the layout is,
     what commands to run, and which rules must not be broken. Keep every hard
     rule already in the Architecture section, because those are load-bearing:
     the `xcodegen generate` requirement, `buildPhase: resources`, the
     `Info.plist` bundle-identifier crash, the `List` and `.onTapGesture`
     failure, the `AyahKit` marker-enum shadowing, isolated conformances, the
     `.onAppear` timing hazard, `City.displayName`, and the deliberate
     triplication of the Quran checksum algorithm. These are the parts that save
     real debugging time.
   - `docs/history/BUILD_LOG.md` receives the stage narrative, verbatim, in
     date order. It stops being maintained; it is a record.
   - `ARCHITECTURE.md` keeps design rationale but drops the running
     supersession commentary. Where a decision was reversed, state the current
     decision and one line on what it replaced, not the full argument of both.
     Section 13 currently carries its own reversal in its heading and should be
     rewritten to describe the in-notch design directly.

2. **Establish the update rule** at the top of `CLAUDE.md`: describe what is
   true now. If a change makes a sentence wrong, edit that sentence. Do not
   append a paragraph explaining that the earlier sentence used to be right.
   Append-only history belongs in git and in the build log.

3. **Sweep for stale claims** while splitting. The 2026-08-22 security review
   found `PRIVACY.md` had drifted out of sync with two shipped features, and one
   of its claims had never been true. Re-check `PRIVACY.md`, `SECURITY.md`, and
   `README.md` against the code as it stands after P1 through P5, particularly
   anything describing entitlements, settings storage, or location behaviour.

4. **Fold the P1 to P5 changes in** from the Completion log below, in their
   correct sections rather than as new dated paragraphs.

### Verify

`CLAUDE.md` fits in a single reading. Every rule in its Architecture section
still names a symbol or file that exists; grep each one. `THIRD_PARTY_LICENSES.md`
and the KFGQPC text-licensing risk statement must survive the edit unchanged,
since that is a deliberate accepted risk and not documentation debt.

---

## Appendix A — Saudi Arabic-name override draft

A starting point for P5 Phase A, covering all 26 Saudi cities currently lacking
an Arabic name, ordered by population. GeoNames ids are from the bundled
database.

**These are drafted from transliteration and must be reviewed by a native
speaker before committing.** Several are ambiguous:
`King Faisal Military City` is a compound name that may be better left in
Latin or given an official Arabic form; `Sulţānah` is a district of Medina
rather than an independent city and its correct display name should be
confirmed.

| GeoNames id | Current | Draft Arabic | Population |
|---|---|---|---|
| 101760 | Sulţānah | سلطانة | 946,697 |
| 101732 | Unaizah | عنيزة | 183,319 |
| 110325 | Ad Dawādimī | الدوادمي | 86,861 |
| 103369 | Qal‘at Bīshah | بيشة | 81,828 |
| 12495725 | Bariq | بارق | 75,351 |
| 103035 | Rābigh | رابغ | 72,928 |
| 109253 | Al Līth | الليث | 72,000 |
| 101313 | Ţurayf | طريف | 66,014 |
| 104828 | King Faisal Military City | مدينة الملك فيصل العسكرية | 65,000 |
| 109380 | Al Khafjī | الخفجي | 54,857 |
| 102985 | Raḩīmah | رحيمة | 41,188 |
| 101516 | Taymā’ | تيماء | 37,579 |
| 13631408 | Ḥawṭah Banī Tamīm | حوطة بني تميم | 30,720 |
| 104716 | Laylá | ليلى | 29,698 |
| 109306 | Al Khurmah | الخرمة | 28,491 |
| 107744 | Badr Ḩunayn | بدر حنين | 27,257 |
| 409682 | Thuwal | ثول | 26,957 |
| 102451 | Şāmitah | صامطة | 26,945 |
| 106102 | Ḩaql | حقل | 25,649 |
| 108048 | As Sulayyil | السليل | 24,097 |
| 101322 | Turabah | تربة | 23,235 |
| 104578 | Mahd adh Dhahab | مهد الذهب | 20,272 |
| 104923 | Khulayş | خليص | 20,139 |
| 110059 | Al ‘Aqīq | العقيق | 19,269 |
| 109915 | Al Baţţālīyah | البطالية | 16,606 |
| 109059 | Al Munayzilah | المنيزلة | 16,296 |

To regenerate this list against the current database:

```sh
sqlite3 -separator ' | ' Resources/GeoNames/cities_filtered.sqlite \
  "select geoname_id, name, population from cities
   where country_code='SA' and name_arabic is null
   order by population desc;"
```

---

## Appendix B — Reviewed and deliberately not changing

Recorded so a future pass does not spend time re-deriving these, or "fix" a
decision that was made on purpose.

- **The English attribution block in `AboutView`.** Intentional, with an
  explicit left-to-right layout environment. Source attribution and
  non-endorsement language stays in English.
- **arm64-only Release builds.** Documented in `ARCHITECTURE.md`, `README.md`,
  and both sets of release notes. It does mean the non-notch fallback bar,
  which exists to serve Macs without a notch, cannot reach Intel Macs at all,
  so its real audience is Apple Silicon machines without a notch: MacBook Air
  M1, Mac mini, Mac Studio, and the 24-inch iMac. That is still a real
  audience. Note the interaction; do not treat it as a defect.
- **The Quran checksum algorithm existing in three independent copies**, across
  `import_quran`, `verify_quran`, and `QuranIntegrityTests`. Deliberate
  belt-and-suspenders for integrity-critical data. Do not consolidate it.
- **The KFGQPC Quran text redistribution risk.** An explicit, re-confirmed
  product decision recorded in `THIRD_PARTY_LICENSES.md`. Not documentation
  debt, and not to be resolved by quietly swapping the data source.
- **Running the full AyahKit suite as a Release pre-build script.** Slow and
  unconventional, and it couples building to testing. It is also the gate that
  makes it impossible to ship a Release binary against unverified Quran data,
  which is this project's stated first priority. Keep it.
- **`MemorizationSet.RepetitionMode.random` not being offered in the editor.**
  Deliberate. It is exercised by tests but shuffling away the order a user is
  memorizing in is not a useful option to expose.

---

## Completion log

Record each item as it lands, in one or two lines. P6 folds these into the
permanent documentation and this section is then deleted along with the rest of
this plan's working state.

- [x] **P1 — Unify prayer-location resolution** (2026-09-01). Added
  `Prayer/PrayerLocationResolver.swift` (`ResolvedPrayerLocation` +
  `PrayerLocationResolver.resolve`). `PrayerAlertScheduler.resolveLocation()`
  deleted, `armNextTimer()` calls the resolver.
  `PopoverContentView.activeTimeZoneIdentifier` deleted; `todaysPrayerTimes`
  collapsed from two switch branches to one `PrayerCalculator.prayerTimes`
  call taking a `ResolvedPrayerLocation`, and `prayerRow`/`formattedTime` now
  take a `TimeZone` instead of an identifier string. The resolver has a second
  internal `city:` overload (`@autoclosure`, so the repository's linear city
  scan stays behind the `.city` branch as before) — it is the seam the
  unparseable-timezone test needs, since `LocationRepository` rejects an
  invalid identifier at load and no real repository can produce such a city.
  Also retired the ambiguous-`Coordinates` workaround comment above
  `todaysPrayerTimes`, and corrected the two doc sentences that pointed at it
  or at the now-deleted `resolveLocation()` (`CLAUDE.md`'s marker-enum rule,
  `ARCHITECTURE.md` §9's "Update").
  **Verified**: 11 new `PrayerLocationResolverTests`; 118 AyahKit tests pass
  (107 baseline + 11). Two of the new tests were confirmed to genuinely fail
  first — weakening the city branch to `TimeZone(identifier:) ?? .current`
  fails `testCitySourceReturnsNilWhenTheCityTimeZoneDoesNotParse` with the
  exact wrong-zone symptom, and letting `.city` fall through to a cached fix
  fails `testCitySourceIgnoresCachedCurrentLocationCoordinates`. Debug
  `xcodebuild` succeeds. Ran the built app with Jakarta (`Asia/Jakarta`,
  UTC+7) selected on a Mac set to `Asia/Riyadh` (UTC+3): the popover's six
  rows read 4:41 ص / 5:53 ص / 11:52 ص / 3:11 م / 5:52 م / 7:22 م, matching the
  scheduler's own resolver+calculator path exactly. Re-checked the
  unresolvable case (bogus `selectedCityID`): the popover renders
  "اختر مدينة لعرض أوقات الصلاة" and no times. Test settings were written to
  the app container's prefs and restored from a backup afterwards.
  **For the next release notes**: a selected city whose stored IANA identifier
  no longer parses now shows no prayer times instead of times computed in the
  Mac's own timezone. There is no unreleased notes file yet, so this is
  recorded here for whoever opens one.
- [x] **P2 — Collapse duplicated layout constants** (2026-09-01). Added
  `App/UI/LayoutMetrics.swift` with `NotchMetrics.expandedSize` (480×220) and
  `PopoverMetrics.contentSize` (320×620), and deleted the four literals in
  `NotchController`, `NotchContentView`, `StatusItemController`, and
  `PopoverContentView`. Values unchanged — this moves where they are defined,
  not what they are. Ran `xcodegen generate` (new file under `App/`;
  `LayoutMetrics.swift` confirmed present in `project.pbxproj`). Replaced
  `CLAUDE.md`'s two "keep them in sync manually" warnings with a rule pointing
  at the new file; the notch top-clearance constraint the plan asked to record
  is stated both there and in `NotchMetrics`' own doc comment.
  **Verified**: Debug `xcodebuild` succeeds. Ran the built app: the expanded
  card measured 480×220 via Accessibility and rendered a full ayah
  (يس 59-60) with the reference line and top clearance intact, nothing
  clipped. The popover measured 346×646 outer — identical to the pre-change
  measurement — with both footer buttons ("حول التطبيق" / "إغلاق آية")
  reachable, and scrolling to the bottom showed the "عام" section and its
  launch-at-login toggle fully visible.
  **Left alone deliberately**: `AboutWindowController`'s 480×520 vs
  `AboutView`'s `minWidth: 480, minHeight: 520` is a third pair, but it is a
  *minimum* against a resizable window, so a divergence degrades gracefully
  instead of clipping. Not the hazard this item is about; not in the plan's
  scope.
- [x] **P3 — Arabic launch alerts** (2026-09-01). The three English
  `AppDelegate` alerts (Quran missing from bundle, Quran integrity failure,
  memorization database unavailable) now use the plan's suggested Arabic
  wording, and `presentErrorAlert`'s button is `موافق` rather than `OK`. The
  interpolated `\(error)` is kept on the two alerts that carry it. The city
  alert and `AboutView.englishSummary` are untouched.
  **Verified** against real bundles, not by reading the diff — each failure was
  actually induced and the resulting alert read back through Accessibility:
  removing `quran.sqlite` produced the critical alert
  "آية: بيانات القرآن غير متوفرة / لم يتم العثور على ملفات بيانات القرآن ضمن
  حزمة التطبيق." (screenshotted; renders right-aligned with a موافق button);
  flipping one byte of `quran.sqlite` produced the integrity alert still
  carrying `checksumMismatch`; replacing the container's `ayah_user.sqlite`
  with a directory produced the memorization alert still carrying
  `cannotOpenDatabase("unable to open database file")`; removing
  `cities_filtered.sqlite` produced the existing city alert with its title and
  message unchanged. All three bundle tests ran against a re-signed copy in a
  scratch directory, so the real build product was never modified — its
  signature and resources were re-checked afterwards. The memorization test
  touched the real container DB; it was backed up first and restored to a
  byte-identical SHA-256. A clean launch afterwards shows no alert.
  **Note**: the Arabic wording is the plan's own draft. The plan asks for a
  native-speaker review before committing — that review has not happened.
- [ ] P4 — App-layer tests for the notch state machine
- [ ] P5 — Arabic city names and importer checksum
- [ ] P6 — Documentation restructure
- [x] **P4 — App-layer tests for the notch state machine** (2026-09-01).
  `NotchViewModel.autoCollapseDelay` moved from a `private static let` to
  an init parameter defaulting to `.seconds(12)`; `NotchController` was
  left alone, since the default already gives it the production value and
  threading a constant through it would add a parameter no caller varies.
  New `AyahTests` target in `project.yml` (`Tests/App`, hosted in the Ayah
  app), plus an explicit `scheme:` on the `Ayah` target so a *shared*
  scheme carrying the test action is generated — `xcodebuild`'s
  autocreated user scheme is not committed and cannot be relied on to
  notice a new bundle in CI. `Tests/App/NotchViewModelTests.swift` covers
  all nine cases the plan listed, and CI gained an `xcodebuild test`
  (Debug) step next to the existing Release build.
  **Two things the plan did not anticipate, both load-bearing**: (1) the
  package dependency on the test target is declared `link: false` —
  AyahKit builds as a static library, so linking it into the test bundle
  as well as the host would give the two modules separate, mutually
  incompatible copies of every AyahKit type, and `@testable import Ayah`
  would then be handing `NotchViewModel.init` the wrong `SettingsStore`.
  (2) An app-hosted bundle is injected into a *real* `Ayah` process, so
  `AppDelegate.applicationDidFinishLaunching` now stands down under XCTest
  (`XCTestConfigurationFilePath`); without that the app would open its
  panel, start both schedulers against their real repositories, and write
  a last-shown record into the user's real preferences underneath the
  suite. `Tests/App/AppLaunchGuardTests.swift` is the one extra test that
  keeps that guard honest, asserting no `NotchPanel` exists during a run.
  Also corrected three now-false doc claims: `CLAUDE.md`'s "there is no
  `xcodebuild test` action wired up for the App scheme" (replaced with the
  real command), `LazySingleton`'s "`App/` has no test target of its own",
  and `ARCHITECTURE.md` §2 / "Continuous integration" (which additionally
  still said `runs-on: macos-14` where the workflow says `macos-15`).
  **Verified**: 10 App tests and 118 AyahKit tests pass; Debug and Release
  `xcodebuild` both succeed. Every one of the 10 tests was confirmed to
  genuinely fail first, via 12 separate one-at-a-time mutations of the
  code each covers — restoration not populating `content`; restoration
  expanding the notch; the launch emission never skipped; the launch
  emission always skipped; recorded ids not matching the displayed ayahs;
  no auto-collapse armed; a manual tap not cancelling the pending
  auto-collapse; the disable path leaving stale verses; the disable path
  also clearing a prayer alert; replay not expanding; replay restamping
  the record; and the `AppDelegate` guard removed. All 12 failed as
  expected and the file was restored byte-identical after each.
  Entitlements re-checked unchanged (Debug: `app-sandbox`,
  `get-task-allow`, `personal-information.location`; Release: the first
  and third), and both a Debug and a Release `build` were confirmed to
  produce an `Ayah.app` with no `Contents/PlugIns` — the test bundle is
  embedded only by `build-for-testing`, never shipped.
  **Not verified here**: the CI step has not been observed running on a
  hosted runner. It launches a GUI app process, which GitHub's macOS
  runners support, but per this repository's existing note on CI, files
  alone prove configuration, not remote execution.
- [x] **P5 — Arabic city names, and the GeoNames importer checksum gap**
  (2026-09-01). **The trap first.** `import_geonames` now computes SHA-256
  over the database it just wrote and emits `GEONAMES_CHECKSUM` in
  `import_quran`'s exact `sha256:<hex>` shape, and writes the matching
  "Bundled SQLite SHA-256" line into `SOURCE.md` (that line existed in the
  committed file but nothing generated it — it was hand-added). Also
  removed the `generated_at` timestamp from the database's own `meta`
  table, keeping it in `SOURCE.md` only: a checksum over a file containing
  a per-run timestamp can detect corruption but can never be reproduced,
  and `import_quran` had already made exactly this change for the same
  reason. Not in the plan's letter, but it is what makes the checksum
  worth having. `override_name_count` replaces it in `meta`.
  **The data.** New
  `Scripts/import_geonames/Sources/import_geonames/ArabicNameOverrides.swift`,
  merged at the single lookup site as the plan specified, plus a loud
  stderr warning (not a hard failure) naming any override id that matched
  no bundled city, since a curated table rots silently otherwise.
  **Verified**, and the plan's step-5 expectation needed correcting.
  Re-downloading the dumps gave a 2026-09-01 `cities1000`, not the
  2026-08-21 one the committed data came from, so the row count is
  **4,659, not the 4,654 the plan predicted**. The diff is otherwise
  exactly what step 5 asked for and was checked field by field against the
  old committed database: five cities added (Bagrām AF, Abu Gharaq IQ,
  Yoff SN, Kojomkul KG, Bağlar Mahallesi TR), none removed, zero changes
  to any existing row's name, country, timezone, coordinates, or
  population, and zero previously-populated `name_arabic` values changed
  or lost. Arabic coverage 1,529 → 1,893 of 4,659 (33% → 41%). The
  importer is now deterministic: three separate runs over the same input
  produced byte-identical databases (`b5a910b7…`), and the emitted
  checksum matches the shipped file. The trap itself was demonstrated
  through the real runtime path before being called fixed — a temporary
  test paired the freshly imported database with the previously committed
  checksum and confirmed `LocationRepository` throws `checksumMismatch`,
  then confirmed the importer-written one is accepted; the temporary test
  was removed afterwards. No new permanent test was added, because
  `testInitSucceedsAgainstBundledData` already passes both paths and so
  already fails if the committed pair ever drifts.
  118 AyahKit tests and 10 App tests pass; Debug and Release builds
  succeed; Release entitlements unchanged. Ran the built app: no "city
  data unavailable" alert (which is what proves the emitted checksum
  works end to end), and the city picker was driven through Accessibility
  to confirm previously-Latin rows now render Arabic, right-aligned, with
  the country code on the left — "Unaizah" → عنيزة, "Berrechid" → برشيد,
  "Wad Medani" → ود مدني.
  **Scope call that differs from the plan, deliberately.** The plan staged
  75 + 41 + 298 = 414 entries. The table ships **364 of 415** (415, not
  414, because the fresher dump added one Iraqi city to the gap). The
  other 51 were left in Latin on purpose. The plan assumed these could be
  drafted from transliteration and reviewed later; the deciding fact is
  that the full 19M-row `alternateNamesV2` dump carries an Arabic-script
  alternate for only **6** of the 415, so 358 entries are authored, not
  sourced. Where the standard Arabic form is unambiguous that is fine.
  Where it is not — Somali endonyms with no Arabic exonym (23, the whole
  country omitted under the plan's own "do not invent transliterations"
  rule), Amazigh toponyms whose Arabic-script spelling varies (11
  Moroccan), and 17 others across Mauritania, Tunisia, Iraq, Libya and
  Sudan — omitting is correct: a Latin name reads as missing data, a wrong
  Arabic name reads as fact. `ArabicNameOverrides.swift`'s doc comment
  records the count, the per-country omissions, and which six entries are
  attested upstream.
  **Still owed, and stated in the file itself**: a native-speaker review of
  the authored entries, most of all the Phase C ones where transliterating
  back from French-derived Latin is least certain. This is the one part of
  `Resources/GeoNames/` not mechanically derived from upstream data.
  **Incidental finding, not fixed here**: the picker's Latin search is
  diacritic-sensitive, so typing "Sultanah" does not match GeoNames'
  "Sulţānah". Unrelated to this item, and the Arabic names make it less
  reachable rather than worse.
  **Docs**: `SOURCE.md`'s Arabic-names bullet now splits dump-sourced from
  override-sourced counts (changed in the generator, so it survives future
  runs). Corrected stale figures in `CLAUDE.md` (Stage 6's "4,654 cities,
  ~376 KB" and two "~33%" claims, all now pointing at `SOURCE.md` instead
  of duplicating numbers that move on every import) and documented the
  importer's checksum/determinism guarantees next to its command.
  `ARCHITECTURE.md` §12 now records that the database has sat just past
  its "tens to low hundreds of KB" target since the Arabic-name column was
  added (~410 KB; this pass added ~4 KB), rather than leaving a target the
  artifact quietly misses. `LocationRepositoryPerformanceTests`' hardcoded
  4,654 row count is now 4,659 with a comment saying it tracks `SOURCE.md`
  and is meant to move on a re-import. The dated files under
  `docs/audits/` and `docs/performance/` still say 4,654 and were left
  alone on purpose — they are records of what was true when they were
  written.
- [x] **P6 — Documentation restructure** (2026-09-02). `CLAUDE.md` went from
  69,287 to ~18,800 bytes and is now current-state only: purpose, layout,
  commands, the rules that must not be broken, the deliberate decisions not
  to "fix", and the verification standard. The update rule sits at the top.
  The 43-paragraph build narrative moved verbatim to
  `docs/history/BUILD_LOG.md`, which states in its own header that it is a
  frozen record and that `CLAUDE.md`/`ARCHITECTURE.md`/the code win on any
  conflict. **It did not hit the plan's 15,000-byte target**, and that was a
  deliberate choice: the remaining excess is the rules section (~8 KB), which
  the plan separately said to keep in full because those are the parts that
  save real debugging time. Trimming to the number would have meant cutting
  the justifications that make the rules stick. It does fit in a single
  reading.
  `ARCHITECTURE.md` lost its running supersession commentary. §13's heading
  no longer announces its own reversal and the section now describes the
  in-notch design directly, including the fact that its two settings are
  still *named* for the deleted `UNUserNotificationCenter` design because
  renaming them is a settings schema migration — a live gotcha that the old
  "Update: superseded" framing buried. §9's "Update:" block became a direct
  statement of the timezone rule plus the single-resolver rule; §12's
  "Update: this has since been built" became a plain description; §4 lost
  two "before this…" clauses. `PrayerLocationResolver` was added to "Module
  responsibilities", and the post-Stage-6 summary no longer points at
  `CLAUDE.md` sections that no longer exist.
  **Stale claims found in the sweep**, all now fixed: `README.md` still said
  "1.0.1 release candidate" (it is approved and tagged) and described
  non-notch Macs as getting only a popover fallback — false since the
  floating-bar work, and it undersold a shipped feature. `SECURITY.md`'s
  posture section was dated 2026-08-30 and predated P1–P5; it now records
  the 2026-09-01 re-verification and says explicitly that none of those
  changes altered the posture. Its two "Correction/Updated" blocks became
  current statements — the location-key one keeps the lesson (check the
  API's documented requirement, not the code's intent) without the
  blow-by-blow. The GeoNames bullet now says where `GEONAMES_CHECKSUM` comes
  from, which is the part that changed in P5. `PRIVACY.md` needed one fix:
  its preference list omitted `prayerLocationSource` and called the alert
  settings "prayer-notification". `CONTRIBUTING.md` gained the
  GeoNames-is-generated rule and the see-a-test-fail-first rule, and now
  points at `CLAUDE.md` for current state.
  **Verified**: every symbol and file named in `CLAUDE.md`'s rules section
  was grepped — 86 resolve, and the 9 that do not are OS and tooling
  concepts (`NSOutlineView`, `PBXFileReference`, `SIGTRAP`,
  `SQLITE_CANTOPEN`, `libsecinit_appsandbox`, `Contents/Resources/`) plus
  three my grep script mangled and that were then confirmed by hand
  (`App/UI/LayoutMetrics.swift`, `LayoutMetrics`, `project.yml`). No broken
  file reference anywhere in `CLAUDE.md`. `THIRD_PARTY_LICENSES.md` is
  byte-for-byte unchanged and the KFGQPC text-licensing risk statement
  survives intact. 118 AyahKit tests and 10 App tests pass; Release build
  succeeds.
  **One deviation from the plan, stated rather than done quietly**: this
  Completion log was *not* deleted. The plan called it transient working
  state, but the entries carry the verification evidence for P1–P5, and a
  dated document under `docs/plans/` is no more maintained than the ones
  under `docs/audits/` — deleting it would destroy the record without
  reducing any maintenance burden. The durable rules from all six items are
  folded into the permanent docs regardless, which was the actual point.
