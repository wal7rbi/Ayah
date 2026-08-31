# Ayah 1.0.0 stable release checklist

This checklist records both the original release gates and post-publication
acceptance. An unchecked item remains outstanding evidence and must not be
treated as an assumed pass. Record the date, macOS version, Mac model,
operator, result, and evidence location for each manual run.

## Automated gate

- [x] Clean release commit with annotated tag `v1.0.0`.
- [ ] `Scripts/run_release_candidate_checks.sh --idle-minutes 30 --ui-cycles 200` passes with zero automated failures.
- [ ] All tests, Debug/Release builds, Quran/GeoNames verification, resource checks, arm64 check, hardened ad-hoc signature, and entitlement allowlist pass.
- [x] Final DMG and published download both match the `.sha256` file.

## Supported-system matrix

- [x] Apple Silicon Mac running macOS 13, tested from a fresh user account.
- [x] Apple Silicon Mac running the current macOS release, tested from a fresh user account.
- [x] Physical notch presentation and interaction.
- [x] No-notch fallback presentation.
- [x] External display and display-configuration changes.

## Core behavior

- [x] First launch, menu-bar popover, verse display, settings changes, and relaunch persistence.
- [x] Memorization create, edit, enable/disable, delete, and persistence.
- [x] City selection and representative prayer calculations.
- [x] Current-location allow, deny, retry, refresh, and stale-location disclosure.
- [x] Prayer reminders at-time and before-time.
- [x] Sleep/wake and manual clock/time-zone changes rearm schedules correctly.
- [x] Launch-at-login enable, approval-required, disable, logout/login, and relaunch behavior.

## About, accessibility, and language

- [x] `حول التطبيق` closes the popover and reuses one About window.
- [x] Version/build are correct and bundle-derived.
- [x] KFGQPC Quran/font, Adhan Swift, and GeoNames credits are visible and accurate.
- [x] Independence/no-endorsement and Quran-text licensing caveat are visible.
- [x] Every HTTPS source/license link opens the expected page in the default browser.
- [x] Acknowledgements open in-app and remain selectable/scrollable.
- [x] Arabic RTL layout, English LTR block, keyboard traversal, Escape, and Command-L work.
- [x] VoiceOver labels, reading order, links, controls, and window transitions are usable.

## Published-download acceptance

- [x] GitHub release title/tag/version and uploaded filenames are exact.
- [x] Release notes clearly say Apple Silicon, macOS 13+, ad-hoc signed, and unnotarized.
- [ ] A fresh download is quarantined and follows the documented Privacy & Security > Open Anyway path.
- [ ] Installed app launches, requests location only after user action, opens About, and relaunches successfully.

## Release decision

- Original decision: **APPROVED FOR PRIVATE LIMITED RELEASE**
- Operator: wal7rbi
- Date: 2026-08-30
- Release commit: commit referenced by annotated tag `v1.0.0`
- Evidence: `docs/release/QA_APPROVAL_1.0.0.md`
- Public distribution authorized by wal7rbi on 2026-08-31.
- Current status: **PUBLISHED PUBLICLY**; the two unchecked fresh-profile
  acceptance items above remain explicitly outstanding.
