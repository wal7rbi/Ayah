# Ayah 1.0.1 stable release checklist

An unchecked item remains outstanding and must not be treated as a pass.
Record the date, macOS version, Mac model, operator, result, and evidence for
each manual run.

## Automated gate

- [ ] Clean release commit with annotated tag `v1.0.1`.
- [ ] `Scripts/run_release_candidate_checks.sh --idle-minutes 30 --ui-cycles 200` passes with zero automated failures.
- [x] All tests, Debug/Release builds, Quran/GeoNames verification, resource checks, arm64 check, hardened ad-hoc signature, and entitlement allowlist pass.
- [ ] Final DMG and uploaded download both match the `.sha256` file.

## Last Shown and Replay

- [x] Last Shown appears after a verse and Replay presents it again on the test Mac (operator-confirmed 2026-09-01).
- [x] Last Shown survives quitting and reopening Ayah (operator-confirmed from the 1.0.1 rehearsal DMG on 2026-09-01).
- [ ] Prayer-alert content, with and without an ayah, replays correctly.
- [ ] A new item replaces the previous Last Shown item.
- [ ] No-notch fallback and physical-notch presentation both work.

## Regression checks

- [ ] First launch, menu-bar popover, verse display, settings, and relaunch persistence.
- [ ] Memorization create/edit/enable/disable/delete and persistence.
- [ ] City selection, current location, and representative prayer calculations.
- [ ] Prayer reminders at-time and before-time.
- [ ] Sleep/wake and manual clock/time-zone changes rearm schedules correctly.
- [ ] Launch-at-login behavior.
- [ ] Arabic RTL layout, keyboard traversal, and VoiceOver.
- [ ] External display and display-configuration changes.

## Distribution checks

- [ ] Release title, tag, version, and filenames are exactly `1.0.1` / `v1.0.1` / `Ayah-1.0.1-macOS-arm64.dmg`.
- [ ] Release notes clearly state Apple Silicon, macOS 13+, ad-hoc signing, and no notarization.
- [ ] Fresh GitHub download follows the documented Privacy & Security > Open Anyway path.
- [ ] Installed app launches, opens About, requests location only after user action, and relaunches successfully.

## Release decision

- Decision: **APPROVED FOR PUBLICATION**
- Operator: wal7rbi
- Approval date: 2026-09-01
- Apple Developer account: **not used**
- Signature: ad-hoc with hardened runtime
- Notarization: none
- Manual approval record: `QA_APPROVAL_1.0.1.md`.
