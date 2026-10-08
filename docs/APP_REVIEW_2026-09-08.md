**Ayah: product and codebase review — 8 September 2026**

Reviewed revision: `681f597`. The working tree was clean before the review. This report and its two diagnostic evidence files are the only lasting changes; production code and existing tests are unchanged.

**Overall judgment**

Ayah has a coherent purpose and a sound technical foundation: an Arabic, private, native macOS companion that brings Quran passages and prayer reminders into the user's working day. Its strongest qualities are Quran integrity, limited permissions, a small dependency footprint, and event-driven scheduling. These are concrete implementation choices, not merely marketing statements.

The next release should concentrate on reading quality and reminder reliability. Several ordinary user journeys still produce misleading information or lose useful context. The memorization feature is currently a weighted exposure and sequential repetition tool; it does not yet establish whether the user has learned a passage. That is a reasonable v1 scope, but future product decisions should acknowledge the distinction.

This assessment establishes neither market demand nor religious certification. Product suggestions below are design judgments based on the implemented experience, rather than user-research findings. No critical security vulnerability was confirmed in the inspected runtime paths.

**What I inspected and verified**

I traced app startup, repository initialization, Quran verification, settings persistence, memorization CRUD and cursor updates, both schedulers, location resolution, popup presentation, replay, settings and management views, CI, and release scripts. I also reviewed the existing release/performance evidence. OCR 1.8.8 was available; I retrieved its default correctness/security/performance review rules and performed the review directly. This was not an OCR-managed LLM scan or a formal exhaustive security assessment.

Fresh checks in this session:

| Check | Result | What it establishes |
|---|---|---|
| Existing AyahKit suite | 129 tests passed, zero failures | Core regression tests pass on this machine |
| Existing app suite and Debug build | 17 tests passed, zero failures | App builds and existing hosted state/presentation tests pass |
| Two temporary diagnostic probes | Both passed by asserting the problematic current behavior | Old invalid-accuracy locations are accepted; a polar-summer calculation produces no events |
| Bundled Quran verifier | 114 surahs, 6,236 ayahs; checksum and manifest passed | Committed dataset matches the repository's approved integrity records |
| SQLite integrity checks | Both databases returned `ok` | No SQLite structural corruption detected |
| GeoNames SHA-256 | Matches committed checksum; 4,659 cities | City artifact matches the expected local file |

The diagnostic probes are preserved in [ReviewProbeTests.swift](/Users/waleedalharbai/myproject/Ayah/docs/review-2026-09-08/ReviewProbeTests.swift), with [results](/Users/waleedalharbai/myproject/Ayah/docs/review-2026-09-08/probe-results.txt). They are deliberately outside the test target: they demonstrate current defects, rather than define the behavior a fix should preserve.

Full fresh logs are ephemeral: `/tmp/ayah-review-package-tests.log`, `/tmp/ayah-review-app-tests.log`, and the `.xcresult` under `/tmp/ayah-review-derived/Logs/Test/`. The test build emitted warnings about the installed XCTest framework targeting a newer macOS than the app's deployment target; passing here does not verify macOS 13 compatibility.

I did not conduct a live visual walkthrough, VoiceOver session, physical clamshell/display test, fresh quarantined installation, or new Release packaging run. Visual risks are labeled accordingly. I did not re-download the authoritative Quran source or verify remote CI/branch protection. A green workflow file alone cannot prove that merging is protected.

**What is good, why it matters, and how to preserve it**

| Area | What is good and why | Improvement direction |
|---|---|---|
| Product focus | Quran reminders, selected memorization passages, and prayer times fit a daily desktop routine. A menu-bar utility is an appropriate form for this scope. | Give the user one easy first-run path to a useful reminder; validate it with Arabic-speaking Mac users. |
| Quran integrity | Read-only Quran repository verifies content before use; tests exercise tampering; build and CI gates verify the dataset. This directly protects the app's most important content. | Retain the full chain when changing presentation. Add rendered long-passage coverage; textual integrity does not guarantee readable display. |
| Privacy | Runtime source has no identified networking calls, and source entitlements request sandbox and opt-in location without network access. This reduces both exposure and maintenance burden. | Keep manual city selection as the permission-free default. Preserve the clear disclosure that macOS location services may use networking outside the app. |
| Architecture | AppKit/SwiftUI presentation is separated from AyahKit repositories/calculators/schedulers. Shared location resolution prevents UI and alerts from using separate rules. | Add a small presentation coordinator and explicit feature/error states where needed; no rewrite is justified. |
| Scheduling | One-shot timers, generation guards, cancellation, clock/time-zone handling, and wake rearming are substantially better than frequent polling. | Keep the event-driven design; add collision and unavailable-calculation recovery behavior. |
| Mutable data | Bound SQLite parameters, range checks, row validation, and partial updates protect against malformed values and stale editor snapshots. | Surface failures consistently and make delete recoverable. |
| Persistence | Last-shown records store identifiers instead of duplicated Quran text; replay resolves through verified data. Settings tolerate individual missing/invalid fields. | Separate historical presentation from live wording and provide visible recovery when a whole settings blob fails. |
| Tests | Fake timers and location managers make difficult lifecycle paths testable. The fresh 146-test baseline passed. | Expand around the specific missing behaviors below, rather than adding tests that merely mirror getters. |
| Performance | Initialization caches and low-frequency work are proportionate to roughly 6,000 verses and 4,700 cities. Existing local release evidence reports stable idle memory and no settled growth after 200 popover cycles. | Preserve reproducible baselines in versioned documentation and measure before optimizing. |
| Distribution honesty | Documentation clearly states arm64-only, ad-hoc signing, no notarization, and manual checks that were not performed. | Complete and record hardware/accessibility/install checks. Developer ID signing is an optional future distribution decision, consistent with budget and policy. |

Performance evidence deserves a precise limit: the earlier 30-minute run reports sampled CPU rounded to 0.000% and memory from 30 to 21 MiB; the earlier popover run reports settled RSS from 123.18 to 101.61 MiB. These are previous local observations, not fresh measurements or proof of zero battery cost. Raw reports currently live under ignored `dist/`, while the performance README links to a baseline file not present in this checkout. Commit a compact revision-tagged summary with method, environment, and uncertainty so future comparisons survive cleanup.

**Priority findings**

P1 means resolve before treating the relevant behavior as reliable. P2 means a meaningful follow-up improvement. These are product/correctness priorities, not claims of security exploit severity.

**1. P1 — Historical prayer alerts still announce “now” or “five minutes remaining.”**

Evidence: [NotchViewModel.swift:147](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchViewModel.swift:147), [NotchContentView.swift:146](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchContentView.swift:146), [PopoverContentView.swift:184](/Users/waleedalharbai/myproject/Ayah/App/UI/MenuBar/PopoverContentView.swift:184).

The saved event is resolved unchanged on replay. Both message formatters use only the stored reminder offset; neither checks the current time or distinguishes history from a live alert. Replaying yesterday's Asr alert therefore says prayer time is now, and an expired five-minute reminder still says five minutes remain. The popover has a historical heading, but the replayed popup lacks that context.

Why it matters: users may mistake a historical card for a current prayer reminder.

Improve: introduce live versus historical presentation context. Historical cards should show the prayer name and original date/time, with an explicit replay label. Derive live countdown wording from the event time when appropriate. Share the formatter between popup and popover.

Acceptance: replay an at-time alert a day later and a five-minute reminder ten minutes later. Both must communicate historical context, and neither may claim the event is happening now. Preserve the original saved timestamp.

**2. P1 — A verse can replace a prayer alert before the user reads it.**

Evidence: [NotchViewModel.swift:121](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchViewModel.swift:121) and [NotchViewModel.swift:131](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchViewModel.swift:131).

