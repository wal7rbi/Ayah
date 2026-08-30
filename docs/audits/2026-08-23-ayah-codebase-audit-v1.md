# Ayah full-workspace codebase audit v1

Date: 2026-08-23  
Repository: `/Users/waleedalharbai/myproject/Ayah`  
Baseline revision: `873d3f87e635db083d09e2bd31d8daeaa0ce2c49` (`main`)  
Scope: exact tracked, modified, and non-ignored untracked workspace; generated build caches excluded

## Executive conclusion

Ayah has a deliberately small attack surface: it is a native macOS 13+
application with no backend, account, WebView, analytics, telemetry, crash
reporter, application networking API, or outbound-network entitlement. No
critical or high-severity vulnerability was found. The audit did confirm two
medium-integrity risks, multiple low-severity correctness/reliability defects,
and documentation/release-compliance drift.

Safe fixes in this pass make bundled Quran and city SQLite reads fail closed,
require the Quran manifest, checksum and validate GeoNames data, validate local
settings and memorization rows, prevent unsolicited Core Location access,
bound/cancel location requests, exclude Adhan's unconfigured zero-angle
`other` method, preserve the time zone captured with current location, rearm
prayer alerts on clock/time-zone changes, surface UI write failures, harden CI,
bind Xcode to the reviewed SwiftPM resolution, add third-party notices, improve
notch accessibility/reduced-motion behavior, and correct the six requested
documentation files.

Residual risk is explicit. Repository-local checksums do not independently
authenticate KFGQPC or GeoNames; the manual Quran importer still needs resource
bounds; cached precise coordinates remain plaintext local state; final
Developer-ID signing/notarization, hosted CI policy, hardware UI/VoiceOver,
and long-run interactive energy exercises were not available in this session.
Post-fix Debug/Release builds and an ad-hoc signed-bundle inspection did
complete in an approved local execution context. The independent Deep Scan is
also formally **partial**, not evidence
that the repository is vulnerability-free.

## Workspace preservation and fingerprint

The initial workspace was `main` at `873d3f8`, with 92 tracked files, 12
modified tracked files, and four non-ignored untracked files. All original 16
dirty paths were preserved and reviewed as current source; no stash, reset,
checkout, clean, index mutation, bulk formatter, commit, or push was used.

- Original binary patch:
  `/private/tmp/ayah-audit-20260823.Zo6VO8/original-workspace.patch`
- Original untracked archive:
  `/private/tmp/ayah-audit-20260823.Zo6VO8/original-untracked-files.tgz`
- Baseline: `git diff --check` clean; 70 AyahKit tests passed; all three
  script packages built; Quran verifier passed; isolated Debug and Release
  application builds passed.
- Tools: Xcode 26.3, Swift 6.2.4, SQLite 3.51.0, OpenCodeReview 1.8.8,
  XcodeGen present; target floor macOS 13.

New changes were applied narrowly on top of that state. The Xcode project was
regenerated from `project.yml` only to enumerate the new resources; its diff is
limited to those resource references.

## Method and coverage

1. Fingerprinted Git state, hashes, resources, package resolution, build tools,
   entitlements, plist, Xcode configuration, workflow, and binary baseline.
2. Read every repository source/config/test/document path. Binary Quran,
   GeoNames, and font resources received SQLite/hash/manifest/license
   dispositions rather than source-code review.
3. Ran a whole-repository Codex Security Deep Scan and reconciled its nine
   validated findings with independent source tracing. The scan stopped after
   three later discovery workers hit the environment usage limit, so canonical
   coverage is `partial`.
4. Ran OpenCodeReview delegation selection/rule resolution before and after
   changes. Its final preview selected 31 code-reviewable paths out of 44
   changed/untracked paths (2,367 insertions/306 deletions, including the audit);
   unsupported Markdown, Xcode, lock, and checksum files were manually read.
5. Applied vibe-security checks only to relevant surfaces: secrets, local
   SQLite/UserDefaults, entitlements/signing, build tools, workflow/actions,
   dependencies, and bundled data. Backend auth, payments, browser-client
   trust, AI endpoints, remote rate limiting, CORS, and hosted databases are
   not applicable.
6. Reproduced or established a complete source-to-sink path before fixing.
   Community reports were treated as UX evidence or investigation leads, not
   proof of defects.

Coverage dispositions:

| Surface | Disposition |
|---|---|
| `App/**/*.swift` | Read and final Swift 6 whole-app type-check passed against freshly built AyahKit/Adhan modules. UI/runtime-only behaviors separately limited below. |
| `Packages/AyahKit/Sources/**/*.swift` | Read, Deep Scan/OCR/manual reviewed, built and exercised by 98 tests. |
| `Packages/AyahKit/Tests/**/*.swift` | Read; original and new tests executed. |
| `Scripts/**` | Every manifest/source read; all three executables compiled; verifier executed positive and negative fixtures. Both offline profiling scripts passed syntax/input checks, and the opt-in UI-cycle workflow completed against an isolated Release product. Importers were not run against large upstream archives. |
| Workflow, entitlements, plist, `project.yml`, pbxproj, workspace lock | Read; plist lint, lock comparison, XcodeGen regeneration, action/permission review. Hosted settings/run unavailable. |
| Top-level Markdown/license files | Read manually; six requested drift files and third-party packaging records corrected. |
| Quran SQLite/checksum/manifest | `integrity_check`, 114/6,236 structure, canonical checksum, file hash, manifest, read-only/tamper tests. External authenticity remains deferred. |
| GeoNames SQLite/source/checksum | `integrity_check`, 4,654 rows, SHA-256, runtime checksum, type/range/IANA-zone tests. External authenticity remains deferred. |
| Font | SHA-256 and documented embedded EULA disposition; visual shaping not re-exercised. |
| `.git`, `.build`, `.swiftpm`, DerivedData, assistant/session state | Excluded generated/metadata state except read-only Git fingerprint/history and build products used for verification. |

