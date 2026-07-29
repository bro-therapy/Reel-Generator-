#!/usr/bin/env bash
#
# Render a scene to PNG without a monitor.
#
#   ./tools/screenshot.sh scenes/tests/species_field.tscn build/shots/species.png
#   ./tools/screenshot.sh scenes/tests/enemy_field.tscn build/shots/enemy.png 60 180 300
#
# Extra numbers capture the same run at several frames, which is how you catch
# an animation or a telegraph instead of a static pose.
#
# Wraps scripts/tools/capture_scene.gd in a virtual X display with software GL,
# so it works on a headless box. `--headless` cannot be used instead: its dummy
# renderer draws nothing and every pixel comes back blank.
#
# Needs Xvfb and Mesa. On the Mac just run Godot normally — you have a screen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${1:-}"
OUT="${2:-build/shots/capture.png}"
shift 2 2>/dev/null || true

if [[ -z "$SCENE" ]]; then
  echo "usage: $0 <scene.tscn> [out.png] [frame ...]" >&2
  exit 1
fi

if ! command -v xvfb-run >/dev/null; then
  echo "✗ xvfb-run not found — install Xvfb, or run Godot directly if you have a display" >&2
  exit 1
fi

# llvmpipe: no GPU here, and Vulkan has no software fallback installed, so the
# OpenGL driver is the one that works.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

cd "$ROOT"
xvfb-run -a --server-args="-screen 0 1920x1080x24" \
  godot --path . \
    --display-driver x11 \
    --rendering-driver opengl3 \
    --resolution 1920x1080 \
    --script scripts/tools/capture_scene.gd \
    -- "$SCENE" "$OUT" "$@" 2>&1 |
  grep -viE "ALSA|pulse|V-Sync|audio driver|servers/audio|gl_manager|^\s*at: |^$" || true
