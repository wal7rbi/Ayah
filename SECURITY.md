# Security

## Reporting a vulnerability

If you find a security issue in Ayah, do **not** post exploit details,
private data, or an unreleased vulnerability in a public issue. Request a
private maintainer contact or use GitHub private vulnerability reporting if
it is enabled for the repository; public issues are appropriate only for
non-sensitive hardening discussions. Since this project has no telemetry,
no backend, and no server component, most security concerns will relate to
the local application itself (e.g. entitlement misconfiguration, unsafe
file handling, or a dependency vulnerability) rather than a remote attack
surface.

## Security posture (verified 2026-09-01)

This section records a real review against a built app, not a design
intent. Verified on macOS 26.5.2 (arm64), Xcode 26.3, both Debug and local
Release configurations. The entitlement, network, and SQL findings below
were re-confirmed on 2026-09-01 against a freshly built app after the
prayer-location, layout, test-target, and GeoNames-importer changes of that
day; none of them altered the app's security posture.

This review still describes the **published 1.0.2 build** (tag `v1.0.2`,
revision `a35e112`): the only commit between the reviewed revision and the
tag changed `README.md` and two files under `docs/release/`, and touched no
source, resource, entitlement, or build-configuration file.

- **App Sandbox**: on. `App/Ayah.entitlements` requests exactly two keys —
  `com.apple.security.app-sandbox` and
  `com.apple.security.personal-information.location` (added deliberately
  for the opt-in "use current location" prayer-time convenience; see
  `PRIVACY.md`'s "Location" section). Confirmed against the actual signed
  binary, not just the source entitlements file. Debug builds may include
  `com.apple.security.get-task-allow`; the Release configuration sets
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, and the packaging gate requires
  the final ad-hoc-signed app to contain exactly the sandbox and location
  keys. Any debug or network entitlement fails packaging. Hardened runtime
  is required (`flags=...,runtime` in `codesign -dv`), and all runtime data,
  font, acknowledgement, and third-party notice resources must be present
  and sealed in the final bundle.
- **No network entitlement**: `com.apple.security.network.client` is
  deliberately never requested — confirmed absent in the entitlement dump
  above. This is a real, kernel-enforced restriction (see `PRIVACY.md` for
  detail), not a policy statement. A repo-wide search for networking APIs
  (`URLSession`, `URLRequest`, `NWConnection`, `NWListener`, raw sockets,
  `SCNetworkReachability`) across `App/` and `Packages/AyahKit/Sources`
  turns up zero matches — nothing in the code even attempts to reach the
  network, so the sandbox restriction is defense-in-depth on top of an
  already-networkless codebase, not the only thing standing in the way.
- **No unnecessary permissions**: confirmed via both the entitlements file
  and `Info.plist` — no Accessibility, Screen Recording, Microphone,
  Camera, or Contacts entitlement/usage-description key exists anywhere.
  Location is the one deliberate exception (see above), using
  `requestWhenInUseAuthorization()` (`CurrentLocationProvider.swift`) —
  the minimal-scope request, not `requestAlwaysAuthorization()`. That call
  is backed by `Info.plist`'s `NSLocationWhenInUseUsageDescription`, which
  is the key it specifically requires; verified against a fresh build by
  triggering the real macOS permission dialog and reading back its Arabic
  disclosure text.
  **A lesson worth keeping from how that was found**: an earlier pass of
  this review cited the legacy `NSLocationUsageDescription` key as the
  evidence, which does not back that call at all. The key it needs was
  absent, and macOS silently ignores the request when it is — no dialog,
  no delegate callback — so the whole "استخدام الموقع الحالي" flow hung
  with a spinner and no visible failure, and the review had certified it
  as correct. When reviewing permission-prompt code, check the API's
  actual documented requirement, not the code's evident intent.
- **SQL injection surface**: reviewed every raw-SQLite call site
  (`Persistence/SQLiteConnection.swift`, `Quran/QuranRepository.swift`,
  `Prayer/LocationRepository.swift`, `Memorization/MemorizationRepository.swift`).
  Every query that incorporates a value outside a fixed schema/column-list
  string uses `sqlite3_bind_*` through a prepared statement — none build
  SQL by interpolating caller-supplied data directly into a query string.
  The only `String`-interpolated SQL anywhere is `\(Self.columns)`/
  `\(Self.ayahColumns)`/`\(Self.cityColumns)`, each a private `static let`
  constant, never a parameter — there is no reachable injection path from
  UI input (memorization-set surah/ayah numbers, city selection, etc.)
  into a raw query string.
- **Quran data integrity**: the bundled `quran.sqlite` is treated as
  immutable, checksummed content. `Resources/Quran/CHECKSUM` records a
  content hash that `QuranRepository` verifies at startup via
  `QuranIntegrityChecker`; `AppDelegate` surfaces a mismatch as a blocking
  `NSAlert` rather than silently showing unverified text (confirmed by
  reading `AppDelegate.makeQuranRepository()`). This is verified at three
  further layers beyond runtime:
  `.github/workflows/quran-integrity.yml` independently re-verifies the
  checksum (and the `MANIFEST.json` provenance record) on every push/PR,
  plus a provenance guard blocking an unexplained `quran.sqlite` change,
  and a Release-only Xcode build gate runs the same check before compiling
  a Release build. See "Quran data supply-chain trust model" below for the
  full chain. The workflow is hardened with read-only contents permission,
  disabled checkout credential persistence, a bounded timeout, and a
  full-SHA action pin. Remote execution still has to be observed in the
  actual GitHub repository; local inspection cannot claim a hosted run
  succeeded.
- **Local mutable data (`ayah_user.sqlite`)**: written only to a fixed,
  non-user-controlled path (`Application Support/Ayah/ayah_user.sqlite`
  inside the sandbox container, built entirely from
  `FileManager.default.url(for: .applicationSupportDirectory, ...)` with
  no externally-influenced path components) — no path-traversal surface.
- **GeoNames integrity**: `LocationRepository` verifies the bundled
  `cities_filtered.sqlite` against `GEONAMES_CHECKSUM`, validates SQLite
  column types, coordinate ranges, and IANA time zones, and refuses city
  selection/prayer display if any check fails. The checksum authenticates
  an approved local artifact; it is not an independent upstream signature.
  `GEONAMES_CHECKSUM` is written by `Scripts/import_geonames` itself, and
  the importer is deterministic — two runs over the same dump produce
  byte-identical output — so the committed database can be independently
  reproduced and checked. It was previously hand-written, which meant it
  could only detect corruption, never confirm provenance, and any
  re-import silently produced a database the app refused to load.
- **Dependencies**: kept intentionally minimal. Adhan Swift (MIT, zero
  dependencies) is the only third-party code dependency, pinned in
  `Packages/AyahKit/Package.resolved` to a specific tagged revision
  (`1.5.0`, commit `a6fa2de...`) rather than a floating branch — see
  `THIRD_PARTY_LICENSES.md`.

**Deliberately not part of the distribution policy**: Developer ID
signing and Apple notarization require an Apple Developer Program account.
Ayah instead produces an arm64, hardened-runtime, ad-hoc-signed DMG and
documents macOS's per-app Privacy & Security > Open Anyway flow. The fresh,
quarantined GitHub-download exercise remains a mandatory manual release
check; a local build cannot prove that path. Also not yet done: a live
sandbox-violation trace via `sudo log stream` while
exercising every feature (a manual launch-and-quit during this review
produced no denial events under `log show`, but that predicate is weak
evidence on its own — treat the static entitlement dump above as the
authoritative check, not this).

## Quran data supply-chain trust model

Added 2026-08-22 alongside the source-verification/manifest/tampering-test/
CI/release-gate work described in `CLAUDE.md`. Each layer below protects a
different stage and proves a different, narrow thing — they are not
substitutes for one another, and none of them is a substitute for the
others:

1. **KFGQPC establishes textual authority.** Ayah's sole Quran textual
   authority is the King Fahd Glorious Quran Printing Complex's official
   developer platform (Hafs narration, Uthmanic Unicode script) — see
   `ARCHITECTURE.md` §5. No second Quran dataset is reconciled against it.
2. **Official KFGQPC MD5/SHA-1 establish identity of the downloaded
   package.** `Scripts/import_quran` computes these from the archive and
   compares them against the values KFGQPC publishes on the same download
   page, hard-failing on mismatch, before any parsing happens. This proves
   the local archive is byte-identical to what KFGQPC actually published
   — nothing more, and specifically not a claim about the text's religious
   authoritativeness.
3. **Ayah's own SHA-256 establishes a modern cryptographic identity** for
   the approved source archive and the generated dataset, recorded in
   `MANIFEST.json` — see `ARCHITECTURE.md` §8.
4. **The deterministic importer establishes how the database was
   produced.** One documented path (`Scripts/import_quran`), the Uthmanic
   text preserved exactly (never normalized, diacritic-stripped, or
   otherwise transformed), structural validation on every field. See
   `ARCHITECTURE.md` §7–§8 for the two-tier reproducibility model (source
   integrity vs. semantic Quran integrity).
5. **Tampering-detection tests prove the integrity mechanism actually
   works**, not just that it exists — `QuranTamperingTests.swift` exercises
   the real production checksum/count-guard code paths against
   deliberately corrupted temp copies (never the real bundled file) and
   confirms they're rejected.
6. **CI prevents unverified Quran-data changes from merging** —
   `.github/workflows/quran-integrity.yml`, see the updated bullet above.
7. **macOS code signing protects the final application bundle after
   signing** — a different stage from everything above, not a
   replacement for it. Once `Ayah.app` is signed, modifying any resource
   inside the bundle (including `quran.sqlite`) invalidates the code
   signature; `codesign --verify --deep` (or Gatekeeper at launch, for a
   notarized build) independently detects that. This says nothing about
   whether the data was *correct* before signing — that's layers 1–6 —
   only that the signed bundle hasn't been altered since.
8. **Runtime SHA-256 verification is the final defense, not the only
   one.** `QuranRepository`'s startup check (unchanged by this pass —
   still opens the database read-only, verifies, refuses-and-alerts on
   failure) catches anything that slipped past every layer above,
   including a bundle that was never signed at all (a local/ad-hoc-signed
   build, per this document's own entitlement-verification notes).

**What none of this proves**: a checksum does not independently prove
that Quran text is religiously authoritative. It proves that the data is
identical to an already-approved authoritative source/artifact. The
precise claim this whole chain supports is: *"Ayah's Quran data is
identical to the KFGQPC-derived dataset approved by the project"* — not
"cryptographically proven correct" in any stronger sense.

**Deliberately deferred, not a v1 requirement**: Sigstore or GitHub
Artifact Attestations for release provenance. The release workflow is
structured so this can be added later, targeting the final distributable
artifact (`.app`/`.zip`/`.dmg`) rather than signing `quran.sqlite`
individually — but nothing here is wired up yet; this is a forward-looking
note, not a claim of present capability.

## Out of scope for v1

Ayah has no user accounts, no network-facing API, and no server, so classes
of vulnerability like authentication bypass, injection against a remote
backend, or data breach of a hosted database do not apply to this project's
architecture by construction.