## Architecture and threat model

### Assets

- Exact approved Quran text and provenance.
- Prayer-time coordinates, time zones, calculation method, dates, previews,
  and alerts.
- Cached precise location, settings, and memorization data.
- App availability and low CPU/wakeup/memory behavior.
- Sandbox, signing, dependency, CI, importer, bundle, and release integrity.
- Required third-party attribution and the accuracy of public privacy/security
  claims.

### Trust boundaries

```text
KFGQPC archive -> importer -> quran.sqlite/manifest/checksum
              -> verifier/CI/release gate -> runtime repository -> Arabic UI

GeoNames dumps -> importer -> cities sqlite/checksum
               -> runtime validation -> city/time zone -> Adhan calculation

UI / UserDefaults / user SQLite -> validation -> scheduler and SwiftUI
Core Location callbacks -> pending explicit request -> cached fix + time zone
clock / time-zone / wake events -> timer invalidation -> next prayer alert
dependency / GitHub Action -> build graph -> signed application bundle
```

### Realistic attacker and failure capabilities

- A contributor, compromised publisher/action/dependency, preparation machine,
  or upstream dataset can influence build inputs later accepted for release.
- Same-user local state or an unsigned/ad-hoc app bundle can be malformed or
  replaced; disk/SQLite errors and incompatible old settings can occur without
  an attacker.
- Authorization callbacks, cancellation, denial, sleep/wake, clock changes,
  travel/time-zone changes, and unavailable high-latitude solar events can
  occur in normal operation.
- No anonymous remote client, server database, payment system, account,
  telemetry receiver, or app-network exfiltration channel is assumed because
  those surfaces do not exist.

### Security objectives

Fail closed and visibly on unapproved/malformed sacred text or prayer inputs;
collect precise location only for a pending user action; preserve offline and
sandbox boundaries; prevent malformed local state from causing traps or
silently unsafe schedules; resolve build inputs from reviewed immutable
references; and keep documentation no stronger than the evidence.

## Findings and disposition

Severity describes realistic impact in this offline local architecture, not a
generic internet-service score. Line references are post-fix anchors unless
marked baseline.

### AYAH-001 — Quran integrity lacks an independent authenticity anchor

| Field | Value |
|---|---|
| Severity / confidence | Medium / high |
| CWE | CWE-345 (insufficient verification of data authenticity) |
| Affected | `Scripts/import_quran/.../ArchiveExtractor.swift`, `Scripts/import_quran/.../main.swift`, `Resources/Quran/{CHECKSUM,MANIFEST.json}`, workflow, runtime repository |
| Expected / observed | Expected automated gates to distinguish an approved KFGQPC artifact from coordinated replacement. Observed every automated expected value is mutable beside the text; baseline verifier also allowed a missing manifest. |
| Preconditions / reachability | A malicious/compromised contributor or preparation source must get altered, structurally valid data and matching metadata accepted into a build. Normal same-user preference input cannot reach this path. |
| Impact / root cause | Altered Quran text could pass self-consistency gates. Integrity and authenticity were conflated; official digests are operator-supplied and the trust root is not independently protected. |
| Strongest counterevidence | Current SQLite is healthy, 114/6,236 and contiguous; canonical/file hashes match; importer checks official MD5/SHA-1; tampering tests reject uncoordinated changes; signed bundles seal resources. |
| Reproduction / evidence | Static archive-to-renderer trace plus canonical Deep Scan finding 1. Missing-manifest fixture previously succeeded; it now exits 1. |
| Remediation / regression | `verify_quran` now requires `MANIFEST.json`; CI requires it and gates Release. Add protected CODEOWNERS/two-person review and an authenticated offline KFGQPC digest/source snapshot or signed project trust-root record. Negative missing-manifest validation added at CLI level. |
| Final status | **Partially fixed / deferred trust anchor.** Safe local enforcement applied; independent governance/source authentication needs policy and external coordination. |

### AYAH-002 — GeoNames data lacked fail-closed integrity and provenance