The independent scheduler callbacks both assign `content`, overwrite last-shown storage, and restart collapse timing. If the verse deadline follows the prayer deadline, the verse immediately replaces the prayer card. Mutual exclusivity of the content enum prevents two cards from being active, but does not establish priority or a reading window. This is a direct code-path finding; the existing hosted tests do not exercise both schedulers together.

Why it matters: the more time-sensitive reminder can disappear almost immediately and also become unavailable from last-shown replay.

Improve: prioritize an active prayer card for a minimum dwell period and defer a pending verse. Coordinate selection with display so deferred or discarded verses do not advance the memorization cursor without being presented. Define the reverse collision and manual replay policy explicitly.

Acceptance: fire both fake timers in both orders and one second apart. The prayer remains readable, no pending content is lost unintentionally, and cursor advancement reflects the selected presentation policy.

**3. P1 — Reading space and duration do not adapt to Quran passage length.**

Evidence: [LayoutMetrics.swift:24](/Users/waleedalharbai/myproject/Ayah/App/UI/LayoutMetrics.swift:24), [NotchContentView.swift:87](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchContentView.swift:87), [NotchViewModel.swift:55](/Users/waleedalharbai/myproject/Ayah/App/UI/Notch/NotchViewModel.swift:55).

The card is fixed at 480×220 points. Verse text permits shrinking from 22 points to 35% (7.7 points); prayer verse text permits 18 points to 40% (7.2 points). Both impose line limits, and every card collapses after 12 seconds. The bundled 2:282 text contains 1,190 SQLite characters. The last-shown preview also limits lines, and replay uses the same constrained card.

Why it matters: preserving every source character is insufficient if a passage is too small to read or disappears before the user finishes. Exact clipping and diacritic behavior still need visual reproduction; the fixed dimensions, scale floors, line limits, and time limit are confirmed in source.

Improve: set a readable minimum size, offer an explicit full-passage reader with scrolling, and provide a pin/pause action or configurable display duration. The popup may summarize the reference while providing complete, unmodified text in the reader. Avoid shortening or normalizing the authoritative Quran string.

Acceptance: visually inspect 2:282, long consecutive batches, short surahs, and prayer-card passages in both physical-notch and floating modes. Every passage must be fully accessible at a readable size. Verify keyboard and VoiceOver access to the full-reader action.

**4. P1 — Location freshness and quality are discarded.**

Evidence: [CurrentLocationProvider.swift:142](/Users/waleedalharbai/myproject/Ayah/Packages/AyahKit/Sources/AyahKit/Prayer/CurrentLocationProvider.swift:142), [CurrentLocationViewModel.swift:30](/Users/waleedalharbai/myproject/Ayah/App/UI/Prayer/CurrentLocationViewModel.swift:30), [PopoverContentView.swift:396](/Users/waleedalharbai/myproject/Ayah/App/UI/MenuBar/PopoverContentView.swift:396).

