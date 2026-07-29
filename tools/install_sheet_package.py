#!/usr/bin/env python3
"""Install the eleven-sheet production package into assets/.

    ./tools/install_sheet_package.py ~/Downloads/Project_Zero_Climb_All_11_Sheets_v1.0
    ./tools/install_sheet_package.py ~/Downloads/Project_Zero_Climb_All_11_Sheets_v1.0.zip

Unlike the first-playtest package, this one ships its split cells with the
`#00ff00` chroma still baked in — the package README lists the chroma key as an
import rule for the consumer, not something it applied itself. So this script
does three things the earlier restore script did not have to:

  1. verifies every file against the package SHA256SUMS
  2. converts chroma to alpha, including the one-pixel anti-aliased halo
  3. renames cells into the project convention the builders glob for,
     ``{row:02d}_{row_name}__{col:02d}_{col_name}.png``

Sheet 10 is a set of opaque tiling textures with no chroma background, so it is
copied through unkeyed.

Requires Pillow and numpy. Neither is needed at runtime — this is a one-off
import step, same as tools_split_pzc_atlases.py.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CHROMA = (0, 255, 0)

# Where each sheet lands, and how its cells are renamed.
#
# `rows` / `cols` give the project-side names in package order. `row_offset` and
# `col_offset` let a sheet extend an existing grid rather than start a new one —
# the boss extras continue the boss atlas at column 8, and the enemy hit
# reactions become column 6 of the enemy atlas.
SHEETS = {
    1: {
        "dir": "assets/actors/summon_awakened_frames",
        "rows": ["volt_hound", "twin_oath_blades", "burst_golem"],
        "cols": ["idle", "move", "aim_or_windup", "attack", "attack_recover", "hit", "reform"],
    },
    2: {
        "dir": "assets/actors/summon_ascendant_frames",
        "rows": ["tempest_fenrir", "halo_blade_seraph", "arsenal_titan"],
        "cols": ["idle", "move", "aim_or_windup", "attack", "attack_recover", "hit", "reform"],
    },
    3: {
        "dir": "assets/enemies/elite_action_frames",
        "rows": ["gilded_bellguard"],
        "cols": ["idle", "move_contact", "move_passing", "attack_windup", "attack_active", "death"],
    },
    4: {
        # Continues the existing First Bell atlas, which ends at column 7.
        "dir": "assets/enemies/boss_action_frames",
        "rows": ["the_first_bell"],
        "cols": ["chain_sweep_active", "hit", "phase_two", "enrage"],
        "col_offset": 8,
    },
    5: {
        "dir": "assets/vfx/convergence_frames",
        "rows": ["lightning_wolf", "circular_blade_cut", "multi_cannon_barrage"],
        "cols": [f"fx_{i:02d}" for i in range(1, 9)],
    },
    6: {
        "dir": "assets/vfx/rally_marker_frames",
        "rows": ["rally_marker"],
        "cols": [f"fx_{i:02d}" for i in range(1, 7)],
    },
    7: {
        "dir": "assets/environment/spirit_core_frames",
        "rows": ["spirit_core"],
        "cols": ["intact", "damaged", "destroyed"],
    },
    8: {
        # Column 6 of the existing Level 1 enemy atlas, which ends at column 5.
        # Package row order already matches the project's enemy row order.
        "dir": "assets/enemies/enemy_action_frames",
        "rows": [
            "rift_crawler",
            "lantern_hexer",
            "bellguard",
            "nest_idol",
            "blade_mite",
            "siphon_eye",
        ],
        "cols": ["hit"],
        "col_offset": 6,
    },
    9: {
        "dir": "assets/ui/component_frames",
        "flat": True,  # laid out on a grid, but the cells are unrelated elements
    },
    10: {
        "dir": "assets/environment/textures",
        "flat": True,
        "keep_chroma": True,  # opaque tiling textures, no background to key
    },
    11: {
        "dir": "assets/environment/decals",
        "flat": True,
    },
}

# Sheet 9 ships two blank filler cells to square off its grid. Nothing consumes
# them and an empty PNG in assets/ only invites a "why is this here" later.
SKIP_FRAMES = {"empty_01", "empty_02"}


def verify_checksums(pkg: Path) -> int:
    """Check every file against the package manifest. Returns the count checked."""
    sums = pkg / "SHA256SUMS.txt"
    if not sums.exists():
        raise SystemExit(f"✗ no SHA256SUMS.txt in {pkg}")

    checked = 0
    for line in sums.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        expect, _, name = line.partition("  ")
        name = name.lstrip("*").strip()
        target = pkg / name
        if not target.exists():
            raise SystemExit(f"✗ missing from package: {name}")
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != expect:
            raise SystemExit(f"✗ checksum mismatch: {name}")
        checked += 1
    return checked


def chroma_to_alpha(im: Image.Image) -> tuple[Image.Image, int]:
    """Key out the #00ff00 background and its anti-aliased halo.

    Returns the keyed image and the number of halo pixels removed.

    Two passes, deliberately conservative. The first clears pixels that are
    exactly the chroma. The second clears green-dominant pixels that touch
    already-cleared ones — the one-pixel blend of chroma against the subject
    outline. Restricting the second pass to pixels adjacent to the background
    is what keeps it away from the palette's own `#61D095` reward green, which
    is green-dominant but never touches the key.
    """
    rgba = np.array(im.convert("RGBA"), dtype=np.int16)
    r, g, b = rgba[..., 0], rgba[..., 1], rgba[..., 2]

    clear = (r == CHROMA[0]) & (g == CHROMA[1]) & (b == CHROMA[2])
    greenish = (g > r + 40) & (g > b + 40) & ~clear

    # 4-neighbour dilation of the cleared region, then intersect with the
    # green-dominant pixels. Repeat until it stops growing; on this package it
    # converges after one or two rounds.
    halo = 0
    while True:
        touching = np.zeros_like(clear)
        touching[1:, :] |= clear[:-1, :]
        touching[:-1, :] |= clear[1:, :]
        touching[:, 1:] |= clear[:, :-1]
        touching[:, :-1] |= clear[:, 1:]

        newly = greenish & touching & ~clear
        count = int(newly.sum())
        if count == 0:
            break
        clear |= newly
        halo += count

    out = rgba.copy()
    out[clear] = [0, 0, 0, 0]
    return Image.fromarray(out.astype(np.uint8), "RGBA"), halo


def install(pkg: Path, dry_run: bool = False) -> None:
    import json

    manifest = json.loads((pkg / "manifest.json").read_text())

    print(f"→ verifying {pkg.name}")
    print(f"  {verify_checksums(pkg)} files match SHA256SUMS")
    print()

    total = 0
    total_halo = 0
    for sheet in manifest["sheets"]:
        number = sheet["number"]
        spec = SHEETS.get(number)
        if spec is None:
            print(f"  ! sheet {number} ({sheet['name']}) has no destination — skipped")
            continue

        dest = ROOT / spec["dir"]
        if not dry_run:
            dest.mkdir(parents=True, exist_ok=True)

        written = 0
        halo = 0
        for frame in sheet["frames"]:
            if frame["name"] in SKIP_FRAMES:
                continue

            src = pkg / frame["path"]
            if spec.get("flat"):
                out_name = f"{frame['name']}.png"
            else:
                row_i = frame["row"] - 1 + spec.get("row_offset", 0)
                col_i = frame["column"] - 1 + spec.get("col_offset", 0)
                rows = spec["rows"]
                cols = spec["cols"]
                out_name = "%02d_%s__%02d_%s.png" % (
                    row_i,
                    rows[frame["row"] - 1],
                    col_i,
                    cols[frame["column"] - 1],
                )

            if dry_run:
                print(f"    {frame['path']}  ->  {spec['dir']}/{out_name}")
            elif spec.get("keep_chroma"):
                shutil.copyfile(src, dest / out_name)
            else:
                keyed, removed = chroma_to_alpha(Image.open(src))
                keyed.save(dest / out_name, optimize=True)
                halo += removed
            written += 1

        total += written
        total_halo += halo
        note = "copied unkeyed" if spec.get("keep_chroma") else f"{halo} halo px removed"
        print(f"  sheet {number:>2}  {written:>2} frames  ->  {spec['dir']}  ({note})")

    print()
    print(f"✓ {total} frames installed, {total_halo} halo pixels removed")
    if dry_run:
        return
    print()
    print("Next:")
    print("  godot --headless --path . --import")
    print("  godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd")
    print("  godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd")
    print("  godot --headless --path . --script scripts/tools/build_vfx_spriteframes.gd")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source", help="package directory or .zip")
    ap.add_argument("--dry-run", action="store_true", help="print the mapping and stop")
    args = ap.parse_args()

    src = Path(args.source).expanduser()
    if not src.exists():
        raise SystemExit(f"✗ no such path: {src}")

    work = None
    try:
        if src.suffix == ".zip":
            work = Path(tempfile.mkdtemp())
            subprocess.run(["unzip", "-q", str(src), "-d", str(work)], check=True)
            found = list(work.glob("*/manifest.json")) + list(work.glob("manifest.json"))
            if not found:
                raise SystemExit("✗ no manifest.json inside the zip")
            src = found[0].parent
        elif not (src / "manifest.json").exists():
            raise SystemExit(f"✗ no manifest.json in {src}")

        install(src, dry_run=args.dry_run)
    finally:
        if work is not None:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
