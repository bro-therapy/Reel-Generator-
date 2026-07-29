# Master Generation Prompt

One block to paste into a fresh ChatGPT conversation. It sets the style once, then walks
all eleven sheets one at a time.

Paste everything between the rules below, then reply `next` after each sheet.

---

You are producing sprite sheets for an original 2D action game called Project Zero Climb.
I will paste this brief once. You will then produce ELEVEN separate sheets, ONE PER
RESPONSE, in the order listed. After each sheet, wait for me to say "next" before
producing the following one. Never combine two sheets into a single image. Never produce
a contact sheet or preview of all of them together.

## LOCKED STYLE — applies to every sheet, never deviate

Bold 16-bit-inspired anime pixel art. Thick near-black contour lines. Large flat colour
blocks, four or five shades per material. Hard cel shadows, restrained internal texture.
No smooth painterly rendering, no micro-detail, no gradients, no bloom, no lens effects.

## LOCKED COLOURS

- Friendly / summon energy: violet `#9C6BFF`, indigo, blue-white core `#F8F4FF`
- Hostile attacks and telegraphs: red `#FF5B67`, orange `#FF8A3D`, warm white `#FFF0D4`
- Rewards and interactables: gold `#F3C65C`, teal `#44D7E8`, soft green `#61D095`
- Environment: sandstone, terracotta, wood, green plants, less saturated than characters

Never draw a large violet hostile shape. Never tint a friendly effect red. Friendly and
hostile colour languages must stay separable at a glance.

## LOCKED TECHNICAL RULES

1. Flat `#00ff00` chroma background, edge to edge. No shadow, glow, or vignette touching
   the background.
2. Exact grid, exact cell size, no overlap, no bleed between cells.
3. **Every frame in a row places the subject's CONTACT FOOT (or lowest point) on the SAME
   PIXEL ROW.** A consistent ground line across a row is the single most important
   requirement in this brief. Frames that drift vertically are unusable.
4. Identical subject scale across every cell in a sheet.
5. No text, no labels, no numbers, no watermark, no logo, no borders, no grid lines drawn
   into the image.
6. Original designs only. Do not reproduce any existing game's character, creature,
   interface, or asset.
7. Each subject and its effects stay fully inside their own cell.

---

## SHEET 1 — Awakened summons

Grid: 7 columns × 3 rows. Cell 220×342 px. Total image 1540×1026 px.

Rows, in this exact order:
1. **Volt Hound** — an evolved four-legged spirit hound wreathed in crackling violet
   lightning, larger and more armoured than a base hound, with a crescent-shaped energy
   mane. Eager, aggressive posture.
2. **Twin Oath Blades** — a floating pair of mirrored spirit swords bound by a violet
   ribbon, orbiting a small glowing core. Disciplined, silent, precise.
3. **Burst Golem** — a squat armoured construct with a heavy multi-barrel cannon arm and
   violet vents. Planted, stubborn, mechanical.

Columns, in this exact order, identical for every row:
1. idle — neutral resting pose
2. move — mid-travel pose
3. windup — visibly gathering energy before the attack
4. attack — the strike at full commitment
5. attack recovery — settling after the strike
6. hit — recoiling from taking a blow
7. reform — dissolving into violet particles and reassembling

Each creature is roughly 0.6× the height of a human hero. Violet energy with a blue-white
core only, never red.

## SHEET 2 — Ascendant summons

Identical grid, cells, columns and rules as Sheet 1. Total image 1540×1026 px.

Rows:
1. **Tempest Fenrir** — a large storm-wolf of violet lightning with chained energy arcs
   trailing from its shoulders, wider and heavier than Volt Hound.
2. **Halo Blade Seraph** — three orbiting spirit blades around a haloed violet core, with
   a ring of interception light.
3. **Arsenal Titan** — a broad siege construct with three shoulder-mounted missile pods
   and glowing violet exhaust ports.

All three stay below roughly 1.5× hero height and keep clean, readable silhouettes.

## SHEET 3 — Gilded Bellguard elite

Grid: 6 columns × 1 row. Cell 209×209 px. Total 1254×209 px.

Subject: an elite version of a broad armoured tank carrying a cracked ceremonial bell
shield. Gold and polished bronze plating instead of dull bronze, with TWO glowing red
cores on the chest. Visibly richer and heavier than a standard guard, but the same
silhouette family so it reads as the same species.

Columns: idle, move contact, move passing, attack windup (shield raised, red wedge
telegraph forming at its feet), attack active (slam impact), death (collapsing, gold
plating cracking, cores going dark).

## SHEET 4 — Boss additional frames

Grid: 4 columns × 1 row. Cell 272×724 px. Total 1088×724 px.

Subject: **The First Bell** — a towering corrupted civic guardian fused to a cracked
ceremonial bell. Bronze and black armour, chained arms, belfry shoulders, an exposed red
core, restrained violet corruption cracks. Roughly 2.5× human hero height. One fixed
ground line across all four cells.