| Field | Value |
|---|---|
| Severity / confidence | Medium / high |
| CWE | CWE-345 and CWE-20 |
| Affected | `LocationRepository.swift:40,77-174`, `AppDelegate.swift:119`, `Resources/GeoNames/GEONAMES_CHECKSUM` |
| Expected / observed | Expected corrupt/substituted coordinates/time zones to be rejected. Baseline trusted the bundled file, coerced numeric values, accepted invalid coordinates/zones, and treated terminal SQLite errors as end-of-data. |
| Preconditions / reachability | Modified/ad-hoc bundle, compromised import/release input, or corruption before a city is selected/calculated. |
| Impact / root cause | Wrong prayer day/time or loss of city functionality. No checksum and incomplete SQLite/semantic result validation. |
| Strongest counterevidence | Baseline database passed integrity, had 4,654 rows, expected country set, valid tested Riyadh data, and was sealed by the baseline signature. No runtime network/updater can replace it. |
| Reproduction / evidence | Wrong checksum and out-of-range coordinate/invalid-zone fixtures now throw; SQLite integrity/hash checks pass. |
| Remediation / regression | Added required SHA-256 bundle resource, runtime verification, exact column-type/nonempty/range/population/country/IANA validation, terminal-step errors, initializer cleanup, and tests. |
| Final status | **Partially fixed.** Runtime integrity/validation fixed; checksum remains repository-coordinated rather than an independent GeoNames authenticity proof. |

### AYAH-003 — malformed Quran SQLite text could trap and row errors looked complete

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-476, CWE-252 |
| Affected | `QuranRepository.swift:136-220`, verifier `SQLiteReader.swift:39-101` |
| Expected / observed | Corrupt `NULL`/wrong-type required text or `sqlite3_step` error should throw. Baseline force-created `String(cString:)` and stopped loops on every non-row result. |
| Preconditions / reachability | Corrupt/replaced bundle or verifier input; normal immutable signed bundle is counterevidence. |
| Impact / root cause | Process trap, partial dataset mistaken for normal completion, or availability loss before the visible integrity alert. Raw SQLite pointer/result assumptions. |
| Strongest counterevidence | Schema uses `NOT NULL`, runtime opens read-only, checksum/count usually detects ordinary tampering. SQLite corruption can violate those assumptions before the checksum runs. |
| Reproduction / evidence | Temporary database with `surahs.name_arabic = NULL` throws `.corruptedColumn` without a crash; full tests pass. |
| Remediation / regression | Required TEXT helpers, explicit `ROW`/`DONE`/error switches, and post-open initializer handle cleanup in runtime and verifier. |
| Final status | **Fixed.** |

### AYAH-004 — GitHub Action used a mutable tag and implicit token posture

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-829 |
| Affected | `.github/workflows/quran-integrity.yml:23-48` |
| Expected / observed | Third-party actions immutable and token permissions least privilege. Baseline used `actions/checkout@v4`, default credential persistence, no explicit permissions or timeout. |
| Preconditions / reachability | Compromised action tag/publisher or over-broad repository defaults during hosted CI. |
| Impact / root cause | Build/repository token exposure or altered verification. Convenience defaults were trusted. |
| Strongest counterevidence | Checkout is first-party GitHub-maintained; this workflow does not intentionally publish artifacts/secrets. |
| Reproduction / evidence | Static workflow trace and official GitHub guidance. |
| Remediation / regression | Added `contents: read`, `persist-credentials: false`, 20-minute timeout, full SHA `34e114...f8d5` with `v4.3.1` comment, and locked Release build. |
| Final status | **Fixed locally; hosted run/org policy unverified.** |

### AYAH-005 — authorization callbacks could request location without pending intent

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-285 |
| Affected | `CurrentLocationProvider.swift:74-143` |
| Expected / observed | Core Location access only after an explicit pending button action. Baseline authorization callback called `requestLocation()` whenever authorized, including manager-initialization callbacks. |
| Preconditions / reachability | Already-authorized app and unsolicited authorization callback. Returned coordinates were discarded, limiting confidentiality impact. |
| Impact / root cause | Privacy/consent timing violation and unnecessary system location work. Authorization capability was treated as current user intent. |
| Strongest counterevidence | One-shot API, disclosed opt-in UI, no network/exfiltration sink, and no continuation meant the update was not persisted. |
| Reproduction / evidence | Fake manager callback with no pending request now confirms zero `requestLocation` calls. |
| Remediation / regression | Pending continuation and one-start guard; cancellation, timeout, denial/restriction/failure, repeated callback, invalid coordinates, and concurrent-request tests. |
| Final status | **Fixed.** |

### AYAH-006 — Quran archive/CSV importer has unbounded resource use

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-400 |
| Affected | `Scripts/import_quran/.../ArchiveExtractor.swift`, `CSVParser.swift`, `main.swift` |
| Expected / observed | Manual import should bound archive/extracted size, rows, field length, and subprocess duration. It reads whole archive/CSV and can wait without explicit caps. |
| Preconditions / reachability | A developer deliberately runs the offline importer on a hostile/misidentified archive. It is not shipped runtime code and has no automatic download path. |
| Impact / root cause | Developer/CI memory, disk, or time exhaustion. Whole-input parsing favored simplicity. |
| Strongest counterevidence | Hash checks precede normal approved imports; fixed `/usr/bin/unzip` argument array prevents shell injection; runtime users cannot invoke it. |
| Reproduction / evidence | Static source trace; no oversized hostile archive executed to avoid resource damage. |
| Remediation / regression | Add archive compressed/uncompressed caps, streaming CSV with exact 6,236-row early cutoff, per-field byte limits, subprocess timeout, and oversized/truncated fixtures. |
| Final status | **Deferred.** A safe streaming rewrite and fixtures are larger than the backward-compatible runtime-fix boundary. |

### AYAH-007 — semantically invalid memorization state could crash or corrupt scheduling

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-20 |
| Affected | `MemorizationRepository.swift:34-92,195-350`, editor view |
| Expected / observed | Ranges/cursor/types/dates must match canonical surah bounds before Swift ranges/UI/scheduler use. Baseline checked ordering only and SQLite coercion could hide wrong types; cursor writes did not verify the selected set. |
| Preconditions / reachability | Corrupt/hand-edited same-user SQLite, restored malformed data, or erroneous internal caller. |
| Impact / root cause | Swift closed-range trap, impossible memorization display, repeat loop, or silent state corruption. Persistence was trusted semantically. |
| Strongest counterevidence | Current UI steppers generate valid values; SQLite schema constrains nullability; sandbox/local-only storage narrows attacker reach. |
| Reproduction / evidence | Surah 1 ayah 8, wrong SQLite type, invalid persisted range/cursor, overflow, and missing-ID fixtures. |
| Remediation / regression | Canonical 1...114 counts, exact integer/text decoding, valid modes/dates/options, finite factors, cursor-within-stored-range, and tests before/alongside fixes. UI writes now surface failure and retain the editor on failed save. |
| Final status | **Fixed.** |

### AYAH-008 — Xcode app graph was not bound to reviewed SwiftPM resolution

| Field | Value |
|---|---|
| Severity / confidence | Low / medium |
| CWE | CWE-1104 |
| Affected | Xcode workspace `Package.resolved`, workflow Release build |
| Expected / observed | App and package tests use the same reviewed Adhan 1.5.0 revision. Only the nested AyahKit lock existed; SwiftPM documents that a library's nested lock is not authoritative for a consuming graph. |
| Preconditions / reachability | Fresh Xcode/CI resolution while a compatible newer/malicious version is available. |
| Impact / root cause | Untested dependency code in app artifact. Distinct resolver graph lacked a workspace lock. |
| Strongest counterevidence | Manifest minimum was 1.5.0 and existing local/test lock pinned commit `a6fa2d...`; only one zero-dependency package exists. |
| Reproduction / evidence | Static resolver/config trace; the two committed lockfiles now compare byte-identical. |
| Remediation / regression | Added workspace lock and `-disableAutomaticPackageResolution` Release CI build. Network/cache refresh was not authorized, so the already-reviewed lock remained unchanged. |
| Final status | **Fixed in configuration; fresh hosted resolution/build still requires CI evidence.** |

### AYAH-009 — prayer alert timer was stale after clock/time-zone changes

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-682 |
| Affected | `PrayerAlertScheduler.swift:38-160` |
| Expected / observed | Recompute on wake, settings, clock, and time-zone changes. Baseline handled wake/settings/firing but an already-armed deadline remained based on the old wall-clock/zone. |
| Preconditions / reachability | User/system adjusts clock or zone while app is awake with alerts enabled. |
| Impact / root cause | Early, late, or missed prayer alert. Timer invalidation did not subscribe to relevant Foundation notifications. |
| Strongest counterevidence | Prayer calculations themselves use explicit target zones; launch/wake/settings already rearmed; no persisted OS notification remained stale. |
| Reproduction / evidence | Injected notification center test observes exactly one generation advance per clock/zone event and none after stop. |
| Remediation / regression | Added clock/time-zone subscriptions, cancellable lifecycle, schedule generation guard against stale handlers, and defensive reminder clamp. |
| Final status | **Fixed; real sleep/clock hardware exercise remains.** |

### AYAH-010 — Adhan `other` exposed zero-angle calculations as a valid method

| Field | Value |
|---|---|
| Severity / confidence | Medium correctness / high |
| CWE | CWE-20 (configuration validation) |
| Affected | `PrayerCalculator.swift:17-49`, `PopoverContentView.swift:113`, `AppSettings.swift:141` |
| Expected / observed | Every visible preset produces documented prayer parameters. Adhan defines `other` as 0°/0°, intended only as a template when callers supply custom angles; Ayah supplied none. |
| Preconditions / reachability | User selected “Other” or old/malformed settings decoded it. |
| Impact / root cause | Materially incorrect Fajr/Isha/prayer alerts presented without warning. Library enum was exposed wholesale without matching custom fields. |
| Strongest counterevidence | Default is Umm al-Qura; other named methods are configured by Adhan; user had to choose the problematic option. |
| Reproduction / evidence | Official Adhan method source/docs and regression asserting `other` is excluded/rejected. |
| Remediation / regression | Central supported-method list excludes it; calculator returns nil defensively; decoded `other` normalizes to Umm al-Qura. |
| Final status | **Fixed.** |

### AYAH-011 — persisted settings accepted unsafe numeric and semantic values

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-20 |
| Affected | `AppSettings.swift:130-159`, `SettingsStore.swift:25-43` |
| Expected / observed | Corrupt/incompatible UserDefaults should default only invalid fields and make top-level load failure observable. Baseline accepted negative/huge intervals, counts, weights, reminders, coordinates, city IDs, and zones; malformed JSON silently looked like first launch. |
| Preconditions / reachability | Same-user preferences modification, old schema, corruption, or erroneous internal mutation. |
| Impact / root cause | Tight timer loops, excessive work, wrong prayer input, or silent preference loss. Tolerant decode lacked semantic bounds/diagnostics. |
| Strongest counterevidence | Current UI controls constrain ordinary input; no remote settings channel exists. |
| Reproduction / evidence | Raw invalid JSON fixture now defaults each invalid field; non-JSON records `lastLoadError`. |
| Remediation / regression | Finite/bounded interval, 1...5 verses, 0...100 weight, positive city, coordinate/IANA validation, 0...180 reminder, `other` normalization, observable load error. |
| Final status | **Fixed.** |

