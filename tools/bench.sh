#!/usr/bin/env bash
#
# Render the game at combat density and report what costs frames.
#
#   ./tools/bench.sh 75
#   ./tools/bench.sh 250
#   ./tools/bench.sh 250 12    # ...plus twelve live realistic effects
#
# Runs under Xvfb with software GL, so frame time is comparable between runs on
# this machine and meaningless as an absolute. Draw calls and primitive counts
# are hardware-independent and are the numbers to optimise against.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
cd "$ROOT"
xvfb-run -a --server-args="-screen 0 1920x1080x24" \
  godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
    --script scripts/tools/density_bench.gd -- "${1:-150}" "${2:-0}" 2>&1 |
  grep -viE "ALSA|pulse|V-Sync|audio driver|servers/audio|gl_manager|^\s*at: |^$|^Godot Engine|Condition .status" || true