Columns:
1. chain sweep active — chain mid-swing at full extension, motion trailing
2. hit — recoiling from damage, chains rattling, brief white contour flash
3. phase two — the idle pose, but the red core burns visibly brighter and the violet
   cracks spread further across the armour
4. enrage — core at maximum intensity, bell tilted forward, aggressive forward lean

## SHEET 5 — Convergence signature effects

Grid: 8 columns × 3 rows. Cell 222×222 px. Total 1776×666 px.

Each row is one energy effect animating left to right across 8 frames, starting small and
fully dissipated by the final frame. No characters in this sheet.

Rows:
1. a horizontal lightning-wolf streak tearing across frame — violet lightning shaped like
   a lunging wolf, blue-white core
2. a large circular blade cut — a violet ring of energy expanding outward with a sharp
   blue-white leading edge
3. a multi-cannon barrage — several violet energy bolts firing outward in a spread, with
   muzzle bursts

Violet with blue-white cores throughout. No red anywhere in this sheet.

## SHEET 6 — Rally target marker

Grid: 6 columns × 1 row. Cell 222×222 px. Total 1332×222 px.

A floating diamond target marker animating as a 6-frame pulse loop that reads cleanly when
looping — frame 6 must flow back into frame 1.

The diamond body is hostile red `#FF5B67` because it marks an enemy. It is surrounded by a
thin violet `#9C6BFF` outline showing the player placed it. Keep the two colours clearly
separate; do not blend them into a muddy purple-red. Nothing else in frame.

## SHEET 7 — Spirit Core objective

Grid: 3 columns × 1 row. Cell 222×222 px. Total 666×222 px.

A fragile floating crystal shard held in a small bronze cradle, glowing teal `#44D7E8`.

Columns: intact (calm steady glow, crystal whole), damaged (crystal cracked, glow
flickering and dimmer, cradle bent), destroyed (crystal shattered, fragments falling, glow
going out).

## SHEET 8 — Enemy hit reactions

Grid: 1 column × 6 rows. Cell 209×209 px. Total 209×1254 px.

One "recoiling from a hit" frame per creature, in this exact row order:
1. Rift Crawler — low black-stone chaser with horn plates and a red core
2. Lantern Hexer — tall ranged caster with a red lantern staff
3. Bellguard — broad tank with a cracked bronze bell shield
4. Nest Idol — small spawner carrying a corruption nest
5. Blade Mite — lean dasher with scissor limbs
6. Siphon Eye — floating leech with a red tether

Each shows damage being taken: head snapped back, body compressed, limbs trailing, brief
white flash on the contour. Must be clearly distinct from an attack windup — this is
damage received, not damage about to be dealt.

## SHEET 9 — UI components

Flat `#00ff00` background. Separate elements laid out on a clean grid with generous
spacing. Dark charcoal panels, bronze edging, violet energy accents. Symbols and shapes
only — **absolutely no text of any kind**.

Include each as its own separate element:
- a horizontal bar frame and its fill, three times: red (health), teal (stability), violet
  (special meter)
- a circular cooldown ring, shown empty and full
- three small pips in a row, shown twice: unfilled and filled
- five action icons: a staff, a dash arrow, a diamond, a chevron, a starburst
- three card border frames of increasing ornateness: plain bronze, silver-violet, gold
- a coin, a circular reroll arrow loop, a padlock
- a small square button glyph and a small round button glyph

Every element must stay readable at 48 pixels. Consistent line weight and bronze tone
throughout.

## SHEET 10 — Environment tiling textures

A grid of separate square texture swatches with clear gaps between them. Each swatch must
tile seamlessly with itself.

Include: three subtly different warm cobblestone floor variants, sandstone block wall,
terracotta roof tiles, weathered wood planking, cream plaster, green leafy planter
foliage.

Warm and sunlit, but noticeably LESS saturated than a character would be — this is the
combat floor and it must sit behind the actors rather than compete with them. No
characters, no props.

## SHEET 11 — Floor decals

Flat `#00ff00` background. Four separate elements with clear spacing, each viewed straight
down from directly above, completely flat with no perspective.

1. corruption breach — violet crystal shards breaking through blackened cracked stone
2. arena floor emblem — a large circular ceremonial bell sigil in worn bronze inlay
3. sealed gate marking — a violet warded barrier sigil
4. spirit well marker — a teal circular inlay with soft radiating lines

---

## Reminders for every sheet

- Same ground line across every frame in a row. This is the rule that matters most.
- Flat `#00ff00` background, no text, no watermark, no borders.
- One sheet per response. Wait for "next".

---

## After you have the images

Convert chroma to alpha, split to cells, and name the files to match the existing
convention so they drop straight into the project:

```
{row:02d}_{subject}__{col:02d}_{state}.png
00_volt_hound__00_idle.png
00_volt_hound__01_move.png
...
```

Then rebuild and audit:

```bash
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
```

Check `baseline_spread_px` in `docs/generated/*.json`. **Target 0.** Above ~3 needs a
runtime pivot correction; above ~15 is visible as a hop and should be regenerated.
