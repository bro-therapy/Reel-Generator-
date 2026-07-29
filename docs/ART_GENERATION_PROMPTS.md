# Art Generation Prompts — remaining slice assets

Copy-paste prompts for producing the art still missing from the vertical slice.

Matches the pipeline the package already used (recorded in
`docs/IMAGE_GENERATION_PROMPTS.md`): generate on a flat `#00ff00` chroma background,
convert to alpha locally, align to a divisible grid, split into cells.

Read `docs/ANIMATION_GUIDE.md` §6 first. **Generate key poses, not cycles** — the shipped
art's 28 px pivot drift is what happens when a model draws a cycle without memory of the
previous frame.

---

## The style header

Prepend this to **every** prompt below. It carries the locked identity from master guide
§2 and the colour rules from `ASSET_MANIFEST.json`, so nothing drifts between sheets.

```
STYLE (do not deviate):
Bold 16-bit-inspired anime pixel art. Thick near-black contour lines. Large flat colour
blocks, four or five shades per material. Hard cel shadows, restrained internal texture.
No smooth painterly rendering, no micro-detail, no gradients, no lighting bloom.

COLOUR RULES:
- Friendly / summon effects: violet #9C6BFF, indigo, blue-white core #F8F4FF
- Hostile attacks and telegraphs: red #FF5B67, orange #FF8A3D, warm white #FFF0D4
- Rewards and interactables: gold #F3C65C, teal #44D7E8, soft green #61D095
- Environment: sandstone, terracotta, wood, green plants — less saturated than actors
Never use a large violet hostile shape. Never tint a friendly effect red.

TECHNICAL (mandatory):
- Flat #00ff00 chroma background, edge to edge. No shadows or glow on the background.
- Every cell exactly the same size, laid out on an even grid, no overlap, no bleed.
- Every frame in a row places the character's CONTACT FOOT ON THE SAME PIXEL ROW.
  Consistent ground line across the whole row is the single most important requirement.
- Identical character scale across every cell in the sheet.
- No text, no labels, no frame numbers, no watermark, no logo, no borders.
- Original designs only. Do not reproduce any existing game's character or interface.
```

---

## 1. Summon evolution forms — **highest priority, blocks Phase 7**

Only the Bound tier ships as usable frames. Names come from the package's own generation
record, so they are canon.

| Species | Bound (ships) | Awakened | Ascendant |
|---|---|---|---|
| Rune Hound | Rune Hound | **Volt Hound** | **Tempest Fenrir** |
| Sword Wisp | Sword Wisp | **Twin Oath Blades** | **Halo Blade Seraph** |
| Gun Construct | Gun Construct | **Burst Golem** | **Arsenal Titan** |

Generate as **two sheets** (one per tier) so each stays a 3-row image — models hold
consistency far better across 3 rows than 6.

```
[STYLE HEADER]

A sprite sheet of three original summoned creatures, one species per row, 7 columns.

Grid: exactly 7 columns x 3 rows. Cell size 220 x 342 pixels. Total 1540 x 1026.

ROWS, in this exact order:
1. Volt Hound — an evolved four-legged spirit hound wreathed in crackling violet
   lightning. Larger and more armoured than a base hound, with a crescent-shaped energy
   mane. Aggressive, eager posture.
2. Twin Oath Blades — a floating pair of mirrored spirit swords bound by a violet ribbon,
   orbiting a small glowing core. Disciplined, silent, precise.
3. Burst Golem — a squat armoured construct with a heavy multi-barrel cannon arm and
   violet vents. Planted, stubborn, mechanical.

COLUMNS, in this exact order, same for every row:
1. idle — neutral resting pose
2. move — mid-travel pose
3. windup — visibly gathering energy, before the attack
4. attack — the strike itself, at full commitment
5. attack recovery — settling after the strike
6. hit — recoiling from taking a blow
7. reform — dissolving into violet particles and reassembling

All effects stay inside their own cell. Each creature is roughly 0.6x the height of a
human hero. Violet energy with a blue-white core only — never red.
```

Then the same prompt for the Ascendant tier, swapping the three rows for:

```
1. Tempest Fenrir — a large storm-wolf of violet lightning, chained energy arcs trailing
   from its shoulders, wider and heavier than Volt Hound.
2. Halo Blade Seraph — three orbiting spirit blades around a haloed violet core, with a
   ring of interception light.
3. Arsenal Titan — a broad siege construct with three shoulder-mounted missile pods and
   glowing violet exhaust ports.

All three remain below roughly 1.5x hero height and stay animation-friendly silhouettes.
```

