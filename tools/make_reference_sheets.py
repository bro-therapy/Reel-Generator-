#!/usr/bin/env python3
"""Build reference images for regenerating the three off-model sheets.

    ./tools/make_reference_sheets.py

Sheets 3, 4 and 8 of the eleven-sheet package came back off-model — they were
generated from text alone, so they re-invented creatures that already exist.
The fix is to hand the generator a picture of the creature it is extending.

This composites those pictures out of the frames already in `assets/`. It
creates no new art: every pixel is a copy of a shipped frame.

Output lands in `build/references/` (gitignored) on a `#00ff00` background, so
the reference also demonstrates the background convention the output needs.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "references"
CHROMA = (0, 255, 0, 255)

ENEMIES = ROOT / "assets/enemies/enemy_action_frames"
BOSS = ROOT / "assets/enemies/boss_action_frames"

# Row order of the Level 1 enemy atlas.
ENEMY_ROWS = [
    "00_rift_crawler",
    "01_lantern_hexer",
    "02_bellguard",
    "03_nest_idol",
    "04_blade_mite",
    "05_siphon_eye",
]

BOSS_COLUMNS = [
    "00_idle",
    "01_move",
    "02_slam_windup",
    "03_slam_impact",
    "04_chain_sweep_windup",
    "05_bell_toll",
    "06_stagger_core_open",
    "07_defeat",
]

BELLGUARD_COLUMNS = [
    "00_idle",
    "01_move_contact",
    "02_move_passing",
    "03_attack_windup",
    "04_attack_active",
    "05_death",
]

# The boss occupies rows 199-521 of its 724 px cell. Cropping the dead space
# uniformly keeps every frame's proportions intact while roughly doubling the
# detail that survives an upload's downscale.
BOSS_CROP = (180, 545)


def grid(images: list[Image.Image], columns: int, gutter: int = 16) -> Image.Image:
    """Lay images out on a chroma background, padding cells to a common size.

    The gutter matters: several of these creatures fill their cell edge to edge
    (the boss's chains reach x=0 and x=271), so butted-up cells read as one
    continuous drawing instead of separate frames.
    """
    cw = max(i.width for i in images) + gutter
    ch = max(i.height for i in images) + gutter
    rows = (len(images) + columns - 1) // columns
    canvas = Image.new("RGBA", (cw * columns + gutter, ch * rows + gutter), CHROMA)
    for index, im in enumerate(images):
        x = gutter + (index % columns) * cw + (cw - gutter - im.width) // 2
        y = gutter + (index // columns) * ch + (ch - gutter - im.height) // 2
        canvas.alpha_composite(im, (x, y))
    return canvas


def load(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(
            f"✗ missing {path.relative_to(ROOT)}\n"
            "  Restore the package art first: ./tools/restore_package_assets.sh <package>"
        )
    return Image.open(path).convert("RGBA")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    written: list[tuple[str, tuple[int, int]]] = []

    # ── Sheet 3: the base Bellguard the elite has to resemble ────────────────
    base = [load(ENEMIES / f"02_bellguard__{c}.png") for c in BELLGUARD_COLUMNS]
    img = grid(base, columns=3)
    img.convert("RGB").save(OUT / "ref_sheet03_base_bellguard.png")
    written.append(("ref_sheet03_base_bellguard.png", img.size))

    # ── Sheet 4: the boss, in detail and in cell ─────────────────────────────
    frames = [load(BOSS / f"00_the_first_bell__{c}.png") for c in BOSS_COLUMNS]
    cropped = [f.crop((0, BOSS_CROP[0], f.width, BOSS_CROP[1])) for f in frames]
    img = grid(cropped, columns=4)
    img.convert("RGB").save(OUT / "ref_sheet04_first_bell_detail.png")
    written.append(("ref_sheet04_first_bell_detail.png", img.size))

    # One untouched cell, so the size-within-cell is unambiguous.
    placement = Image.new("RGBA", frames[0].size, CHROMA)
    placement.alpha_composite(frames[0])
    placement.convert("RGB").save(OUT / "ref_sheet04_first_bell_placement.png")
    written.append(("ref_sheet04_first_bell_placement.png", placement.size))

    # ── Sheet 8: every enemy, idle beside its attack ─────────────────────────
    pairs: list[Image.Image] = []
    for row in ENEMY_ROWS:
        pairs.append(load(ENEMIES / f"{row}__00_idle.png"))
        pairs.append(load(ENEMIES / f"{row}__04_attack_active.png"))
    img = grid(pairs, columns=2)
    img.convert("RGB").save(OUT / "ref_sheet08_enemies.png")
    written.append(("ref_sheet08_enemies.png", img.size))

    # Each enemy on its own, for one-at-a-time regeneration.
    for row in ENEMY_ROWS:
        name = row.split("_", 1)[1]
        one = grid(
            [
                load(ENEMIES / f"{row}__00_idle.png"),
                load(ENEMIES / f"{row}__04_attack_active.png"),
                load(ENEMIES / f"{row}__05_death.png"),
            ],
            columns=3,
        )
        one.convert("RGB").save(OUT / f"ref_sheet08_{name}.png")
        written.append((f"ref_sheet08_{name}.png", one.size))

    print(f"→ {OUT.relative_to(ROOT)}")
    for name, size in written:
        print(f"  {name:<42} {size[0]}x{size[1]}")
    print(f"\n✓ {len(written)} reference images built from shipped frames only")


if __name__ == "__main__":
    sys.exit(main())
