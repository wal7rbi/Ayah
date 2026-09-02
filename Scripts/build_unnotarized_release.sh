#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

usage() {
    cat <<'USAGE'
Usage: Scripts/build_unnotarized_release.sh --output <directory> [mode]

Builds and verifies Ayah's Apple-Silicon-only, ad-hoc-signed,
unnotarized DMG. It never commits, tags, configures a remote, or publishes.

Required:
  --output <directory>       Directory for the DMG, checksum, and report.

Stable mode:
  --manual-qa-approved       Assert the manual stable-release checklist passed.
                             Requires a clean tree at annotated tag v1.0.2.

Rehearsal mode:
  --allow-dirty-rehearsal   Permit a dirty tree and run shortened resource
                             checks. Output is marked REHEARSAL and must not
                             be published.

  -h, --help                 Show this help.
USAGE
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

OUTPUT_DIR=""
MANUAL_QA_APPROVED=0
REHEARSAL=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            [ "$#" -ge 2 ] || fail "--output requires a directory"
            OUTPUT_DIR=$2
            shift 2
            ;;
        --manual-qa-approved)
            MANUAL_QA_APPROVED=1
            shift
            ;;
        --allow-dirty-rehearsal)
            REHEARSAL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) fail "unknown option: $1" ;;
    esac
done

[ -n "$OUTPUT_DIR" ] || fail "--output is required"
[ "$REHEARSAL" -eq 0 ] || [ "$MANUAL_QA_APPROVED" -eq 0 ] \
    || fail "--manual-qa-approved and --allow-dirty-rehearsal are mutually exclusive"

for COMMAND in awk basename bash codesign cmp date ditto find git grep hdiutil lipo ln mkdir mktemp plutil rm sed shasum strings tail tr wc xcodebuild; do
    command -v "$COMMAND" >/dev/null 2>&1 || fail "required command not found: $COMMAND"
done

EXPECTED_VERSION=1.0.2
EXPECTED_BUILD=3
EXPECTED_TAG=v$EXPECTED_VERSION
REVISION=$(git -C "$REPO_ROOT" rev-parse HEAD) || fail "could not resolve HEAD"
WORKTREE_STATUS=$(git -C "$REPO_ROOT" status --porcelain)

if [ "$REHEARSAL" -eq 0 ]; then
    [ "$MANUAL_QA_APPROVED" -eq 1 ] || fail "stable packaging requires --manual-qa-approved"
    [ -z "$WORKTREE_STATUS" ] || fail "stable packaging requires a clean worktree"
    CURRENT_TAG=$(git -C "$REPO_ROOT" describe --tags --exact-match HEAD 2>/dev/null) \
        || fail "stable packaging requires HEAD to be tagged $EXPECTED_TAG"
    [ "$CURRENT_TAG" = "$EXPECTED_TAG" ] || fail "HEAD tag is $CURRENT_TAG, expected $EXPECTED_TAG"
    [ "$(git -C "$REPO_ROOT" cat-file -t "refs/tags/$EXPECTED_TAG" 2>/dev/null)" = tag ] \
        || fail "$EXPECTED_TAG must be an annotated tag"
    ARTIFACT_STEM=Ayah-$EXPECTED_VERSION-macOS-arm64
    RELEASE_MODE="Stable release"
else
    TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
    ARTIFACT_STEM=Ayah-$EXPECTED_VERSION-macOS-arm64-REHEARSAL-$TIMESTAMP
    RELEASE_MODE="Dirty-tree rehearsal — DO NOT PUBLISH"
fi

mkdir -p "$OUTPUT_DIR" || fail "could not create output directory"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)

DMG_PATH=$OUTPUT_DIR/$ARTIFACT_STEM.dmg
CHECKSUM_PATH=$OUTPUT_DIR/$ARTIFACT_STEM.dmg.sha256
REPORT_PATH=$OUTPUT_DIR/$ARTIFACT_STEM-release-report.md

for ARTIFACT in "$DMG_PATH" "$CHECKSUM_PATH" "$REPORT_PATH"; do
    [ ! -e "$ARTIFACT" ] || fail "refusing to overwrite existing artifact: $ARTIFACT"
done