### AYAH-012 — cached current location was later reinterpreted in a new system zone

| Field | Value |
|---|---|
| Severity / confidence | Low correctness/privacy / high |
| CWE | CWE-682 |
| Affected | `CurrentLocationViewModel.swift:30-34`, settings, popover, scheduler |
| Expected / observed | Cached coordinates retain the local calendar-zone context used when captured. Baseline always used the Mac's current zone, so travel could reinterpret an old coordinate fix. |
| Preconditions / reachability | Current-location mode, cached fix, user travels/changes system zone without refreshing. |
| Impact / root cause | Wrong prayer calendar day/times/alerts. Coordinates were stored without their temporal context. |
| Strongest counterevidence | UI displays fetch time and user can manually refresh; selected-city flow always has IANA zone. |
| Reproduction / evidence | Source trace of stored fields and both consumers. Existing explicit-zone calculator test protects the downstream rule. |
| Remediation / regression | Added additive optional settings key for fetch-time IANA zone, used by preview/scheduler with legacy fallback only. |
| Final status | **Fixed compatibly.** |

### AYAH-013 — cached precise coordinates are not independently encrypted

| Field | Value |
|---|---|
| Severity / confidence | Low hardening / medium |
| CWE | CWE-312 |
| Affected | `AppSettings.currentLocationCoordinates`, `SettingsStore`, `PRIVACY.md` |
| Expected / observed | Apple recommends protecting stored location appropriately. Coordinates/time/fetch zone are Codable data in UserDefaults and persist until replaced; memorization is plaintext SQLite. |
| Preconditions / reachability | Malicious process/person already operating as the same macOS user, backup exposure, or disk access outside Ayah's process sandbox. |
| Impact / root cause | Disclosure of a precise prior location and religious-use preferences. Simple local persistence was selected without an encryption/retention control. |
| Strongest counterevidence | No network/exfiltration sink, one-shot opt-in collection, FileVault and user-account protections may apply, app sandbox contains Ayah, no account/cloud copy. |
| Reproduction / evidence | Static encode/storage trace. No attempt was made to read a real user's stored coordinates. |
| Remediation / regression | Offer “forget current location,” retention policy, reduced precision where acceptable, and Keychain/encrypted blob with migration and failure UX. |
| Final status | **Deferred** because an encryption/retention migration changes persisted-data behavior. Privacy documentation now states the limitation. |

### AYAH-014 — UI persistence failures were swallowed

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-390 |
| Affected | `MemorizationSetsView.swift:26,72-213` |
| Expected / observed | Failed create/update/delete remains visible and save sheet closes only on success. Baseline used `try?`, closed the editor, and reloaded as if successful. |
| Preconditions / reachability | Locked/corrupt DB, disk/full permission error, or newly enforced validation error. |
| Impact / root cause | Silent user-data loss/reversion and inaccessible validation feedback. Throwing repository errors were discarded. |
| Strongest counterevidence | Normal sandbox Application Support writes generally succeed; repository errors were already typed. |
| Reproduction / evidence | Static source trace; previous Release build emitted an unused-result warning at create. |
| Remediation / regression | `do/catch`, visible Arabic error state, dismiss only on success; repository failure paths covered headlessly. |
| Final status | **Fixed; UI alert/focus requires manual exercise.** |

### AYAH-015 — final bundle omitted required dependency/data notices

| Field | Value |
|---|---|
| Severity / confidence | Low compliance / high |
| CWE | Not applicable |
| Affected | `Resources/ThirdParty/*`, `THIRD_PARTY_LICENSES.md`, generated pbxproj |
| Expected / observed | Distributed app includes Adhan MIT notice and GeoNames CC BY attribution. Baseline signed bundle contained only four runtime resources and neither notice. |
| Preconditions / reachability | Any distribution of that baseline bundle. |
| Impact / root cause | License/attribution non-compliance. Repository documentation was not included in application resources. |
| Strongest counterevidence | Repository-level `THIRD_PARTY_LICENSES.md` documented both correctly; no release had been notarized/published in scope. |
| Reproduction / evidence | Baseline bundle resource enumeration. |
| Remediation / regression | Added exact upstream Adhan MIT license and GeoNames attribution/license link under bundled `Resources/ThirdParty`; XcodeGen project includes them. |
| Final status | **Fixed and confirmed in the locally signed Release bundle.** |

### AYAH-016 — SQLite handles leaked on throwing initialization paths

