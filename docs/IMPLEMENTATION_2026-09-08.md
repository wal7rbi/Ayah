**Follow-up — 8 October 2026**

- The memorization fallback is now real: `AppDelegate` builds `VerseScheduler` whenever the Quran data loads, so a memorization-storage failure no longer stops verses. The rollback had restored startup wiring that skipped the scheduler in that case. The failure alert now says verses continue from the whole Quran.
- Open-on-hover and the non-notch “آية” tab (added after the rollback; see `ARCHITECTURE.md` §4) do not open when there is no content yet.
- Removed `VerseScheduler.startDue`, which belonged to the rolled-back presentation arbitration. `deleteReturningSet`, `restore` and `MemorizationAccess.retry` stay, with tests, but no UI calls them yet.
- The location permission dialog has its own 120-second timeout; the 30-second fix timeout starts only once a location is requested.
- A successful cursor save no longer clears an unrelated memorization read-error message.

Verified with both suites and in the running app (isolated bundle ID): hover open/close, no hover-open on empty content, and verses shown after deliberately corrupting the memorization database.

**UI/UX rollback — 8 September 2026**

At the user’s request, all interface and presentation changes described below were reverted to the original design. The original app startup wiring was also restored. Location validation and measurement metadata, settings recovery, repository operations, prayer scheduler retry, and profiling corrections remain. Reader, pause, duration controls, UI recovery messages, range editor, undo controls, and presentation arbitration are no longer part of the app. The implementation and validation notes below are historical, before this rollback.

Rollback validation: 143 core tests and the hosted app test suite passed; the Debug app built successfully. Restored view files match the original commit exactly.

**Ayah reliability and reading improvements — 8 September 2026**

Implemented against `681f597` following the approved review plan. Changes are local and unpublished; the existing 1.0.4 download is unchanged.

**Implemented behavior**

- Prayer replay and reopening use explicit historical wording with the original prayer date/time. A shared formatter handles popup, history, and reader messages. Legacy history remains readable; its original time zone was not stored, so the display explicitly labels the zone used for formatting.
- Live prayer alerts take priority over automatic verses. Waiting verse deadlines coalesce into one request. Selection and cursor advancement occur when the request is admitted for presentation; an interrupted passage resumes without advancing again. Manual dismissal can end the prayer reading window early. Replaying during an active prayer opens a reader instead of replacing the alert.
- The full reader retains a passage snapshot, displays unmodified verified Uthmanic text with scrolling, and provides an 18–36 point font control. Popup text also scrolls at readable size. Card duration offers 12/20/30/60/120 seconds. Session pause stops new verse selection and verse auto-close; enabled prayer alerts continue. Pause/resume is available in the popup and menu-bar settings.
- Current-location requests preserve measurement timestamp and accuracy. New fixes reject invalid coordinates, negative/nonfinite or greater-than-5km accuracy, measurements older than five minutes, and measurements over one minute in the future. These are application quality limits. Legacy providers/settings retain unknown metadata rather than inventing freshness. Saved location age and effective time zone are visible, with refresh guidance after travel.
- When no prayer event can be calculated, the scheduler arms one cancellable retry at the next local day boundary. UI text distinguishes unavailable calculations from a missing location. A minute-level UI clock runs only while the popover is visible, refreshing date-dependent content without a hidden polling loop.
- Ordinary Quran reminders remain available when memorization storage fails. Shared repository availability and Retry restore management and selection using the existing user database. Settings, history, and cursor errors receive visible messages. A malformed top-level settings blob is preserved in one local recovery key before future edits overwrite the active key.
- Memorization controls have contextual Arabic accessibility labels. Deletion captures the latest persisted row in a transaction; Undo restores its ID, cursor, dates, and review fields and refuses to overwrite a conflicting row. Undo is session-local. The editor accepts Arabic/Western range digits, offers whole-surah selection, validates bounds, and retains input with errors inside the sheet.

**Regression coverage**

New tests exercise deferred cursor advancement, prayer/verse ordering, coalesced demands, interruption/resumption, pause behavior, historical replay dates, complete reader snapshots, storage fallback/retry, malformed settings recovery, migration defaults, location metadata validation, midnight retry, and transactional delete/undo. Diagnostic probes from the original review remain outside the test targets because they assert the earlier defective behavior.

The initial integrated suites passed 143 core tests and 27 hosted app tests. Screenshot output was moved into the app's permitted temporary directory after the first rendering attempt correctly failed to write directly to `/tmp` under App Sandbox. Rendering fixtures wait for layout, disable transitions, and close their test windows even on failure. Reader text and popup text were visually inspected. Native button drawing in `NSHostingView` bitmap captures was inconsistent: separate captures showed complete controls for each presentation, while others omitted them. This capture limitation is recorded rather than treated as proof of flawless physical presentation.

**Validation limits**

The current machine is arm64, macOS 26.6.2, Xcode 26.3. Automated screen-geometry tests and rendered view checks cannot certify physical camera occlusion, clamshell/external-display transitions, VoiceOver interaction, macOS 13 compatibility, a real launch-at-login approval, or a fresh quarantined installation. Those require separate hardware/operator verification. No publication, notarization, dependency update, or Quran resource change is included in this work.

**Final automated verification**

The release-candidate pipeline passed all 22 automated checks with zero failures: 143 core tests, 27 app tests, Debug/Release builds, integrity, architecture, signatures, and resources. The 200-cycle check passed using corrected aggregation (126.06→122.69 MiB settled RSS). A one-minute idle orchestration smoke also passed; this is not a full idle-performance classification. The reporting script was corrected afterward to exclude a post-exit zero-RSS sample, then validated by replaying the real CSV and a synthetic all-zero case. See [the durable validation summary](performance/2026-09-08-reliability-validation.md) for measurements and limits.

**Popup interaction follow-up**

At the user's request, the popup control row (full reader, pause, close) was removed. Clicking the popup toggles expansion. An explicit close discards deferred presentation requests so it cannot immediately reopen; automatic expiry still resumes interrupted passages. Full reading and pause remain available from menu-bar settings.
