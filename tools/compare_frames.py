#!/usr/bin/env python3
"""Build side-by-side sheets for judging whether new frames are on-model.

    ./tools/compare_frames.py --preset all
    ./tools/compare_frames.py --row 02_bellguard --extra 06_hit

Sheets 3, 4 and 8 of the eleven-sheet package came back depicting different
creatures than the ones they were meant to extend. That was caught by eye, and
it has to stay that way: see docs/ART_REGENERATION_SHEETS_3_4_8.md for the
measurements showing why an automated identity check does not work here. Every
genuine death frame in this project scores *less* like its own creature than
every one of the ten known redesigns does, on silhouette overlap and on palette
alike — so no threshold separates them.

What this does instead is make the human check cheap: shipped frames on the top
row, candidates below, same scale, labelled. The judgement takes seconds.

Output lands in `build/comparisons/` (gitignored).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "comparisons"

ENEMIES = ROOT / "assets/enemies/enemy_action_frames"
BOSS = ROOT / "assets/enemies/boss_action_frames"
ELITE = ROOT / "assets/enemies/elite_action_frames"

BG = (28, 28, 36, 255)
SHIPPED = (120, 200, 130, 255)
CANDIDATE = (240, 170, 90, 255)
SCALE = 2

ENEMY_COLUMNS = ["00_idle", "01_move_contact", "02_move_passing",
                 "03_attack_windup", "04_attack_active", "05_death"]
BOSS_COLUMNS = ["00_idle", "01_move", "02_slam_windup", "03_slam_impact",
                "04_chain_sweep_windup", "05_bell_toll", "06_stagger_core_open", "07_defeat"]


def strip(title: str, groups: list[tuple[str, list[Path], tuple]], scale: int = SCALE) -> Image.Image:
    """One labelled row per group, all cells padded to a common size."""
    every = [p for _, paths, _ in groups for p in paths]
    frames = {p: Image.open(p).convert("RGBA") for p in every}
    cw = max(i.width for i in frames.values())
    ch = max(i.height for i in frames.values())
    cols = max(len(paths) for _, paths, _ in groups)

    pad, header, label = 8, 30, 16
    row_h = ch * scale + label + pad
    canvas = Image.new("RGBA", (cols * (cw * scale + pad) + pad,
                                header + len(groups) * row_h + pad), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 8), title, fill=(235, 235, 245, 255))

    for r, (name, paths, colour) in enumerate(groups):
        y = header + r * row_h
        draw.text((pad, y + 2), name, fill=colour)
        for c, p in enumerate(paths):
            im = frames[p]
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            x = pad + c * (cw * scale + pad)
            cell = Image.new("RGBA", (cw * scale, ch * scale), (0, 0, 0, 0))
            cell.alpha_composite(im, ((cw * scale - im.width) // 2, ch * scale - im.height))
            canvas.alpha_composite(cell, (x, y + label))
            draw.rectangle([x - 1, y + label - 1, x + cw * scale, y + label + ch * scale],
                           outline=(60, 60, 74, 255))
    return canvas


def existing(paths: list[Path]) -> list[Path]:
    return [p for p in paths if p.exists()]


def build(name: str, title: str, groups: list, scale: int = SCALE) -> Path | None:
    groups = [(n, existing(p), c) for n, p, c in groups]
    groups = [g for g in groups if g[1]]
    if len(groups) < 2:
        print(f"  {name}: nothing to compare (candidates not installed)")
        return None
    img = strip(title, groups, scale)
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / f"{name}.png"
    img.convert("RGB").save(out)
    print(f"  {out.relative_to(ROOT)}  {img.width}x{img.height}")
    return out


def preset_boss() -> None:
    build(
        "compare_boss",
        "THE FIRST BELL — shipped frames vs sheet 4 candidates",
        [
            ("shipped (canon — guide §11)", [BOSS / f"00_the_first_bell__{c}.png" for c in BOSS_COLUMNS], SHIPPED),
            ("sheet 4 candidates", [BOSS / f"00_the_first_bell__{c}.png" for c in
                                    ("08_chain_sweep_active", "09_hit", "10_phase_two", "11_enrage")], CANDIDATE),
        ],
        scale=1,
    )


def preset_elite() -> None:
    build(
        "compare_elite_bellguard",
        "BELLGUARD — shipped base vs sheet 3 Gilded elite",
        [
            ("shipped Bellguard", [ENEMIES / f"02_bellguard__{c}.png" for c in ENEMY_COLUMNS], SHIPPED),
            ("sheet 3 Gilded elite", sorted(ELITE.glob("00_gilded_bellguard__*.png")), CANDIDATE),
        ],
    )


def preset_enemy_hits() -> None:
    rows = ["00_rift_crawler", "01_lantern_hexer", "02_bellguard",
            "03_nest_idol", "04_blade_mite", "05_siphon_eye"]
    for row in rows:
        name = row.split("_", 1)[1]
        build(
            f"compare_{name}",
            f"{name.replace('_', ' ').upper()} — shipped row vs sheet 8 hit frame",
            [
                ("shipped", [ENEMIES / f"{row}__{c}.png" for c in ENEMY_COLUMNS], SHIPPED),
                ("sheet 8 hit", [ENEMIES / f"{row}__06_hit.png"], CANDIDATE),
            ],
        )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preset", choices=["boss", "elite", "enemy_hits", "all"], default="all")
    ap.add_argument("--row", help="enemy row prefix, e.g. 02_bellguard")
    ap.add_argument("--extra", nargs="+", help="extra column suffixes to show as candidates")
    args = ap.parse_args()

    print(f"→ {OUT.relative_to(ROOT)}")
    if args.row:
        build(
            f"compare_{args.row}",
            f"{args.row} — shipped row vs candidates",
            [
                ("shipped", [ENEMIES / f"{args.row}__{c}.png" for c in ENEMY_COLUMNS], SHIPPED),
                ("candidates", [ENEMIES / f"{args.row}__{c}.png" for c in (args.extra or [])], CANDIDATE),
            ],
        )
    else:
        if args.preset in ("boss", "all"):
            preset_boss()
        if args.preset in ("elite", "all"):
            preset_elite()
        if args.preset in ("enemy_hits", "all"):
            preset_enemy_hits()

    print("\nTop row is canon. If the row below is not obviously the same creature,")
    print("it is off-model — regenerate it with the reference image attached.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