| Field | Value |
|---|---|
| Severity / confidence | Low / high |
| CWE | CWE-772 |
| Affected | SQLite connection, Quran and Location repository initializers |
| Expected / observed | Every handle returned by `sqlite3_open_v2`, including error handles and handles opened before later validation throws, must close. Baseline relied on `deinit`, which is unavailable before successful initialization. |
| Preconditions / reachability | Repeated unopenable/corrupt/checksum-invalid database attempts in one process. |
| Impact / root cause | Native heap/file-resource growth and eventual availability degradation. Throwing initializer ownership was incomplete. |
| Strongest counterevidence | Repositories normally initialize once per app launch. |
| Reproduction / evidence | 2,000-failure heap-growth regression tests for all three classes; wrong-checksum/corrupt post-open paths reviewed. |
| Remediation / regression | Explicit close on open failure and `do/catch` close before stored-property ownership on later failure. |
| Final status | **Fixed.** |

## Rejected false positives and non-applicable classes

- No SQL injection: every external value reaches a prepared statement bind;
  interpolated column lists are private constants.
- No application network/exfiltration path: no relevant networking API or
  entitlement was found. Core Location may let macOS `locationd` use network
  facilities outside Ayah's process; this is disclosed and is not an Ayah
  socket path.
- No backend authentication, authorization, payment, server secret, CORS,
  remote database, browser-client trust, SSRF, XSS, upload, or API-rate-limit
  finding: those components do not exist.
- A candidate that `authorizedWhenInUse` was unhandled was rejected; both
  authorized cases are handled. The real issue was unsolicited callbacks and
  lack of timeout/cancellation.
- Shell injection in Quran extraction was rejected: executable path and
  argument vector are fixed/no shell. Resource exhaustion remains.
- Direct bundle tampering is substantially countered in a signed distribution;
  that does not authenticate pre-sign inputs or ad-hoc/local builds.
- No known Adhan security advisory was found in the reviewed official
  repository/issues/advisory searches as of the access date. Absence from a
  search is not proof that none exists.

## Dependency, privacy, licensing, CI, and release assessment

### Dependencies

Adhan Swift 1.5.0 at revision
`a6fa2deee80c5abb0b9ad04466f8ab12b53144e7` is the only third-party code
dependency and declares no dependency of its own. The AyahKit and Xcode
workspace lockfiles are byte-identical. Its full MIT notice is now bundled.
No new code dependency or network capability was added.

### Privacy and sandbox

Source entitlements contain only App Sandbox and Location; outbound network,
camera, microphone, contacts, accessibility, screen capture, and broad file
entitlements are absent. `Info.plist` contains both relevant location purpose
strings. Location is explicit, one-shot, cancellable, timed out, locally
cached, and never transmitted by Ayah. Plaintext same-user storage and manual
retention remain AYAH-013. README/PRIVACY/SECURITY claims were narrowed to the
observed architecture.

### Licensing/provenance

- Adhan: MIT; exact notice now bundled.
- GeoNames: CC BY 4.0; attribution/license link now bundled; upstream data is
  explicitly “as is” and accuracy is not guaranteed.
- KFGQPC font: bundled unmodified under the embedded use/copy/distribute EULA;
  SHA-256 `d560bbbc...41bd041`.
- KFGQPC Quran text: no explicit redistribution license found in the reviewed
  project/source records; the maintainer's documented accepted legal risk
  remains. This audit does not provide legal advice.

### CI/release

The workflow is least-privilege, immutable-action pinned, timeout bounded,
requires Quran manifest verification, runs all AyahKit tests, and attempts a
Release build with automatic package resolution disabled. External branch
protection, CODEOWNERS, required reviews, organization action policy, token
defaults, and an actual hosted run were unavailable. Recommended governance:
two-person approval for Quran/GeoNames trust anchors, CODEOWNERS for resources,
workflow, entitlements, locks, and signing configuration, plus final artifact
attestation after notarization.

The baseline ad-hoc Release bundle passed `codesign --verify --deep --strict`,
had hardened-runtime flags, linked only expected system frameworks/libraries,
and carried sandbox/location plus development `get-task-allow`; no network
entitlement. It contained four sealed resources before this pass. `spctl`
returned a Code Signing subsystem internal error in this restricted session;
in any case, acceptance is not expected before Developer-ID signing and
notarization. A post-fix ad-hoc Release bundle was subsequently produced in an
approved local execution context and received the same signing, entitlement,
linked-library, resource, and SQLite checks described below.

## Research corpus

Accessed 2026-08-23. Technical conclusions use primary/official sources;
community material is used only for product themes or leads.

