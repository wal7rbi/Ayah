**Reliability update validation — 8 September 2026**

Environment: Apple Silicon, macOS 26.6.2 (25G83), Xcode 26.3 (17C529).
Base revision: `681f597e11beed2831089ef53b6e768e6d708375`, with the uncommitted reliability changes described in `docs/IMPLEMENTATION_2026-09-08.md`.

The final release-candidate run completed with **22 automated PASS, zero failures**, and seven explicitly manual statuses. **143 core and 27 hosted app tests passed (170 total).** Both Debug and Release builds passed, as did Quran/GeoNames integrity, lockfile consistency, arm64 architecture, ad-hoc signature, sandbox/location-only release entitlements, sealed resources, and exclusion of profiling automation from the shipping build.

Raw artifacts are ephemeral: `/private/tmp/ayah-fixes-release-checks/report.md`, `results.tsv`, and `logs/`. This versioned summary preserves the observations if those files are removed. No DMG was published by these checks.

**200 popover cycles**

| Measurement | Observed result |
|---|---|
| Open/close cycles | 200, 50ms delay after each action |
| Valid samples | 101, approximately 250ms apart |
| Baseline mean RSS | 126.06 MiB, 8 samples |
| Cooldown mean RSS | 122.69 MiB, 7 samples |
| Settled RSS change | −3.37 MiB |
| Peak RSS | 126.06 MiB |
| Mean sampled CPU during cycles | 0.41% |
| Peak threads | 9 |
| Provisional RSS guardrail | Pass |

One post-exit sample reported zero RSS and exaggerated the original report's decrease. `Scripts/profile_ui_cycles.sh` now excludes invalid/nonpositive RSS samples from aggregation, reports their count, and requires valid samples in baseline, cycles, and cooldown before declaring a pass. Replaying the real captured CSV through the corrected report code produced the numbers above and excluded exactly one row. A synthetic all-zero CSV produced **Inconclusive**, not Pass. Shell syntax and diff-format checks passed after this reporting-only change; application binaries were unchanged by it.

Original raw CSV: `/private/tmp/ayah-fixes-release-checks/ui-cycles/samples.csv`.
Corrected raw report: `/private/tmp/ayah-fixes-release-checks/ui-cycles/corrected-report.md`.
This single run is an RSS trend check, not a leak proof or statistically established improvement over older measurements.

**One-minute idle smoke**

Six samples: mean CPU 0.267%, peak/p95 CPU 1.600%, memory 31→30 MiB, and zero second-half settled growth. The orchestration smoke passed. This was deliberately a short functional sample and does not replace a 30-minute idle run or establish wakeup/energy attribution.

**Remaining manual evidence**

The script leaves VoiceOver/keyboard/RTL interaction, About links, controlled sleep/wake/clock changes, representative notch/external-display hardware, launch-at-login approval, fresh quarantined installation, and Instruments idle-wakeup attribution as manual. Minimum-supported macOS 13 also needs a separate environment. Hosted tests cover geometry, cancellation, and state behavior; those do not certify real hardware behavior.

Reader and popup Quran text were inspected in generated captures. Native button compositing was inconsistent in the NSHostingView bitmap capture mechanism, so those screenshots are not a complete visual acceptance test. No production layout change was made solely to compensate for that test-capture limitation.