**Output: 42 frames.** Unblocks Phase 7's "evolution visibly changes the summon".

---

## 2. Enemy hit column — 6 frames

Only needed if you want real flinch art rather than a shader flash (see
`ANIMATION_GUIDE.md`; the flash is the cheaper recommendation).

```
[STYLE HEADER]

A sprite sheet of six original enemy creatures, one per row, 1 column — a single "hit
reaction" frame each.

Grid: exactly 1 column x 6 rows. Cell size 209 x 209 pixels. Total 209 x 1254.

ROWS, in this exact order, matching an existing lineup:
1. Rift Crawler — low black-stone chaser with horn plates and a red core
2. Lantern Hexer — tall ranged caster with a red lantern staff
3. Bellguard — broad tank with a cracked bronze bell shield
4. Nest Idol — small spawner carrying a Rift nest
5. Blade Mite — lean dasher with scissor limbs
6. Siphon Eye — floating leech with a red tether

Each frame shows the creature recoiling from an impact: head snapped back, body
compressed, limbs trailing. Clearly distinct from an attack windup — this is damage
taken, not damage about to be dealt. Brief white impact flash on the contour.
```

---

## 3. Gilded Bellguard — 6–7 frames

The elite currently reuses standard Bellguard frames, so a player cannot tell an elite
from a normal tank.

```
[STYLE HEADER]

A sprite sheet of one original elite enemy, 6 columns x 1 row.

Grid: exactly 6 columns x 1 row. Cell size 209 x 209 pixels. Total 1254 x 209.

SUBJECT: Gilded Bellguard — an elite version of a broad armoured tank carrying a cracked
ceremonial bell shield. Gold and polished bronze plating instead of dull bronze, with
TWO glowing red cores on the chest. Visibly richer and heavier than the standard version,
same silhouette family so it reads as the same species.

COLUMNS, in this exact order:
1. idle
2. move contact
3. move passing
4. attack windup — shield raised, red wedge telegraph forming at its feet
5. attack active — slam impact
6. death — collapsing, gold plating cracking, cores going dark
```

---

## 4. Boss gap frames — 3–4 frames

Eight ship. These are the ones guide §11 requires and the package does not contain.

```
[STYLE HEADER]

A sprite sheet of one original boss, 4 columns x 1 row.

Grid: exactly 4 columns x 1 row. Cell size 272 x 724 pixels. Total 1088 x 724.

SUBJECT: The First Bell — a towering corrupted civic guardian fused to a cracked
ceremonial bell. Bronze and black armour, chained arms, belfry shoulders, an exposed red
core, restrained violet Rift cracks. Roughly 2.5x human hero height. One fixed ground
line across all four cells.

COLUMNS, in this exact order:
1. chain sweep active — the chain mid-swing at full extension, motion trailing
2. hit — recoiling from damage, chains rattling, brief white contour flash
3. phase two — same pose as an idle but the red core burns visibly brighter and the
   violet Rift cracks spread further across the armour
4. enrage — core at maximum intensity, bell tilted forward, aggressive forward lean
```

---

## 5. Convergence signature attacks — 3 sequences

One per summon, described in guide §5 and shipped nowhere. These are effects, not
characters, so a model handles a short sequence far better here — there is no face or
anatomy to keep on-model.

```
[STYLE HEADER]

A sprite sheet of three original energy-effect sequences, one per row, 8 columns.

Grid: exactly 8 columns x 3 rows. Cell size 222 x 222 pixels. Total 1776 x 666.

Each row is one effect animating left to right across 8 frames, starting small and
dissipating by the final frame.

ROWS:
1. A horizontal lightning-wolf streak tearing across the frame — violet lightning shaped
   like a lunging wolf, blue-white core.
2. A large circular blade cut — a violet ring of energy expanding outward with a sharp
   blue-white leading edge.
3. A multi-cannon barrage — several violet energy bolts firing outward in a spread, with
   muzzle bursts.

Violet with a blue-white core throughout. No red anywhere in this sheet.
```

---

## 6. Rally mark — 1 looping marker

