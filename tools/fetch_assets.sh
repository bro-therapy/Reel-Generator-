#!/usr/bin/env bash
#
# Install assets/ into a fresh checkout, from a URL or a local archive.
#
#   ./tools/fetch_assets.sh                        # uses ASSET_URL below
#   ./tools/fetch_assets.sh <url>
#   ./tools/fetch_assets.sh ~/Downloads/pzc-assets-20260729.zip
#
# The project runs without assets — it boots, every scene loads, and the
# acceptance suites pass or skip cleanly. It just has no art or audio, so the
# actors are invisible. This is the script that fixes that.
#
# Every file is verified against the SHA256 manifest packed inside the archive.
# A download that reports success is not evidence it delivered the right bytes,
# and silently-corrupt art is much harder to diagnose than a missing file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# macOS ships shasum, most Linux images ship sha256sum. Pick whichever exists so
# the same script works on the Mac that will run it and the box that wrote it.
if command -v shasum >/dev/null; then SHA=(shasum -a 256); else SHA=(sha256sum); fi

# Fill this in after uploading a bundle to a GitHub Release, then this script
# takes no arguments. Left empty rather than guessed: a wrong URL here fails in a
# confusing way months later.
ASSET_URL=""

SOURCE="${1:-$ASSET_URL}"

if [[ -z "$SOURCE" ]]; then
  cat >&2 <<'EOF'
✗ No asset source.

  Pass one:
      ./tools/fetch_assets.sh <url-or-local-zip>

  Or set ASSET_URL at the top of this script, once, to a GitHub Release asset
  URL and never pass it again.

  To make a bundle in the first place, from a checkout that has assets/:
      ./tools/bundle_assets.sh
EOF
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARCHIVE="$TMP/assets.zip"

if [[ -f "$SOURCE" ]]; then
  echo "Using local archive: $SOURCE"
  cp "$SOURCE" "$ARCHIVE"
else
  echo "Downloading: $SOURCE"
  # --fail so an HTML 404 page is not silently unzipped as if it were the bundle.
  curl -fSL --retry 4 --retry-delay 2 -o "$ARCHIVE" "$SOURCE"
fi

echo "Unpacking"
unzip -q -o "$ARCHIVE" -d "$TMP/out"

if [[ ! -d "$TMP/out/assets" ]]; then
  echo "✗ archive has no assets/ directory at its root" >&2
  exit 1
fi

MANIFEST="$TMP/out/ASSET_SHA256SUMS.txt"
if [[ ! -f "$MANIFEST" ]]; then
  echo "⚠ no ASSET_SHA256SUMS.txt in the archive — installing unverified" >&2
fi

# Replace rather than merge. A merge leaves files from an older bundle behind,
# which is how you end up with two generations of the same sprite and no way to
# tell which one Godot imported.
if [[ -d assets ]]; then
  echo "Replacing the existing assets/ (moved to assets.bak)"
  rm -rf assets.bak
  mv assets assets.bak
fi
mv "$TMP/out/assets" assets

if [[ -f "$MANIFEST" ]]; then
  echo "Verifying"
  # The manifest was written relative to the repo root, so it checks in place.
  if "${SHA[@]}" -c "$MANIFEST" --quiet 2>/dev/null; then
    echo "  all $(wc -l < "$MANIFEST" | tr -d ' ') files match their checksums"
  else
    echo "✗ checksum mismatch — the archive or the download is corrupt" >&2
    echo "  the previous assets/ is still at assets.bak" >&2
    "${SHA[@]}" -c "$MANIFEST" 2>/dev/null | grep -v ': OK$' | head -10 >&2
    exit 1
  fi
fi

COUNT="$(find assets -type f | wc -l | tr -d ' ')"
echo
echo "✓ installed $COUNT files into assets/"
echo
echo "Now let Godot import them (first run takes a minute):"
echo "  godot --headless --path . --import"
echo
echo "Then rebuild the generated resources and check it:"
echo "  godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd"
echo "  ./tools/check_project.sh"
