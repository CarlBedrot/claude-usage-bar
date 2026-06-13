#!/usr/bin/env bash
# Build ClaudeUsageBar and assemble a runnable, ad-hoc-signed .app bundle.
# No Xcode required: SwiftPM release build + hand-assembled bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsageBar"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> swift build -c release"
swift build -c release

BINARY=".build/release/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    echo "error: release binary not found at $BINARY" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Ad-hoc codesign"
codesign --force --sign - "$APP_BUNDLE"

echo "==> Done: $(pwd)/$APP_BUNDLE"
