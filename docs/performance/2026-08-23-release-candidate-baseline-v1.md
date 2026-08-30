# Ayah release-candidate performance baseline v1

Date: 2026-08-23  
Status: **Partial baseline collected — deterministic Release metrics and sanitized launch traces complete; long-run interactive metrics remain open**

## Purpose

This scorecard defines the first reproducible baseline for Ayah. It separates proposed guardrails from observed measurements so an unmeasured target cannot be mistaken for a passing result.

## Environment

Facts recorded while the workflow was prepared:

| Field | Value |
|---|---|
| Repository revision | `873d3f87e635db083d09e2bd31d8daeaa0ce2c49` |
| Branch | `main` |
| Worktree | Dirty; includes pre-existing and audit changes |
| Host architecture | `arm64` |
| macOS | 26.5.2 (25F84) |
| Xcode | 26.3 (17C529) |
| Swift | Apple Swift 6.2.4 |
| Minimum supported macOS | 13.0 |

Complete these fields for every actual run:

| Field | Recorded value |
|---|---|
| Measurement revision and diff identifier | `873d3f8` plus the dirty audit/performance worktree; snapshot `/private/tmp/ayah-performance-rc-20260823.mL8c8u` |
| Mac model / CPU / RAM | `Mac16,13` / Apple M4 / 16 GiB |
| Power source / battery percentage | Battery, 97%, discharging at test start |
| Low Power Mode / thermal state | Low Power Mode not independently recorded; no thermal warning appeared |
| Display and notch configuration | Built-in MacBook Air display; launch trace exercised the available notch path; external display not tested |
| Build configuration / signing identity | Release; local ad-hoc `Sign to Run Locally`, hardened-runtime flag present |
| Warm-up procedure | One unreported Release run, followed by three independent recorded runs; each XCTest also performs fixed warm-up/correctness work |
| Raw artifact directory | `/private/tmp/ayah-performance-rc-v1-final`; sanitized traces listed below |
| Operator and start/end time | Codex local run; XCTest started 2026-08-23 19:00:18 UTC |

## Proposed scorecard

The guardrails below are hypotheses to validate, not achieved measurements. Populate observed values with median, p95, maximum, variability, and sample count.

| Metric | Controlled scenario | Proposed initial guardrail | Observed | Status |
|---|---|---:|---:|---|
| Cold launch | Process start until status item is usable | p95 ≤ 1 s | Internal `LaunchInitialization` interval 52.65 ms, n=1; process-start/UI-ready endpoints not captured | Partial |
| Popover latency | Status-item activation until interactive content | p95 ≤ 150 ms | Not Run | Not Run |
| Notch presentation | Trigger until verse is visible | p95 ≤ 200 ms | `NotchPresentation` method interval 11.63 ms, n=1; visual readiness not observed | Partial |
| Idle CPU | Stable isolated app, UI closed, 30 minutes | median ≤ 0.1%; p95 ≤ 0.5% | 180 samples: median 0.000%; p95 0.000%; mean 0.023%; peak 3.400% | Pass |
| Idle wakeups | Stable app, UI closed, 30 minutes | ≤ 1/min attributable to Ayah | Not Run | Not Run |
| Retained memory | 5 warm-up + 200 measured popover open-close cycles | ≤ 5 MiB settled RSS growth | Baseline 120.40 MiB; cooldown 103.58 MiB; change −16.82 MiB; peak 121.39 MiB | Pass — RSS trend, not leak proof |
| Quran lookup | 1,000 fixed ayah lookups | p95 ≤ 10 ms for the batch | median 5.618 ms; p95/max 5.908 ms; CV 2.88%; n=15 | Pass |
| City search | 50 alternating English/Arabic searches over 4,654 cities | p95 ≤ 500 ms for the batch | median 305.731 ms; p95/max 319.091 ms; CV 1.44%; n=15 | Pass |
| Prayer calculation | 365 days × every supported method, Riyadh | p95 ≤ 50 ms for the batch | median 22.108 ms; p95/max 23.184 ms; CV 2.49%; n=15 | Pass |
| Awake alert timing | Stable clock, app awake | target time ±5 s | Not Run | Not Run |
| Wake recovery | System wake until scheduler is rearmed | ≤ 2 s | Not Run | Not Run |
| Main-thread stalls | Standard interaction checklist | no stall ≥ 100 ms | Not Run | Not Run |
| Idle disk writes | Stable app, UI closed, 30 minutes | no recurring Ayah writes | Not Run | Not Run |

