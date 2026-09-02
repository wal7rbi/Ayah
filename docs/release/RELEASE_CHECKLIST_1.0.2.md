# Ayah 1.0.2 stable release checklist

An unchecked item remains outstanding and must not be treated as a pass.
Record the date, macOS version, Mac model, operator, result, and evidence for
each manual run.

Every box starts unchecked. Nothing carries over from `RELEASE_CHECKLIST_1.0.1.md`:
1.0.2 changes prayer-time resolution, the bundled city database, and the launch
alerts, so a 1.0.1 pass is not evidence about this build.

## Automated gate

- [ ] Clean release commit with annotated tag `v1.0.2`.
- [ ] `Scripts/run_release_candidate_checks.sh --idle-minutes 30 --ui-cycles 200` passes with zero automated failures.
- [ ] The gate's `App test suite` and `GeoNames bundled checksum` steps both
      appear in the report and pass. Both are new in 1.0.2; a report without
      them was produced by a stale script.
- [ ] `.github/workflows/quran-integrity.yml` passes on the release commit in
      GitHub Actions, observed in the web UI — not inferred from a local run.
      This includes the App test step, which has never been observed on a
      hosted runner.
- [ ] Final DMG and uploaded download both match the `.sha256` file.

## Prayer-time correctness (the substance of this release)

- [ ] With a city whose time zone differs from the Mac's, the popover's six
      rows match what the alerts actually fire at. Verify on at least one
      far-away city, not only a local one.
- [ ] A city selected before upgrading still shows correct times after
      upgrading — settings migrate rather than reset.
- [ ] Current-location mode still resolves and shows times, and still requests
      permission only on an explicit tap.
- [ ] Prayer alerts fire at the right moment for both the reminder offset and
      the exact prayer time.
- [ ] Sleep/wake and manual clock/time-zone changes rearm schedules correctly.

## City names and data

- [ ] Previously-Latin cities render in Arabic in the picker, right-aligned,
      with the country code on the left. Spot-check across regions —
      e.g. عنيزة (SA), برشيد (MA), ود مدني (SD).
- [ ] Cities with no Arabic name still render in Latin without visual glitches
      in the right-to-left list. This is correct behaviour, not a gap.
- [ ] Search finds a city by both its Latin and Arabic name.
- [ ] **The curated Arabic names have been reviewed by a native speaker**, or
      the release notes' "Known limitation" section is accepted as-is with
      that review still outstanding. Record which.

## Launch alerts

- [ ] The three launch failure alerts render in Arabic, right-aligned, with a
      موافق button. Induce at least one against a copy of the built app rather
      than assuming — do not modify the real build product.

## Regression checks

- [ ] First launch, menu-bar popover, verse display, settings, and relaunch persistence.
- [ ] Last Shown appears after a verse, and Replay presents it again.
- [ ] Last Shown survives quitting and reopening Ayah.
- [ ] Prayer-alert content, with and without an ayah, replays correctly.
- [ ] A new item replaces the previous Last Shown item.
- [ ] Memorization create/edit/enable/disable/delete and persistence.
- [ ] Launch-at-login behavior.
- [ ] No-notch fallback and physical-notch presentation both work.
- [ ] Arabic RTL layout, keyboard traversal, and VoiceOver.
- [ ] External display and display-configuration changes.

## Distribution checks

- [ ] Release title, tag, version, and filenames are exactly `1.0.2` / `v1.0.2` / `Ayah-1.0.2-macOS-arm64.dmg`.
- [ ] The built app reports `1.0.2` / build `3`.
- [ ] `README.md`'s download button, filename, and `shasum` example all point
      at 1.0.2. These are deliberately left at 1.0.1 until publication, so
      they must be updated as part of this release.
- [ ] Release notes clearly state Apple Silicon, macOS 13+, ad-hoc signing, and no notarization.
- [ ] Fresh GitHub download follows the documented Privacy & Security > Open Anyway path.
- [ ] Installed app launches, opens About, requests location only after user action, and relaunches successfully.

## Release decision

- Decision: **NOT YET APPROVED**
- Operator:
- Approval date:
- Apple Developer account: **not used**
- Signature: ad-hoc with hardened runtime
- Notarization: none
- Manual approval record: `QA_APPROVAL_1.0.2.md` (to be written on approval).
