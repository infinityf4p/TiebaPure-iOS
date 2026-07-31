#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
PACKAGE_ROOT="$BUILD_DIR/unsigned-ipa"
DERIVED_DATA="${TIEBAPURE_DERIVED_DATA:-/private/tmp/TiebaPurePackageDerivedData}"
ARCHIVE_PATH="$PACKAGE_ROOT/TiebaPure.xcarchive"
PAYLOAD_DIR="$PACKAGE_ROOT/Payload"
APP_NAME="TiebaPure.app"
OUTPUT="$BUILD_DIR/TiebaPure-unsigned.ipa"
XCODEGEN_CHECK_DIR=""

cleanup() {
  if [[ -n "$XCODEGEN_CHECK_DIR" ]]; then
    rm -rf "$XCODEGEN_CHECK_DIR"
  fi
}
trap cleanup EXIT

if [[ "${TIEBAPURE_SKIP_XCODEGEN_CHECK:-}" == "1" ]]; then
  echo "WARNING: TIEBAPURE_SKIP_XCODEGEN_CHECK=1 is set." >&2
  echo "WARNING: Skipping the xcodegen project-consistency release gate; the packaged IPA may not match project.yml." >&2
elif ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to verify TiebaPure.xcodeproj matches project.yml before packaging." >&2
  echo "Install xcodegen, or set TIEBAPURE_SKIP_XCODEGEN_CHECK=1 to bypass this release gate." >&2
  exit 1
else
  XCODEGEN_CHECK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/TiebaPureXcodeGen.XXXXXX")"
  cp "$ROOT/project.yml" "$XCODEGEN_CHECK_DIR/project.yml"
  ln -s "$ROOT/TiebaPure" "$XCODEGEN_CHECK_DIR/TiebaPure"
  ln -s "$ROOT/TiebaPureTests" "$XCODEGEN_CHECK_DIR/TiebaPureTests"
  ln -s "$ROOT/TiebaPureUITests" "$XCODEGEN_CHECK_DIR/TiebaPureUITests"
  ln -s "$ROOT/LICENSE" "$XCODEGEN_CHECK_DIR/LICENSE"
  ln -s "$ROOT/LICENSES" "$XCODEGEN_CHECK_DIR/LICENSES"
  xcodegen generate \
    --spec "$XCODEGEN_CHECK_DIR/project.yml" \
    --project "$XCODEGEN_CHECK_DIR" \
    --project-root "$XCODEGEN_CHECK_DIR" \
    --quiet

  if ! cmp -s \
    "$ROOT/TiebaPure.xcodeproj/project.pbxproj" \
    "$XCODEGEN_CHECK_DIR/TiebaPure.xcodeproj/project.pbxproj"; then
    echo "TiebaPure.xcodeproj is out of date with project.yml." >&2
    diff -u \
      "$ROOT/TiebaPure.xcodeproj/project.pbxproj" \
      "$XCODEGEN_CHECK_DIR/TiebaPure.xcodeproj/project.pbxproj" >&2 || true
    exit 1
  fi

  rm -rf "$XCODEGEN_CHECK_DIR"
  XCODEGEN_CHECK_DIR=""
fi

mkdir -p "$PACKAGE_ROOT"
rm -rf "$ARCHIVE_PATH" "$PAYLOAD_DIR" "$OUTPUT"
mkdir -p "$PAYLOAD_DIR"

xcodebuild \
  -quiet \
  -project "$ROOT/TiebaPure.xcodeproj" \
  -scheme TiebaPure \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CADisableMinimumFrameDurationOnPhone' "$APP_PATH/Info.plist")" != "true" ]]; then
  echo "Packaged app must opt into adaptive ProMotion frame rates." >&2
  exit 1
fi

/usr/bin/ditto "$APP_PATH" "$PAYLOAD_DIR/$APP_NAME"
rm -rf "$PAYLOAD_DIR/$APP_NAME/_CodeSignature"
rm -f "$PAYLOAD_DIR/$APP_NAME/embedded.mobileprovision"

(cd "$PACKAGE_ROOT" && /usr/bin/zip -qry "$OUTPUT" Payload)

echo "$OUTPUT"
