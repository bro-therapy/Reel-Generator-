#!/usr/bin/env python3
"""Check generated/commissioned sprite frames against docs/SPRITE_DELIVERY_SPEC.md.

Run this on a trial batch BEFORE paying for a subscription or a commission.

    python3 tools/validate_sprite_delivery.py <folder> [--kind hero|summon]

Why this exists
---------------
Two sprite-generation paths have already been evaluated for this project and
both failed on the same axis, and it was never art quality:

  - Higgsfield image-to-video: 25% character-height variance across one walk
    cycle. Each frame looked fine; the cycle pulsed.
  - Higgsfield `autosprite`: uncallable ("Job set type not supported").

Every tool in this space advertises "consistent proportions". The only way to
know is to measure a real batch, which takes seconds — so measure first, buy
second. A tool that passes this on a free trial is safe to subscribe to.

What it measures (per animation cycle, not per frame — the cycle is what the
eye judges):

  height variance   the killer. >4% and the character visibly pulses.
  width variance    reported, not rejected on — a walk legitimately widens at
                    contact and narrows at passing. Flat width across a cycle
                    means duplicate frames, which IS rejected.
  ground row        feet drifting off a shared baseline reads as bobbing. The
                    Godot pipeline auto-corrects +/-2 px and audits the rest.
  side margins      content jammed against a canvas edge means the generator
                    cropped the character; a limb is probably missing.
  transparency      a baked background cannot be composited over the world.
  stray blobs       disconnected pieces touching a border = atlas bleed, the
                    exact defect tools/clean_frame_residue.py had to fix on the
                    shipped package (23,040 px on the hero alone).
  palette           the hero's five signature elements must survive: coat,
                    orange scarf, gauntlet, boots, white hair streak. Checked
                    loosely, as presence of warm-orange and near-white pixels.

Exit code 0 = the batch is installable. Non-zero = do not pay yet.
"""
from __future__ import annotations

import argparse
import collections
import pathlib
import re
import sys

import numpy as np
from PIL import Image

ALPHA_FLOOR = 8

# From SPRITE_DELIVERY_SPEC.md. Not enforced as a hard equality — a tool that
# emits a different canvas is fine as long as it is CONSISTENT, since the
# builder measures rather than assumes. Reported for information.
HERO_CANVAS = (162, 242)

# Thresholds. The height one is the whole point of the script: 25% is the
# measured failure, 4% is roughly where a pulse stops being visible at the
# 88 px on-screen size this project targets.
MAX_HEIGHT_VARIANCE_PCT = 4.0
# Width is reported but never rejected on. A walk's contact pose has the legs
# apart and its passing pose has them together — the shipped, correct art
# varies 8-20% between the two, so a width threshold flags good animation as
# broken. HEIGHT is the invariant: a character does not change stature
# mid-stride. Keeping width visible is still useful, because a cycle where
# width is *identical* usually means the frames are duplicates.
MAX_WIDTH_VARIANCE_PCT = 45.0
MAX_GROUND_DRIFT_PX = 6
# Cropping is measured by the EXTENT of edge contact, not by contact at all.
# The shipped package's atlas split is tight: in 23 frames a boot or a cape
# corner reaches the canvas edge for a handful of rows, and the art is fine.
# A genuinely sliced silhouette leaves a long flat run against the edge — the
# hero is ~213 px tall, so 12% of canvas height is well clear of incidental
# contact and well under any real amputation.
MAX_EDGE_CONTACT_FRACTION = 0.12


def content_box(alpha: np.ndarray):
    ys, xs = np.where(alpha > ALPHA_FLOOR)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def border_blobs(alpha: np.ndarray) -> int:
    """Pixels in disconnected components that touch a frame border."""
    h, w = alpha.shape
    seen = np.zeros_like(alpha, dtype=bool)
    comps = []
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
                comps.append(pixels)
    if len(comps) < 2:
        return 0
    comps.sort(key=len, reverse=True)
    stray = 0
    for comp in comps[1:]:
        if any(y == 0 or x == 0 or y == h - 1 or x == w - 1 for y, x in comp):
            stray += len(comp)
    return stray


def cycle_of(name: str) -> str:
    """Group frames into the cycle the eye judges them as.

    `02_west__01_walk_contact.png` -> `02_west__walk`. Falls back to the whole
    stem so an unrecognised naming scheme still gets grouped by something rather
    than compared against unrelated frames.
    """
    stem = pathlib.Path(name).stem
    m = re.match(r"(\d+_[a-z]+)__\d+_([a-z]+)", stem)
    if m:
        gait = m.group(2)
        # walk_contact / walk_passing belong to one cycle; run_* to another.
        return "%s__%s" % (m.group(1), gait)
    return stem


