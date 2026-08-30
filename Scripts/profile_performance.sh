#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

usage() {
    cat <<'USAGE'
Usage:
  Scripts/profile_performance.sh tests [options]
  Scripts/profile_performance.sh launch [options]
  Scripts/profile_performance.sh attach <pid> [options]

Modes:
  tests       Run the AyahKit performance tests repeatedly with SwiftPM.
  launch      Build Ayah locally, then launch it under an xctrace recording.
  attach      Attach xctrace to an already-running Ayah process by numeric PID.

Options:
  --output <directory>       Raw-output directory. Default:
                             /private/tmp/ayah-performance-<timestamp>-<pid>
  --runs <1-10>             Test repetitions. Default: 3 (tests only).
  --filter <regex>           Swift test filter. Default: Performance
                             (tests only).
  --configuration <name>    Debug or Release. Default: Release (launch only).
  --template <name>         Installed Instruments template. Default:
                             Time Profiler (launch/attach only).
  --duration <bounded-time>  5s, 10s, 15s, 30s, 1m, 2m, 5m, or 10m.
                             Default: 30s (launch/attach only).
  -h, --help                 Show this help.

This script does not install tools, update packages, or initiate network work.
SwiftPM/Xcode resolution is restricted to Package.resolved. The command fails
if the pinned dependency is not already available in local caches.
Each successful xctrace recording also exports a matching *-toc.xml file.
USAGE
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

is_bounded_duration() {
    case "$1" in
        5s|10s|15s|30s|1m|2m|5m|10m) return 0 ;;
        *) return 1 ;;
    esac
}

[ "$#" -ge 1 ] || { usage >&2; exit 64; }

MODE=$1
shift

case "$MODE" in
    -h|--help) usage; exit 0 ;;
    tests|launch|attach) ;;
    *) usage >&2; fail "unknown mode: $MODE" ;;
esac

ATTACH_PID=""
if [ "$MODE" = "attach" ]; then
    [ "$#" -ge 1 ] || fail "attach mode requires a numeric PID"
    ATTACH_PID=$1
    shift
    case "$ATTACH_PID" in
        ''|*[!0-9]*) fail "attach PID must contain only digits" ;;
    esac
    [ "$ATTACH_PID" -gt 1 ] || fail "attach PID must be greater than 1"
fi

TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
OUTPUT_DIR="/private/tmp/ayah-performance-${TIMESTAMP}-$$"
RUNS=3
TEST_FILTER=Performance
CONFIGURATION=Release
TEMPLATE='Time Profiler'
DURATION=30s

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            [ "$#" -ge 2 ] || fail "--output requires a directory"
            OUTPUT_DIR=$2
            shift 2
            ;;
        --runs)
            [ "$#" -ge 2 ] || fail "--runs requires a value"
            RUNS=$2
            shift 2
            ;;
        --filter)
            [ "$#" -ge 2 ] || fail "--filter requires a regular expression"
            TEST_FILTER=$2
            shift 2
            ;;
        --configuration)
            [ "$#" -ge 2 ] || fail "--configuration requires Debug or Release"
            CONFIGURATION=$2
            shift 2
            ;;
        --template)
            [ "$#" -ge 2 ] || fail "--template requires a name"
            TEMPLATE=$2
            shift 2
            ;;
        --duration)
            [ "$#" -ge 2 ] || fail "--duration requires a value"
            DURATION=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

case "$RUNS" in
    ''|*[!0-9]*) fail "--runs must be an integer from 1 through 10" ;;
esac
[ "$RUNS" -ge 1 ] && [ "$RUNS" -le 10 ] || fail "--runs must be from 1 through 10"
[ -n "$TEST_FILTER" ] || fail "--filter must not be empty"

case "$CONFIGURATION" in
    Debug|Release) ;;
    *) fail "--configuration must be Debug or Release" ;;
esac

is_bounded_duration "$DURATION" || fail "--duration must be one of: 5s, 10s, 15s, 30s, 1m, 2m, 5m, 10m"

[ -d "$REPO_ROOT/Packages/AyahKit" ] || fail "AyahKit package not found beneath $REPO_ROOT"
[ -f "$REPO_ROOT/Packages/AyahKit/Package.resolved" ] || fail "AyahKit Package.resolved is missing"

mkdir -p "$OUTPUT_DIR" || fail "could not create output directory: $OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)

