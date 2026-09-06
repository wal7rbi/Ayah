# Ayah code review — 2026-09-05

**Historical review:** the approved fixes have since been implemented. See [implementation and validation](FIX_VALIDATION_2026-09-05.md) for current status; findings below describe the original revision.

Reviewed revision: `81d9415`. Source code was not changed. This report covers the app's scheduling, settings, memorization, location, persistence, and presentation paths, with inspection of build/CI configuration. It is not an exhaustive audit of every importer or a hardware UI test.

Found six functional issues, one performance improvement, and one provenance discrepancy requiring investigation. Fix the prayer scheduler first, then memorization progress and editing.

## 1. High — Prayer settings changes schedule against the previous value

Location: [PrayerAlertScheduler.swift:60](../Packages/AyahKit/Sources/AyahKit/Scheduling/PrayerAlertScheduler.swift:60).

The `$settings` subscriber discards its emitted value and calls `armNextTimer()`, which rereads `settingsStore.settings`. Publication happens before that property is updated. Consequently, enabling prayer alerts from a disabled state cancels the timer and returns using the old disabled value. Disabling alerts from an enabled state instead schedules another alert using the old enabled value. A location, calculation-method, or reminder change likewise uses the preceding configuration until another rearm occurs.

**Evidence:** A temporary test using the production scheduler and its injected `now` closure confirmed zero scheduling calculations after enabling, then one calculation after disabling. A valid cached Riyadh location was present throughout. The event handler checks the generation but does not recheck whether notifications remain enabled.

**Fix:** Pass the emitted `AppSettings` snapshot into `armNextTimer(settings:)` and use it consistently throughout that operation. For timer, wake, and clock callbacks, explicitly pass the current stored snapshot. Consider observing only prayer-relevant fields, so verse settings do not unnecessarily rebuild the prayer schedule. Update all fields from a current-location fetch in one assignment rather than four intermediate states.

**Regression tests:** Assert the actual armed event or injected timer state after enable, disable, location switch, method switch, and reminder changes. Checking only that `rearmGeneration` increases does not establish that the correct schedule was created.

## 2. Medium — Editing a valid memorization range can fail

Location: [MemorizationSetsView.swift:178](../App/UI/Memorization/MemorizationSetsView.swift:178).

The editor changes the surah/range but keeps the previous `cursorAyah`. The repository correctly rejects a cursor outside the new range. For example, a set spanning 2:1–20 with cursor 15 cannot be shortened to 2:1–10, even though every visible field is valid. The error asks the user to check values, but the invalid cursor is not editable in the form. Changing the surah while retaining an in-range cursor can also resume at an unintended point in the new surah.

**Evidence:** Reproduced using the production repository; the valid range edit throws `valueOutOfRange` because cursor 15 is retained.

**Fix:** Establish an explicit cursor policy for edits. Reset to the new start when the surah changes, and reset or clamp when the cursor falls outside a changed range. Preserve current progress for unrelated edits.

**Regression tests:** Shorten a range past its cursor, raise its start beyond the cursor, and change surahs with both in-range and out-of-range old cursors.

## 3. Medium — Enabling/disabling a set can overwrite newer progress

Location: [MemorizationSetsView.swift:194](../App/UI/Memorization/MemorizationSetsView.swift:194).

The view stores a snapshot of all sets in `@State`. The scheduler can advance the database cursor after that snapshot is loaded. Toggling a row then calls the full-row `update` with its stale snapshot, writing the old cursor back over the scheduler's newer progress. This is possible even on one thread; it is a stale-data problem, not a simultaneous-access requirement. The management window is retained across openings, so simply closing and reopening it does not establish a fresh snapshot.

**Evidence:** A temporary test loaded a UI-equivalent snapshot, advanced the database cursor to 15, then toggled the snapshot and called the same update API. The persisted cursor reverted to the snapshot's older value.

**Fix:** Add a narrow `setEnabled(id:enabled:)` update that changes only `is_enabled`. Similarly, use an editor-specific repository operation that merges editable fields with current stored progress and applies the range policy from finding 2. Refresh the visible list when the window opens, but do not rely on refreshing alone to protect against later scheduler writes.

**Regression test:** Load a snapshot, advance the cursor, toggle enabled state, and assert the new cursor survives.

## 4. Medium — Restoring the last card can skip memorization verses

Locations: [NotchViewModel.swift:135](../App/UI/Notch/NotchViewModel.swift:135), [VerseScheduler.swift:67](../Packages/AyahKit/Sources/AyahKit/Scheduling/VerseScheduler.swift:67), and [VerseScheduler.swift:127](../Packages/AyahKit/Sources/AyahKit/Scheduling/VerseScheduler.swift:127).

When a last-shown record is restored, the view model intentionally discards the first scheduler callback. However, `start()` has already selected verses and persisted the sequential-set cursor before invoking that callback. With 100% memorization weight and two verses per display, restarting can consume the next two verses without displaying them. Repeated restarts can repeatedly advance progress unseen.

**Evidence:** Source-traced across startup, selection, cursor persistence, and the callback's early return. This app-layer scenario was not executed during this review.

**Fix:** Add a scheduler start mode that arms the initial timer without selecting verses when restoring content. Do not call selection and then discard its result, because selection currently has persistence side effects. Longer term, separate selection from committing displayed progress.

