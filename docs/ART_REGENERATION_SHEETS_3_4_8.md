# Regenerating sheets 3, 4 and 8

The eleven-sheet package delivered eight sheets that were immediately usable and three
that were not. Sheets 3, 4 and 8 came back depicting **different creatures** than the ones
they were meant to extend.

All three failed the same way, and it is worth being precise about it because the fix
follows directly: they were generated from a text description alone. Nothing in the
request showed the generator what the creature already looked like, so it invented a
plausible creature matching the words. Sheets 1 and 2 succeeded because they were
*supposed* to be new designs — an evolution is allowed to look different. Sheets 3, 4 and
8 were supposed to match.

**The whole fix is one thing: attach a picture of the creature.**

---

## 1. Build the reference images

```bash
./tools/make_reference_sheets.py
```

Writes to `build/references/`. Every pixel is copied from a frame already in `assets/` —
this generates no art.

| File | Attach to |
|---|---|
| `ref_sheet03_base_bellguard.png` | Sheet 3 |
| `ref_sheet04_first_bell_detail.png` | Sheet 4 |
| `ref_sheet04_first_bell_placement.png` | Sheet 4 (second attachment) |
| `ref_sheet08_rift_crawler.png` … `ref_sheet08_siphon_eye.png` | Sheet 8, one per request |

---

## 2. Sheet 4 — The First Bell, four missing frames

**Attach both `ref_sheet04_first_bell_detail.png` and `ref_sheet04_first_bell_placement.png`.**

Do this one first. It is the clearest failure — the delivered frames are a slender
blue-grey tower where the shipped boss is a squat warm-bronze bell, and guide §11 settles
which is canon: *"Use those frames before attempting substitute art"*, and the identity is
locked as "bronze, black armor, chains, a red core, and restrained violet Rift cracks."

````
I am extending an existing sprite sheet for my own game. The first attached image shows
the EXACT creature, in eight existing frames. The second shows one full untouched cell so
you can see how large the creature is inside it.

Draw FOUR MORE FRAMES OF THIS SAME CREATURE. This is not a redesign, a reinterpretation,
or an upgrade. Someone must be able to put your four frames next to my eight and not be
able to tell which are which.

Match from the reference, exactly:
- Warm bronze and dark gunmetal plating. NOT blue, NOT grey-blue, NOT silver.
- The squat, wide, bell-shaped body — much wider than it is tall.
- The small belfry cap on top with a cross finial and two large curved pale-gold horns.
- The glowing red core in the MIDDLE of the bell face, at the vertical crack.
- The tattered dark red cloth hanging below the bell.
- Two heavy armoured arms on chains, each ending in a small bronze bell.
- Short stubby armoured legs.
- Restrained violet lightning cracks on the plating — thin, not dominant.

Output: ONE image, 1088 x 724 pixels, 4 columns x 1 row, each cell exactly 272 x 724.

CRITICAL SIZE RULE — this is where the last attempt went wrong. In every cell the
creature must be:
- about 300 pixels tall (no more than 315, no less than 280)
- roughly as wide as the cell, up to the full 272 pixels
- with its lowest point — the feet — on pixel row 516, counting from the top

So the creature sits in the middle of a tall cell with large empty space above and below
it. Do NOT zoom in. Do NOT fill the cell. Do NOT make it tall and narrow. It is a wide,
squat shape in a tall frame, exactly as in the second attached image.

The four columns, in this order:
1. chain sweep active — chain mid-swing at full extension, motion trailing behind it
2. hit — recoiling from damage, chains rattling, brief white flash on the contour
3. phase two — the idle pose, but the red core burns brighter and the violet cracks
   spread further across the plating
4. enrage — core at maximum intensity, bell tilted forward, aggressive forward lean

Also required:
- Flat #00ff00 background, edge to edge, no shadow or glow touching it
- Same ground line in all four cells
- No text, no labels, no borders, no grid lines
- Same bold 16-bit anime pixel art style as the reference: thick near-black outlines,
  flat colour blocks, hard cel shadows, no gradients, no bloom
````

---

## 3. Sheet 3 — Gilded Bellguard elite

**Attach `ref_sheet03_base_bellguard.png`.**

The delivered elite is a gold humanoid holding a bell. The creature it elites is dominated
by a large cracked round disc shield. They do not read as the same species.

````
I am making an elite version of an existing enemy in my own game. The attached image shows
the standard version in its six existing frames.

Draw the ELITE version of THIS creature, in the same six poses. It must be recognisably
the same species — someone should see it and think "that is a fancier version of that
enemy", not "that is a different enemy".

Keep from the reference, without exception:
- The LARGE CIRCULAR SHIELD is the dominant shape. It fills most of the cell, is cracked
  through the middle, and the creature stands behind and slightly to the right of it.
  This silhouette is the single most important thing to preserve.
- The armoured body behind the shield, with two large curved horns on the helmet.
- Heavy segmented shoulder plating.
- The tattered dark red cloth.

Change only these, to mark it as elite:
- The shield and armour become polished gold and bronze instead of dull tan and gunmetal.
- TWO glowing red cores on the chest instead of the single core in the shield.
- Slightly heavier, more ornate plating.

Do NOT replace the round shield with a bell. Do NOT make it a standing humanoid holding an
object. The shield stays.

Output: ONE image, 1254 x 209 pixels, 6 columns x 1 row, each cell exactly 209 x 209.

The six columns, in this order:
1. idle
2. move contact
3. move passing
4. attack windup — shield raised, red wedge telegraph forming at its feet
5. attack active — slam impact
6. death — collapsing, gold plating cracking, cores going dark

