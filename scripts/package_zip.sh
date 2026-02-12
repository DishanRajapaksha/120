#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-OneTwenty}"
VERSION="${VERSION:-1.0.0}"

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.zip"

if [[ ! -d "$APP_BUNDLE" ]]; then
    "$ROOT_DIR/scripts/build_app.sh"
fi

rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
echo "ZIP package created at $ZIP_PATH"