write_metadata() {
    METADATA_PATH=$OUTPUT_DIR/environment.txt
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)" ]; then
        GIT_DIRTY=true
    else
        GIT_DIRTY=false
    fi
    {
        printf 'recorded_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'mode=%s\n' "$MODE"
        printf 'repository=%s\n' "$REPO_ROOT"
        printf 'git_revision=%s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
        printf 'git_branch=%s\n' "$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || printf unknown)"
        printf 'git_dirty=%s\n' "$GIT_DIRTY"
        printf 'host_architecture=%s\n' "$(uname -m)"
        printf 'hardware_model=%s\n' "$(sysctl -n hw.model 2>/dev/null || printf unavailable)"
        printf 'cpu_model=%s\n' "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf unavailable)"
        printf 'memory_bytes=%s\n' "$(sysctl -n hw.memsize 2>/dev/null || printf unavailable)"
        sw_vers 2>/dev/null || true
        xcodebuild -version 2>/dev/null || true
        swift --version 2>/dev/null || true
        pmset -g batt 2>/dev/null || true
        xcrun xctrace version 2>/dev/null || true
    } > "$METADATA_PATH"
}

run_tests() {
    require_command swift
    require_command git
    require_command /usr/bin/time

    LOCAL_ADHAN_CHECKOUT=$REPO_ROOT/Packages/AyahKit/.build/checkouts/adhan-swift
    [ -d "$LOCAL_ADHAN_CHECKOUT/.git" ] || fail "local pinned Adhan checkout is missing at $LOCAL_ADHAN_CHECKOUT; refusing a test run that could require network access"

    MODULE_CACHE=$OUTPUT_DIR/ModuleCache
    mkdir -p "$MODULE_CACHE" || fail "could not create compiler module cache: $MODULE_CACHE"

    INDEX=1
    while [ "$INDEX" -le "$RUNS" ]; do
        LOG_PATH=$OUTPUT_DIR/tests-run-${INDEX}.log
        TIME_PATH=$OUTPUT_DIR/tests-run-${INDEX}.time
        printf 'Running performance tests (%s/%s); raw log: %s\n' "$INDEX" "$RUNS" "$LOG_PATH"
        if ! /usr/bin/time -p -o "$TIME_PATH" \
            env \
                CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
                SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
            swift test \
                --package-path "$REPO_ROOT/Packages/AyahKit" \
                --configuration release \
                --only-use-versions-from-resolved-file \
                --skip-update \
                --filter "$TEST_FILTER" \
                > "$LOG_PATH" 2>&1; then
            printf 'Test run %s failed. See %s and %s.\n' "$INDEX" "$LOG_PATH" "$TIME_PATH" >&2
            exit 1
        fi
        INDEX=$((INDEX + 1))
    done

    printf 'Completed %s test runs. Timing files report wall/user/system time; XCTest metric samples remain in the logs.\n' "$RUNS"
}

preflight_trace() {
    require_command xcrun
    require_command xcodebuild
    xcrun --find xctrace >/dev/null 2>&1 || fail "xctrace is unavailable; install/select a complete local Xcode before profiling"
}

export_trace_toc() {
    TRACE_TO_EXPORT=$1
    TOC_PATH=$2
    EXPORT_LOG=$3

    printf 'Exporting trace table of contents: %s\n' "$TOC_PATH"
    if ! xcrun xctrace export \
        --input "$TRACE_TO_EXPORT" \
        --toc \
        --output "$TOC_PATH" > "$EXPORT_LOG" 2>&1; then
        fail "xctrace recorded a trace but its table-of-contents export failed; see $EXPORT_LOG"
    fi
    [ -s "$TOC_PATH" ] || fail "xctrace table-of-contents export produced no data at $TOC_PATH; see $EXPORT_LOG"
}

reject_sensitive_trace_environment() {
    TOC_PATH=$1
    if grep -Ei 'key="[^"]*(API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)' "$TOC_PATH" >/dev/null 2>&1; then
        fail "trace metadata contains a potentially sensitive environment-variable name; delete this artifact directory and launch Ayah from a sanitized environment"
    fi
}

