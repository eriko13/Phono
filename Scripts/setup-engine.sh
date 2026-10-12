#!/bin/bash
# setup-engine.sh — install the local Phonon-2 engine Phono talks to.
#
# Creates a private Python venv, installs FermionResearch's `fermion` CLI with
# its MLX backend, and downloads the Phonon-2 weights (164 MB) from Hugging
# Face. This is the only step that uses the network. After it, dictation runs
# fully offline.
#
# Nothing here needs sudo. Everything lands in:
#   ~/Library/Application Support/Phono/engine/.venv
# Delete that folder to remove the engine.
set -euo pipefail

ENGINE_DIR="$HOME/Library/Application Support/Phono/engine"
VENV="$ENGINE_DIR/.venv"

# --- Preflight ---------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "error: the MLX engine needs a Mac with Apple silicon." >&2
  exit 1
fi

# macOS's own python3 is 3.9; the engine needs 3.10 or newer.
PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3.10 \
                 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 \
                 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.10 python3; do
  if command -v "$candidate" >/dev/null 2>&1 &&
     "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PYTHON="$(command -v "$candidate")"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  cat >&2 <<'MSG'
error: Python 3.10 or newer not found (macOS ships 3.9).

Install one, then re-run this script:

    brew install python@3.12
MSG
  exit 1
fi
echo "==> Using $PYTHON ($("$PYTHON" --version))"

# --- Venv + packages ---------------------------------------------------------
mkdir -p "$ENGINE_DIR"
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "==> Creating venv at ${VENV}…"
  "$PYTHON" -m venv "$VENV"
fi

echo "==> Installing the fermion CLI…"
"$VENV/bin/pip" install --quiet --upgrade pip
# Order matters: the engine docs install fermion-research first, then MLX.
"$VENV/bin/pip" install --quiet --upgrade fermion-research
echo "==> Installing the MLX backend…"
"$VENV/bin/pip" install --quiet --upgrade mlx mlx-audio mlx-lm soundfile scipy zstandard

# --- Model -------------------------------------------------------------------
# Transcribing one second of silence downloads and verifies Phonon-2 and
# proves the whole chain works before Phono depends on it.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
"$VENV/bin/python" - "$SCRATCH/silence.wav" <<'PY'
import sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    w.writeframes(b"\x00\x00" * 16000)
PY

echo "==> Downloading and checking Phonon-2 (164 MB, first run only)…"
"$VENV/bin/fermion" transcribe phonon-2 "$SCRATCH/silence.wav" >/dev/null

cat <<MSG

Engine ready: $VENV/bin/fermion

Phono finds it there by itself. Start (or restart) Phono and hold ⌥ Option
to dictate.
MSG
