# Higgsfield asset guide — what it can and cannot make for this game

Written 2026-07-30, from measurements against the live account (ultra plan,
~2,848 credits at time of writing), not from marketing pages. Read this before
spending credits.

The one-line summary: **Higgsfield is good for still images and useless, today,
for character animation frames.** Plan asset requests accordingly.

---

## 1. The hard finding: no sprite animation path

The owner's standing wish is better walk cycles for the hero and side-profile
walks for the summons. Both are blocked, and the blocker was measured twice:

### `autosprite` exists but cannot be invoked
The catalog lists a purpose-built sprite tool — `autosprite`, with
`iso_walk_right` / `iso_walk_up` presets, `remove_bg: ultra`, `frame_count`
2–64, an `is_humanoid` flag. It is exactly the right tool. It does not run:

- cost preflight: `Error estimating cost: Something went wrong`
- submission: **`Job set type not supported: autosprite`**

It appears to be catalogued ahead of being enabled. Re-test it first whenever
this guide feels stale — if it ever turns on, it obsoletes most of this page.
No credits were spent on the attempts (both calls failed before billing).

### Image-to-video cannot hold a character stable
The fallback — animate a reference frame with image-to-video, then slice
frames — was measured in `docs/HIGGSFIELD_ANIMATION_TEST.md`: the character's
height drifted **25% across the clip**. A walk cycle lives or dies on a stable
silhouette and a fixed ground pivot; 25% height variance reads as the actor
breathing like a balloon. Fatal. Do not re-try this without a reason to believe
the model changed.

**Consequence:** hero/summon/enemy animation frames stay on the shipped split
PNGs. The side-profile summon walk stays open in `ART_CLEANUP_TODO.md` until
`autosprite` turns on or the owner sources frames another way (e.g. a
commissioned sheet, or ChatGPT image gen if it can hold a grid — verify pivot
stability the same way before installing anything).

---

## 2. What Higgsfield IS good for here

Static images have no pivot-stability problem. These are the asset classes
worth credits, in priority order for making the ward feel less primitive:

| Priority | Asset | Why it works | Where it lands |
|---|---|---|---|
| 1 | **Floor/wall decals** — scorch rings, cracked emblems, moss patches, worn thresholds | flat textures, no silhouette to hold | `assets/environment/decals/`, used by `ward_builder._build_decal` |
| 2 | **Prop textures** — crate faces, awning stripes, banner cloth, market signage | tiling or single-face textures on existing blockout boxes | `assets/environment/textures/`, via `_surface()` |
| 3 | **Title key art** — one painted Sunfall Ward vista behind the menu | single still, shown at rest; the title screen is plain indigo today | `assets/ui/title_bg.png`, `TitleScreen._build` |
| 4 | **Icon art** — relic/echo/currency icons at 64–128 px | small stills, already have placeholder slots | `assets/ui/icons/` |
| 5 | **Boss key art** — First Bell portrait for the results screen | still, decorative | results screen |

Rules that still apply to every generated image (CLAUDE.md, guide §2):

- **Colour ownership is a hard gate.** Violet/indigo/blue-white = friendly,
  red/orange/warm-white = hostile, gold/teal/soft-green = rewards. Run
  `tools/vfx_from_video.py`'s hue-histogram check on anything ambiguous. A
  violet decal under a hostile spawn point is a bug, not a style choice.
- **The environment sheet is reference, not a texture source** — but generated
  textures must match its palette: warm sandstone, terracotta, cream plaster,
  sunlit and less saturated than the actors.
- **Pixel-fidelity boundary.** Actors are pixel art; the environment is not.
  Generated environment textures should be painterly/photographic and slightly
  soft, so the pixel actors pop in front of them. Do not generate fake pixel
  art — it will fight the real frames' grid.
- Import with the same settings as everything else: filtering per material
  type (props/decals may filter; actor sprites never do).

## 3. Workflow that has worked

1. `generate_image` with an explicit palette callout in the prompt
   ("warm sandstone cobbles, terracotta accents, soft late-afternoon sun,
   subtle wear, seamless tile").
2. For tiling textures, ask for "seamless, top-down, even lighting" and test
   the tile in-engine at the uv_scale the material really uses (`_surface()`
   scales are 0.12–0.7 — a texture that reads at 1.0 can smear at 0.14).
3. `remove_background` for decals that need alpha.
4. `upscale_image` only if the source resolution actually limits you —
   floor decals live under actors and rarely need it.
5. Record every generated file in `docs/VFX_SOURCES.json` alongside the video
   sources, so a fresh clone can re-derive what came from where.

## 4. Credit discipline

- Preflight cost on every job type the first time it is used.
- Stills are cheap; video is not. The realistic VFX (fire, beams) already
  exist and were the one video spend that survived measurement — do not
  re-generate them casually.
- If a job type errors at preflight (as `autosprite` does), stop. Errors
  before billing are free; retries "to see if it works now" are how credits
  evaporate.
