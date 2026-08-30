# Ayah performance measurement

Ayah's performance workflow is local, dependency-free, and intentionally does not upload traces or measurements. Raw output defaults to a timestamped directory beneath `/private/tmp`; treat those directories as disposable and potentially privacy-sensitive because Instruments traces can contain process and system metadata.

## Quick start

From the repository root:

```bash
# Run XCTest performance cases three times in Release configuration.
Scripts/profile_performance.sh tests

# Build Ayah and record separate bounded CPU and signpost launch traces.
Scripts/profile_performance.sh launch \
  --template 'Time Profiler' \
  --output /private/tmp/ayah-launch-time-profiler

Scripts/profile_performance.sh launch \
  --template 'Logging' \
  --duration 10s \
  --output /private/tmp/ayah-launch-signposts

# Attach to an existing Ayah process for two minutes.
Scripts/profile_performance.sh attach 12345 --duration 2m

# Use another installed Instruments template.
Scripts/profile_performance.sh attach 12345 \
  --template 'Allocations' \
  --duration 5m \
  --output /private/tmp/ayah-allocations
```

Use `Scripts/profile_performance.sh --help` for the full interface. Recordings are bounded to one of the durations accepted by the script, with a maximum of ten minutes. Every successful recording includes the raw `.trace` bundle and a sibling `*-toc.xml` table-of-contents export that makes the available trace tables explicit. The script disables package updates, restricts resolution to checked-in `Package.resolved` files, and requires the pinned Adhan checkout to exist beneath `Packages/AyahKit/.build`. Launch mode builds with a unique temporary product name and bundle identifier, runs `xctrace` under a minimal environment, verifies that the trace targeted that exact build, and rejects sensitive-looking environment-variable names in exported metadata. These profiling-only overrides do not change Ayah's shipping configuration. The script does not install tools or dependencies and will fail if Xcode, `xctrace`, or the local checkout is unavailable.

To automate the repeated popover memory exercise instead of clicking manually:

```bash
Scripts/profile_ui_cycles.sh --cycles 200 \
  --output /private/tmp/ayah-ui-cycles-rc
```

This builds a uniquely named profiling product with an automation compilation condition, performs five unmeasured warm-up cycles so one-time AppKit/SwiftUI caches are present before the baseline, opens and closes the real `NSPopover`, samples RSS/CPU/thread count approximately four times per second, waits through baseline and cooldown phases, and writes `report.md` plus raw `samples.csv`. The automation entry point is not compiled into normal Debug or Release builds and does not require Accessibility permission. Its provisional result compares settled RSS against the scorecard's 5 MiB growth guardrail; it is a trend check rather than proof that no allocation leaked.

## What to capture

Use the smallest tool that answers the question:

| Question | Mode/template | Primary evidence |
|---|---|---|
| Did a repository operation regress? | `tests` | XCTest metric samples and wall time |
| Where is launch/main-thread CPU time spent? | `launch`, Time Profiler | sampled call tree |
| How long do instrumented operations take? | `launch` or `attach`, Logging on Xcode 26.3 (or the installed signpost-capable template) | named signpost intervals |
| Does memory grow after repeated UI use? | `attach`, Allocations | persistent bytes and generation comparison |
| Is there a leak? | `attach`, Leaks | confirmed leak backtraces |
| Does idle work wake the system? | interactive Instruments Energy Log/System Trace | timers, wakeups, CPU, activity states |
| Are settings or databases written while idle? | interactive Instruments File Activity | filesystem operations by path and call stack |

Instruments template names vary by Xcode release. Confirm them with `xcrun xctrace list templates` and use an installed name exactly. Xcode 26.3 exposes Ayah's signpost intervals through the `Logging` template; a template named `Points of Interest` is not installed here. Record Time Profiler and signposts as separate traces: neither recording is assumed to contain the other template's data. Energy measurements are especially sensitive to machine state and should be collected interactively on real hardware.

Instruments traces and TOCs may include process metadata and environment variables even though Ayah's own signposts contain no user data. Launch mode minimizes and checks that metadata. Attach mode cannot sanitize an already-running process: launch it from Finder or another known-clean environment, and delete the artifact directory immediately if the script reports a sensitive-environment failure.

## Measurement protocol

1. Record the build revision, dirty-worktree state, Mac model, CPU, memory, macOS, Xcode, Swift, power source, thermal state, display configuration, and configuration (`Release` unless testing Debug-only behavior).
2. Reboot or close unrelated heavy applications when comparing release candidates. Keep power source and Low Power Mode constant.
3. Perform one warm-up run that is not included in the result. For short deterministic operations, collect at least ten samples per run and three independent runs.
4. For each scenario, report median, p95, maximum, standard deviation or median absolute deviation, sample count, and failure count. Keep raw logs/traces until the comparison is reviewed.
5. Change one relevant variable at a time. Compare the same scenario on the same machine; shared CI runners are not suitable for tight timing gates.
6. Investigate both statistical and practical significance. A percentage change on a sub-millisecond operation may not matter, while a smaller change in idle wakeups may matter greatly.

Suggested regression policy:

- Require three reproducible runs before classifying a regression.
- Initially alert, rather than fail, on noisy launch, UI, memory, and energy metrics.
- Consider gating deterministic repository/calculation metrics after a stable history exists; a provisional 15% threshold must include an absolute floor so measurement noise cannot fail the build.
- Never average away crashes, hangs, failed samples, leaks, or correctness failures. Report them separately.

## Interaction checklist

Use the same scripted sequence for before/after traces:

- Cold launch after terminating Ayah; wait until the status item is usable.
- Open and close the popover 20 times; switch between its major views.
- Trigger verse/notch presentation where the hardware supports it.
- Search/select cities and switch between saved city and current location.
- Create, edit, and delete a temporary memorization set.
- Leave Ayah idle for 30 minutes with no popover open.
- Sleep and wake the Mac, then confirm the scheduler rearms.
- Change time zone and clock in a disposable test session, then restore both.
- Repeat popover/notch presentation 200 times for a retained-memory comparison.
- Repeat on a non-notch Mac or fallback display path and with an external display where available.

Do not infer energy or accessibility quality from a Time Profiler trace. VoiceOver, keyboard navigation, RTL order, text scaling, reduced motion, and multi-display behavior require separate functional observation.

## Result storage

Keep reviewed summaries under `docs/performance/`. Keep raw `.trace` bundles, their generated `*-toc.xml` exports, and verbose logs outside source control, preferably beneath `/private/tmp`. A summary must link or name its raw artifact directory, but should also state when that directory is ephemeral or was removed.

The initial release-candidate template is [2026-08-23-release-candidate-baseline-v1.md](2026-08-23-release-candidate-baseline-v1.md).

## One-command release-candidate run

Run all safe local automated checks, the 200-cycle popover exercise, and a
30-minute idle sample with:

```bash
Scripts/run_release_candidate_checks.sh
```

Use `--idle-minutes 1` for a smoke test of the orchestration itself. The final
Markdown report distinguishes automated pass/fail evidence from checks that
still require physical hardware, interactive accessibility evaluation, or
release credentials.
