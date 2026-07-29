#!/usr/bin/env bash
#
# One command, from nothing to a running game. Run this on your Mac.
#
#   curl -fsSL <this-file> -o bootstrap.sh && bash bootstrap.sh
#   # or, if you already have it:
#   bash bootstrap_mac.sh
#
# What it does, in order:
#   1. clones (or updates) the repo
#   2. downloads both art packages straight from the "My video game" Drive folder
#   3. installs them — the eleven-sheet package needs its chroma keyed, which is
#      why copying the PNGs by hand produces green frames
#   4. regenerates the placeholder audio and the SpriteFrames
#   5. runs all nineteen acceptance suites
#
# Everything it downloads is either this repo or a file already in your own Drive
# folder. Nothing else is fetched.
#
# Safe to re-run. It updates in place rather than starting over.
set -euo pipefail

REPO="https://github.com/bro-therapy/Reel-Generator-.git"
BRANCH="claude/repository-cleanup-reset-uyhypz"
DIR="${PZC_DIR:-$HOME/project-zero-climb}"

# File ids in the "My video game" Drive folder. Link-shared, so curl can fetch
# them without a token — but only through drive.usercontent.google.com. The old
# drive.google.com/uc endpoint answers 303 with an empty body for files this size,
# which is very likely why downloading them has been awkward.
SHEETS_ID="1McddC5wmqBf_UKmc1n5YY886JwHuFTL-"
PLAYTEST_ID="1UYklnJDqAz_bMMod9LfnT8S99SFxNh1z"
DRIVE="https://drive.usercontent.google.com/download"

say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die() { printf "\n\033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- requirements

say "Checking what you have"
for cmd in git curl unzip python3; do
  command -v "$cmd" >/dev/null || die "$cmd is not installed"
done
printf "  git, curl, unzip, python3 ✓\n"

GODOT=""
for candidate in godot /Applications/Godot.app/Contents/MacOS/Godot \
                 "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
  if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
    GODOT="$candidate"; break
  fi
done
if [[ -n "$GODOT" ]]; then
  printf "  Godot: %s\n" "$("$GODOT" --version 2>/dev/null | head -1)"
else
  printf "  Godot not found — the art will still install, but the build and test\n"
  printf "  steps will be skipped. Get 4.3 from godotengine.org/download.\n"
fi

# Pillow and numpy do the chroma keying and the audio synthesis; PyAV reads the
# effect clips. The first two are required, PyAV is not — without it the four
# realistic effects are skipped and everything else still works.
if ! python3 -c "import PIL, numpy" 2>/dev/null; then
  say "Installing Pillow and numpy (to key the sheets and synthesise the audio)"
  python3 -m pip install --quiet --user Pillow numpy || die "pip install failed"
fi
printf "  Pillow, numpy ✓\n"
if ! python3 -c "import av" 2>/dev/null; then
  python3 -m pip install --quiet --user av 2>/dev/null || true
fi
python3 -c "import av" 2>/dev/null && printf "  PyAV ✓ (realistic effects will be rebuilt)\n" \
  || printf "  PyAV missing — the four realistic effects will be skipped\n"

# ----------------------------------------------------------------------- repo

if [[ -d "$DIR/.git" ]]; then
  say "Updating $DIR"
  git -C "$DIR" fetch origin "$BRANCH"
  git -C "$DIR" checkout "$BRANCH"
  git -C "$DIR" pull --ff-only origin "$BRANCH"
else
  say "Cloning into $DIR"
  git clone --branch "$BRANCH" "$REPO" "$DIR"
fi
cd "$DIR"

# ------------------------------------------------------------------- the art

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
  local id="$1" out="$2"
  # -J alone is not enough: without --location the redirect to the file host is
  # not followed and you get a zero-byte "download".
  curl -fSL --retry 4 --retry-delay 2 --progress-bar \
    -o "$out" "$DRIVE?id=$id&export=download&confirm=t"
  unzip -tq "$out" >/dev/null 2>&1 || die "$(basename "$out") did not download as a valid zip"
}