```
[STYLE HEADER]

A sprite sheet of one original target marker, 6 columns x 1 row.

Grid: exactly 6 columns x 1 row. Cell size 222 x 222 pixels. Total 1332 x 222.

SUBJECT: a floating diamond target marker, animating as a 6-frame pulse loop that reads
cleanly when looping (frame 6 flows back into frame 1).

The diamond body is HOSTILE RED #FF5B67 — it marks an enemy. It is surrounded by a thin
VIOLET #9C6BFF friendly outline showing it was placed by the player. Both colours must
stay clearly separate; do not blend them into purple-red.

Nothing else in the frame. No character, no ground.
```

---

## 7. Spirit Core — 3 frames

The protect-the-core object for the optional Rift. Not in the package at all.

```
[STYLE HEADER]

A sprite sheet of one original objective object, 3 columns x 1 row.

Grid: exactly 3 columns x 1 row. Cell size 222 x 222 pixels. Total 666 x 222.

SUBJECT: a Spirit Core — a fragile floating crystal shard held in a small bronze cradle,
glowing teal #44D7E8 as a protectable objective.

COLUMNS:
1. intact — calm, steady teal glow, crystal whole
2. damaged — crystal visibly cracked, glow flickering and dimmer, cradle bent
3. destroyed — crystal shattered, fragments falling, glow going out
```

---

## 8. UI component set

The largest remaining body of work. The three shipped UI sheets are flattened mockups and
cannot be used as an interactive interface — the brief requires native Godot `Control`
nodes, so what is needed is **components on transparent background**, not screens.

```
[STYLE HEADER]

A sprite sheet of original game UI components on a flat #00ff00 background, arranged on a
clean grid with generous spacing between elements.

Dark charcoal panels with bronze edging and violet energy accents.
Symbols and shapes only — NO TEXT of any kind.

INCLUDE, each as its own separate element:
- A horizontal bar frame and its fill, three times: health (red), Stability (teal),
  Convergence meter (violet)
- A circular cooldown ring, empty and full
- Three small pips in a row, shown twice: unfilled, and filled (bond tier indicators)
- Five action icons: a staff, a dash arrow, a rally diamond, a team-command chevron, a
  convergence starburst
- Three card border frames of increasing ornateness: plain bronze, silver-violet, gold
- A currency coin, a reroll arrows-loop, a padlock
- A small square button glyph and a small round button glyph

Every element readable at 48 pixels. Consistent line weight and bronze tone throughout.
```

---

## 9. Environment materials and decals

Blockout geometry is built in-engine; what is missing is surfacing.

```
[STYLE HEADER]

A sheet of seamless tiling texture swatches for a warm tower-town district, arranged as a
grid of separate square swatches with clear gaps between them.

Each swatch must tile seamlessly with itself.

INCLUDE:
- Three cobblestone floor variants, warm sandstone tones, subtly different
- Sandstone block wall
- Terracotta roof tiles
- Weathered wood planking
- Cream plaster
- Green leafy planter foliage

Warm, sunlit, LESS saturated than a character would be — this is the combat floor and it
must sit behind the actors, not compete with them. No characters, no props, no labels.
```

```
[STYLE HEADER]

A sheet of four original floor decals on a flat #00ff00 background, each a separate
circular or square element with clear spacing.

1. Rift corruption — violet crystal shards breaking through blackened cracked stone
2. Boss arena floor emblem — a large circular ceremonial bell sigil in worn bronze inlay
3. Sealed gate marking — a violet warded barrier sigil
4. Spirit Well marker — a teal circular inlay with soft radiating lines

Viewed straight down from above, flat, no perspective. Suitable for projecting onto a
floor.
```

---

## Priority order

1. **Summon evolution forms** (42 frames, two sheets) — blocks Phase 7, the next phase.
2. **Gilded Bellguard** (6) — the elite is currently invisible as an elite.
3. **Boss gap frames** (4) — blocks Phase 11 readability.
4. **Convergence signatures + Rally mark** (~30) — blocks Phase 12.
5. **UI component set** — blocks Phases 9 and 13.
6. **Environment materials and decals** — Phase 8 surfacing.
7. **Spirit Core** (3) — Phase 10.
8. **Enemy hit column** (6) — optional; the shader flash is cheaper and reads fine.

---

## After generating

1. Convert chroma to alpha and split to cells — the package's own workflow.
2. Drop the split frames into the matching `assets/` directory.
3. Rebuild and audit:

```bash
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
```

4. Check `baseline_spread_px` in `docs/generated/*.json`. **Target 0.** Anything above ~3
   will need a runtime pivot correction, and anything above ~15 will be visible as a hop.
5. Record any inconsistency in `ART_CLEANUP_TODO.md` rather than repainting — that is a
   locked project rule.
