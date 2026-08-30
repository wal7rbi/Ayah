#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

usage() {
    cat <<'USAGE'
Usage: Scripts/profile_ui_cycles.sh [options]

Builds an isolated profiling-only Ayah product, performs five unmeasured warm-up
cycles, automatically opens and closes the real menu-bar popover, samples the
process, and writes a Markdown report.

Options:
  --cycles <1-500>       Number of open/close cycles. Default: 200.
  --delay-ms <20-2000>   Delay after each open and close. Default: 50.
  --output <directory>   Artifact directory. Default: a timestamped directory
                         beneath /private/tmp.
  -h, --help             Show this help.

The profiling-only automation is excluded from normal Ayah builds. This script
does not install tools, update dependencies, use Accessibility automation, or
initiate network work.
USAGE
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

integer_in_range() {
    VALUE=$1
    MINIMUM=$2
    MAXIMUM=$3
    case "$VALUE" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$VALUE" -ge "$MINIMUM" ] && [ "$VALUE" -le "$MAXIMUM" ]
}

CYCLES=200
DELAY_MS=50
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
OUTPUT_DIR=/private/tmp/ayah-ui-cycles-$TIMESTAMP-$$

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cycles)
            [ "$#" -ge 2 ] || fail "--cycles requires a value"
            CYCLES=$2
            shift 2
            ;;
        --delay-ms)
            [ "$#" -ge 2 ] || fail "--delay-ms requires a value"
            DELAY_MS=$2
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || fail "--output requires a directory"
            OUTPUT_DIR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) fail "unknown option: $1" ;;
    esac
done

integer_in_range "$CYCLES" 1 500 || fail "--cycles must be an integer from 1 through 500"
integer_in_range "$DELAY_MS" 20 2000 || fail "--delay-ms must be an integer from 20 through 2000"

for COMMAND in xcodebuild ps awk grep git; do
    command -v "$COMMAND" >/dev/null 2>&1 || fail "required command not found: $COMMAND"
done

PACKAGE_STORAGE=$REPO_ROOT/Packages/AyahKit/.build
[ -d "$PACKAGE_STORAGE/checkouts/adhan-swift/.git" ] || fail "local pinned Adhan checkout is missing beneath $PACKAGE_STORAGE; refusing a build that could require network access"
[ -f "$REPO_ROOT/Ayah.xcodeproj/project.pbxproj" ] || fail "Ayah.xcodeproj is missing"

mkdir -p "$OUTPUT_DIR" || fail "could not create output directory: $OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)
DERIVED_DATA=$OUTPUT_DIR/DerivedData
BUILD_LOG=$OUTPUT_DIR/xcodebuild.log
APP_LOG=$OUTPUT_DIR/app.log
SAMPLES=$OUTPUT_DIR/samples.csv
REPORT=$OUTPUT_DIR/report.md
PRODUCT_NAME=AyahUICycles$$
BUNDLE_IDENTIFIER=com.ayah.app.performance.ui.$TIMESTAMP.$$

printf 'Building the isolated profiling product; log: %s\n' "$BUILD_LOG"
if ! xcodebuild \
    -project "$REPO_ROOT/Ayah.xcodeproj" \
    -scheme Ayah \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$PACKAGE_STORAGE" \
    -disableAutomaticPackageResolution \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates \
    PRODUCT_NAME="$PRODUCT_NAME" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) AYAH_PERFORMANCE_AUTOMATION' \
    build > "$BUILD_LOG" 2>&1; then
    fail "profiling build failed; see $BUILD_LOG"
fi

EXECUTABLE=$DERIVED_DATA/Build/Products/Release/$PRODUCT_NAME.app/Contents/MacOS/$PRODUCT_NAME
[ -x "$EXECUTABLE" ] || fail "profiling executable not found at $EXECUTABLE"

