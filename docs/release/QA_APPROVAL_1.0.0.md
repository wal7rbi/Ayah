# Ayah 1.0.0 manual QA approval

- Date: 2026-08-30
- Operator: wal7rbi
- Distribution scope: private GitHub repository, limited external testing
- Decision: approved to package and publish `v1.0.0`

The operator confirmed in the release task that the manual QA checklist was
completed and explicitly approved the `v1.0.0` release. This repository record
captures that attestation. Raw screenshots and device logs were not supplied
for inclusion in the repository.

Published-download acceptance remains a post-publication activity: the final
DMG must still be downloaded from GitHub on a fresh macOS user profile, its
checksum verified, and its quarantine, installation, first-launch, About,
location, and relaunch behavior recorded.

## Post-publication update — 2026-08-31

- The repository and `v1.0.0` release were made public by wal7rbi.
- The published DMG was repackaged from the already-released `Ayah.app` to
  contain only the app and the Applications shortcut. No application binary
  or bundled resource was rebuilt or changed.
- A fresh GitHub CLI download matched its published SHA-256 file, passed
  `hdiutil verify`, retained a valid ad-hoc code signature, and mounted with
  exactly `Ayah.app` and `Applications` at the volume root.
- Current DMG SHA-256:
  `de1ee580e7c308f723a49085b000beadb717928affa0cd40a84ad631b579cfa0`.

GitHub CLI download verification does not exercise Finder quarantine or a
fresh macOS user profile. The quarantine, first-launch, location, About, and
relaunch acceptance steps therefore remain outstanding rather than being
inferred from the artifact checks above.
