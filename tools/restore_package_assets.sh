#!/usr/bin/env bash
#
# Restore the prototype art from the first-playtest package.
#
#   ./tools/restore_package_assets.sh ~/Downloads/Project_Zero_Climb_First_Playtest_v1.0
#   ./tools/restore_package_assets.sh ~/Downloads/Project_Zero_Climb_First_Playtest_v1.0.zip
#
# The 209 prototype assets are not committed from the remote build environment,
# whose network policy blocks lfs.github.com. Run this once locally, then commit
# them yourself with Git LFS working:
#
#   git lfs install
#   git add assets && git commit -m "chore: add prototype assets via LFS" && git push
#
set -euo pipefail

SRC="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$SRC" ]]; then
  echo "usage: $0 <path-to-package-dir-or-zip>" >&2
  exit 1
fi

WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

if [[ "$SRC" == *.zip ]]; then
  WORK="$(mktemp -d)"
  echo "→ extracting $(basename "$SRC")"
  unzip -q "$SRC" -d "$WORK"
  # No depth limit. The real package zip wraps everything in a version-named
  # directory, so level1_prototype/ sits three levels down —  `-maxdepth 2` found
  # nothing, `dirname ""` became ".", and the error blamed the current directory.
  # Searching the whole extraction costs nothing and works whatever the wrapper.
  FOUND="$(find "$WORK" -type d -name 'level1_prototype' -print -quit)"
  if [[ -z "$FOUND" ]]; then
    echo "✗ no level1_prototype/ anywhere inside $(basename "$SRC")" >&2
    echo "  contents:" >&2
    find "$WORK" -maxdepth 2 -type d | sed "s|$WORK|  |" >&2
    exit 1
  fi
  SRC="$(dirname "$FOUND")"
else
  [[ -d "$SRC/assets/level1_prototype" ]] && SRC="$SRC/assets"
fi

PROTO="$SRC/level1_prototype"
if [[ ! -d "$PROTO" ]]; then
  echo "✗ could not find level1_prototype/ under $SRC" >&2
  exit 1
fi

for c in actors enemies environment ui vfx maps; do
  if [[ -d "$PROTO/$c" ]]; then
    mkdir -p "$ROOT/assets/$c"
    cp -r "$PROTO/$c/." "$ROOT/assets/$c/"
    printf "  %-14s %s files\n" "$c" "$(find "$ROOT/assets/$c" -type f | wc -l | tr -d ' ')"
  fi
done

echo
echo "✓ restored $(find "$ROOT/assets" -type f | wc -l | tr -d ' ') files into assets/"
echo
echo "Next:"
echo "  godot --headless --path . --import"
echo "  godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd"
echo "  godot --headless --path . --script scripts/tests/phase1_acceptance.gd"
