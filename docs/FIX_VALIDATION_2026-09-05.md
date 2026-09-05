# Approved review fixes — implementation and validation

Implemented against the working tree based on `81d9415`. No commit, release publication, or installation was performed.

- Prayer popups schedule against the newly published settings snapshot. Disabling cancels the pending timer; generation checks discard stale callbacks. System clock/time-zone callbacks return to the main actor. A current-location fetch publishes one complete settings update.
- Memorization toggles update only the enabled flag. Editor updates atomically preserve the live database cursor and review metadata, resetting the cursor to an unstarted walk when the surah changes or the new range excludes it. The retained management window refreshes its shared list model on opening. No schema migration is needed.
- Restored cards start the verse scheduler without selecting or advancing unseen verses. Interval changes replace the pending deadline with one full new interval from the change, without immediately selecting. A published startup snapshot also controls the first selection and interval.
- Display changes rebuild only presentation when switching between physical-notch and floating modes; content and schedulers survive. Temporary loss of all screens hides presentation until a screen returns.
- The non-notch popup is an opaque black card with white Arabic content, 20-point rounded corners and a 20-point gap below the menu bar. Its card-sized, nonactivating window slides as a whole over 0.4 seconds, with slight opening overshoot. Text remains mounted during closing. Completion generations prevent an old dismissal from hiding a newer popup. Reduce Motion shows/hides immediately. Moving the window rather than using a large transparent animation canvas avoids a large invisible input region.
- City search computes its filtered results once per body evaluation.
- The verified DynamicNotchKit MIT notice is bundled and included in the release resource gate. Source comments, About, acknowledgements, and third-party documentation accurately identify the original source and the historical boring.notch connection. No new framework dependency was added.

## Validation

- AyahKit: **129 tests passed** in Debug (Release build gate) and **129 passed** in Release.
- App-hosted Xcode suite: **17 tests passed**, including live repository cursor preservation across launch restoration, current-location publication, display transitions, dismissal cancellation, Reduce Motion, and rendered appearance.
- Release app build: succeeded with the existing macOS 13 deployment target.
- Quran Release gate: **114 surahs, 6,236 ayahs, checksum verified**.
- Release app signature: `codesign --verify --deep --strict` passed.
- Bundled DynamicNotchKit license matches the checked-in notice byte for byte.
- `git diff --check` and release-script shell syntax checks passed.
- A rendered appearance test verifies opaque black interior, transparent rounded corners, and readable text remaining mounted during the closing state. Its PNG is retained in the Xcode test result.
- The existing Release city-search benchmark averaged approximately **0.325 seconds for 50 searches** (about 6.5 ms/search). This measures filtering, not end-to-end UI latency; the view now invokes filtering once instead of twice for a matching query. No percentage improvement in UI frame time is claimed.

## Checks still requiring real hardware

Physical clamshell/external-monitor transitions, visible animation interruption under different window-server conditions, full-screen/Spaces behavior, actual macOS 13 runtime execution, and typing/energy profiling were not exercised on a separate hardware configuration. Automated display tests use injected screen snapshots and panel spies; the appearance test renders the real SwiftUI content. These limits do not invalidate the regression checks, but they are not substitutes for a final hardware smoke test.

The earlier formal security scan failed inside the scan tool's own database and was not rerun as part of these functional fixes. No security clearance is claimed.

Build and test logs from this session are in `/private/tmp/ayah-fix-*.log`; Xcode results and the locally built Release app are under `/private/tmp/ayah-fixes-xcode/`. Temporary artifacts may be cleaned by macOS.
