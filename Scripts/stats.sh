#!/bin/bash
# stats.sh — measure what an app costs on this Mac: disk and memory.
#
#   ./Scripts/stats.sh                 Phono
#   ./Scripts/stats.sh Detta           Phono, then Detta, for comparison
#
# Memory is the resident size of the app plus every process it started, so
# a helper (like a Python engine) counts too. Open the apps and let them
# finish loading first.
set -euo pipefail

MODEL="${PHONO_MODEL_DIR:-$HOME/Library/Application Support/Phono/Phonon-2-CoreML}"
# Core ML's copy of the model, compiled for this Mac on first launch.
COMPILED="$HOME/Library/Caches/phonon-coreml"

megabytes() {   # size of the given paths on disk, in MB
  du -sk "$@" 2>/dev/null | awk '{ kb += $1 } END { printf "%d MB", kb / 1024 }'
}

memory() {   # resident memory of a process and all its descendants, in MB
  ps -A -o pid=,ppid=,rss= | awk -v root="$1" '
    { parent[$1] = $2; rss[$1] = $3 }
    END {
      for (pid in rss) {
        for (p = pid; p != "" && p != 0 && p != 1; p = parent[p]) {
          if (p == root) { total += rss[pid]; break }
        }
      }
      printf "%d MB", total / 1024
    }'
}

report() {   # name, app bundle, process name, extra files that belong to it
  local name="$1" app="$2" process="$3"
  shift 3
  local pid
  pid="$(pgrep -x "$process" | head -1 || true)"
  echo "$name"
  echo "  On disk:  $(megabytes "$app" "$@")"
  if [[ -n "$pid" ]]; then
    echo "  Memory:   $(memory "$pid")"
  else
    echo "  Memory:   not running"
  fi
}

report "Phono" "${PHONO_APP:-/Applications/Phono.app}" phono "$MODEL" "$COMPILED"
if [[ $# -gt 0 ]]; then
  report "$1" "/Applications/$1.app" "$1"
fi