| Publisher/source | Applicable scope/version | Claim used |
|---|---|---|
| [Apple — App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) | macOS app distribution/runtime | Sandbox capabilities are entitlement-controlled and required for Mac App Store distribution. |
| [Apple — requesting Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) | Current Core Location/macOS | Ask in context, prefer When In Use, disclose purpose, and plan for denial/unavailability. |
| [Apple — configuring Location Services](https://developer.apple.com/documentation/corelocation/configuring-your-app-to-use-location-services) | Current Core Location | Location is sensitive and retained location should be protected appropriately. |
| [Apple — CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager) | Current manager lifecycle | Authorization callbacks may occur as manager state changes/initializes; capability callback is not user intent. |
| [Apple — SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) | macOS 13+ | Modern launch-at-login API and status model. |
| [Apple HIG — right to left](https://developer.apple.com/design/human-interface-guidelines/right-to-left) | macOS Arabic UI | Mirror layout/reading order and preserve natural RTL behavior. |
| [Apple — VoiceOver evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/) | App Store accessibility | Common tasks and controls need labels, operability, and equivalent custom-element behavior. |
| [Apple — Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/BestPractices.html) | macOS timers/wakeups | Minimize timers/wakeups and use tolerance where timing semantics permit. |
| [Apple — App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Current App Store review | Accurate privacy disclosure, consent, minimum permissions, sandbox, and user-controlled login items. |
| [SQLite — `sqlite3_step`](https://www.sqlite.org/c3ref/step.html) | SQLite 3 C API | `ROW` and `DONE` are distinct; other return codes are errors, not end-of-results. |
| [SQLite — open](https://sqlite.org/c3ref/open.html) | SQLite 3 C API | A handle can be returned even on open failure and must be closed. |
| [GitHub — secure Actions use](https://docs.github.com/en/actions/reference/security/secure-use) | GitHub Actions | Full commit SHA is the immutable action reference. |
| [GitHub — hardening Actions](https://docs.github.com/en/code-security/tutorials/secure-your-organization/protect-against-threats) | GitHub Actions | Explicit minimum token permissions and action/pipeline hardening. |
| [SwiftPM — resolving package versions](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/resolvingpackageversions/) | SwiftPM 6 | Resolution belongs to the consuming graph; library locks do not bind consumers. |
| [Apple — Swift packages in CI](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows) | Xcode/SwiftPM CI | Commit workspace resolution and disable automatic resolution for reproducible CI. |
| [Swift evolution SE-0337](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md) and [SE-0302](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md) | Swift 6 concurrency | Strict checking/isolation and Sendable boundaries informed callback/task review. |
| [Adhan Swift official repository](https://github.com/batoulapps/adhan-swift) | 1.5.0 | Offline calculation library, method/madhab behavior, MIT license. |
| [Adhan methods](https://github.com/batoulapps/adhan-js/blob/master/METHODS.md) | Shared Batoul Apps method model | `Other` uses zero angles for callers to customize; high-latitude/method limitations. |
| [KFGQPC developer platform](https://qurancomplex.gov.sa/en/techquran/dev/) | Hafs/Uthmanic export | Official developer export authority, schemas, and published legacy digests. |
| [GeoNames dump README](https://download.geonames.org/export/dump/readme.txt) and [export page](https://www.geonames.org/export/) | Current export schema/license | CC BY 4.0 attribution, timezone field semantics, and “as is” accuracy caveat. |

## Community/user evidence and ranked product backlog

Reviewed [Athan Pro macOS reviews](https://apps.apple.com/us/app/athan-pro-muslim-prayer-times/id743843090?platform=mac&see-all=reviews), the recent native
[Iqamah discussion](https://www.reddit.com/r/muslimtechnet/comments/1vfknnp/every_mac_prayer_times_app_i_tried_was_a_webpage/), and a native
[Sajda macOS discussion](https://www.reddit.com/r/macapps/comments/1n3wd3w/i_couldnt_find_a_modern_native_prayer_times_app/), alongside Adhan's public issues. Recurring themes—not proof of Ayah defects—were native
menu-bar glanceability, prayer-time trust, per-prayer adjustments, privacy/no
account/telemetry, Arabic readability, DST/travel reliability, battery use,
and avoiding feature overload.

Ranked advisory backlog:

1. **Prayer-time trust panel**: show method, madhab, location/zone, last
   location refresh, and per-prayer diagnostic values; add documented manual
   per-prayer minute offsets. Highest recurrence and trust impact.
2. **Non-notch parity**: show current verse/next prayer/countdown in the
   menu-bar popover and deliver in-app prayer alerts there. Current scheduler
   intentionally starts only with notch hardware.
3. **Location privacy controls**: “forget current location,” precision choice,
   and retention explanation; consider encrypted migration.
4. **High-latitude/no-event UX**: explain unavailable solar events and let the
   user choose a documented high-latitude rule rather than silently showing
   nothing.
5. **Accessibility completion**: real VoiceOver rotor/focus/order testing,
   keyboard shortcuts for core tasks, Dynamic Type/text scaling, contrast, and
   reduced-motion audit on macOS 13 and current macOS.
6. **Multi-display/sleep diagnostics**: display attachment state and last alert
   rearm reason; validate notch/external-only configurations.
7. **Arabic city-data quality**: report/correct upstream Arabic-name errors and
   expand optional Arabic names without introducing an online lookup.
8. **Themes only after trust/accessibility**: white/beige/black reading themes
   remain desirable but rank below correctness and parity.

## Verification evidence

| Check | Result |
|---|---|
| AyahKit full suite | **Pass: 98/98**, baseline was 70. Includes corrupt/null/out-of-range/locked SQLite, checksum/tamper, settings, location denial/restriction/failure/cancellation/timeout/concurrency, prayer DST-zone/Ramadan/all-supported-method logic, scheduler clock/time-zone, cursor, handle-leak regressions, and eight deterministic performance cases. |
| Script executables | **Pass:** all three Swift 6 packages (`import_quran`, `import_geonames`, and `verify_quran`) completed fresh final `swift build` checks after the compiler-cache sandbox retry. |
| Quran verifier | Pass: manifest cross-check, 114 surahs, 6,236 ayahs, canonical checksum. Missing-manifest fixture exits 1 as intended. |
| SQLite/resources | Both `PRAGMA integrity_check` = `ok`; Quran 114/6,236; GeoNames 4,654; GeoNames file SHA-256 matches `GEONAMES_CHECKSUM`; project includes checksum and third-party notices. |
| App source | Whole `App/**/*.swift` Swift 6 type-check passed against current AyahKit and Adhan modules after fixing an actor-isolated default-argument issue. |
| Debug/Release Xcode | **Pass post-fix** in fresh `/private/tmp` DerivedData after the approved retry outside the nested sandbox; automatic package resolution remained disabled and the reviewed local Adhan 1.5.0 resolution was used. |
| ASan / TSan | Instrumented builds complete, but both test runners are denied by macOS platform policy because sanitizer dylib insertion is not allowed for this process. Recorded unsupported, not passed. |
| Post-fix codesign | `--verify --deep --strict` pass; ad-hoc hardened runtime; expected system libraries; sandbox + location + local development `get-task-allow`; no network entitlement. Seven sealed resources include both SQLite databases, both checksums, font, and third-party notices. |
| `spctl` / notarization | `spctl` returned internal Code Signing subsystem error on ad-hoc baseline; Developer-ID/notarization not present, so no distribution acceptance claim. |
| Plist/entitlements | `plutil -lint` pass; location purpose keys present; source entitlements have sandbox/location only. |
| Dependency | AyahKit and Xcode workspace locks compare identical at Adhan 1.5.0/revision `a6fa2d...`. No new dependency. |
| Network/secrets | No application networking API match, outbound entitlement, hardcoded credential, backend, analytics, or telemetry sink found. |
| Performance | Three Release runs produced stable baselines for eight deterministic workloads (all CV < 4%). Sanitized Logging, Time Profiler, and Allocations traces were captured. The canonical full run completed five warm-up plus 200 measured real-popover cycles with −16.82 MiB settled RSS change and a separate 30-minute/180-sample idle phase with CPU median/p95 0.000% and memory 30→21 MiB. Both provisional trend guardrails pass; see the [release-candidate baseline](../performance/2026-08-23-release-candidate-baseline-v1.md). No timer-leeway change was made without per-process wakeup attribution. |
| OCR/final formatting | Final delegation preview/rules reviewed; `git diff --check` clean at handoff. |

Runtime menu/notch hardware behavior, no-notch alert parity, interactive
location permission decisions, launch-at-login system approval, multi-display,
sleep/wake, manual clock changes, VoiceOver/Accessibility Inspector, keyboard
focus restoration, contrast/text scaling, 30-minute wakeup attribution, and a
notch-specific repeated-cycle comparison were not re-exercised after the
fixes. The automated 200-cycle popover RSS trend passed, while a 30-second
sanitized Time Profiler trace and Allocations trace remain only partial
evidence for the other long-run interactive scenarios.

## Canonical external scan artifacts

The Codex Security scan ID is
`f9764465-e4a3-4ea0-a560-7ab798cc772f`. Its canonical artifacts were sealed
outside source control and the completion lifecycle was called exactly once:

- [scan-manifest.json](/private/var/folders/sh/wv6m88m90dzcf23054ckz_pc0000gn/T/codex-security-scans-1AtKO5/Ayah/873d3f87e635db083d09e2bd31d8daeaa0ce2c49_20260823T150830Z_2k8m3_0j/scan-manifest.json)
- [findings.json](/private/var/folders/sh/wv6m88m90dzcf23054ckz_pc0000gn/T/codex-security-scans-1AtKO5/Ayah/873d3f87e635db083d09e2bd31d8daeaa0ce2c49_20260823T150830Z_2k8m3_0j/findings.json)
- [coverage.json](/private/var/folders/sh/wv6m88m90dzcf23054ckz_pc0000gn/T/codex-security-scans-1AtKO5/Ayah/873d3f87e635db083d09e2bd31d8daeaa0ce2c49_20260823T150830Z_2k8m3_0j/coverage.json)
- [report.md](/private/var/folders/sh/wv6m88m90dzcf23054ckz_pc0000gn/T/codex-security-scans-1AtKO5/Ayah/873d3f87e635db083d09e2bd31d8daeaa0ce2c49_20260823T150830Z_2k8m3_0j/report.md)
- [results.sarif](/private/var/folders/sh/wv6m88m90dzcf23054ckz_pc0000gn/T/codex-security-scans-1AtKO5/Ayah/873d3f87e635db083d09e2bd31d8daeaa0ce2c49_20260823T150830Z_2k8m3_0j/exports/results.sarif)

TAC was not granted; enrollment remains available at
`https://chatgpt.com/cyber`. This has no effect on the static findings but is
part of the scan-evidence record.

## Acceptance and remaining uncertainty

All repository files have a coverage disposition, all applied logic fixes have
headless regression evidence, 98 tests and data-integrity checks are green, no
network capability or dependency was added, the requested documentation now
matches current behavior, and the original dirty workspace has a recovery
snapshot and remains present beneath the audit changes.

Acceptance is intentionally qualified by the unverified items above:
real-hardware accessibility/long-run energy exercises, hosted CI/security
settings, importer oversized-input tests, independent data authenticity,
Developer-ID/notarization, and private vulnerability-reporting enablement must
be completed in an environment that can perform them. Do not convert any of
those into an assumed success or a “vulnerability-free” claim.