def variance_pct(values) -> float:
    if not values:
        return 0.0
    lo, hi = min(values), max(values)
    return 0.0 if hi == 0 else (hi - lo) / hi * 100.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--kind", choices=["hero", "summon"], default="hero")
    args = ap.parse_args()

    root = pathlib.Path(args.folder)
    files = sorted(root.glob("*.png"))
    if not files:
        print("no PNGs in %s" % root)
        return 2

    print("Validating %d frame(s) in %s against docs/SPRITE_DELIVERY_SPEC.md\n"
          % (len(files), root))

    problems: list[str] = []
    warnings: list[str] = []
    cycles: dict[str, list] = collections.defaultdict(list)
    canvases = set()
    warm_seen = False
    bright_seen = False

    for path in files:
        img = np.array(Image.open(path).convert("RGBA"))
        h, w = img.shape[:2]
        canvases.add((w, h))
        alpha = img[:, :, 3]

        opaque_frac = float((alpha > 250).sum()) / (w * h)
        if opaque_frac > 0.92:
            problems.append("%s: no transparency (%.0f%% fully opaque) — background is baked in"
                            % (path.name, opaque_frac * 100))
            continue

        box = content_box(alpha)
        if box is None:
            problems.append("%s: completely empty" % path.name)
            continue
        x0, y0, x1, y1 = box

        stray = border_blobs(alpha)
        if stray > 0:
            warnings.append("%s: %d px of border-touching stray blobs (atlas bleed — "
                            "tools/clean_frame_residue.py removes these)" % (path.name, stray))
        left_run = int((alpha[:, 0] > ALPHA_FLOOR).sum())
        right_run = int((alpha[:, w - 1] > ALPHA_FLOOR).sum())
        top_run = int((alpha[0, :] > ALPHA_FLOOR).sum())
        worst_side = max(left_run, right_run)
        if worst_side > h * MAX_EDGE_CONTACT_FRACTION:
            problems.append("%s: %d rows of silhouette flush against a side edge "
                            "(%.0f%% of the canvas) — the character is cropped"
                            % (path.name, worst_side, worst_side / h * 100))
        elif worst_side > 0 or top_run > 0:
            warnings.append("%s: content grazes the canvas edge (%d side rows, "
                            "%d top cols) — tight but not clipped"
                            % (path.name, worst_side, top_run))
        if top_run > w * MAX_EDGE_CONTACT_FRACTION:
            problems.append("%s: %d columns flush against the TOP edge — the head "
                            "is cut off" % (path.name, top_run))

        rgb = img[:, :, :3][alpha > 128].astype(float)
        if len(rgb):
            r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
            if ((r > 140) & (g > 60) & (g < 170) & (b < 90)).any():
                warm_seen = True
            if ((r > 215) & (g > 215) & (b > 215)).any():
                bright_seen = True

        cycles[cycle_of(path.name)].append({
            "name": path.name,
            "height": y1 - y0 + 1,
            "width": x1 - x0 + 1,
            "ground": y1,
        })

    if len(canvases) > 1:
        problems.append("mixed canvas sizes: %s — every frame must share one canvas"
                        % sorted(canvases))
    else:
        only = list(canvases)[0]
        note = ""
        if args.kind == "hero" and only != HERO_CANVAS:
            note = "  (spec says %dx%d; consistent is what matters, the builder measures)" % HERO_CANVAS
        print("  canvas: %dx%d%s" % (only[0], only[1], note))

    print("\n  %-26s %6s %6s %6s %7s  %s"
          % ("cycle", "frames", "hgt%", "wid%", "ground", "verdict"))
    for key in sorted(cycles):
        frames = cycles[key]
        if len(frames) < 2:
            continue
        hv = variance_pct([f["height"] for f in frames])
        wv = variance_pct([f["width"] for f in frames])
        grounds = [f["ground"] for f in frames]
        drift = max(grounds) - min(grounds)

        bad = []
        if hv > MAX_HEIGHT_VARIANCE_PCT:
            bad.append("height %.1f%%" % hv)
        if wv > MAX_WIDTH_VARIANCE_PCT:
            bad.append("width %.1f%% (extreme — limbs may be clipped)" % wv)
        if len(frames) > 1 and wv < 0.5 and hv < 0.5:
            bad.append("frames are near-identical — no actual animation")
        if drift > MAX_GROUND_DRIFT_PX:
            bad.append("ground drift %d px" % drift)

        verdict = "ok" if not bad else "FAIL: " + ", ".join(bad)
        print("  %-26s %6d %5.1f%% %5.1f%% %6dpx  %s"
              % (key, len(frames), hv, wv, drift, verdict))
        if bad:
            problems.append("%s: %s" % (key, ", ".join(bad)))

    if args.kind == "hero":
        if not warm_seen:
            warnings.append("no warm-orange pixels found — the scarf is a signature "
                            "element that must survive at 88 px")
        if not bright_seen:
            warnings.append("no near-white pixels found — the white hair streak is a "
                            "signature element that must survive at 88 px")

    if warnings:
        print("\nWarnings (installable, but look):")
        for w_ in warnings[:12]:
            print("  - %s" % w_)
        if len(warnings) > 12:
            print("  ... and %d more" % (len(warnings) - 12))

    print()
    if problems:
        print("REJECT — %d problem(s):" % len(problems))
        for p in problems[:15]:
            print("  x %s" % p)
        if len(problems) > 15:
            print("  ... and %d more" % (len(problems) - 15))
        print("\nDo not buy credits on this tool's output yet.")
        return 1

    print("ACCEPT — frames meet the delivery spec. Install them, then run:")
    print("  python3 tools/clean_frame_residue.py")
    print("  godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd")
    print("  ./tools/check_project.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
