#!/usr/bin/env bash
#
# Update this copy of the game to the latest pushed build.
#
#   bash tools/update_mac.sh
#
# Works from anywhere inside the project folder. Your installed art, audio, and
# Godot's own generated files are untouched — only the game's tracked code moves.
#
# Why this exists instead of `git pull`
# -------------------------------------
# Godot rewrites project.godot (and, on 4.4+, drops *.uid files) the moment you
# open the project. Those are automatic edits nobody made on purpose, but git
# cannot know that: a plain pull refuses with "your local changes would be
# overwritten by merge" — which is exactly what stopped the owner after the
# first playtest fixes were pushed. In this copy the remote is always right, so
# the policy is: discard local edits to tracked files, take the pushed build.
#
# The one situation where that policy is wrong is a hand-made local edit worth
# keeping. This copy is a play copy, not a dev copy — but the script still shows
# what it is about to discard and keeps a safety stash, so nothing is ever
# silently unrecoverable.
set -euo pipefail

BRANCH="claude/repository-cleanup-reset-uyhypz"

# Run from anywhere inside the project.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f project.godot ]] || { echo "✗ $ROOT is not the game folder" >&2; exit 1; }

echo "==> Fetching the latest build"
git fetch origin "$BRANCH"

# Show what is about to be discarded, and stash it first. The stash is a safety
# net, not a workflow: `git stash list` finds it if something ever mattered.
CHANGED="$(git status --porcelain=v1 | grep -v '^??' || true)"
if [[ -n "$CHANGED" ]]; then
  echo "==> Discarding local edits to tracked files (Godot makes these on open):"
  echo "$CHANGED" | sed 's/^/      /'
  git stash push --quiet -m "update_mac safety stash $(date +%Y-%m-%d_%H:%M)" || true
fi

git reset --hard "origin/$BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH" 2>/dev/null || true

# Generated stills (title key art etc.) ship as URLs in VFX_SOURCES.json, not
# binaries — same policy as the effect sheets. Fetch whatever this build added
# that this copy does not have yet. Non-fatal: CDN links can expire, and the
# game falls back cleanly (the title screen goes plain indigo, nothing breaks).
if command -v python3 >/dev/null; then
  python3 - <<'PY' || echo "  (could not fetch new art — the game still runs)"
import json, pathlib, urllib.request
spec = json.loads(pathlib.Path("docs/VFX_SOURCES.json").read_text())
for path, meta in spec.get("generated_stills", {}).items():
    dest = pathlib.Path(path)
    if dest.exists() or not meta.get("source_url"):
        continue
    dest.parent.mkdir(parents=True, exist_ok=True)
    print("  fetching %s" % path, flush=True)
    urllib.request.urlretrieve(meta["source_url"], dest)
PY
fi

# CC0 packs (props, music) — same policy: URLs in the repo, binaries fetched.
if [[ -f tools/fetch_free_assets.sh ]]; then
  bash tools/fetch_free_assets.sh || echo "  (asset packs unavailable — blockout primitives still work)"
fi

echo
echo "✓ now at: $(git log --oneline -1)"
echo
echo "  Untracked files (your art in assets/, Godot's .uid and .godot/) were not touched."
echo "  Open the project in Godot and press F5. First open after an update"
echo "  re-imports for a few seconds — that is normal."