**Regression test:** Restore a valid card with a deterministic sequential set, start scheduling, and assert the cursor is unchanged until the first new batch is actually displayed.

## 5. Medium — Changing the verse interval leaves the old deadline active

Locations: [VerseScheduler.swift:72](../Packages/AyahKit/Sources/AyahKit/Scheduling/VerseScheduler.swift:72) and [PopoverContentView.swift:406](../App/UI/MenuBar/PopoverContentView.swift:406).

The interval picker only writes settings. The scheduler reads the interval when it next arms, and the view model observes only the enabled toggle. Changing from three hours to 15 minutes therefore can still leave almost three hours until the next verse; the new setting applies only after the old timer fires. Increasing the interval has the inverse surprise.

**Evidence:** Source-traced picker binding, settings subscription, and timer creation; no interval-change rearm exists.

**Fix:** Observe interval changes and cancel/rearm the pending timer without emitting a new batch. Define whether the new deadline is measured from the change or from the last display, and test that policy. Pass the published value directly to avoid repeating finding 1.

**Regression tests:** Change long-to-short and short-to-long with an injected timer/clock; verify exactly one pending timer and no extra immediate cursor advance.

## 6. Medium — Switching to an external-only display hides all cards

Location: [NotchController.swift:148](../App/UI/Notch/NotchController.swift:148).

After starting on a notched MacBook, closing its lid while using an external monitor removes the notched screen. The display-change handler orders the panel out and returns. It never switches to the already-implemented fallback presentation; verse and prayer schedulers keep running without visible cards. Restarting in the external-only configuration restores fallback behavior.

**Evidence:** Source-confirmed behavior. The class comment explicitly declares live mode switching out of scope, so this is a documented product limitation rather than an undisclosed implementation promise. It still affects an ordinary laptop workflow. No physical monitor transition was tested here.

**Fix:** Reevaluate presentation mode on display changes and rebuild/reconfigure the panel for the available screen while retaining the view model and scheduler state. Manage fallback visibility subscriptions as the mode changes. Do not restart schedulers or register duplicate observers during a presentation transition.

**Verification:** Exercise notched-to-external-only, reconnect/open-lid, and launch-in-clamshell transitions; verify both prayer and verse cards remain visible when due.

## 7. Low — City search repeats a full scan in one render

Location: [CityPickerView.swift:40](../App/UI/Prayer/CityPickerView.swift:40).

For matching queries, `filteredCities` scans all 4,659 cities once to test `isEmpty` and again to supply `List`. Both scans perform localized string comparisons synchronously during view rendering. This duplicates work on every query update.

**Measurement:** The existing Debug benchmark averaged approximately 0.348 seconds for 50 representative searches: about 7 ms per search. Two comparable scans are roughly 14 ms before list/layout work. These are warm unit-benchmark figures, not measured UI frame times or a Release regression claim.

**Fix:** First compute one local result in `body` and reuse it for both branches. If Release profiling still shows typing latency, move filtering into cached query state or use a cancellable, debounced search over immutable city values. Preserve Arabic/English matching behavior.

**Verification:** Compare identical query sequences in Release before/after; measure typing/render responsiveness rather than interpreting the entire 50-search benchmark as one keystroke. The current measurements do not justify a broad repository or database rewrite.

## 8. Notice — Shape provenance statements conflict

Locations: [NotchShape.swift:5](../App/UI/Notch/NotchShape.swift:5) and [THIRD_PARTY_LICENSES.md:111](../THIRD_PARTY_LICENSES.md:111).

The source comment says the shape was “Ported from TheBoredTeam/boring.notch,” while the third-party notices say no code from those reference projects was copied. These are inconsistent accounts of the same component's origin.

**Next step:** Inspect the implementation's introduction and original authoring evidence, then make the source comments and notices accurately describe its provenance. A comment alone does not prove copying or establish a licensing violation; this review did not compare upstream code or reach a legal conclusion. Do not resolve the discrepancy by merely deleting the attribution without checking its history.

## Validation and limits

- The original AyahKit suite passed: **118 tests, zero failures**, about 4.49 seconds of test execution, Debug configuration. This includes existing integrity, persistence, location, scheduling, and performance cases.
- Three temporary evidence tests also passed, confirming the **current buggy behavior** for findings 1–3. They are reproductions, not tests asserting the desired fixed behavior. The temporary test file was removed from the package after execution.
- Evidence files for this session: [test log](/private/tmp/ayah-review-tests.log), [reproduction log](/private/tmp/ayah-review-evidence.log), and [reproduction test source](/private/tmp/ayah-review-evidence-tests.swift). Temporary files may be cleaned by the operating system.
- Swift's default module-cache path was unwritable under the session sandbox. Tests succeeded after directing module caches to `/tmp` and disabling SwiftPM's nested build sandbox; no elevated execution was needed.
- App-hosted Xcode tests, physical display changes, location permission dialogs, Release UI profiling, energy measurements, and hosted GitHub CI were not run. Passing package tests does not establish these behaviors.
- The formal Codex Security scan could not start: its tool returned `sqlite3.OperationalError: duplicate column name: retained_source_digests_json`. No formal security scan was completed, and this report is not security clearance. The failure belongs to the scan tool's internal database, not Ayah's database.

Recommended implementation order: **1 → 2 and 3 together → 4 → 5 → 6 → 7**. Investigate the provenance discrepancy separately before making stronger claims about code origin.
