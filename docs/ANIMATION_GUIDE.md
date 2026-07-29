# Animation Recommendations

How to get the smoothest, best-looking result out of this project's art pipeline.

Grounded in what the build actually measured during Phases 0–6, not general advice.
Every number here comes from `docs/LEVEL1_BALANCE.json`, the generated audits in
`docs/generated/`, or the frame counts on disk.

---

## 1. The single biggest problem: one frame per state

The package ships **poses, not animations**. Counting what is actually on disk:

| Actor | Frames | States | Frames per state |
|---|---|---|---|
| Starter summons | 21 | 7 × 3 species | **1** |
| Level 1 enemies | 36 | 6 × 6 roles | **1** (move has 2) |
| The First Bell | 8 | 8 | **1** |
| Tower Exile locomotion | 40 | 2 × 8 directions | idle 1, run 4 |

So today: **every attack is a single frame. Every death is a single frame. Every idle is
frozen.** The hero's 4-frame run is the only real cycle in the package.

No amount of engine work fixes that. Smoothness is bought with frames, and everything
below is about spending them well.

---

## 2. Frame budget — what to draw

**Unique drawings, not playback frames.** Holds do the rest (see §3).

| Action | Unique frames | Notes |
|---|---|---|
| Idle | **4** | breathing loop, 6 fps → 0.67 s cycle |
| Run | **8** | currently 4; doubling this is the most visible single upgrade |
| Walk | **6** | or reuse run at 8 fps if budget is tight |
| Attack windup | **3** | held to fill the balance duration exactly (§4) |
| Attack active | **2** | contact + one smear |
| Attack recovery | **2–3** | |
| Hit / flinch | **2** | |
| Death | **6** | currently 1 — the weakest moment in the whole game |
| Reform (summons) | **4** | violet dissolve/reassemble |
| Boss slam windup | **5** | 1.25 s telegraph needs real build-up |

Priority if you can only do some: **death (6) > run (8) > attack active (2) > idle (4)**.
Death is a single frame today and it is the moment the player is most likely to be
looking at.

---

## 3. Timing technique

**Base rate: 12 fps.** Not 24. Bold 16-bit anime action reads at 10–15 fps with holds —
that is the language the guide locks in (§2: "hard cel shadows", "large color blocks").
Higher rates make pixel art look mushy, not smoother.

**Anticipation → contact → follow-through, and hold the contact.**
Impact does not read from smooth interpolation; it reads from the *pause*. Give the
contact frame 2–3 ticks while the surrounding frames get 1. A 6-frame attack with one
held contact beats a 12-frame attack spaced evenly.

**Smear frames on the three fastest moves.** The build moves these faster than the eye
can track, so a single distorted in-between sells the speed:
- Rune Hound lunge — travels at **3.4×** follow speed
- Blade Mite dash — **4.5×** its own speed
- Sword Wisp slice — **2.6×**

**Loop seams.** The first frame of a loop must not duplicate the last, or the cycle
stutters once per revolution.

**Eight-direction phase parity.** The hero has 8-direction locomotion. Frame index *n*
must be the same point in the cycle across all eight rows, or turning mid-run pops.

---

## 4. Match animation length to the balance timings

The build already drives state duration from data. Animation should land on the same
numbers, so a telegraph ends exactly when the hit lands.

Set each windup animation's fps to `frames ÷ windup_seconds`:

| Role | Windup | 3 frames at |
|---|---|---|
| Rift Crawler | 0.40 s | 7.5 fps |
| Nest Idol | 0.50 s | 6 fps |
| Siphon Eye | 0.50 s | 6 fps |
| Blade Mite | 0.70 s | 4.3 fps |
| Lantern Hexer | 0.75 s | 4 fps |
| Bellguard | 0.90 s | 3.3 fps |
| Boss slam | 1.25 s | 5 frames at 4 fps |
| Boss chain sweep | 0.95 s | 4 frames at 4.2 fps |

Summon windups are much shorter and need fewer frames:
Rune Hound 0.18 s, Sword Wisp 0.10 s, Gun Construct 0.08 s — **2 frames each is plenty**.

*This is engine work, not art work.* The builders can compute fps from the balance JSON
automatically once the frames exist.

---

## 5. Pivot discipline — non-negotiable

This is the one rule that costs nothing and is currently violated everywhere.

**49 of 97 actor frames need a runtime vertical correction.** Measured worst cases:

| Row | Drift |
|---|---|
| Rift Crawler | **28 px** |
| Sword Wisp | 17 px |
| Siphon Eye | 17 px |
| Tower Exile | 17 px |
| Rune Hound | 16 px (26 px *within one attack*) |

Every actor row in the package has needed correction. The engine compensates, so the game
looks fine — but the compensation is a workaround and it will fight any future outline
shader, auto-crop, or squash-and-stretch.

**The rule: within one row, every frame's contact foot sits on the same pixel row.**
State it explicitly in the generation prompt and verify before splitting. The audit that
measures it is already written:

```bash
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
# -> docs/generated/enemy_metrics.json, baseline_spread_px per row
```

Target: `baseline_spread_px` of **0** on every row. Blade Mite already achieves it, so it
is clearly achievable with the same pipeline.

---

## 6. Be realistic about generated animation

The package art is AI-generated, and the build measured exactly where that succeeds and
fails.

**It succeeds at single poses.** Every individual frame on disk reads well — silhouettes
are clean, the palette is consistent, the character is on-model.

**It fails at frame-to-frame consistency.** The 28 px pivot drift *is* that failure,
expressed as a number. A model drawing six frames of the same creature independently has
no memory of where it put the feet last time.

**Recommendation:** generate **key poses**, not cycles.

1. Generate the extremes — the 2–3 frames that define an action (windup, contact,
   recovery).
2. Produce in-betweens by hand, or with a tool that interpolates from real frames
   (Aseprite tweening, EbSynth, or similar).
3. Run the pivot audit and fix the baseline before splitting.

Asking a text-to-image model for "an 8-frame run cycle on one sheet" reliably produces
eight *different* characters running. That is the expensive failure mode, and this project
already has measurements proving it happens.

---

## 7. Engine-side work (already done or ready to do)

Done:
- Nearest-neighbour filtering, alpha discard, no mipmaps, lossless import.
- Per-frame pivot correction generated from the audits.
- Billboarded `AnimatedSprite3D`, on-screen sizes verified against guide §2 targets.
- Friendly effects pinned below hostile telegraphs in draw order.

Ready when the frames exist:
- Derive animation fps from the balance timings (§4).
- Hold-frame support for contact emphasis.
- Pixel-snapping the billboard position. Sprites currently move continuously in world
  space, which shimmers slightly at nearest-neighbour. Worth one look on hardware before
  deciding — it may not be visible at the 88 px hero size.
