#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-OneTwenty}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.example.onetwenty}"

BUILD_DIR="$ROOT_DIR/.build/$BUILD_CONFIG"
BINARY="$BUILD_DIR/$APP_NAME"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INFO_TEMPLATE="$ROOT_DIR/Resources/Info.plist"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG"

if [[ ! -f "$BINARY" ]]; then
    echo "Expected binary not found: $BINARY" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

/usr/bin/sed \
    -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD_NUMBER|g" \
    "$INFO_TEMPLATE" > "$INFO_PLIST"

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
echo "App bundle created at $APP_BUNDLE"
