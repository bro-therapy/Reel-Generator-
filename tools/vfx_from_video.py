#!/usr/bin/env python3
"""Turn generated effect videos into additive sprite sheets the game can draw.

    ./tools/vfx_from_video.py [--sources DIR] [--only NAME]

Reads docs/VFX_SOURCES.json, writes assets/vfx/realtime/<name>.png plus a
docs/generated/vfx_sheets.json describing what it built.

Three things happen here that are worth knowing about:

*Colour ownership is enforced, not assumed.* The master guide gives red and
orange to hostile things and violet and blue-white to friendly ones, and the
player reads that split before they read anything else. A generated effect that
drifts across it is worse than no effect, so the hue histogram is checked and a
sheet that fails is refused rather than written. Measured on the four shipped
clips the wrong-side fraction is 0.000-0.056%, against a 0.5% ceiling - so the
gate has roughly two orders of magnitude of headroom and would still catch a
real leak.

*The background is left black rather than keyed.* These are drawn additively, so
black contributes nothing and there is no alpha channel to get wrong - no halo,
no matte line, no cutout threshold to tune. It also means the effects glow over
whatever is behind them, which is the entire reason for using them.

*Frames are cropped to their own content.* A flame column uses about a third of a
square frame; storing the rest is wasted texture and wasted fill rate. The crop
is symmetric about the anchor so the effect does not shift, and the resulting
aspect ratio is written to the metadata so the quad can be sized to match.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

import numpy as np

try:
    import av
except ImportError:  # pragma: no cover
    sys.exit("PyAV is required: pip install av")

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "docs" / "VFX_SOURCES.json"
OUT_DIR = ROOT / "assets" / "vfx" / "realtime"
META_OUT = ROOT / "docs" / "generated" / "vfx_sheets.json"

# Hue bands, in degrees. The gap between them is deliberate: a hue that lands in
# neither band is neither claimed nor an offence, which is what lets a white-hot
# core (desaturated, so excluded anyway) and a green ember pass without argument.
WARM_BANDS = ((0.0, 60.0), (330.0, 360.0))
COOL_BANDS = ((200.0, 300.0),)
PALETTE_BANDS = {"hostile": WARM_BANDS, "friendly": COOL_BANDS}
OPPOSITE = {"hostile": "friendly", "friendly": "hostile"}


# --------------------------------------------------------------------- colour

def hsv_parts(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Hue in degrees, saturation and value, for a float array in 0..1."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    delta = np.maximum(mx - mn, 1e-6)

    hue = np.zeros_like(mx)
    m = mx == r
    hue[m] = ((g - b)[m] / delta[m]) % 6.0
    m = (mx == g) & (mx != r)
    hue[m] = ((b - r)[m] / delta[m]) + 2.0
    m = (mx == b) & (mx != r) & (mx != g)
    hue[m] = ((r - g)[m] / delta[m]) + 4.0
    hue *= 60.0

    sat = np.where(mx > 0.0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    return hue, sat, mx


def in_bands(hue: np.ndarray, bands) -> np.ndarray:
    hit = np.zeros(hue.shape, dtype=bool)
    for lo, hi in bands:
        hit |= (hue >= lo) & (hue <= hi)
    return hit


@dataclass
class ColourReport:
    chromatic_px: int
    own_side_pct: float
    wrong_side_pct: float
    neutral_pct: float

    def passes(self, ceiling: float) -> bool:
        return self.wrong_side_pct <= ceiling * 100.0


def check_palette(frames: np.ndarray, palette: str, v_floor: float,
                  s_floor: float) -> ColourReport:
    """Hue census over pixels bright and saturated enough to have a real hue.

    Dark and desaturated pixels are excluded on purpose. A near-black pixel has a
    numerically valid hue that means nothing perceptually, and counting those
    would swamp the measurement with noise from compression artefacts.
    """
    rgb = frames.astype(np.float32) / 255.0
    hue, sat, val = hsv_parts(rgb)
    chromatic = (val > v_floor) & (sat > s_floor)
    total = int(chromatic.sum())
    if total == 0:
        return ColourReport(0, 0.0, 0.0, 0.0)

    h = hue[chromatic]
    own = int(in_bands(h, PALETTE_BANDS[palette]).sum())
    wrong = int(in_bands(h, PALETTE_BANDS[OPPOSITE[palette]]).sum())
    return ColourReport(
        chromatic_px=total,
        own_side_pct=own / total * 100.0,
        wrong_side_pct=wrong / total * 100.0,
        neutral_pct=(total - own - wrong) / total * 100.0,
    )


# --------------------------------------------------------------------- frames

def decode(path: Path) -> np.ndarray:
    container = av.open(str(path))
    frames = [f.to_ndarray(format="rgb24") for f in container.decode(video=0)]
    container.close()
    if not frames:
        raise SystemExit(f"{path.name}: decoded no frames")
    return np.stack(frames)


def trim_to_action(frames: np.ndarray, floor: float) -> tuple[int, int]:
    """First and last frame carrying meaningful light.

    An effect with its own build and fade wastes most of its budget on frames
    that are almost entirely black. The floor is a fraction of the clip's own
    peak brightness rather than an absolute, so it scales with the clip.

    It is still worth setting per effect. A burst wants two or three frames of
    anticipation and no more: lightning at the 0.02 default kept seven frames of
    a barely-visible spark, a quarter of the whole animation spent before the
    payoff. It is a pacing decision, so it lives in the spec where it can be
    seen and argued with.
    """
    energy = frames.astype(np.float32).max(axis=3).mean(axis=(1, 2))
    threshold = energy.max() * floor
    live = np.nonzero(energy >= threshold)[0]
    if live.size == 0:
        return 0, len(frames) - 1
    return int(live[0]), int(live[-1])


def pick(frames: np.ndarray, start: int, end: int, count: int) -> list[int]:
    """`count` indices spread evenly across [start, end]."""
    if count >= (end - start + 1):
        return list(range(start, end + 1))
    return [int(round(start + (end - start) * i / count)) for i in range(count)]


def content_box(frames: np.ndarray, floor: int = 12) -> tuple[int, int, int, int]:
    """Bounding box of everything above the black floor, across all frames."""
    lit = frames.max(axis=3).max(axis=0) >= floor
    if not lit.any():
        return 0, 0, frames.shape[2], frames.shape[1]
    ys, xs = np.nonzero(lit)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def symmetric_crop(box, width, height, anchor):
    """Grow the content box so the anchor stays put.

    Cropping to a box that is not centred on the anchor slides the effect
    sideways relative to where the game places it. Mirroring the box about the
    anchor axis costs a little texture and keeps the effect where it was aimed.
    """
    x0, y0, x1, y1 = box
    cx = width / 2.0
    half = max(cx - x0, x1 - cx)
    x0, x1 = int(np.floor(cx - half)), int(np.ceil(cx + half))

    if anchor == "center":
        cy = height / 2.0
        halfv = max(cy - y0, y1 - cy)
        y0, y1 = int(np.floor(cy - halfv)), int(np.ceil(cy + halfv))
    # anchor == "bottom": the base is pinned to the bottom of the source frame,
    # so the bottom edge must not move. Only the top is free to tighten.
    elif anchor == "bottom":
        y1 = height

    return (max(0, x0), max(0, y0), min(width, x1), min(height, y1))


def edge_fade(cells: np.ndarray, fade: dict) -> np.ndarray:
    """Ramp the outer border of every cell down to black.

    An effect whose glow reaches the edge of its source frame gets hard-cut by
    the edge of the quad it is drawn on, and additive blending turns that cut
    into a visible bright-edged rectangle floating in the room. The lightning
    burst does exactly this - at its peak not one pixel of its frame is black.

    The ramp is applied per side because the right answer differs per side: a
    beam is *supposed* to run off the top and bottom of its quad, so fading those
    would turn a continuous column into a floating capsule.
    """
    if not fade:
        return cells
    h, w = cells.shape[1], cells.shape[2]
    mask = np.ones((h, w), dtype=np.float32)

    def ramp(n: int, frac: float) -> np.ndarray:
        span = max(1, int(round(n * frac)))
        # smoothstep, so the falloff has no visible start line of its own
        t = np.linspace(0.0, 1.0, span, dtype=np.float32)
        return t * t * (3.0 - 2.0 * t)

    if fade.get("x", 0.0) > 0.0:
        r = ramp(w, fade["x"])
        mask[:, :r.size] *= r[None, :]
        mask[:, w - r.size:] *= r[::-1][None, :]
    if fade.get("top", 0.0) > 0.0:
        r = ramp(h, fade["top"])
        mask[:r.size, :] *= r[:, None]
    if fade.get("bottom", 0.0) > 0.0:
        r = ramp(h, fade["bottom"])
        mask[h - r.size:, :] *= r[::-1][:, None]

    out = cells.astype(np.float32) * mask[None, :, :, None]
    return np.clip(out, 0, 255).astype(np.uint8)


def grid_for(count: int) -> tuple[int, int]:
    """Columns and rows closest to square, preferring wider than tall."""
    best = (count, 1)
    best_score = None
    for cols in range(1, count + 1):
        rows = -(-count // cols)
        if cols * rows != count:
            continue
        score = abs(cols - rows)
        if best_score is None or score < best_score:
            best, best_score = (cols, rows), score
    return best


# ---------------------------------------------------------------------- build

def build(effect: dict, source_dir: Path, spec: dict) -> dict:
    name = effect["name"]
    src = source_dir / effect["source"]
    if not src.exists():
        raise SystemExit(f"{name}: source video missing: {src}")

    frames = decode(src)
    n_src, height, width = frames.shape[0], frames.shape[1], frames.shape[2]

    if effect.get("trim"):
        start, end = trim_to_action(frames, float(effect.get("trim_floor", 0.02)))
    elif "source_range" in effect:
        start, end = effect["source_range"]
        end = min(end, n_src - 1)
    else:
        start, end = 0, n_src - 1

    indices = pick(frames, start, end, int(effect["frames"]))
    chosen = frames[indices]

    report = check_palette(
        chosen,
        effect["palette"],
        float(spec["chromatic_value_floor"]),
        float(spec["chromatic_saturation_floor"]),
    )
    ceiling = float(spec["max_wrong_side_fraction"])
    status = "ok" if report.passes(ceiling) else "REFUSED"
    print(f"  {name:<10} palette {effect['palette']:<8} "
          f"own {report.own_side_pct:6.3f}%  wrong {report.wrong_side_pct:6.3f}%  "
          f"neutral {report.neutral_pct:6.3f}%  [{status}]")
    if status == "REFUSED":
        raise SystemExit(
            f"{name}: {report.wrong_side_pct:.3f}% of chromatic pixels are "
            f"{OPPOSITE[effect['palette']]}-side, over the "
            f"{ceiling * 100:.1f}% ceiling. Colour ownership is a readability "
            f"rule, not a preference - regenerate rather than relax the gate."
        )

    box = symmetric_crop(
        content_box(chosen), width, height, effect.get("anchor", "center"))
    cropped = chosen[:, box[1]:box[3], box[0]:box[2], :]
    cropped = edge_fade(cropped, effect.get("edge_fade", {}))
    crop_h, crop_w = cropped.shape[1], cropped.shape[2]

    long_edge = int(effect["long_edge_px"])
    if crop_w >= crop_h:
        cell_w = long_edge
        cell_h = max(4, int(round(long_edge * crop_h / crop_w)))
    else:
        cell_h = long_edge
        cell_w = max(4, int(round(long_edge * crop_w / crop_h)))
    # Multiples of four keep every cell origin on a texel boundary the GPU is
    # happy with, and stop rounding from drifting cell to cell across the sheet.
    cell_w -= cell_w % 4
    cell_h -= cell_h % 4

    cols, rows = grid_for(len(indices))
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (0, 0, 0))
    for i in range(cropped.shape[0]):
        cell = Image.fromarray(cropped[i]).resize((cell_w, cell_h), Image.LANCZOS)
        sheet.paste(cell, ((i % cols) * cell_w, (i // cols) * cell_h))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{name}.png"
    sheet.save(out, optimize=True)

    duration = len(indices) / float(effect["fps"])
    meta = {
        "name": name,
        "texture": f"res://assets/vfx/realtime/{name}.png",
        "job_id": effect["job_id"],
        "model": effect["model"],
        "palette": effect["palette"],
        "orientation": effect["orientation"],
        "anchor": effect.get("anchor", "center"),
        "loop": bool(effect["loop"]),
        "cols": cols,
        "rows": rows,
        "frame_count": len(indices),
        "cell_width": cell_w,
        "cell_height": cell_h,
        "aspect": round(cell_w / cell_h, 6),
        "fps": float(effect["fps"]),
        "duration_seconds": round(duration, 4),
        "source_frames": [int(indices[0]), int(indices[-1])],
        "source_size": [width, height],
        "crop_box": list(box),
        "sheet_size": [sheet.width, sheet.height],
        "sheet_bytes": out.stat().st_size,
        "colour": asdict(report),
        "note": effect.get("note", ""),
    }
    print(f"             {cols}x{rows} of {cell_w}x{cell_h}  "
          f"-> {sheet.width}x{sheet.height}  {out.stat().st_size / 1024:.0f} KiB  "
          f"{duration:.2f}s {'loop' if effect['loop'] else 'one-shot'}")
    return meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sources", type=Path, required=True,
                    help="directory holding the source .mp4 files")
    ap.add_argument("--only", help="build a single effect by name")
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text())
    effects = spec["effects"]
    if args.only:
        effects = [e for e in effects if e["name"] == args.only]
        if not effects:
            return print(f"no effect named {args.only}") or 1

    print(f"Building {len(effects)} effect sheet(s) from {args.sources}")
    built = [build(e, args.sources, spec) for e in effects]

    META_OUT.parent.mkdir(parents=True, exist_ok=True)
    META_OUT.write_text(json.dumps(
        {"effects": built}, indent=2, sort_keys=False) + "\n")
    total = sum(b["sheet_bytes"] for b in built)
    print(f"\nWrote {META_OUT.relative_to(ROOT)}")
    print(f"{len(built)} sheets, {total / 1024 / 1024:.2f} MiB on disk")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
