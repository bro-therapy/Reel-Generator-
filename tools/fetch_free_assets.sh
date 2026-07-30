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
import json, pathlib, shutil, subprocess, sys, tempfile, urllib.parse, urllib.request

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

# Packs fetched file-by-file from a URL instead of cloned. Needed because the
# best mirrors keep their binaries in Git LFS, and a plain clone of one of those
# dies with "smudge filter lfs failed" before a single byte lands. GitHub's media
# host serves the real content for exactly those paths.
for key, pack in spec.get("direct", {}).items():
    dest = pathlib.Path(pack["install_dir"])
    base = pack["base_url"].rstrip("/")
    missing = {out: src for out, src in pack["files"].items()
               if not (dest / out).exists()}
    if not missing:
        print("  %s: already installed" % key)
        continue
    print("  %s: fetching %d file(s) from %s" % (key, len(missing), base))
    dest.mkdir(parents=True, exist_ok=True)
    # The media host only serves paths that are actually in LFS. Small text
    # files — the license among them — are stored plainly and 404 there, so
    # raw.githubusercontent.com is tried second. Reversing the order does not
    # work: raw returns the LFS *pointer* for a tracked file, with a 200.
    hosts = [base]
    if "media.githubusercontent.com/media/" in base:
        hosts.append(base.replace("media.githubusercontent.com/media/",
                                  "raw.githubusercontent.com/"))
    for out, src in missing.items():
        errors = []
        for host in hosts:
            try:
                urllib.request.urlretrieve(host + "/" + urllib.parse.quote(src),
                                           dest / out)
                break
            except Exception as e:  # noqa: BLE001 — a dead file must not kill setup
                errors.append(str(e))
        else:
            print("    ! %s failed (%s)" % (out, "; ".join(errors)))
            continue
        # A 404 page or an unsmudged LFS pointer both arrive as a "successful"
        # download. Both are text; a real asset is not.
        if out.endswith(".png"):
            head = (dest / out).read_bytes()[:8]
            if head[:4] != b"\x89PNG":
                print("    ! %s is not a PNG (LFS pointer or error page) — removed"
                      % out)
                (dest / out).unlink()

for name, meta in spec.get("images", {}).items():
    out = pathlib.Path(meta["file"])
    # Existence is NOT enough. An image hand-downloaded from an older link sits
    # at the same path and silently blocks the current one forever — which is
    # exactly what stopped the title art from ever reaching the owner. When the
    # manifest states a size, a local file of a different size is stale.
    expected = int(meta.get("bytes", 0))
    if out.exists():
        actual = out.stat().st_size
        if expected == 0 or actual == expected:
            print("  image %s: already installed" % name)
            continue
        print("  image %s: replacing a stale copy (%d bytes, expected %d)"
              % (name, actual, expected))
    out.parent.mkdir(parents=True, exist_ok=True)
    print("  image %s: %s" % (name, meta.get("source", "")))
    try:
        urllib.request.urlretrieve(meta["url"], out)
    except Exception as e:  # noqa: BLE001
        print("    ! fetch failed (%s) — the menu falls back to a plain background" % e)

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
