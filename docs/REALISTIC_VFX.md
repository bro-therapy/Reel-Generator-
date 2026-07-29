# Realistic effects

Four filmed-looking effects — fire, beam, lightning, shockwave — drawn additively
over the pixel actors. They are the **only** generated art in the project.
Everything else still comes from the shipped package; see `CLAUDE.md`.

They exist because the owner asked for them directly: *"I want like realistic
fire effects and realistic like beams and different things like that, to really
give it that cool two D pixel, but then some realistic effects to make the game
look cool."* That is an explicit override of the no-generated-art rule, scoped to
effects. It is **not** an override of colour ownership, which is a readability
rule rather than a style preference — see below.

## The pipeline

```bash
./tools/vfx_from_video.py --sources <dir with the mp4s>
godot --headless --path . --import
godot --headless --path . --script scripts/tools/build_additive_vfx.gd
godot --headless --path . --script scripts/tests/vfx_acceptance.gd
```

`docs/VFX_SOURCES.json` is the recipe and the provenance: for each effect it
records the Higgsfield job id, the exact prompt, and every build decision. Nothing
about a sheet is implicit — a sheet can be regenerated or audited without guessing
what was done to it.

`docs/generated/vfx_sheets.json` is the output. Do not hand-edit it, and do not
hand-edit `data/vfx/realtime/*.tres`: the grid there is used to index the texture,
and if the two disagree every frame samples the wrong rectangle. It still renders,
so nothing but the acceptance check would notice.

## Three decisions worth knowing about

**Additive, on black.** The clips were generated on pure black and are never
keyed. Black adds nothing, so there is no alpha channel, no matte line, no halo
and no cutout threshold to tune. It also means the effects *glow over* what is
behind them instead of punching a hole in it, which is the whole reason for using
filmed fire on top of pixel art.

**A quad and a shader, not an `AnimatedSprite3D`.** `SpriteBase3D` has no blend
mode, and its `material_override` replaces the material carrying the per-frame
texture — there is no way to get an additive sprite out of it. A quad indexing a
sprite sheet costs the same single draw call and actually glows. The frame is a
uniform, so an entire animation is one texture and one material: twenty effects is
twenty draw calls, not twenty draw calls plus twenty texture binds per frame.

**Cropped to content.** A flame column uses about a third of a square frame;
storing the rest is wasted texture and wasted fill rate. The crop is symmetric
about the anchor so the effect does not shift, and the cell aspect is carried into
the resource so the quad is sized to match rather than stretched back to square.
The beam went from 256 px wide to 124.

## Colour ownership is enforced, not documented

Violet and blue-white belong to the player; red and orange belong to whatever is
trying to kill them. The player reads that split before they read anything else,
and it is what the no-aim promise rests on.

So it is measured, twice, on the shipped pixels:

- `tools/vfx_from_video.py` refuses to write a sheet whose hue histogram crosses
  into the other side's band.
- `scripts/tests/vfx_acceptance.gd` re-measures the built texture every run —
  reading the `.png` that ships, not the `.json` that produced it, because
  checking the input passes happily against a texture nobody rebuilt.

Measured wrong-side fractions on the four shipped effects are **0.000%** against a
0.5% ceiling, so the gate has two orders of magnitude of headroom and would still
catch a real leak. Both mutants — mislabelling fire as friendly, and pointing the
beam entry at the fire video — are caught and exit non-zero.

## Draw order

| Layer | Priority |
|---|---|
| Friendly effect (beam, lightning) | -20 |
| Actor | 0 |
| Pickup | 10 |
| **Hostile effect (fire, shockwave)** | **20** |
| Hostile telegraph | 40 |

`HOSTILE_EFFECT` was added for these. A warm-coloured effect is not a telegraph:
being on the hostile side of the palette earns it the top of the effect stack, not
the right to cover the thing the player is supposed to dodge. The guide's rule is
that red telegraphs stay visible beneath *all* effects, not only the violet ones.

## Orientation

`AdditiveVfxData.Facing` — the values are the shader's `facing` uniform, so keep
them in step.

| Effect | Facing | Why |
|---|---|---|
| fire | `UPRIGHT` | Stands up in the world. Turns about the vertical axis only, so it never tips over. |
| beam | `UPRIGHT` | A vertical column in the room. Runs off the top and bottom of its quad on purpose. |
| lightning | `VIEW` | A radial burst reads as a disc facing the player; upright would present it foreshortened and leaning. |
| shockwave | `GROUND` | Shot straight down, so it lies flat in XZ and keeps the node's own rotation. |

`play(p)` means the same thing for every effect: **the effect sits on the ground at
p.** Both standing kinds lift the quad by half its height so the node's origin is
at the base.

## Cost

From `./tools/bench.sh <density> <live effects>`, all at 1920x1080:

| | draw calls | frame ms (median) |
|---|---|---|
| 250 enemies, no effects | 322 | 18.6 |
| 250 enemies, 6 effects | 332 | 19.2 |
| 250 enemies, 12 effects | 340 | 19.3 |

Twelve live effects cost **18 draw calls and about 0.7 ms**. Draw calls and node
counts are hardware-independent and are the numbers to optimise against. The frame
times are llvmpipe, a software rasteriser — comparable between runs on the same
machine and meaningless as an absolute. **Absolute FPS has to be confirmed on real
hardware; nothing here can answer it.**

The cost that matters for these is not draw calls but overdraw: a seven-metre
shockwave is one quad, and additive blending cannot early-z reject, so every pixel
under it is shaded and blended. That is why the benchmark takes a live-effect count
and why the pool has a hard per-effect ceiling.

## Settings

`QualityController` applies the graphics and accessibility settings to the live
scene. Before it existed, the `quality_shadows` / `quality_particles` /
`quality_volumetrics` keys had been in `GameSettings` since Phase 0 and nothing
read them.

`reduced_flashes` is the setting these effects most need to obey — additive light
blowing out to white is exactly what it asks not to see. It **dims** rather than
removes: the effect still has to read, or the setting would be changing what the
player can know, which is the line between a quality setting and a cheat.

## Known rough edges

- The lightning burst still shows a faint rectangular boundary at its widest
  frames. Its source fills the frame edge to edge at peak — not one pixel is black
  — so the 12% edge fade cannot fully hide the quad without eating the arcs.
  Regenerating it with the burst held further inside the frame would fix it
  properly. Logged in `ART_CLEANUP_TODO.md`.
- The effects are filtered linearly and the pixel actors are not. That is
  deliberate and is the point of the contrast, but it means these will never look
  right scaled down to a pixel grid.
