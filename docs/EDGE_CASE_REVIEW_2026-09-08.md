# Dead-code and edge-case review — 8 September 2026

Scope: current local source after the requested UI/UX rollback. Read-only production review; no source, UI, interaction, or settings changes. OCR delegation supplied file selection and review rules; findings below were manually traced through current callers. The local data-access checks from the security skill were also applied. This is a focused review, not proof that every edge case is covered.

## Findings

### 1. Medium — general Quran fallback is unreachable on startup storage failure

`App/AppDelegate.swift:35` creates a verse scheduler only inside `memorizationRepository.map`. If the user database cannot open (permissions, corruption, or a filesystem failure), the scheduler is nil and all automatic verse reminders stop. `VerseScheduler` supports a nil memorization repository, and `RecoveryTests.testUnavailableMemorizationStillSelectsVerifiedQuran` tests that library behavior, but startup never uses it. Restoring AppDelegate during the UI rollback restored this dependency too.

Recommendation: decouple scheduler construction from memorization availability while retaining the existing screens. The existing startup error text says reminders are disabled; enabling fallback would also require making that message accurate. This is therefore a behavior change to approve separately, not dead-code removal.

Evidence: direct initialization-path trace plus existing library fallback test. A live corrupted-user-database launch was not performed.

### 2. Medium — a verse deadline can replace a prayer alert immediately

`App/UI/Notch/NotchViewModel.swift:121` and `:131` both assign to the same `content` property unconditionally. A prayer callback followed by a verse callback replaces the prayer card and its persisted last-shown record. The prayer does not necessarily remain visible for its 12-second interval. This is restored original behavior, not a new regression introduced in this review.

Recommendation: add a deterministic same-deadline test before considering any timing policy. Preserving a prayer until dismissal/expiry changes interaction timing, so leave the implementation untouched under the current request.

Evidence: synchronous callback/state assignment trace; the retained app tests do not cover competing prayer and verse callbacks.

### 3. Medium — replayed prayer text still describes the event as current

`App/UI/Notch/NotchViewModel.swift:147` restores the old prayer event; `App/UI/Notch/NotchContentView.swift:146` formats it using only the prayer name and reminder offset. An hours-old alert can still say “حان الآن وقت صلاة …”, or that a fixed number of minutes remain. `App/UI/MenuBar/PopoverContentView.swift:184` duplicates this formatting. The stored event date exists but is not used to distinguish replay text.

Recommendation: distinguish historical and live messages in the existing layout, if later authorized. This would change visible text, so no change was made.

Evidence: direct restoration and formatting trace; no live replay session was performed.

### 4. Low — time-dependent menu content has no clock-driven refresh

`App/UI/MenuBar/PopoverContentView.swift:378` computes prayer times from `Date()` when SwiftUI evaluates the view; relative history text similarly uses `Date()` at line 177. Time passing alone does not invalidate the view. With verse reminders and prayer notifications disabled and no settings changes, a menu held open across midnight can keep showing the previous day's values until another render is triggered.

Recommendation: verify with a controlled clock test and then refresh the existing values on day changes while the menu is visible. No layout change is needed. Do not add perpetual background polling.

Evidence: absence of a clock/notification subscription in the menu; live midnight behavior remains unverified and AppKit redraws can incidentally mask the issue.

### 5. Low — rollback left methods with no production caller

- `Packages/AyahKit/Sources/AyahKit/Memorization/MemorizationRepository.swift:228`: `deleteReturningSet` and `restore` are now used only by tests. The app calls the original `delete(id:)`, so transactional undo support is not active in the app.
- `Packages/AyahKit/Sources/AyahKit/Memorization/MemorizationAccess.swift:17`: `retry()` and its reopen closure are exercised only by tests. Production constructs the wrapper without a reopen closure and does not observe its published error messages.
- Published load/save error properties in `SettingsStore` and `LastShownStore` have no production error consumer. Retaining diagnostic error values is useful; the extra observation mechanism is currently unused.

Recommendation: remove the unused undo/retry feature surface and its feature-only tests if it is no longer planned, or explicitly document it as library-only support. Keep the active fetch/cursor path, settings recovery, and useful error diagnostics. These are cleanup candidates, not current crashes.

`MemorizationAccess` as a whole is NOT dead: `VerseScheduler` calls its fetch and cursor methods. `startDue` is NOT dead either: `start` wraps it. Location measurement metadata is actively saved and decoded. Do not remove these merely because the removed UI no longer references them.

## Checks and limits

Current checks: call-site searches across App and AyahKit sources/tests; startup and timer callback traces; SQLite parameter binding and persisted-row validation review; existing core and hosted app test suites. No confirmed security vulnerability was identified in the inspected data-access paths. No production code was edited. Validation completed: 143 core tests and 18 hosted app tests passed with zero failures; the Debug app built successfully. `git diff --check` passed. Logs: `/tmp/ayah-edge-review-core.log` and `/tmp/ayah-edge-review-app.log`. These are existing regression tests, not new reproductions of the reported edge cases.

Long-text layout, VoiceOver, real permission dialogs, physical notch behavior, and overnight menu rendering were not exercised in this pass. Existing tests passing does not resolve the findings above, especially the gap between library support and app wiring.