Also required:
- Flat #00ff00 background, edge to edge
- In every cell the creature's lowest point sits on pixel row 208, counting from the top
- Same subject scale in all six cells
- No text, no labels, no borders, no grid lines
- Same bold 16-bit anime pixel art style as the reference: thick near-black outlines,
  flat colour blocks, hard cel shadows, no gradients, no bloom
````

---

## 4. Sheet 8 — enemy hit reactions

All six delivered frames are off-model. **Do these one creature at a time**, each with its
own reference attached — one frame per request is the most reliable thing an image model
does, and there is no reason to batch six independent frames into one grid.

Use this template. Substitute the creature block and the foot row from the table.

````
I am adding one frame to an existing sprite sheet for my own game. The attached image
shows the EXACT creature in three of its existing frames: idle, attacking, and dying.

Draw ONE MORE FRAME OF THIS SAME CREATURE: its HIT reaction, the moment it takes damage.

This is the same creature, same design, same palette, same proportions, same everything.
Only the pose changes. Do not redesign it. Do not add or remove body parts. Do not change
its colours.

<<< CREATURE >>>

The hit pose: head or front snapped back, body compressed, limbs trailing behind the
direction of impact, a brief white flash along the contour. It must read clearly as
DAMAGE BEING RECEIVED, not as an attack being wound up.

Output: ONE image, exactly 209 x 209 pixels, a single frame.

Also required:
- Flat #00ff00 background, edge to edge
- The creature's lowest point sits on pixel row <<< FOOT ROW >>>, counting from the top
- Same subject scale as the reference
- No text, no labels, no borders
- Same bold 16-bit anime pixel art style as the reference: thick near-black outlines,
  flat colour blocks, hard cel shadows, no gradients, no bloom
````

| # | Creature | `<<< CREATURE >>>` block | `<<< FOOT ROW >>>` |
|---|---|---|---|
| 1 | Rift Crawler | A low, wide chaser. A cluster of dark charcoal-black stone plates forming a rounded boulder body, several small glowing red eyes across the front, two large curved pale-tan horns sweeping up and back, and many short stubby legs underneath. Wider than it is tall. | 208 |
| 2 | Lantern Hexer | A tall, thin ranged caster. Dark tattered robes with a rust-red inner lining, an ornate horned head with a glowing red core at the chest, and it carries a tall black lamp-post staff nearly its own height topped with a glowing red lantern. | 208 |
| 3 | Bellguard | A broad tank. A large cracked round disc shield of tan bronze plates fills most of the frame with a red core at the crack; a dark gunmetal armoured body with two large curved pale-gold horns stands behind and to the right of it, with a tattered dark red cloth. | 208 |
| 4 | Nest Idol | A stationary spawner. A dark stone base on many short legs, carrying a large segmented pod of pink-red crystal plates rimmed with violet spikes and violet flame at the top. A small red eye in the base. | 192 |
| 5 | Blade Mite | A lean dasher. A dark upright insectoid biped with thin segmented limbs, a small horned head, and two long scythe blades with glowing red edges in place of forearms. Crouched, wide-legged stance. | 208 |
| 6 | Siphon Eye | A floating leech. One large glowing red eyeball under a dark bronze-charcoal shell with small horns, trailing several long thin red tentacle tethers below it. It hovers — it has no feet. | 171 |

---

## 5. Installing and checking what comes back

The split frames from a single-image response need naming before the installer sees them.
For sheet 8, save each frame directly as:

```
assets/enemies/enemy_action_frames/00_rift_crawler__06_hit.png
assets/enemies/enemy_action_frames/01_lantern_hexer__06_hit.png
...
```

Sheets 3 and 4 come back as grids, so run them back through the installer, or split them
with the same cell sizes given in the prompts.

Then look at them:

```bash
./tools/compare_frames.py --preset all
```

That writes side-by-side sheets to `build/comparisons/` — shipped frames on the top row,
new frames below, same scale. **Judge them there before wiring anything.** If the bottom
row is not obviously the same creature, it is off-model, and no amount of engine work
fixes it.

Once they pass, wire them:
- Sheet 8 → add `"hit"` to `COLUMNS` in `scripts/tools/build_enemy_spriteframes.gd`
- Sheet 4 → extend `BOSS_COLUMNS` when Phase 11 lands
- Sheet 3 → needs an on-screen size target first; guide §2 gives none for elites

Then rebuild and re-run the pivot audit:

```bash
godot --headless --path . --import
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
```

---

## 6. Why there is no automated on-model check

I tried to build one, so that this could not slip through again without someone
remembering to look. **It does not work, and the measurements are worth recording so
nobody spends another afternoon on it.**

Four signals were tested against every pair in the shipped art — silhouette overlap after
scale normalisation, saturation-weighted hue distance, content aspect ratio, and the
fraction of the cell the creature fills. Both against a single idle frame and against the
best match anywhere in the creature's own row.

The classes do not separate. Taking the best match across the whole row, which is the
strongest formulation:

| | silhouette overlap | palette intersection |
|---|---|---|
| Same creature, different pose (n=44) | 0.16 – 0.82 | 0.64 – 0.98 |
| Known redesign (n=10) | 0.26 – 0.55 | 0.47 – 0.87 |

Ranges overlap on both axes, and on their sum the ordering **inverts**: every genuine
death frame in this project scores less like its own creature than every one of the ten
known redesigns does. A dying Siphon Eye is a collapsed shape with a scrambled palette; a
competent redesign is a clean, well-drawn creature that simply happens to be the wrong
one. Cheap geometry and colour statistics cannot tell those apart, and a threshold tuned
until it looked like it worked would only be measuring the frames it was tuned on.

So the check stays human, and `tools/compare_frames.py` exists to make it take five
seconds instead of an afternoon.
