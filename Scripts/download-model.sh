#!/bin/bash
# download-model.sh — download Phonon-2 for Core ML (345 MB) from Hugging Face.
#
# The files are pinned to one revision and checked against SHA-256 sums.
# This is the only step that uses the network; Phono itself never does.
# To remove the model, delete the folder it prints.
set -euo pipefail

REVISION="1143812fd4236522232a8c33e3115f0577e3cd7d"
BASE="https://huggingface.co/FermionResearch/Phonon-2-CoreML/resolve/$REVISION"
DEST="${PHONO_MODEL_DIR:-$HOME/Library/Application Support/Phono/Phonon-2-CoreML}"

# The files Phono reads (see Sources/PhonoCore/Model.swift), plus the
# licenses that must travel with the weights.
SUMS="ab3fb5dfd3fc07b1d8a24379d04418f458d0443ba6359d3a5ab2f098a7d64089  manifest.json
36fa7202dda85c603af60d930ab88d7e9f0d2a619490aff46f5384db924cfa70  decoder.bin
6ebc9309aea0e16bda9c7558521fef6307fac0afba9a5b4959fea45ed7cd0429  Phonon-2.mlpackage/Manifest.json
4f6790ec94fe4429b10397c013563d0a51119953ff6d3da466bbcb23a25dee2a  Phonon-2.mlpackage/Data/com.apple.CoreML/model.mlmodel
93aa991318a00ed492fdbb724e7bca4e6a69c6cf671ab4f14a14ef6101e7648b  Phonon-2.mlpackage/Data/com.apple.CoreML/weights/weight.bin
9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411  LICENSE-WEIGHTS-CC-BY-4.0.txt
b468a23a1ce2c5181ea4050432bb68713a6468ce2e452927228d24f3d56226be  NOTICE"

verify() {
  (cd "$1" && shasum -a 256 -c --status <<< "$SUMS") 2>/dev/null
}

if [[ -d "$DEST" ]] && verify "$DEST"; then
  echo "==> Phonon-2 is already in $DEST"
  exit 0
fi

# Download next to the destination, then move it into place in one step, so
# an interrupted download never leaves a half-written model behind.
mkdir -p "$(dirname "$DEST")"
TMP="$(mktemp -d "$(dirname "$DEST")/.download.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
chmod 755 "$TMP"   # mktemp makes it private

echo "==> Downloading Phonon-2 for Core ML (345 MB)…"
while read -r _ FILE; do
  mkdir -p "$TMP/$(dirname "$FILE")"
  curl --fail --location --retry 3 --silent --show-error -o "$TMP/$FILE" "$BASE/$FILE"
done <<< "$SUMS"

if ! verify "$TMP"; then
  echo "error: the download does not match its SHA-256 sums. Try again." >&2
  exit 1
fi

rm -rf "$DEST"
mv "$TMP" "$DEST"
echo "==> Phonon-2 is in $DEST"
