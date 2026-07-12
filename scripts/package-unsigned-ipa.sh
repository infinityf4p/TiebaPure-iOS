#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
PACKAGE_ROOT="$BUILD_DIR/unsigned-ipa"
DERIVED_DATA="$PACKAGE_ROOT/DerivedData"
ARCHIVE_PATH="$PACKAGE_ROOT/TiebaPure.xcarchive"
PAYLOAD_DIR="$PACKAGE_ROOT/Payload"
APP_NAME="TiebaPure.app"
OUTPUT="$BUILD_DIR/TiebaPure-unsigned.ipa"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT" && xcodegen generate >/dev/null)
fi

rm -rf "$PACKAGE_ROOT" "$OUTPUT"
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

/usr/bin/ditto "$APP_PATH" "$PAYLOAD_DIR/$APP_NAME"
rm -rf "$PAYLOAD_DIR/$APP_NAME/_CodeSignature"
rm -f "$PAYLOAD_DIR/$APP_NAME/embedded.mobileprovision"

(cd "$PACKAGE_ROOT" && /usr/bin/zip -qry "$OUTPUT" Payload)

echo "$OUTPUT"
