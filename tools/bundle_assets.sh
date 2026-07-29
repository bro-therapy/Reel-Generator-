#!/usr/bin/env bash
#
# Pack assets/ into one verifiable archive.
#
#   ./tools/bundle_assets.sh                 # -> build/bundles/pzc-assets-<date>.zip
#   ./tools/bundle_assets.sh my-name.zip
#
# Why this exists
# ---------------
# assets/ is gitignored: LFS upload is blocked from the build environment, and
# committing 65 MB of PNGs as raw blobs would need a history rewrite to undo. The
# bundle is how the binaries move without either problem — upload it once to a
# GitHub Release and every clone forever after is one ./tools/fetch_assets.sh away.
#
# Zip, not tar.zst: it opens by double-click on macOS with nothing installed, and
# the person who needs it most is on a Mac and possibly on a phone. Zip already
# deflates each entry, so PNGs and WAVs come out barely smaller than they went in
# — that is expected, and not worth trading double-clickability for.
#
# The manifest is the point as much as the archive. It records a SHA256 per file,
# so fetch_assets.sh can prove it installed what was packed rather than assuming
# a download that reported success delivered the right bytes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# macOS ships shasum, most Linux images ship sha256sum. Pick whichever exists so
# the same script works on the Mac that will run it and the box that wrote it.
if command -v shasum >/dev/null; then SHA=(shasum -a 256); else SHA=(sha256sum); fi

if [[ ! -d assets ]]; then
  echo "✗ no assets/ directory — nothing to bundle" >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%d)"
OUT="${1:-build/bundles/pzc-assets-${STAMP}.zip}"
mkdir -p "$(dirname "$OUT")"
MANIFEST="build/bundles/ASSET_SHA256SUMS.txt"

echo "Bundling assets/ -> $OUT"

# Checksums first, so the manifest describes exactly what goes in the archive.
# Sorted, and relative to the repo root, so the file is reproducible and diffable.
mkdir -p "$(dirname "$MANIFEST")"
find assets -type f \! -name '*.import' -print0 |
  sort -z |
  xargs -0 "${SHA[@]}" > "$MANIFEST"

COUNT="$(wc -l < "$MANIFEST" | tr -d ' ')"
echo "  $COUNT files checksummed"

# .import files are deliberately excluded. Godot regenerates them on first open,
# they carry absolute-path-ish UIDs, and a stale one shipped over a fresh checkout
# is a genuine source of "works here, not there".
rm -f "$OUT"
zip -q -r -X "$OUT" assets -x '*.import' -x '*/.DS_Store'
zip -q -j "$OUT" "$MANIFEST"

SIZE="$(du -h "$OUT" | cut -f1)"
echo "  $OUT  ($SIZE)"
echo
echo "Next, once:"
echo "  1. Upload $OUT to a GitHub Release on bro-therapy/Reel-Generator-"
echo "     (Releases -> Draft a new release -> attach the file). Works from a phone."
echo "  2. Put its download URL in tools/fetch_assets.sh (ASSET_URL), or pass it:"
echo "     ./tools/fetch_assets.sh <url>"
echo
echo "After that any clone gets the assets with one command and no LFS."