run_launch_trace() {
    preflight_trace
    require_command git

    DERIVED_DATA=$OUTPUT_DIR/DerivedData
    BUILD_LOG=$OUTPUT_DIR/xcodebuild.log
    PROFILE_PRODUCT_NAME=AyahPerformance$$
    PROFILE_BUNDLE_IDENTIFIER=com.ayah.app.performance.$TIMESTAMP.$$
    LOCAL_PACKAGE_STORAGE=$REPO_ROOT/Packages/AyahKit/.build
    [ -d "$LOCAL_PACKAGE_STORAGE/checkouts/adhan-swift/.git" ] || fail "local pinned Adhan checkout is missing beneath $LOCAL_PACKAGE_STORAGE; refusing a build that could require network access"
    printf 'Building %s locally; raw log: %s\n' "$CONFIGURATION" "$BUILD_LOG"

    if ! xcodebuild \
        -project "$REPO_ROOT/Ayah.xcodeproj" \
        -scheme Ayah \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -clonedSourcePackagesDirPath "$LOCAL_PACKAGE_STORAGE" \
        -disableAutomaticPackageResolution \
        -onlyUsePackageVersionsFromResolvedFile \
        -skipPackageUpdates \
        PRODUCT_NAME="$PROFILE_PRODUCT_NAME" \
        PRODUCT_BUNDLE_IDENTIFIER="$PROFILE_BUNDLE_IDENTIFIER" \
        build > "$BUILD_LOG" 2>&1; then
        fail "Xcode build failed; see $BUILD_LOG. Confirm the pinned package is already in the local Xcode cache."
    fi

    APP_BUNDLE=$DERIVED_DATA/Build/Products/$CONFIGURATION/$PROFILE_PRODUCT_NAME.app
    EXECUTABLE=$APP_BUNDLE/Contents/MacOS/$PROFILE_PRODUCT_NAME
    [ -d "$APP_BUNDLE" ] || fail "built app bundle not found at $APP_BUNDLE"
    [ -x "$EXECUTABLE" ] || fail "built executable not found at $EXECUTABLE"

    TRACE_PATH=$OUTPUT_DIR/launch.trace
    TRACE_LOG=$OUTPUT_DIR/xctrace-launch.log
    printf 'Recording launch with template "%s" for %s; trace: %s\n' "$TEMPLATE" "$DURATION" "$TRACE_PATH"
    if /usr/bin/env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        TMPDIR=/private/tmp \
        LANG=en_US.UTF-8 \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        xcrun xctrace record \
        --template "$TEMPLATE" \
        --time-limit "$DURATION" \
        --output "$TRACE_PATH" \
        --no-prompt \
        --launch -- "$EXECUTABLE" > "$TRACE_LOG" 2>&1; then
        TRACE_STATUS=0
    else
        TRACE_STATUS=$?
    fi
    [ -e "$TRACE_PATH" ] || fail "xctrace launch recording failed without producing a trace; see $TRACE_LOG. Run from an interactive macOS session with Instruments permissions."

    export_trace_toc \
        "$TRACE_PATH" \
        "$OUTPUT_DIR/launch-toc.xml" \
        "$OUTPUT_DIR/xctrace-export-launch.log"
    if ! grep -F "path=\"$APP_BUNDLE\"" "$OUTPUT_DIR/launch-toc.xml" >/dev/null 2>&1 \
        && ! grep -F "path=\"$EXECUTABLE\"" "$OUTPUT_DIR/launch-toc.xml" >/dev/null 2>&1; then
        fail "launch trace targeted a different Ayah binary; close existing Ayah instances and retry"
    fi
    reject_sensitive_trace_environment "$OUTPUT_DIR/launch-toc.xml"
    if [ "$TRACE_STATUS" -ne 0 ]; then
        printf 'warning: xctrace returned status %s after producing a valid exported trace; see %s\n' "$TRACE_STATUS" "$TRACE_LOG" >&2
    fi
}

run_attach_trace() {
    preflight_trace
    require_command git
    /bin/ps -p "$ATTACH_PID" >/dev/null 2>&1 || fail "no accessible running process found for PID $ATTACH_PID"

    TRACE_PATH=$OUTPUT_DIR/attach-${ATTACH_PID}.trace
    TRACE_LOG=$OUTPUT_DIR/xctrace-attach.log
    printf 'Attaching template "%s" to PID %s for %s; trace: %s\n' "$TEMPLATE" "$ATTACH_PID" "$DURATION" "$TRACE_PATH"
    if xcrun xctrace record \
        --template "$TEMPLATE" \
        --time-limit "$DURATION" \
        --output "$TRACE_PATH" \
        --no-prompt \
        --attach "$ATTACH_PID" > "$TRACE_LOG" 2>&1; then
        TRACE_STATUS=0
    else
        TRACE_STATUS=$?
    fi
    [ -e "$TRACE_PATH" ] || fail "xctrace attach recording failed without producing a trace; see $TRACE_LOG. Confirm PID ownership and Instruments permissions."

    export_trace_toc \
        "$TRACE_PATH" \
        "$OUTPUT_DIR/attach-${ATTACH_PID}-toc.xml" \
        "$OUTPUT_DIR/xctrace-export-attach.log"
    reject_sensitive_trace_environment "$OUTPUT_DIR/attach-${ATTACH_PID}-toc.xml"
    if [ "$TRACE_STATUS" -ne 0 ]; then
        printf 'warning: xctrace returned status %s after producing a valid exported trace; see %s\n' "$TRACE_STATUS" "$TRACE_LOG" >&2
    fi
}

write_metadata

case "$MODE" in
    tests) run_tests ;;
    launch) run_launch_trace ;;
    attach) run_attach_trace ;;
esac

printf 'Performance artifacts: %s\n' "$OUTPUT_DIR"