## Commands

Run one excluded warm-up, then three recorded test runs:

```bash
Scripts/profile_performance.sh tests --runs 1 \
  --output /private/tmp/ayah-performance-warmup

Scripts/profile_performance.sh tests --runs 3 \
  --output /private/tmp/ayah-performance-rc-v1
```

Capture launch and bounded process traces from a normal interactive macOS session:

```bash
Scripts/profile_performance.sh launch \
  --configuration Release \
  --template 'Time Profiler' \
  --duration 30s \
  --output /private/tmp/ayah-launch-time-profiler-rc-v1

Scripts/profile_performance.sh launch \
  --configuration Release \
  --template 'Logging' \
  --duration 30s \
  --output /private/tmp/ayah-launch-signposts-rc-v1

Scripts/profile_performance.sh attach <AYAH_PID> \
  --template 'Allocations' \
  --duration 5m \
  --output /private/tmp/ayah-allocations-rc-v1
```

Time Profiler and Logging are separate recordings on the measured Xcode 26.3 installation: use the first for sampled CPU call trees and the second for named signpost intervals. Other Xcode versions may expose signposts through a differently named template, so confirm installed names before recording. Repeat the attach command with an appropriate locally installed Energy Log, System Trace, Leaks, or File Activity template. Each successful launch or attach recording must contain both its `.trace` bundle and generated sibling `*-toc.xml` export.

## Interaction record

For each trace, mark the completed actions and their timestamps or signpost intervals:

| Action | Result / timestamp |
|---|---|
| Cold launch and status-item readiness | Not Run |
| 20 popover cycles and view switching | Not Run |
| Verse/notch presentation | Not Run |
| City search and location-mode switching | Not Run |
| Memorization create/edit/delete | Not Run |
| 30-minute idle interval | Pass on 2026-08-24: 180/180 samples; CPU median/p95 0.000%; memory 30→21 MiB; wakeup attribution remains separate |
| Sleep/wake recovery | Not Run |
| Clock/time-zone change recovery | Not Run |
| 200-cycle retained-memory exercise | Pass on 2026-08-24: five warm-up + 200 automated real-popover cycles; settled RSS −2.23 MiB |
| Non-notch and external-display paths | Not Run |

## Analysis and variance rules

- Do not combine Debug and Release data or results from different Mac models in one baseline.
- Discard only a documented warm-up. Do not silently discard slow, failed, or interrupted samples.
- For short operations, use at least ten samples within each of three independent runs. Report median and p95; also report maximum and standard deviation or median absolute deviation.
- Compare release candidates under equivalent power, thermal, display, and background-load conditions.
- Call a deterministic metric regressed only when the change exceeds the eventual relative threshold and an absolute noise floor, and reproduces in all three runs.
- Treat confirmed leaks, crashes, hangs, correctness failures, repeated idle writes, and unbounded timer activity as defects regardless of aggregate averages.
- Attribute CPU and wakeups using process/thread stacks or signposts. Do not assign all system activity during the window to Ayah.

## Results

Three independent Release runs completed with 15 samples per metric. All final metrics were stable under the protocol's 15% variability limit:

| Deterministic workload | Median | p95 / max | CV | Status |
|---|---:|---:|---:|---|
| GeoNames initialization + SHA-256 + 4,654-row validation | 3.102 ms | 3.248 ms | 2.17% | Baseline established |
| 50 bilingual city searches | 305.731 ms | 319.091 ms | 1.44% | Baseline established |
| 1,000 in-memory memorization cursor updates | 2.732 ms | 2.906 ms | 3.58% | Baseline established |
| Fetch all + enabled from 1,000 persisted sets | 35.677 ms | 36.155 ms | 0.66% | Baseline established |
| 365 days × all supported prayer methods | 22.108 ms | 23.184 ms | 2.49% | Baseline established |
| 1,000 fixed Quran lookups | 5.618 ms | 5.908 ms | 2.88% | Baseline established |
| Quran initialization + integrity verification | 6.242 ms | 6.492 ms | 1.88% | Baseline established |
| 1,000 deterministic five-verse selections | 66.490 ms | 68.430 ms | 1.48% | Baseline established |

