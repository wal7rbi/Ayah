# Ayah 1.0.1 release approval

- Date: 2026-09-01
- Operator: wal7rbi
- Decision: approved to package and publish `v1.0.1`
- Distribution: public GitHub release
- Signature: ad-hoc with hardened runtime
- Apple Developer ID: none
- Notarization: none

The operator tested the `1.0.1` rehearsal DMG, confirmed that Last Shown and
Replay work, confirmed that Last Shown remains usable after relaunch, merged
the release-preparation pull request after its GitHub checks passed, and then
explicitly stated: **“I approve publishing Ayah 1.0.1.”**

Automated release-candidate runs passed the full AyahKit suite, Quran and
GeoNames integrity checks, Debug and Release builds, arm64 validation,
ad-hoc-signature verification, entitlement allowlisting, bundled-resource
checks, popover RSS stress checks, and idle resource checks. The final stable
packager must repeat its full automated gate from the exact annotated release
tag before the artifact is published.

Unchecked hardware, accessibility, and fresh-profile items in
`RELEASE_CHECKLIST_1.0.1.md` remain outstanding evidence. This approval does
not silently convert those unchecked items into passes. The release notes and
installation instructions disclose that the app has no Developer ID signature
and is not notarized, and direct users to macOS's per-app **Open Anyway** flow.
