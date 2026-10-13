#!/bin/bash
# Build a signed Phono.app bundle from the SwiftPM executable.
set -euo pipefail

# Resolve repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Phono"
BUNDLE_ID="io.github.eriko13.phono"   # must match Settings.domain
BIN_NAME="phono"

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
YEAR="$(date +%Y)"

# VERSION is the single source of truth; the menu reads it back from Info.plist.
if [[ ! -f "$ROOT_DIR/VERSION" ]]; then
  echo "error: VERSION file not found at $ROOT_DIR/VERSION" >&2
  exit 1
fi
VERSION="$(tr -d ' \t\n\r' < "$ROOT_DIR/VERSION")"

# Release build flags for the shipped binary only. -Osize optimizes for size,
# -dead_strip drops unreachable code.
RELEASE_FLAGS=(-c release --arch arm64 -Xswiftc -Osize -Xlinker -dead_strip)

echo "==> Building release (arm64, -Osize, dead-strip)…"
swift build "${RELEASE_FLAGS[@]}"

BIN_PATH="$(swift build "${RELEASE_FLAGS[@]}" --show-bin-path)/$BIN_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: built binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_NAME.app (version $VERSION)…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$BIN_NAME"

# Strip the shipped copy before signing; stripping after would break the
# signature.
echo "==> Stripping symbols from shipped binary…"
strip -rSTx "$MACOS_DIR/$BIN_NAME"

echo "==> Building the app icon from Assets/icon.png…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" Assets/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z $((SIZE * 2)) $((SIZE * 2)) Assets/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Phono records while you hold the dictation shortcut. Audio is transcribed on this Mac, or on your own Phonon server if you set one.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- A Phonon server on a tailnet or LAN is usually plain http. -->
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $YEAR Phono contributors. MIT License.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing…"
codesign --force --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