if [[ -d assets/actors ]] && [[ -n "$(ls -A assets/actors 2>/dev/null)" ]]; then
  say "Art is already installed — skipping the download"
else
  say "Downloading the art from your Drive folder (216 MB, once)"
  fetch "$PLAYTEST_ID" "$WORK/playtest.zip"
  fetch "$SHEETS_ID"   "$WORK/sheets.zip"

  say "Installing the first-playtest package"
  ./tools/restore_package_assets.sh "$WORK/playtest.zip"

  say "Installing the eleven-sheet package (keying the chroma background)"
  ./tools/install_sheet_package.py "$WORK/sheets.zip"
fi

say "Synthesising the placeholder audio"
./tools/make_placeholder_audio.py

# The four realistic effect sheets are built from generated video that is not in
# the repo — but the clips' URLs are, in docs/VFX_SOURCES.json, so they can be
# rebuilt rather than shipped. Non-fatal: these are CDN links and will expire
# eventually, and the game runs perfectly well without them.
if [[ ! -f assets/vfx/realtime/fire.png ]]; then
  say "Rebuilding the four realistic effect sheets"
  CLIPS="$WORK/clips"
  mkdir -p "$CLIPS"
  if python3 -c "import av" 2>/dev/null; then
    if python3 - "$CLIPS" <<'PY'
import json, sys, urllib.request, pathlib
out = pathlib.Path(sys.argv[1])
spec = json.loads(pathlib.Path("docs/VFX_SOURCES.json").read_text())
for e in spec["effects"]:
    url = e.get("source_url", "")
    if not url:
        raise SystemExit("no source_url for %s" % e["name"])
    dest = out / e["source"]
    print("  %s" % e["source"], flush=True)
    urllib.request.urlretrieve(url, dest)
PY
    then
      ./tools/vfx_from_video.py --sources "$CLIPS" \
        && "${GODOT:-true}" --headless --path . --import >/dev/null 2>&1 \
        && [[ -n "$GODOT" ]] \
        && "$GODOT" --headless --path . --script scripts/tools/build_additive_vfx.gd
    else
      printf "  Could not download the clips — they are CDN links and may have expired.\n"
      printf "  Everything else works without them. See docs/REALISTIC_VFX.md.\n"
    fi
  else
    printf "  Skipping: needs PyAV (pip install av) to read the clips.\n"
    printf "  Everything else works without them. See docs/REALISTIC_VFX.md.\n"
  fi
fi

# ---------------------------------------------------------------- build & test

if [[ -z "$GODOT" ]]; then
  say "Done — art installed"
  printf "Install Godot 4.3, then open %s/project.godot\n" "$DIR"
  exit 0
fi

say "Importing (first time takes a minute)"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

say "Rebuilding the generated resources"
for s in build_hero_spriteframes build_summon_spriteframes build_vfx_spriteframes \
         build_enemy_spriteframes build_effect_spriteframes build_additive_vfx; do
  if [[ -f "scripts/tools/$s.gd" ]]; then
    printf "  %s\n" "$s"
    "$GODOT" --headless --path . --script "scripts/tools/$s.gd" >/dev/null 2>&1 || \
      printf "    (skipped — needs art this checkout does not have)\n"
  fi
done

say "Running every acceptance suite"
GODOT="$GODOT" ./tools/check_project.sh || die "some checks failed — see above"

say "Ready"
cat <<EOF

  Open it:      $GODOT --path "$DIR"
  Or in the editor: open $DIR/project.godot and press F5

  WASD moves, Space dashes, F3 toggles the debug overlay.

  Worth looking at first:
    scenes/world/sunfall_ward.tscn      the level
    scenes/tests/vfx_showcase.tscn      the realistic effects
    scenes/tests/evolution_field.tscn   all nine summon forms

  Read: README.md, then docs/ASSET_DELIVERY.md
EOF
