#!/usr/bin/env bash
#
# Fetch the free CC0 asset packs recorded in docs/FREE_ASSETS.json.
#
#   bash tools/fetch_free_assets.sh
#
# Everything this installs is Creative Commons Zero — free for commercial use,
# no attribution required — and every pack's LICENSE.txt is installed next to
# its files. The manifest is the source of truth: which repo, which files,
# which license, and the evidence for it. This script just carries it out.
#
# Why fetch instead of committing the files: LFS uploads are blocked from the
# remote build environment, and committing binaries raw is how this repo once
# hit 556MB of history. So the repo carries provenance, and everyone's copy
# fetches identically from it.
#
# Idempotent: a file that already exists is left alone. Non-fatal: a dead
# mirror skips its pack — the game falls back to blockout primitives and
# synthesized music, and runs fine.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f docs/FREE_ASSETS.json ]] || { echo "✗ docs/FREE_ASSETS.json missing" >&2; exit 1; }

command -v git >/dev/null || { echo "✗ git is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "✗ python3 is required" >&2; exit 1; }

echo "==> Free asset packs (all CC0 — see docs/FREE_ASSETS.json for provenance)"

python3 - <<'PY'
import json, pathlib, shutil, subprocess, sys, tempfile, urllib.request

spec = json.loads(pathlib.Path("docs/FREE_ASSETS.json").read_text())
MODEL_ROOT = pathlib.Path("assets/environment/models")

for key, pack in spec.get("packs", {}).items():
    # Most packs are 3D props under assets/environment/models/<key>/; a pack may
    # override with install_dir (the pixel FX sheets go to assets/vfx/pixel).
    dest = pathlib.Path(pack["install_dir"]) if pack.get("install_dir") \
        else MODEL_ROOT / key
    renames = pack.get("rename", {})
    def installed_name(f, _renames=None):
        name = pathlib.Path(f).name
        renamed = (_renames or {}).get(name)
        if renamed:
            return renamed
        return "LICENSE.txt" if name.lower().startswith("license") else name
    missing = [f for f in pack["files"] if not (dest / installed_name(f, renames)).exists()]
    if not missing:
        print("  %s: already installed" % key)
        continue
    print("  %s: fetching %d file(s) from %s" % (key, len(missing), pack["clone_url"]))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(
                ["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
                 "--quiet", pack["clone_url"], tmp + "/mirror"],
                check=True, timeout=600)
            subprocess.run(
                ["git", "-C", tmp + "/mirror", "sparse-checkout", "set",
                 pack["clone_path"]],
                check=True, timeout=600, capture_output=True)
            src = pathlib.Path(tmp) / "mirror" / pack["clone_path"]
            dest.mkdir(parents=True, exist_ok=True)
            for f in pack["files"]:
                # Installed flat, license normalised to LICENSE.txt. No root
                # fallback for licenses: installing the MIRROR repo's license
                # next to a Kenney pack would misstate what the files are under.
                out = dest / installed_name(f, renames)
                if out.exists():
                    continue
                found = src / f
                if found.exists():
                    shutil.copy2(found, out)
                else:
                    print("    ! %s not found in mirror" % f)
    except Exception as e:  # noqa: BLE001 — a dead mirror must not kill setup
        print("    ! pack failed (%s) — the blockout primitives still work" % e)

for slot, meta in spec.get("music", {}).items():
    out = pathlib.Path(meta["file"])
    if out.exists():
        print("  music %s: already installed" % slot)
        continue
    out.parent.mkdir(parents=True, exist_ok=True)
    print("  music %s: %s — %s" % (slot, meta.get("artist", "?"), meta.get("title", "?")))
    try:
        urllib.request.urlretrieve(meta["url"], out)
    except Exception as e:  # noqa: BLE001
        print("    ! fetch failed (%s) — the synthesized bed still plays" % e)
PY

echo "==> Done. Open the project in Godot once so it imports the new files."