WORK_DIR=$(mktemp -d /private/tmp/ayah-unnotarized-release.XXXXXX) \
    || fail "could not create temporary work directory"
MOUNT_DIR=$WORK_DIR/mount
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT INT TERM

CHECKS_DIR=$WORK_DIR/release-checks
if [ "$REHEARSAL" -eq 1 ]; then
    "$REPO_ROOT/Scripts/run_release_candidate_checks.sh" \
        --idle-minutes 1 \
        --ui-cycles 20 \
        --output "$CHECKS_DIR" \
        || fail "shortened release-candidate checks failed"
else
    "$REPO_ROOT/Scripts/run_release_candidate_checks.sh" \
        --idle-minutes 30 \
        --ui-cycles 200 \
        --output "$CHECKS_DIR" \
        || fail "release-candidate checks failed"
fi

PACKAGE_STORAGE=$REPO_ROOT/Packages/AyahKit/.build
[ -d "$PACKAGE_STORAGE/checkouts/adhan-swift/.git" ] \
    || fail "local pinned Adhan checkout is missing; refusing network resolution"

DERIVED_DATA=$WORK_DIR/DerivedData
BUILD_LOG=$WORK_DIR/xcodebuild-release.log
if ! xcodebuild \
    -project "$REPO_ROOT/Ayah.xcodeproj" \
    -scheme Ayah \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$PACKAGE_STORAGE" \
    -disableAutomaticPackageResolution \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build > "$BUILD_LOG" 2>&1; then
    tail -240 "$BUILD_LOG" >&2
    fail "final Release build failed"
fi

APP_PATH=$DERIVED_DATA/Build/Products/Release/Ayah.app
EXECUTABLE=$APP_PATH/Contents/MacOS/Ayah
[ -d "$APP_PATH" ] || fail "Release app was not produced"
[ -x "$EXECUTABLE" ] || fail "Release executable was not produced"

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")
[ "$VERSION" = "$EXPECTED_VERSION" ] || fail "built version is $VERSION, expected $EXPECTED_VERSION"
[ "$BUILD" = "$EXPECTED_BUILD" ] || fail "built build number is $BUILD, expected $EXPECTED_BUILD"
[ "$(lipo -archs "$EXECUTABLE")" = arm64 ] || fail "Release executable is not arm64-only"

codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
    || fail "ad-hoc code signature verification failed"
SIGNATURE_DETAILS=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
printf '%s\n' "$SIGNATURE_DETAILS" | grep -q '^Signature=adhoc$' \
    || fail "Release app is not ad-hoc signed"
printf '%s\n' "$SIGNATURE_DETAILS" | grep -q '^TeamIdentifier=not set$' \
    || fail "Release app unexpectedly contains a TeamIdentifier"
printf '%s\n' "$SIGNATURE_DETAILS" | grep -q '^CodeDirectory .*[(]adhoc,runtime[)]' \
    || fail "Release app is missing hardened runtime"

ENTITLEMENTS=$WORK_DIR/embedded-entitlements.plist
codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null \
    || fail "could not inspect embedded entitlements"
[ "$(plutil -p "$ENTITLEMENTS" | grep -c '=>')" -eq 2 ] \
    || fail "Release app must contain exactly two entitlements"
grep -q 'com.apple.security.app-sandbox' "$ENTITLEMENTS" \
    || fail "Release app is missing App Sandbox"
grep -q 'com.apple.security.personal-information.location' "$ENTITLEMENTS" \
    || fail "Release app is missing location entitlement"
for FORBIDDEN in \
    com.apple.security.get-task-allow \
    com.apple.security.network.client \
    com.apple.security.network.server; do
    ! grep -q "$FORBIDDEN" "$ENTITLEMENTS" \
        || fail "Release app contains forbidden entitlement: $FORBIDDEN"
done

for RESOURCE in \
    quran.sqlite \
    cities_filtered.sqlite \
    CHECKSUM \
    GEONAMES_CHECKSUM \
    uthmanic_hafs_v20.ttf \
    Adhan-LICENSE.txt \
    GeoNames-NOTICE.txt \
    ACKNOWLEDGEMENTS.txt; do
    [ -f "$APP_PATH/Contents/Resources/$RESOURCE" ] \
        || fail "Release app is missing required resource: $RESOURCE"