The provider validates coordinate ranges, but accepts locations without checking their measurement time or horizontal accuracy. Its return type strips that metadata. The view model then records `Date()` as the freshness timestamp. An isolated probe confirmed acceptance of a location dated 1970 with negative horizontal accuracy. Apple defines the location timestamp as the time the position was determined; it is distinct from when the app receives it ([Apple documentation](https://developer.apple.com/documentation/corelocation/cllocation/timestamp)).

Even legitimate old saved locations are displayed using time-of-day only (`dateStyle = .none`), so a fix saved weeks ago can look like a recent update. Coordinates are also paired with the Mac's current time zone without showing or confirming that assumption.

Why it matters: old or unsuitable input can be presented as fresh and used for prayer times, especially after travel or with a manually configured system zone.

Improve: return a location-fix value containing coordinates, measurement timestamp, and accuracy. Reject invalid accuracy and apply a documented freshness/quality policy. Display full or relative age and the effective time zone. When it is uncertain, let users choose a city or confirm the zone; preserve the one-shot privacy model.

Acceptance: old and invalid fixes must not be reported as freshly measured; test a valid fresh fix, a previous-day fix, invalid accuracy, travel, and a system-zone mismatch. The acceptance probe should become a rejection regression test after the fix.

**5. P2 — Unavailable prayer calculations look like missing location and can leave scheduling dormant.**

Evidence: [PrayerAlertScheduler.swift:140](/Users/waleedalharbai/myproject/Ayah/Packages/AyahKit/Sources/AyahKit/Scheduling/PrayerAlertScheduler.swift:140) and [PopoverContentView.swift:227](/Users/waleedalharbai/myproject/Ayah/App/UI/MenuBar/PopoverContentView.swift:227).

The probe confirms that Tromsø coordinates on 21 June 2026 with the current default method produce no prayer events. When the scheduler finds no events across its two-day window, it returns without scheduling another attempt. Wake, settings, or clock changes can restart it, but an uninterrupted running session has no date-based recovery. The UI uses the same “select a city/get current location” prompt for absent location and calculation failure.

Why it matters: users with valid coordinates receive an ineffective instruction and may see no alerts without an explanation.

Improve: distinguish missing location, invalid input, and unavailable calculation. Schedule one future retry at an appropriate local day boundary when calculation is unavailable. If supporting extreme latitudes, choose and explain a reviewed calculation policy; do not invent fallback religious times silently.

Acceptance: fake-clock tests should cross a period with no events into a valid date without a settings change. The UI should explain the actual state. This finding does not claim that Adhan's failure to calculate polar solar events is itself a library defect.

**6. P2 — A memorization storage failure disables ordinary Quran reminders too.**

Evidence: [AppDelegate.swift:35](/Users/waleedalharbai/myproject/Ayah/App/AppDelegate.swift:35).

The verse scheduler exists only if both Quran and memorization repositories initialize. A locked, unreadable, or unusable user database disables the core verse feature despite the verified bundled Quran remaining available. The startup alert explains this behavior, so it is an availability/design issue rather than a silent failure.

Improve: let general-pool selection run with a clear “memorization unavailable” state. Keep the existing database untouched and provide retry/recovery. Do not reset or delete user progress automatically.

Acceptance: force user-database initialization to fail. Verified ordinary verses still appear, prayer features remain usable where possible, and the app visibly reports the memorization limitation.

**7. P2 — Several recoverable errors never reach the relevant user interface.**

Evidence: [SettingsStore.swift:25](/Users/waleedalharbai/myproject/Ayah/Packages/AyahKit/Sources/AyahKit/Settings/SettingsStore.swift:25), [VerseScheduler.swift:41](/Users/waleedalharbai/myproject/Ayah/Packages/AyahKit/Sources/AyahKit/Scheduling/VerseScheduler.swift:41), [MemorizationSetsView.swift:197](/Users/waleedalharbai/myproject/Ayah/App/UI/Memorization/MemorizationSetsView.swift:197).

A malformed top-level settings blob falls back to defaults and records `lastLoadError`, but no app caller consumes that error. Cursor persistence and last-shown errors are similarly recorded without a user-facing status. Separately, editor-save failures set a message in the parent view while the editing sheet remains open; the sheet itself receives no error state.

Why it matters: users may see unexplained reset settings, repeating memorization passages, or an apparently unresponsive Save action.

Improve: expose a small observable health/status model for actionable failures, preserve recoverable original data, and put sheet save errors inside the sheet. Distinguish a fetch failure from an intentionally empty memorization list. Settings encode errors do not prove disk persistence failure; describe the actual failure precisely.

Acceptance: inject malformed settings and a failed cursor write; show an appropriate message without claiming progress saved. Force an editor-save failure and verify the explanation is visible while editing.

**8. P2 — Memorization management needs better accessibility and recovery.**

Evidence: [MemorizationSetsView.swift:130](/Users/waleedalharbai/myproject/Ayah/App/UI/Memorization/MemorizationSetsView.swift:130) and [MemorizationSetsView.swift:156](/Users/waleedalharbai/myproject/Ayah/App/UI/Memorization/MemorizationSetsView.swift:156).

Each enabled toggle has an empty label, and the trash button has no explicit contextual label identifying its set. Delete is immediate, with no undo path or confirmation. A symbol may receive a generic system accessibility label, but it still does not identify the affected Quran range. This is a source-level accessibility gap; actual VoiceOver traversal was not evaluated.

Improve: label controls with action and surah/range, make deletion undoable or confirm it, and preserve progress in any undo operation. Add a keyboard-accessible workflow through list, editor, save, and close.

Acceptance: a VoiceOver user can identify which set they are enabling or deleting; an accidental delete can be recovered. Test the real interaction, not just the existence of accessibility modifiers.

**Product improvements after the reliability work**

1. Make first use successful in under a minute. Explain the menu-bar entry point, preview a passage, and offer prayer-city setup when the user enables alerts. A small inline guide is sufficient; avoid a long onboarding wizard. Show that alerts require the app to be running, and present launch-at-login next to that explanation.
2. Support uninterrupted reading. Add full passage, pause/resume, and a useful display-duration preference. A temporary snooze can reduce interruptions during work. Validate these controls with users before adding more settings.
3. Make memorization intentional. Add “whole surah” and direct start/end entry: the current stepper-only editor makes long ranges cumbersome. Then consider optional “repeat this passage,” “next passage,” and simple local review feedback. Weighted exposure alone should not be described as measured mastery. Existing ease-factor/review-interval fields are not evidence of an implemented spaced-repetition workflow.
4. Clarify prayer context. Show the selected location/zone, today's date, next prayer, and whether reminders are active. Avoid second-by-second background polling; update only while relevant UI is visible and on meaningful boundaries.
5. Preserve the compact scope. Accounts, cloud synchronization, AI features, social feeds, and analytics would impose substantial maintenance and privacy costs without addressing the identified problems. Add them only if user research establishes a need.
6. Test Arabic reading with people. Ask users to read a long ayah, create a whole-surah set, find their city, replay a missed reminder, and recover from a mistake. Record completion and confusion manually with consent; the app need not add telemetry.

**Maintenance and release improvements**

- Update stale comments describing settings as unbuilt and GeoNames as lacking a checksum. Several comments recount old implementation stages; retain current contracts near code and move historical rationale to documentation.
- Centralize prayer-card wording and reference formatting to prevent the popup and history UI diverging. Keep independent integrity checks independent where they provide useful cross-validation.
- Record a versioned performance summary instead of relying on ignored local `dist/` output and absent baseline links. Use Instruments for wakeup/energy claims; sampled CPU and RSS cannot establish those alone.
- Verify the minimum supported macOS version, hardware display transitions, VoiceOver, actual launch-at-login approval, and a fresh quarantined install. The existing release validation correctly marks these as unverified; preserve that honesty.
- Keep package resolutions consistent and review dependency updates deliberately. The manifest allows compatible versions from 1.5.0, while lockfiles record a resolved version; reproducibility comes from honoring those resolutions, not from the version range alone.

**Suggested delivery order**

| Phase | Work | Completion evidence |
|---|---|---|
| First correctness patch | Historical wording, prayer/verse priority, location metadata/age | Focused fake-clock/timer/location tests plus a replay walkthrough |
| Reading and recovery | Full-passage access, duration/pause, storage fallback, visible save errors | Long-passage visual checks and injected storage-failure scenarios |
| Prayer edge cases and accessibility | Unavailable-calculation status/retry, contextual controls, undo | High-latitude date transition tests and real keyboard/VoiceOver sessions |
| Product refinement | Faster set creation, optional guided setup, manual user evaluation | Users complete the core tasks without assistance |
| Release evidence | Oldest-supported OS, hardware/install/login checks, durable performance summary | Revision-specific recorded results, with remaining unknowns explicit |

The architecture is strong enough to evolve incrementally. Fix the reminder and reading contracts first; these improvements strengthen the app's existing idea more than adding a larger feature set would.