APP_PID=""
cleanup() {
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

printf 'sample,phase,rss_kb,cpu_percent,threads\n' > "$SAMPLES"
printf 'Running %s automated popover cycles; samples: %s\n' "$CYCLES" "$SAMPLES"
/usr/bin/env -i \
    HOME="$HOME" \
    USER="${USER:-}" \
    TMPDIR=/private/tmp \
    LANG=en_US.UTF-8 \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$EXECUTABLE" \
    --ayah-performance-popover-cycles "$CYCLES" \
    --ayah-performance-cycle-delay-ms "$DELAY_MS" \
    > "$APP_LOG" 2>&1 &
APP_PID=$!

SAMPLE_INDEX=0
EXPECTED_CYCLE_SECONDS=$((CYCLES * DELAY_MS * 2 / 1000))
MAX_SAMPLES=$(((EXPECTED_CYCLE_SECONDS + 45) * 4))

while kill -0 "$APP_PID" 2>/dev/null; do
    PHASE=launch
    if grep -q AYAH_PERFORMANCE_BASELINE_READY "$APP_LOG" 2>/dev/null; then PHASE=baseline; fi
    if grep -q AYAH_PERFORMANCE_CYCLES_STARTED "$APP_LOG" 2>/dev/null; then PHASE=cycles; fi
    if grep -q AYAH_PERFORMANCE_CYCLES_FINISHED "$APP_LOG" 2>/dev/null; then PHASE=cooldown; fi

    RESOURCE_ROW=$(ps -p "$APP_PID" -o rss=,%cpu= 2>/dev/null || true)
    if [ -n "$RESOURCE_ROW" ]; then
        set -- $RESOURCE_ROW
        if [ "$#" -eq 2 ]; then
            # Darwin ps has no portable thread-count output keyword. In its
            # `-M` view, lines after the header and process row are threads.
            THREAD_COUNT=$(ps -M -p "$APP_PID" 2>/dev/null | awk 'NR > 2 { count++ } END { print count + 0 }')
            printf '%s,%s,%s,%s,%s\n' "$SAMPLE_INDEX" "$PHASE" "$1" "$2" "$THREAD_COUNT" >> "$SAMPLES"
        fi
    fi

    SAMPLE_INDEX=$((SAMPLE_INDEX + 1))
    [ "$SAMPLE_INDEX" -le "$MAX_SAMPLES" ] || fail "automation exceeded its bounded runtime; see $APP_LOG"
    sleep 0.25
done

if wait "$APP_PID"; then
    APP_STATUS=0
else
    APP_STATUS=$?
fi
APP_PID=""
[ "$APP_STATUS" -eq 0 ] || fail "automated Ayah process exited with status $APP_STATUS; see $APP_LOG"
grep -q AYAH_PERFORMANCE_COMPLETE "$APP_LOG" || fail "automation did not reach its completion marker; see $APP_LOG"
grep -q ',baseline,' "$SAMPLES" || fail "no baseline resource samples were captured"
grep -q ',cycles,' "$SAMPLES" || fail "no cycle resource samples were captured"
grep -q ',cooldown,' "$SAMPLES" || fail "no cooldown resource samples were captured"

awk -F, \
    -v report="$REPORT" \
    -v cycles="$CYCLES" \
    -v delay="$DELAY_MS" '
    NR == 1 { next }
    {
        samples++
        phase[$2]++
        rssSum[$2] += $3
        cpuSum[$2] += $4
        if ($3 > peakRSS) peakRSS = $3
        if ($5 > peakThreads) peakThreads = $5
    }
    END {
        baseline = phase["baseline"] ? rssSum["baseline"] / phase["baseline"] : 0
        cooldown = phase["cooldown"] ? rssSum["cooldown"] / phase["cooldown"] : 0
        growth = cooldown - baseline
        cycleCPU = phase["cycles"] ? cpuSum["cycles"] / phase["cycles"] : 0
        status = "Inconclusive"
        interpretation = "Baseline or cooldown samples were missing."
        if (baseline > 0 && cooldown > 0) {
            if (growth <= 5120) {
                status = "Pass"
                interpretation = "Settled RSS growth is within the provisional 5 MiB guardrail."
            } else if (growth <= 10240) {
                status = "Alert"
                interpretation = "Growth exceeds 5 MiB but remains below 10 MiB; repeat and inspect Allocations."
            } else {
                status = "Investigate"
                interpretation = "Settled growth exceeds 10 MiB; inspect retained allocations before release."
            }
        }

        print "# Ayah automated popover-cycle report" > report
        print "" >> report
        printf "- Cycles: %d\n", cycles >> report
        printf "- Delay after open/close: %d ms\n", delay >> report
        printf "- Samples: %d at approximately 250 ms intervals\n", samples >> report
        printf "- Baseline mean RSS: %.2f MiB (%d samples)\n", baseline / 1024, phase["baseline"] >> report
        printf "- Cooldown mean RSS: %.2f MiB (%d samples)\n", cooldown / 1024, phase["cooldown"] >> report
        printf "- Settled RSS change: %+.2f MiB\n", growth / 1024 >> report
        printf "- Peak RSS: %.2f MiB\n", peakRSS / 1024 >> report
        printf "- Mean sampled CPU during cycles: %.2f%%\n", cycleCPU >> report
        printf "- Peak thread count: %d\n", peakThreads >> report
        printf "- Result: **%s**\n", status >> report
        printf "- Interpretation: %s\n", interpretation >> report
        print "" >> report
        print "This is an RSS trend check, not a leak proof. Confirm alerts with Instruments Allocations/Leaks and repeat under equivalent machine conditions." >> report
    }
' "$SAMPLES"

printf 'Automation complete. Report: %s\n' "$REPORT"
sed -n '1,24p' "$REPORT"
