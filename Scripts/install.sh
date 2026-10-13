#!/bin/bash
# install.sh — download the model, build Phono, install it to
# /Applications, and launch it.
#
# This is Scripts/download-model.sh plus Scripts/bundle.sh plus the manual
# steps that follow. Nothing here is privileged. Read it before you run it — that is
# the point of Phono being distributed as source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Phono"
BIN_NAME="phono"
BUNDLE_ID="io.github.eriko13.phono"
SRC="$ROOT_DIR/build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
OLD_ENGINE="$HOME/Library/Application Support/Phono/engine"

# --- Preflight: the Swift toolchain -----------------------------------------
if ! command -v swift >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: no Swift toolchain found.

Install Apple's command line tools first, then re-run this script:

    xcode-select --install
MSG
  exit 1
fi

# --- Model -------------------------------------------------------------------
"$SCRIPT_DIR/download-model.sh"

# --- Build -------------------------------------------------------------------
"$SCRIPT_DIR/bundle.sh"

if [[ ! -d "$SRC" ]]; then
  echo "error: expected a bundle at $SRC but bundle.sh produced none" >&2
  exit 1
fi

# --- Replace any previous install -------------------------------------------
if pgrep -x "$BIN_NAME" >/dev/null 2>&1; then
  echo "==> Quitting the running ${APP_NAME}…"
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || pkill -x "$BIN_NAME" || true
  sleep 1
fi

if [[ -e "$DEST" ]]; then
  # Only ever remove something that is actually Phono.
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$DEST/Contents/Info.plist" 2>/dev/null || echo "")"
  if [[ "$EXISTING_ID" != "$BUNDLE_ID" ]]; then
    echo "error: $DEST exists but its bundle id is '$EXISTING_ID', not '$BUNDLE_ID'." >&2
    echo "       Refusing to replace it. Move it aside yourself and re-run." >&2
    exit 1
  fi
  echo "==> Replacing the existing ${DEST}…"
  rm -rf "$DEST"
fi

echo "==> Installing to ${DEST}…"
cp -R "$SRC" "$DEST"

echo "==> Launching ${APP_NAME}…"
open "$DEST"

cat <<MSG

Installed: $DEST

  1. Allow the microphone when macOS asks.
  2. Allow Accessibility when asked (Privacy & Security › Accessibility).
     Phono needs it to see the Option key on its own, and to paste.
     This build is ad-hoc signed: after each rebuild, remove the old "Phono"
     row in that list and add the new one.
  3. Wait until the menu-bar wave is no longer dimmed. The first launch
     prepares the model for this Mac, which takes a minute or two. Then hold
     ⌥ Option and talk.

MSG

# Phono 0.1 ran a Python engine. It is no longer used.
if [[ -d "$OLD_ENGINE" ]]; then
  cat <<MSG
The old Python engine is no longer used. To free about 2 GB, run:

    rm -rf "$OLD_ENGINE"

MSG
fi
