# Ayah 1.0.0 stable release checklist

Every item below is a release blocker. Record the date, macOS version, Mac
model, operator, result, and evidence location for each manual run before using
`--manual-qa-approved`.

## Automated gate

- [ ] Clean release commit with annotated tag `v1.0.0`.
- [ ] `Scripts/run_release_candidate_checks.sh --idle-minutes 30 --ui-cycles 200` passes with zero automated failures.
- [ ] All tests, Debug/Release builds, Quran/GeoNames verification, resource checks, arm64 check, hardened ad-hoc signature, and entitlement allowlist pass.
- [ ] Final DMG and published download both match the `.sha256` file.

## Supported-system matrix

- [ ] Apple Silicon Mac running macOS 13, tested from a fresh user account.
- [ ] Apple Silicon Mac running the current macOS release, tested from a fresh user account.
- [ ] Physical notch presentation and interaction.
- [ ] No-notch fallback presentation.
- [ ] External display and display-configuration changes.

## Core behavior

- [ ] First launch, menu-bar popover, verse display, settings changes, and relaunch persistence.
- [ ] Memorization create, edit, enable/disable, delete, and persistence.
- [ ] City selection and representative prayer calculations.
- [ ] Current-location allow, deny, retry, refresh, and stale-location disclosure.
- [ ] Prayer reminders at-time and before-time.
- [ ] Sleep/wake and manual clock/time-zone changes rearm schedules correctly.
- [ ] Launch-at-login enable, approval-required, disable, logout/login, and relaunch behavior.

## About, accessibility, and language

- [ ] `حول التطبيق` closes the popover and reuses one About window.
- [ ] Version/build are correct and bundle-derived.
- [ ] KFGQPC Quran/font, Adhan Swift, and GeoNames credits are visible and accurate.
- [ ] Independence/no-endorsement and Quran-text licensing caveat are visible.
- [ ] Every HTTPS source/license link opens the expected page in the default browser.
- [ ] Acknowledgements open in-app and remain selectable/scrollable.
- [ ] Arabic RTL layout, English LTR block, keyboard traversal, Escape, and Command-L work.
- [ ] VoiceOver labels, reading order, links, controls, and window transitions are usable.

## Published-download acceptance

- [ ] GitHub release title/tag/version and uploaded filenames are exact.
- [ ] Release notes clearly say Apple Silicon, macOS 13+, ad-hoc signed, and unnotarized.
- [ ] A fresh download is quarantined and follows the documented Privacy & Security > Open Anyway path.
- [ ] Installed app launches, requests location only after user action, opens About, and relaunches successfully.

## Release decision

- Decision: **PENDING**
- Operator:
- Date:
- Release commit:
- Evidence directory:
