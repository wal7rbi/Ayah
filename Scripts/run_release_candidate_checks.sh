#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

usage() {
    cat <<'USAGE'
Usage: Scripts/run_release_candidate_checks.sh [options]

Runs Ayah's safe local release-candidate checks and produces one Markdown
report. No dependency updates, downloads, commits, or source mutations occur.

Options:
  --idle-minutes <1-60>  Idle sampling duration. Default: 30.
  --ui-cycles <1-500>    Automated real-popover cycles. Default: 200.
  --output <directory>   Artifact directory. Default: a timestamped directory
                         beneath /private/tmp.
  -h, --help             Show this help.
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

IDLE_MINUTES=30
UI_CYCLES=200
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
OUTPUT_DIR=/private/tmp/ayah-release-checks-$TIMESTAMP-$$

while [ "$#" -gt 0 ]; do
    case "$1" in
        --idle-minutes)
            [ "$#" -ge 2 ] || fail "--idle-minutes requires a value"
            IDLE_MINUTES=$2
            shift 2
            ;;
        --ui-cycles)
            [ "$#" -ge 2 ] || fail "--ui-cycles requires a value"
            UI_CYCLES=$2
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

integer_in_range "$IDLE_MINUTES" 1 60 || fail "--idle-minutes must be an integer from 1 through 60"
integer_in_range "$UI_CYCLES" 1 500 || fail "--ui-cycles must be an integer from 1 through 500"

for COMMAND in awk bash codesign cmp git grep lipo plutil ps sed sqlite3 strings swift top xcodebuild; do
    command -v "$COMMAND" >/dev/null 2>&1 || fail "required command not found: $COMMAND"
done

PACKAGE_STORAGE=$REPO_ROOT/Packages/AyahKit/.build
[ -d "$PACKAGE_STORAGE/checkouts/adhan-swift/.git" ] || fail "local pinned Adhan checkout is missing beneath $PACKAGE_STORAGE; refusing work that could require network access"

mkdir -p "$OUTPUT_DIR" || fail "could not create output directory: $OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)
LOG_DIR=$OUTPUT_DIR/logs
mkdir -p "$LOG_DIR" || fail "could not create log directory"
REPORT=$OUTPUT_DIR/report.md
RESULTS=$OUTPUT_DIR/results.tsv
FAILURES=0

printf 'check\tstatus\tevidence\n' > "$RESULTS"

record_result() {
    NAME=$1
    STATUS=$2
    EVIDENCE=$3
    printf '%s\t%s\t%s\n' "$NAME" "$STATUS" "$EVIDENCE" >> "$RESULTS"
    printf '%-34s %s\n' "$NAME" "$STATUS"
    if [ "$STATUS" = FAIL ]; then
        FAILURES=$((FAILURES + 1))
    fi
}

run_logged() {
    NAME=$1
    LOG_NAME=$2
    shift 2
    LOG_PATH=$LOG_DIR/$LOG_NAME
    if "$@" > "$LOG_PATH" 2>&1; then
        record_result "$NAME" PASS "$LOG_PATH"
        return 0
    fi
    record_result "$NAME" FAIL "$LOG_PATH"
    return 1
}

check_locks() {
    cmp -s \
        "$REPO_ROOT/Packages/AyahKit/Package.resolved" \
        "$REPO_ROOT/Ayah.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}

check_shell_scripts() {
    bash -n "$REPO_ROOT/Scripts/profile_performance.sh"
    bash -n "$REPO_ROOT/Scripts/profile_ui_cycles.sh"
    bash -n "$REPO_ROOT/Scripts/run_release_candidate_checks.sh"
    bash -n "$REPO_ROOT/Scripts/build_unnotarized_release.sh"
}

check_quran_data() {
    RESULT=$(sqlite3 "$REPO_ROOT/Resources/Quran/quran.sqlite" 'PRAGMA integrity_check; SELECT COUNT(*) FROM surahs; SELECT COUNT(*) FROM ayahs;')
    [ "$RESULT" = "ok
114
6236" ]
}

check_geonames_data() {
    RESULT=$(sqlite3 "$REPO_ROOT/Resources/GeoNames/cities_filtered.sqlite" 'PRAGMA integrity_check; SELECT COUNT(*) FROM cities;')
    [ "$RESULT" = "ok
4654" ]
}

printf 'Ayah release-candidate checks\nArtifacts: %s\n\n' "$OUTPUT_DIR"

run_logged 'Git diff formatting' git-diff-check.log git -C "$REPO_ROOT" diff --check || true
run_logged 'Plist and source entitlements' plist.log plutil -lint "$REPO_ROOT/App/Info.plist" "$REPO_ROOT/App/Ayah.entitlements" || true
run_logged 'Pinned lockfile equality' lockfiles.log check_locks || true
run_logged 'Profiling script syntax' shell-syntax.log check_shell_scripts || true
run_logged 'Quran SQLite integrity/counts' quran-sqlite.log check_quran_data || true
run_logged 'GeoNames integrity/counts' geonames-sqlite.log check_geonames_data || true

run_logged 'Quran importer build' import-quran-build.log swift build --package-path "$REPO_ROOT/Scripts/import_quran" || true
run_logged 'GeoNames importer build' import-geonames-build.log swift build --package-path "$REPO_ROOT/Scripts/import_geonames" || true
run_logged 'Quran verifier build' verify-quran-build.log swift build --package-path "$REPO_ROOT/Scripts/verify_quran" || true
run_logged 'Quran manifest/checksum verifier' verify-quran-run.log swift run --package-path "$REPO_ROOT/Scripts/verify_quran" verify_quran "$REPO_ROOT/Resources/Quran" || true
run_logged 'AyahKit full test suite' ayahkit-tests.log swift test --package-path "$REPO_ROOT/Packages/AyahKit" || true

PRODUCT_NAME=AyahReleaseChecks$$
BUNDLE_IDENTIFIER=com.ayah.app.releasechecks.$TIMESTAMP.$$
DEBUG_DERIVED=$OUTPUT_DIR/DerivedData-Debug
RELEASE_DERIVED=$OUTPUT_DIR/DerivedData-Release

run_logged 'Debug application build' xcodebuild-debug.log \
    xcodebuild \
        -project "$REPO_ROOT/Ayah.xcodeproj" \
        -scheme Ayah \
        -configuration Debug \
        -derivedDataPath "$DEBUG_DERIVED" \
        -clonedSourcePackagesDirPath "$PACKAGE_STORAGE" \
        -disableAutomaticPackageResolution \
        -onlyUsePackageVersionsFromResolvedFile \
        -skipPackageUpdates \
        PRODUCT_NAME="$PRODUCT_NAME" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        build || true

run_logged 'Release application build' xcodebuild-release.log \
    xcodebuild \
        -project "$REPO_ROOT/Ayah.xcodeproj" \
        -scheme Ayah \
        -configuration Release \
        -derivedDataPath "$RELEASE_DERIVED" \
        -clonedSourcePackagesDirPath "$PACKAGE_STORAGE" \
        -disableAutomaticPackageResolution \
        -onlyUsePackageVersionsFromResolvedFile \
        -skipPackageUpdates \
        PRODUCT_NAME="$PRODUCT_NAME" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
        build || true

RELEASE_APP=$RELEASE_DERIVED/Build/Products/Release/$PRODUCT_NAME.app
RELEASE_EXECUTABLE=$RELEASE_APP/Contents/MacOS/$PRODUCT_NAME

if [ -d "$RELEASE_APP" ]; then
    check_adhoc_signature() {
        codesign --verify --deep --strict --verbose=2 "$RELEASE_APP"
        DETAILS=$(codesign -dv --verbose=4 "$RELEASE_APP" 2>&1)
        printf '%s\n' "$DETAILS"
        printf '%s\n' "$DETAILS" | grep -q '^Signature=adhoc$'
        printf '%s\n' "$DETAILS" | grep -q '^TeamIdentifier=not set$'
        printf '%s\n' "$DETAILS" | grep -q '^CodeDirectory .*[(]adhoc,runtime[)]'
    }
    run_logged 'Ad-hoc signature integrity' codesign-verify.log check_adhoc_signature || true

    check_release_architecture() {
        [ "$(lipo -archs "$RELEASE_EXECUTABLE")" = arm64 ]
    }
    run_logged 'Apple Silicon architecture' release-architecture.log check_release_architecture || true

    ENTITLEMENTS=$OUTPUT_DIR/embedded-entitlements.plist
    if codesign -d --entitlements :- "$RELEASE_APP" > "$ENTITLEMENTS" 2> "$LOG_DIR/codesign-entitlements.log" \
        && grep -q 'com.apple.security.app-sandbox' "$ENTITLEMENTS" \
        && grep -q 'com.apple.security.personal-information.location' "$ENTITLEMENTS" \
        && [ "$(plutil -p "$ENTITLEMENTS" | grep -c '=>')" -eq 2 ] \
        && ! grep -q 'com.apple.security.get-task-allow' "$ENTITLEMENTS" \
        && ! grep -q 'com.apple.security.network.client' "$ENTITLEMENTS" \
        && ! grep -q 'com.apple.security.network.server' "$ENTITLEMENTS"; then
        record_result 'Embedded entitlement posture' PASS "$ENTITLEMENTS"
    else
        record_result 'Embedded entitlement posture' FAIL "$ENTITLEMENTS"
    fi

    MISSING_RESOURCES=0
    for RESOURCE in \
        quran.sqlite \
        cities_filtered.sqlite \
        CHECKSUM \
        GEONAMES_CHECKSUM \
        uthmanic_hafs_v20.ttf \
        Adhan-LICENSE.txt \
        GeoNames-NOTICE.txt \
        ACKNOWLEDGEMENTS.txt; do
        if [ ! -f "$RELEASE_APP/Contents/Resources/$RESOURCE" ]; then
            printf 'missing: %s\n' "$RESOURCE" >> "$LOG_DIR/sealed-resources.log"
            MISSING_RESOURCES=$((MISSING_RESOURCES + 1))
        fi
    done
    if [ "$MISSING_RESOURCES" -eq 0 ]; then
        record_result 'Required sealed resources' PASS "$RELEASE_APP/Contents/Resources"
    else
        record_result 'Required sealed resources' FAIL "$LOG_DIR/sealed-resources.log"
    fi

    if strings "$RELEASE_EXECUTABLE" | grep -q 'AYAH_PERFORMANCE_WARMUP_STARTED'; then
        record_result 'Shipping automation exclusion' FAIL "$RELEASE_EXECUTABLE"
    else
        record_result 'Shipping automation exclusion' PASS "$RELEASE_EXECUTABLE"
    fi
else
    record_result 'Ad-hoc signature integrity' FAIL 'Release app was not built'
    record_result 'Apple Silicon architecture' FAIL 'Release app was not built'
    record_result 'Embedded entitlement posture' FAIL 'Release app was not built'
    record_result 'Required sealed resources' FAIL 'Release app was not built'
    record_result 'Shipping automation exclusion' FAIL 'Release app was not built'
fi

UI_OUTPUT=$OUTPUT_DIR/ui-cycles
if "$REPO_ROOT/Scripts/profile_ui_cycles.sh" \
    --cycles "$UI_CYCLES" \
    --output "$UI_OUTPUT" > "$LOG_DIR/ui-cycles.log" 2>&1 \
    && grep -q 'Result: \*\*Pass\*\*' "$UI_OUTPUT/report.md"; then
    record_result 'Automated popover RSS trend' PASS "$UI_OUTPUT/report.md"
else
    record_result 'Automated popover RSS trend' FAIL "$LOG_DIR/ui-cycles.log"
fi

IDLE_SAMPLES=$OUTPUT_DIR/idle-samples.csv
IDLE_REPORT=$OUTPUT_DIR/idle-report.md
printf 'sample,cpu_percent,memory,threads,power\n' > "$IDLE_SAMPLES"
IDLE_PID=""

cleanup_idle() {
    if [ -n "$IDLE_PID" ] && kill -0 "$IDLE_PID" 2>/dev/null; then
        kill "$IDLE_PID" 2>/dev/null || true
        wait "$IDLE_PID" 2>/dev/null || true
    fi
}
trap cleanup_idle EXIT INT TERM

if [ -x "$RELEASE_EXECUTABLE" ]; then
    /usr/bin/env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        TMPDIR=/private/tmp \
        LANG=en_US.UTF-8 \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        "$RELEASE_EXECUTABLE" > "$LOG_DIR/idle-app.log" 2>&1 &
    IDLE_PID=$!
    sleep 3

    IDLE_SAMPLE_COUNT=$((IDLE_MINUTES * 6))
    INDEX=1
    while [ "$INDEX" -le "$IDLE_SAMPLE_COUNT" ] && kill -0 "$IDLE_PID" 2>/dev/null; do
        TOP_ROW=$(top -l 2 -s 1 -pid "$IDLE_PID" -stats pid,command,cpu,mem,threads,power 2>/dev/null \
            | awk -v pid="$IDLE_PID" '$1 == pid { row = $0 } END { print row }')
        if [ -n "$TOP_ROW" ]; then
            set -- $TOP_ROW
            if [ "$#" -eq 6 ]; then
                THREADS=${5%%/*}
                printf '%s,%s,%s,%s,%s\n' "$INDEX" "$3" "$4" "$THREADS" "$6" >> "$IDLE_SAMPLES"
            fi
        fi
        if [ "$INDEX" -lt "$IDLE_SAMPLE_COUNT" ]; then sleep 9; fi
        INDEX=$((INDEX + 1))
    done

    cleanup_idle
    IDLE_PID=""

    awk -F, -v minutes="$IDLE_MINUTES" -v expected="$IDLE_SAMPLE_COUNT" -v report="$IDLE_REPORT" '
        function mib(value, suffix, number) {
            suffix = substr(value, length(value), 1)
            number = value + 0
            if (suffix == "G") return number * 1024
            if (suffix == "M") return number
            if (suffix == "K") return number / 1024
            return number / 1048576
        }
        NR == 1 { next }
        {
            count++
            cpu += $2
            power += $5
            cpuValues[count] = $2 + 0
            powerValues[count] = $5 + 0
            if ($2 > 0 || $5 > 0) activeSamples++
            memory = mib($3)
            memoryValues[count] = memory
            if (count == 1) firstMemory = memory
            lastMemory = memory
            if (memory > peakMemory) peakMemory = memory
            if ($2 > peakCPU) peakCPU = $2
            if ($4 > peakThreads) peakThreads = $4
        }
        END {
            minuteUnit = minutes == 1 ? "minute" : "minutes"
            for (i = 1; i <= count; i++) {
                for (j = i + 1; j <= count; j++) {
                    if (cpuValues[j] < cpuValues[i]) {
                        temporary = cpuValues[i]
                        cpuValues[i] = cpuValues[j]
                        cpuValues[j] = temporary
                    }
                    if (powerValues[j] < powerValues[i]) {
                        temporary = powerValues[i]
                        powerValues[i] = powerValues[j]
                        powerValues[j] = temporary
                    }
                }
            }
            medianIndex = int((count + 1) / 2)
            p95Index = int((count * 95 + 99) / 100)
            if (p95Index > count) p95Index = count
            memoryChange = lastMemory - firstMemory
            settledIndex = int(count / 2) + 1
            settledMemoryChange = lastMemory - memoryValues[settledIndex]
            status = "Alert"
            interpretation = "Sampling coverage or the provisional idle guardrail requires investigation."
            if (minutes < 5 && count >= expected * 0.95) {
                status = "Pass"
                interpretation = "Orchestration smoke passed; this short run is not an idle-performance classification."
            } else if (count >= expected * 0.95 && cpuValues[p95Index] <= 0.5 && settledMemoryChange <= 5) {
                status = "Pass"
                interpretation = "CPU p95 and second-half settled memory growth are within their provisional idle guardrails."
            }
            print "# Ayah automated idle report" > report
            print "" >> report
            printf "- Requested duration: %d %s\n", minutes, minuteUnit >> report
            printf "- Samples captured: %d\n", count >> report
            if (count > 0) {
                printf "- Mean sampled CPU: %.3f%%\n", cpu / count >> report
                printf "- Median sampled CPU: %.3f%%\n", cpuValues[medianIndex] >> report
                printf "- CPU p95: %.3f%%\n", cpuValues[p95Index] >> report
                printf "- Peak sampled CPU: %.3f%%\n", peakCPU >> report
                printf "- Mean sampled power impact: %.3f\n", power / count >> report
                printf "- Median sampled power impact: %.3f\n", powerValues[medianIndex] >> report
                printf "- Power-impact p95: %.3f\n", powerValues[p95Index] >> report
                printf "- Samples with nonzero CPU or power: %d\n", activeSamples >> report
                printf "- Initial memory: %.2f MiB\n", firstMemory >> report
                printf "- Final memory: %.2f MiB\n", lastMemory >> report
                printf "- Memory change: %+.2f MiB\n", memoryChange >> report
                printf "- Second-half settled memory change: %+.2f MiB\n", settledMemoryChange >> report
                printf "- Peak memory: %.2f MiB\n", peakMemory >> report
                printf "- Peak thread count: %d\n", peakThreads >> report
            }
            print "- Per-process idle-wakeup attribution: Not Run (not exposed by top; use Instruments System Trace/Power Profiler)" >> report
            printf "- Result: **%s**\n", status >> report
            printf "- Interpretation: %s\n", interpretation >> report
        }
    ' "$IDLE_SAMPLES"

    if grep -q 'Result: \*\*Pass\*\*' "$IDLE_REPORT"; then
        record_result 'Automated idle resource trend' PASS "$IDLE_REPORT"
    else
        record_result 'Automated idle resource trend' FAIL "$IDLE_SAMPLES"
    fi
else
    record_result 'Automated idle resource trend' FAIL 'Release executable was not built'
fi

record_result 'VoiceOver/keyboard/RTL inspection' MANUAL 'Requires Accessibility Inspector and human evaluation'
record_result 'About credits and external links' MANUAL 'Requires keyboard/VoiceOver/link inspection in the About window'
record_result 'Sleep/wake and clock mutation' MANUAL 'Requires controlled physical-system state changes'
record_result 'Notch/non-notch/external display' MANUAL 'Requires representative hardware/display configurations'
record_result 'Launch-at-login approval flow' MANUAL 'Requires interactive ServiceManagement approval state'
record_result 'Gatekeeper Open Anyway flow' MANUAL 'Requires a quarantined GitHub download on a fresh macOS user profile'
record_result 'Idle wakeup attribution' MANUAL 'Requires Instruments System Trace/Power Profiler analysis'

{
    printf '# Ayah release-candidate automated checks\n\n'
    printf -- '- Recorded at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf -- '- Revision: `%s`\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
    printf -- '- Worktree dirty: `%s`\n' "$(if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then printf true; else printf false; fi)"
    printf -- '- Automated failures: **%s**\n' "$FAILURES"
    printf -- '- Raw artifact directory: `%s`\n\n' "$OUTPUT_DIR"
    printf '| Check | Status | Evidence |\n'
    printf '|---|---|---|\n'
    awk -F '\t' 'NR > 1 { printf "| %s | %s | `%s` |\n", $1, $2, $3 }' "$RESULTS"
    printf '\nManual statuses are not failures and must not be interpreted as passes.\n'
} > "$REPORT"

printf '\nRelease-candidate report: %s\n' "$REPORT"
printf 'Automated failures: %s\n' "$FAILURES"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