done

! strings "$EXECUTABLE" | grep -q 'AYAH_PERFORMANCE_WARMUP_STARTED' \
    || fail "Release app contains profiling automation"

STAGING_DIR=$WORK_DIR/dmg-root
mkdir -p "$STAGING_DIR" || fail "could not create DMG staging directory"
ditto "$APP_PATH" "$STAGING_DIR/Ayah.app" || fail "could not stage Ayah.app"
ln -s /Applications "$STAGING_DIR/Applications" || fail "could not add Applications shortcut"

hdiutil create \
    -volname "Ayah $EXPECTED_VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    "$DMG_PATH" >/dev/null \
    || fail "could not create DMG"

mkdir -p "$MOUNT_DIR" || fail "could not create verification mount point"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null \
    || fail "could not mount the finished DMG read-only"
MOUNTED=1

codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/Ayah.app" \
    || fail "mounted app signature verification failed"
cmp -s "$EXECUTABLE" "$MOUNT_DIR/Ayah.app/Contents/MacOS/Ayah" \
    || fail "mounted app executable differs from the verified build"
cmp -s \
    "$APP_PATH/Contents/Resources/ACKNOWLEDGEMENTS.txt" \
    "$MOUNT_DIR/Ayah.app/Contents/Resources/ACKNOWLEDGEMENTS.txt" \
    || fail "mounted acknowledgements differ from the verified build"
[ -L "$MOUNT_DIR/Applications" ] || fail "mounted DMG is missing the Applications shortcut"

DMG_ROOT_ENTRIES=$(find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 ! -name '.Trashes' ! -name '.fseventsd' | wc -l | tr -d ' ')
[ "$DMG_ROOT_ENTRIES" -eq 2 ] \
    || fail "mounted DMG must contain only Ayah.app and the Applications shortcut"

hdiutil detach "$MOUNT_DIR" >/dev/null || fail "could not detach verification DMG"
MOUNTED=0

DMG_NAME=$(basename "$DMG_PATH")
(
    cd "$OUTPUT_DIR" || exit 1
    shasum -a 256 "$DMG_NAME" > "$(basename "$CHECKSUM_PATH")"
) || fail "could not write SHA-256 checksum"
(
    cd "$OUTPUT_DIR" || exit 1
    shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
) >/dev/null || fail "finished DMG checksum verification failed"

DMG_SHA256=$(awk '{ print $1 }' "$CHECKSUM_PATH")
{
    printf '# Ayah %s unnotarized release report\n\n' "$EXPECTED_VERSION"
    printf -- '- Mode: **%s**\n' "$RELEASE_MODE"
    printf -- '- Revision: `%s`\n' "$REVISION"
    printf -- '- Expected tag: `%s`\n' "$EXPECTED_TAG"
    printf -- '- Architecture: `arm64`\n'
    printf -- '- Minimum macOS: `13.0`\n'
    printf -- '- Signature: ad-hoc, hardened runtime, no Apple TeamIdentifier\n'
    printf -- '- Notarization: **none**\n'
    printf -- '- Entitlements: App Sandbox and Location only\n'
    printf -- '- DMG: `%s`\n' "$DMG_NAME"
    printf -- '- SHA-256: `%s`\n' "$DMG_SHA256"
    printf -- '- Manual QA assertion: `%s`\n\n' "$(if [ "$MANUAL_QA_APPROVED" -eq 1 ]; then printf approved; else printf rehearsal-only; fi)"
    printf '## Automated release-candidate results\n\n'
    awk -F '\t' 'NR > 1 { printf "- %s: **%s**\n", $1, $2 }' "$CHECKS_DIR/results.tsv"
    printf '\nThis artifact is not signed by an identified Apple developer and is not notarized. Users must explicitly approve first launch through macOS Privacy & Security.\n'
} > "$REPORT_PATH"

printf '\nCreated %s\n' "$DMG_PATH"
printf 'Checksum %s\n' "$CHECKSUM_PATH"
printf 'Report   %s\n' "$REPORT_PATH"
if [ "$REHEARSAL" -eq 1 ]; then
    printf 'WARNING: rehearsal artifact; do not publish.\n'
fi
