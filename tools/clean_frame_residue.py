#!/usr/bin/env python3
"""Remove atlas-neighbour bleed from the hero locomotion frames.

The split frames were cut from an atlas, and several carry chunks of the
NEIGHBOURING sprite along their edges — most visibly a slab of the row above
sitting over the hero's head in the west/north/east-facing frames (measured up
to 1,079 px in 05_northeast__00_idle). On screen it reads as a dirty cutout.

The rule is deliberately narrow:

    delete a connected alpha component only if it
      (a) is not the largest component (the hero), AND
      (b) touches the frame border.

Nothing else qualifies. Interior detached pixels are left alone, and the
ACTION frames are not processed at all — their detached pieces (dash streaks,
summon circles, knockback debris) are the art, not residue. If a locomotion
frame ever legitimately grows a detached edge-touching piece, this script is
the thing to revisit.

Idempotent; original bytes only change where residue was found. Run:

    python3 tools/clean_frame_residue.py [--dry-run]
"""
from __future__ import annotations

import argparse
import collections
import pathlib
import sys

import numpy as np
from PIL import Image

FRAME_DIR = pathlib.Path("assets/actors/hero_locomotion_frames")
# The three action frames the dash animation ships. ONLY these three: the other
# action frames carry summon circles and debris that legitimately touch borders,
# and nothing displays them yet. Frame 03's border component is an entire
# neighbouring sprite (a summon mid-slash, 9,761 px) — the loudest case of the
# same atlas bleed.
DASH_FRAMES = [
    pathlib.Path("assets/actors/hero_action_frames/00_top__01_dash_or_focus.png"),
    pathlib.Path("assets/actors/hero_action_frames/00_top__02_dash_streak_or_convergence_start.png"),
    pathlib.Path("assets/actors/hero_action_frames/00_top__03_dash_recover_or_convergence.png"),
]
# The summon action frames carry the same bleed — neighbouring cells' slash
# arcs poking across borders in 12 of 21 frames (largest: 5,569 px of someone
# else's crescent on the rune hound's hit frame). Verified by eye with border
# components tinted before enabling: every summon's OWN detached pieces (the
# wisp's orbit sparks) sit interior and never touch a border.
SUMMON_DIR = pathlib.Path("assets/actors/summon_action_frames")

ALPHA_FLOOR = 8  # below this, a pixel is already invisible


def components(alpha: np.ndarray):
    seen = np.zeros_like(alpha, dtype=bool)
    out = []
    h, w = alpha.shape
    for y in range(h):
        for x in range(w):
            if alpha[y, x] > ALPHA_FLOOR and not seen[y, x]:
                queue = collections.deque([(y, x)])
                seen[y, x] = True
                pixels = []
                while queue:
                    cy, cx = queue.popleft()
                    pixels.append((cy, cx))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < h and 0 <= nx < w \
                                    and alpha[ny, nx] > ALPHA_FLOOR and not seen[ny, nx]:
                                seen[ny, nx] = True
                                queue.append((ny, nx))
                out.append(pixels)
    return sorted(out, key=len, reverse=True)


def touches_border(pixels, h: int, w: int) -> bool:
    return any(y == 0 or x == 0 or y == h - 1 or x == w - 1 for y, x in pixels)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not FRAME_DIR.is_dir():
        print("no %s — assets not installed, nothing to clean" % FRAME_DIR)
        return 0

    cleaned = 0
    removed_px = 0
    targets = sorted(FRAME_DIR.glob("*.png")) + [f for f in DASH_FRAMES if f.exists()]
    if SUMMON_DIR.is_dir():
        targets += sorted(SUMMON_DIR.glob("*.png"))
    for path in targets:
        img = np.array(Image.open(path).convert("RGBA"))
        h, w = img.shape[:2]
        comps = components(img[:, :, 3])
        if len(comps) < 2:
            continue
        doomed = [c for c in comps[1:] if touches_border(c, h, w)]
        if not doomed:
            continue
        for comp in doomed:
            for y, x in comp:
                img[y, x] = (0, 0, 0, 0)
        cleaned += 1
        removed_px += sum(len(c) for c in doomed)
        print("  %s: removed %d blob(s), %d px" % (
            path.name, len(doomed), sum(len(c) for c in doomed)))
        if not args.dry_run:
            Image.fromarray(img).save(path)

    print("%s%d frame(s) cleaned, %d px of neighbour bleed removed"
          % ("[dry run] " if args.dry_run else "", cleaned, removed_px))
    return 0


if __name__ == "__main__":
    sys.exit(main())
