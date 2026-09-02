# Ayah 1.0.2 release approval

- Date: 2026-09-02
- Operator: wal7rbi
- Decision: approved to package and publish `v1.0.2`
- Distribution: public GitHub release
- Signature: ad-hoc with hardened runtime
- Apple Developer ID: none
- Notarization: none

The operator was given the `1.0.2` rehearsal DMG
(`Ayah-1.0.2-macOS-arm64-REHEARSAL-20260902T174507Z.dmg`), stated that they
had tested it, and approved publication.

**Scope of that statement, recorded precisely.** The operator did not
enumerate which checks they performed, and none were witnessed here. This
approval therefore records an operator decision, not a per-item pass. The
individual boxes in `RELEASE_CHECKLIST_1.0.2.md` that depend on manual
verification are left unchecked for that reason, and must not be read as
passes. Anyone auditing this release later should treat the automated
evidence below as the only itemized evidence that exists for it.

## Automated evidence

`Scripts/run_release_candidate_checks.sh --idle-minutes 30 --ui-cycles 200`
passed with **zero automated failures** at revision `19de0c5`, covering:
SQLite integrity and row counts for both bundled databases, the GeoNames
bundled-checksum cross-check, `verify_quran` including the `MANIFEST.json`
cross-check, both test suites, Debug and Release builds, arm64, ad-hoc
signature integrity, the entitlement allowlist, sealed resources, exclusion
of profiling automation from the shipping binary, 200 popover cycles
(settled RSS −2.12 MiB), and 30 minutes of idle sampling (median CPU 0.0%,
p95 0.0%, settled memory +1.00 MiB).

`.github/workflows/quran-integrity.yml` passed on the merged pull request
(run 33663596963), observed in GitHub Actions rather than inferred locally.

## Known limitation carried into this release

The curated Arabic city names added in 1.0.2 (`ArabicNameOverrides.swift`,
364 entries, of which 358 were authored rather than sourced from GeoNames)
have **not** been reviewed by a native speaker. This is disclosed in the
release notes under "Known limitation" and is accepted for this release.

## Not performed

The seven items the automated gate marks MANUAL remain outstanding:
VoiceOver, keyboard and RTL traversal; About-window credits and links;
sleep/wake and clock mutation; notch, non-notch and external-display
presentation; the launch-at-login approval flow; the Gatekeeper Open Anyway
path from a fresh quarantined download; and per-process idle-wakeup
attribution via Instruments. This approval does not convert any of them into
a pass.