Sanitized raw evidence:

- XCTest logs: `/private/tmp/ayah-performance-rc-v1-final`
- Logging/signpost launch trace: `/private/tmp/ayah-launch-signposts-rc-v1-unique-product`
- Time Profiler launch trace: `/private/tmp/ayah-launch-time-profiler-rc-v1-verified`
- Allocations launch trace: `/private/tmp/ayah-launch-allocations-rc-v1-verified`
- Automated 200-cycle RSS/CPU/thread report and samples: `/private/tmp/ayah-ui-cycles-20260824-v3`
- Consolidated full release-candidate run, latest 200-cycle result, and 30-minute idle samples: `/private/tmp/ayah-release-checks-20260824-full`

The verified signpost trace measured one launch: `LaunchInitialization` 52.65 ms, Quran initialization 7.19 ms, memorization initialization 1.44 ms, GeoNames initialization 3.94 ms, notch presentation method 11.63 ms, first verse selection 655.5 µs, verse scheduler rearm 15.88 µs, and prayer scheduler rearm 3.04 µs. These are single diagnostic intervals, not percentile claims or proof of visual readiness.

The automated memory exercise used a uniquely named Release profiling product and the real `NSPopover`. Five unmeasured cycles populated one-time AppKit/SwiftUI caches before the baseline; 200 measured cycles then produced 104 process samples. Mean settled RSS changed from 121.37 MiB to 119.14 MiB, peak RSS was 122.34 MiB, mean sampled CPU during the deliberately rapid cycle phase was 4.43%, and peak thread count was eight. The `ps` RSS values are not directly comparable to Activity Monitor's memory-footprint column; only the within-run trend is used for the decision. A flat RSS trend does not independently prove the absence of leaks.

A later canonical full run repeated the protocol with 105 samples: baseline RSS 120.40 MiB, cooldown 103.58 MiB, −16.82 MiB settled change, 121.39 MiB peak, 3.80% mean sampled CPU during rapid cycling, and eight peak threads. Its separate 30-minute isolated idle phase captured all 180 expected samples. CPU median and p95 were both 0.000%, mean was 0.023%, and only two samples were nonzero; the 3.400% peak occurred near the default 30-minute scheduled verse boundary. Activity Monitor-style power impact had median/p95 0.000 and mean 0.032. Memory fell from 30 MiB to 21 MiB, with a 30 MiB peak and six peak threads. These results pass the provisional CPU and memory trend guardrails. Per-process wakeup attribution remains unmeasured because `top` does not expose it; an Instruments System Trace or Power Profiler analysis is still required before changing timer leeway.

No timer-leeway change was made. The approved gate requires two comparable long idle traces attributing at least 10% of Ayah wakeups to the verse timer; this session did not produce that evidence.

## Known limitations requiring an interactive or physical test environment

- Instruments required an approved interactive execution context. The workflow now sanitizes launch environments, gives profiling builds unique temporary product/bundle identifiers, verifies the recorded target, exports a TOC, and rejects sensitive-looking environment keys.
- Notch, non-notch fallback, multi-display, VoiceOver, sleep/wake, clock/time-zone changes, and launch-at-login require hands-on observation.
- Energy and thermal comparisons require stable real hardware; virtualized or shared CI measurements are unsuitable for the baseline.
- Developer ID signing, notarization, and distribution-build launch behavior require release credentials and services not exercised here.
- `/private/tmp` artifacts are ephemeral and are not a durable evidence store.

Once measurements are collected, replace each `Not Run` result with the observed distribution, raw-artifact location, pass/alert/fail decision, and a short interpretation. Preserve this version if the test protocol changes materially; create a new version rather than rewriting history.
