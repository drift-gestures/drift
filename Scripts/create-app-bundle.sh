#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/drift.app"
ZIP_PATH="$ROOT_DIR/build/drift.zip"
DERIVED_DATA_DIR="$ROOT_DIR/build/XcodeDerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILT_APP_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/drift.app"

rm -rf "$APP_DIR" "$ZIP_PATH" "$DERIVED_DATA_DIR"
mkdir -p "$ROOT_DIR/build"

xcodebuild \
  -project "$ROOT_DIR/drift.xcodeproj" \
  -scheme drift \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -destination "platform=macOS" \
  build

if [[ ! -d "$BUILT_APP_DIR" ]]; then
  echo "drift.app not found at expected Xcode build path: $BUILT_APP_DIR"
  exit 1
fi

ditto "$BUILT_APP_DIR" "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$APP_DIR"
echo "$ZIP_PATH"
