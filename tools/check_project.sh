#!/usr/bin/env bash
#
# Run everything. One command to answer "is this project healthy?"
#
#   ./tools/check_project.sh
#
# Runs the sixteen phase suites plus the effects and audio suites, and reports a
# single total. Exits non-zero if anything failed, so it works as a CI gate and as
# the thing you run before believing a change.
#
# Suites that need assets skip cleanly rather than failing when assets/ is absent,
# so this is also safe to run on a fresh clone — it will just tell you the art is
# missing instead of pretending that is a defect.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null; then
  echo "✗ '$GODOT' not on PATH. Set GODOT=/path/to/godot" >&2
  exit 1
fi

echo "Project Zero Climb — full check"
echo "$("$GODOT" --version 2>/dev/null | head -1)"
echo

total_pass=0
total_fail=0
failed_suites=()

run_suite() {
  local label="$1" script="$2"
  local out
  out="$("$GODOT" --headless --path . --script "$script" 2>&1)"
  local line
  line="$(echo "$out" | grep -E "[0-9]+ passed, [0-9]+ failed" | tail -1)"

  # A suite that passes every assertion while spraying script errors is not
  # green. This is exactly how the freed-enemy targeting bug shipped: the guard
  # returned false either way, so no assertion could see the error — but the
  # editor halts on it, which read as "the game crashed" in the first playtest.
  # Plain ERROR: lines are NOT counted: the dummy renderer emits hundreds of
  # them ("Parameter m is null") on scenes a real renderer draws cleanly.
  local script_errors
  script_errors="$(echo "$out" | grep -c "^SCRIPT ERROR:")"
  if [[ "$script_errors" != "0" ]]; then
    printf "  %-22s ✗ %s script error(s) at runtime\n" "$label" "$script_errors"
    echo "$out" | grep -A1 "^SCRIPT ERROR:" | head -6 | sed 's/^/      /'
    failed_suites+=("$label")
    total_fail=$((total_fail + 1))
    return
  fi

  if [[ -z "$line" ]]; then
    if echo "$out" | grep -q "SKIP"; then
      printf "  %-22s skipped (assets not present)\n" "$label"
      return
    fi
    printf "  %-22s ✗ no result — suite did not report\n" "$label"
    failed_suites+=("$label")
    total_fail=$((total_fail + 1))
    return
  fi

  local p f
  p="$(echo "$line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
  f="$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')"
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))

  if [[ "$f" == "0" ]]; then
    printf "  %-22s %3d passed\n" "$label" "$p"
  else
    printf "  %-22s %3d passed, %d FAILED\n" "$label" "$p" "$f"
    failed_suites+=("$label")
    echo "$out" | grep -E "^  FAIL" | sed 's/^/      /'
  fi
}

# Scene-based suites run the project's main loop, so the autoloads are bound —
# the one thing a --script suite can never test. The shell suite exists because
# the autoload path broke while all twenty --script suites were green.
# Suites that must see actual pixels. --headless uses a dummy renderer whose
# viewport reads back empty, so these run under a virtual X server with software
# GL when one is available, and SKIP otherwise. Colour ownership was declared
# correctly in data and still rendered as white light on screen; only a real
# frame could catch that.
run_render_suite() {
  local label="$1" scene="$2"
  if ! command -v xvfb-run >/dev/null; then
    printf "  %-22s skipped (no xvfb — rendered checks need a display)\n" "$label"
    return
  fi
  local out
  out="$(xvfb-run -a --server-args="-screen 0 1280x720x24" "$GODOT" \
    --display-driver x11 --rendering-driver opengl3 \
    --path . --quit-after 3000 "$scene" 2>&1)"
  if echo "$out" | grep -q "^SKIP:"; then
    printf "  %-22s skipped (%s)\n" "$label" "$(echo "$out" | grep '^SKIP:' | head -1 | cut -c7-)"
    return
  fi
  _tally_suite "$label" "$out"
}

run_scene_suite() {
  local label="$1" scene="$2"
  local out
  out="$("$GODOT" --headless --path . --quit-after 3000 "$scene" 2>&1)"
  _tally_suite "$label" "$out"
}

_tally_suite() {
  local label="$1" out="$2"
  local line
  line="$(echo "$out" | grep -E "[0-9]+ passed, [0-9]+ failed" | tail -1)"

  local script_errors
  script_errors="$(echo "$out" | grep -c "^SCRIPT ERROR:")"
  if [[ "$script_errors" != "0" ]]; then
    printf "  %-22s ✗ %s script error(s) at runtime\n" "$label" "$script_errors"
    echo "$out" | grep -A1 "^SCRIPT ERROR:" | head -6 | sed 's/^/      /'
    failed_suites+=("$label")
    total_fail=$((total_fail + 1))
    return
  fi

  if [[ -z "$line" ]]; then
    printf "  %-22s ✗ no result — suite did not report\n" "$label"
    failed_suites+=("$label")
    total_fail=$((total_fail + 1))
    return
  fi

  local p f
  p="$(echo "$line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
  f="$(echo "$line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')"
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))

  if [[ "$f" == "0" ]]; then
    printf "  %-22s %3d passed\n" "$label" "$p"
  else
    printf "  %-22s %3d passed, %d FAILED\n" "$label" "$p" "$f"
    failed_suites+=("$label")
    echo "$out" | grep -E "^  FAIL" | sed 's/^/      /'
  fi
}

for i in $(seq 0 15); do
  run_suite "phase $i" "scripts/tests/phase${i}_acceptance.gd"
done
run_suite "realistic vfx" "scripts/tests/vfx_acceptance.gd"
run_suite "audio" "scripts/tests/audio_acceptance.gd"
run_suite "presentation" "scripts/tests/presentation_acceptance.gd"
run_suite "playable" "scripts/tests/playable_acceptance.gd"
run_scene_suite "shell" "scenes/tests/shell_acceptance.tscn"
run_render_suite "rendered colour" "scenes/tests/render_acceptance.tscn"

echo
echo "────────────────────────────────────────────"
printf "TOTAL: %d passed, %d failed\n" "$total_pass" "$total_fail"
if [[ ${#failed_suites[@]} -gt 0 ]]; then
  echo "Failing: ${failed_suites[*]}"
fi
echo "────────────────────────────────────────────"

# Asset presence is reported, never failed on. A clone without art is expected.
if [[ ! -d assets/actors ]] || [[ -z "$(ls -A assets/actors 2>/dev/null)" ]]; then
  echo
  echo "⚠ No art or audio in this checkout — the game runs but nothing is visible."
  echo "  ./tools/fetch_assets.sh <bundle-url-or-zip>    (see docs/ASSET_DELIVERY.md)"
fi

[[ "$total_fail" == "0" ]] || exit 1
