# Art and Animation Requirements

What the first-playtest package ships, what is defective in it, and what still has to
be produced to finish the vertical slice.

Compiled from `docs/ASSET_MANIFEST.json`, `docs/IMAGE_GENERATION_PROMPTS.md`, the master
guide, and defects measured during Phases 0–6. Frame counts are exact, not estimates — they come from the
generated audits in `docs/generated/`.

Status as of Phase 6 complete. Nothing here is speculative scope: every item is
required by a phase in `docs/CLAUDE_GODOT_BUILD_BRIEF.md` or by a locked rule in the
master guide.

---

## 0. Delivered by the eleven-sheet package

`Project_Zero_Climb_All_11_Sheets_v1.0` answers most of §3 below. Installed with
`tools/install_sheet_package.py`; 142/142 files matched the package checksums.
Sections 2 and 3 are kept as written so the original gaps stay legible — this table
is what actually changed.

| Sheet | Delivers | Frames | State |
|---|---|---|---|
| 1 | Awakened summons — Volt Hound, Twin Oath Blades, Burst Golem | 21 | **wired** — `data/spirits/*_frames.tres` |
| 2 | Ascendant summons — Tempest Fenrir, Halo Blade Seraph, Arsenal Titan | 21 | **wired** |
| 3 | Gilded Bellguard elite | 6 | installed, not wired — off silhouette family |
| 4 | Boss chain sweep / hit / phase two / enrage | 4 | installed, not wired — **off-model redesign** |
| 5 | Convergence signatures ×3 | 24 | **wired** — `data/vfx/convergence_frames.tres` |
| 6 | Rally target marker loop | 6 | **wired** — `data/vfx/rally_marker_frames.tres` |
| 7 | Spirit Core intact/damaged/destroyed | 3 | **wired** — `data/environment/spirit_core_frames.tres` |
| 8 | Enemy hit reactions ×6 | 6 | installed, not wired — **all six off-model** |
| 9 | UI components | 23 | installed — consumed by Phase 13 |
| 10 | Tiling textures | 8 | installed — verified seamless, consumed by Phase 8 |
| 11 | Floor decals | 4 | installed — consumed by Phase 8 |

**Phase 7 is unblocked.** Its one art-dependent criterion — evolution visibly changes
the summon — is met by sheets 1 and 2, and all nine species now build with a 0–1 px
contact baseline.

Sheets 3, 4 and 8 are logged in `ART_CLEANUP_TODO.md`. All three failed the same way:
generated from text alone, with no reference image of the creature they were meant to
extend, so they re-invented actors that already exist. **Any regeneration of those three
must supply the existing frame as a reference image.**

`docs/ART_REGENERATION_SHEETS_3_4_8.md` has the finished prompts for all three, built
around that reference. It also records why an automated on-model check is not possible
here — the measurements are in §6 of that document.

### Open question — on-screen size for evolved forms

Guide §2 gives pixel targets for the three starters only (Rune Hound 52 px, Sword Wisp
58 px, Gun Construct 46 px) and says evolution "changes the visible body and one
behavior" without mentioning size. `build_summon_spriteframes.gd` therefore gives every
tier of a line its starter's target rather than inventing a number, so an Ascendant
currently reads at the same height as its Bound form. If evolved forms are meant to read
larger, that is a design value the guide needs to state.

---

## 1. What ships and is already wired

185 split frames across seven `prototype_ready` atlases. 129 are consumed by the build
today; 56 ship but are not yet used because their phase has not landed.

| Atlas | Grid | Frames | Consumed by |
|---|---|---|---|
| Tower Exile locomotion | 5×8 @ 162×242 | 40 | **Phase 1** — 8-direction idle + run |
| Starter summons action | 7×3 @ 220×342 | 21 | **Phase 3/4** — all three species |
| Level 1 enemy action | 6×6 @ 209×209 | 36 | **Phase 5** — all six roles |
| Combat VFX | 8×4 @ 222×222 | 32 | **Phase 4** — friendly/hostile/pickup rows |
| Tower Exile action | 8×2 @ 222×444 | 16 | *not yet* — Phase 12 |
| The First Bell action | 8×1 @ 272×724 | 8 | *not yet* — Phase 11 |
| Pickup / relic icons | 8×4 @ 222×222 | 32 | *not yet* — Phase 7 |

Reference-only sheets (**not game-ready**, cannot be used as frames): summon evolution
paths, enemy lineup, boss production sheet, boss gameplay keyframe, Sunfall Ward modular
kit, three UI triptychs, route map.

---

## 2. Defects in shipped art — fix before production

All are corrected at runtime today so the slice is playable, and the shipped art is
untouched. Each correction is a workaround, not a fix. Detail per frame is in
`ART_CLEANUP_TODO.md`.

### 2.1 Ground-pivot drift — every actor row

| Row | Worst drift | Frames needing correction |
|---|---|---|
| Rift Crawler | **28 px** | worst in the package, on the most-used Level 1 enemy |
| Sword Wisp | 17 px | reform frame sits 17 px low |
| Siphon Eye | 17 px | |
| Tower Exile | 17 px | southeast column floats 10–17 px |
| Rune Hound | 16 px | swings 26 px between windup and recovery *inside one attack* |
| Nest Idol | 16 px | |
| Gun Construct | 13 px | |
| Bellguard | 6 px | |
| Blade Mite | 0 px | the only clean row |

**49 of 97 actor frames carry a runtime vertical offset.** Every actor row shipped so
far has needed correction. Treat baselining as a required step for new actor art, not an
exception.

**Ask:** re-baseline each row so all states in a row share one contact-foot row. Then the
offset tables can be deleted.

### 2.2 Enemy atlas has no hit / flinch frame

The enemy atlas ships six columns (idle, move_contact, move_passing, attack_windup,
attack_active, death). The summon atlas ships seven, including a hit frame. Enemies
therefore have **no distinct reaction to being struck**.

Current workaround maps `hit` onto the `attack_windup` cell, so a struck enemy briefly
shows its windup pose — readable, but wrong, and easily misread as an incoming attack.

**Ask:** a seventh column per enemy row (**6 frames**), or an explicit decision to use a
shader flash instead.

### 2.3 Gilded Bellguard has no art

Guide §10 specifies a **gold silhouette with twin red cores**. The elite currently reuses
the standard Bellguard frames at 420 HP, so the player cannot tell an elite from a normal
tank — which directly undermines the elite's role as a route landmark.

**Ask:** a gold-palette Bellguard row (**6 frames**, or 7 with the hit column above).

### 2.4 Scale and silhouette inconsistencies

- The Gun Construct's contact row sits **93 px above** the other two summons in the same
  220×342 grid. Defensible for a hovering wisp, unexplained for the construct.
- Hero opaque content height varies **192–242 px** in a fixed 162×242 cell, so silhouette
  mass differs between directions. Invisible now, but it will affect any outline shader
  or auto-crop.

---

## 3. Missing art by phase

### Phase 7 — Rewards, inventory, evolution *(next phase, currently blocked)*

**Summon evolution forms are the single biggest gap in the package.**

Guide §5 defines three tiers per species — Bound → Awakened → Ascendant — and the brief
requires that "evolution visibly changes the summon and one behavior". Only the **Bound**
tier ships as usable frames. `PZC_Starter_Summon_Evolution_Paths_v1.png` is a
`production_reference` sheet, not game-ready cells.

| Species | Awakened | Ascendant |
|---|---|---|
| Rune Hound | **Volt Hound** — crescent slash every fourth strike | **Tempest Fenrir** — chains through two targets |
| Sword Wisp | **Twin Oath Blades** — delayed second slash | **Halo Blade Seraph** — three blades, intercepts projectiles |
| Gun Construct | **Burst Golem** — every sixth shot pierces | **Arsenal Titan** — three-missile volley |

All six names come from the package's own generation record in
`docs/IMAGE_GENERATION_PROMPTS.md`, so they are canon rather than invented. That record
also fixes the constraint that final forms stay **below roughly 1.5× hero height** and
remain animation-friendly silhouettes.

**Ask: 3 species × 2 tiers × 7 states = 42 frames**, on the same 220×342 grid and
matching row/column order as the Bound atlas.

Also needed:
- **Reward card rarity borders** — common / uncommon / rare (3 frames or 9-slice sets).
- **Summon portraits** for the three Bond slots. The HUD mockup shows them; no portrait
  assets ship. **3 portraits minimum, 9 if each evolution tier gets its own.**
- Confirm the 32 pickup/relic icons cover the six reward categories in guide §6. They
  ship but are unmapped.

### Phase 8 — Sunfall Ward blockout

Geometry is 3D primitives built in-engine, per the brief. What art is needed is
**surfacing**, since the modular kit is a 2D reference sheet:

- **Materials/textures:** sandstone, terracotta roof, wood, plaster, cobblestone
  (3 floor variants per guide §8), green plant.
- **Decals:** Rift corruption (violet crystal, blackened stone), boss floor emblem,
  arena emblem, sealed-gate marking.
- **Props** as simple meshes: crate, barrel, bench, planter, lantern, signpost, fountain,
  broken cart, market stalls (red/cream and blue/cream), house facade, roof, balcony.

Guide §8 lists ~20 modules. For the slice these are primitives, so the real ask is a
**small tiling material set (6–8 materials) plus 4 decals**.

### Phase 9 — Spirit Well and merchant

The triptych is a flattened mockup and cannot be used as an interactive UI. Needs, as
Godot `Control` assets:
- Panel frames, slot frames, Bond-slot pips (Bound/Awakened/Ascendant states).
- Currency icon, reroll icon, lock icon, disabled state.
- **Spirit Well prop** — a 3D interactable, not in the package.
- **Merchant kiosk prop** — not in the package.

### Phase 10 — Optional Rift

- **Spirit Core** — the fragile protect-the-core object. Not in the package at all.
  Needs an idle, a damaged state, and a destroyed state (**3 frames or a simple mesh**).
- Rift entry portal / gate visual.
- Reward-category preview icon shown before entry.

### Phase 11 — The First Bell

Eight frames ship: idle, move, slam_windup, slam_impact, chain_sweep_windup, bell_toll,
stagger_core_open, defeat. Comparing against guide §11, these are missing:

- **chain_sweep_active** — only the windup ships, so the sweep has no impact frame.
- **hit / flinch** — same gap as the regular enemies.
- **Phase 2 variant** — guide §11 requires a visibly brighter core at 50% HP.
- **Enrage state** at 180 s — cadence increases; no visual is specified or shipped.

**Ask: 3–4 additional boss frames**, on the same 272×724 grid.

### Phase 12 — Rally, Stability, Convergence

- **Convergence signature attacks — one per summon**, described in guide §5 and shipped
  nowhere: lightning-wolf streak (hound), large circular cut around the Rally target
  (wisp), multi-cannon barrage (construct). **3 effect sequences, ~6–8 frames each.**
- **Rally mark** — guide §4 specifies a red diamond with a violet friendly outline. Not
  in the VFX atlas. **1 looping marker.**
- **Convergence hero state** — intensified violet aura, brighter gauntlet core, longer
  scarf trail. The hero action atlas has convergence-labelled cells but see the note
  below.
- Stability meter art (see Phase 13).

**Hero action atlas — mapping resolved.** The dual cell labels (`idle_or_rally`,
`dash_or_focus`, …) are not ambiguous: **the top row is the first label of each pair and
the bottom row is the second.** Verified by inspecting frames — `00_top__00` is a neutral
idle, `01_bottom__00` is a rally cast standing in a violet summoning circle, and
`01_bottom__07` is the hero face-down with the staff dropped. The sheet therefore carries
16 distinct states, and no new art is required for it:

| Column | Top row | Bottom row |
|---|---|---|
| 00 | idle | rally |
| 01 | dash | focus |
| 02 | dash streak | convergence start |
| 03 | dash recover | convergence |
| 04 | hurt | victory |
| 05 | knockback | interact |
| 06 | summon start | revive |
| 07 | summon release | defeat |

**One open question remains:** these poses are front-facing three-quarter and
**non-directional**, while locomotion is fully 8-directional. A dash to the northeast has
no matching pose.

*Recommendation: accept non-directional actions for the slice.* Producing 8-direction
coverage for the ~6 core actions is 48+ frames, and the actor billboards toward the
camera anyway, so the mismatch is least visible exactly where it would cost most. Revisit
after the first playtest if dash facing reads badly.

### Phase 13 — HUD and menus

All three UI sheets are flattened mockups. The brief is explicit that they must be
rebuilt with native `Control` nodes, so what is needed is **component art**, not screens:

- Health bar, Stability bar, Convergence meter (fill + frame each).
- Summon cooldown ring, bond pips, three summon portraits (also listed in Phase 7).
- Focus Weapon icon, dash icon, Rally icon, team-command icon, Convergence icon.
- Controller and keyboard/mouse button prompt glyphs (guide §17 requires input parity).
- Reward card frame, rarity borders (also Phase 7).
- Title screen background, pause panel, accessibility panel, results panel.

### Phase 14 — Save and results

- Victory and defeat panel art, best-time and discovery iconography. Largely covered by
  the Phase 13 component set.

### Phase 15 — Performance and QA

No new art.

---

## 4. Audio — nothing ships

Guide §14 is explicit that the package intentionally contains no licensed music, voice,
or third-party SFX, and that placeholders must not block gameplay work.

**Music — 3 tracks:** `music_sunfall_explore`, `music_sunfall_combat`, `music_first_bell`.

**SFX families:**
- Hero: steps, dash, hurt, staff shot, staff impact, Rally mark, Convergence start/end.
- Rune Hound: growl, lunge, bite, crescent.
- Sword Wisp: hover, lunge, slash, return.
- Gun Construct: servo, aim, shot, burst.
- Six enemies × windup, attack, hit, death.
- Boss: slam, chain sweep, toll, stagger, core break, defeat.
- Interface: pickup, reward card, purchase, reroll, evolve, gate, Rift entry.

Roughly **60 distinct cues.** Mix priority is fixed in guide §14: player damage warning
first, then boss/elite telegraph, then Rally/Convergence, then summon signatures, then
normal attacks, then environment.

---

## 5. Priority order

Ordered by what blocks the next phase, not by size.

1. **Summon evolution frames (42)** — blocks Phase 7, the next phase. Nothing else in the
   package gates work as directly.
2. ~~Hero action atlas mapping~~ — **resolved, no art needed.** Only the
   directional-coverage question remains, and the recommendation is to accept
   non-directional poses for the slice.
3. **Enemy hit column (6) + Gilded Bellguard row (6–7)** — small, and the elite is
   currently indistinguishable from a normal tank.
4. **Boss gap frames (3–4)** — blocks Phase 11's readability criteria.
5. **Convergence signatures (3 sequences) + Rally mark** — blocks Phase 12.
6. **UI component set** — blocks Phases 9 and 13; the largest single body of work.
7. **Environment materials and decals** — blocks Phase 8 surfacing, though blockout
   geometry can proceed without it.
8. **Pivot re-baselining (49 frames)** — no phase is blocked, since the runtime
   correction works. Do it before commercial production.
9. **Spirit Core, Spirit Well, merchant kiosk props** — three small 3D objects.
10. **Audio (~60 cues + 3 tracks)** — placeholders keep every phase unblocked.

---

## 5a. See also

- `docs/ANIMATION_GUIDE.md` — frame budgets, timing technique, and why generated cycles
  drift.
- `docs/ART_GENERATION_PROMPTS.md` — copy-paste prompts for everything listed here.

## 6. Totals

Updated after the eleven-sheet package landed. "Delivered" means installed and wired;
"delivered, unusable" means the frames exist but are off-model (see §0).

| Category | Frames / assets | State |
|---|---|---|
| Summon evolution forms | 42 frames | **delivered** |
| Convergence signatures | 24 frames | **delivered** |
| Rally mark | 6-frame loop | **delivered** |
| Spirit Core states | 3 frames | **delivered** |
| UI components | 23 elements | **delivered** |
| Environment materials/decals | 12 | **delivered** |
| Enemy hit column | 6 frames | delivered, unusable — regenerate with references |
| Gilded Bellguard row | 6 frames | delivered, unusable — regenerate with references |
| Boss gap frames | 4 frames | delivered, unusable — regenerate with references |
| Pivot re-baselining | 49 existing frames | still open |
| Props (3D) | 3 | still open |
| Audio | 3 tracks + ~60 cues | still open |

**Remaining actor/effect frames to produce: 16** — the three off-model sheets, redone
with reference images. That is down from roughly 80–85.

Everything else outstanding is the pivot re-baselining of the original package art, three
3D props, and the audio pass.

Every one of these is required by an existing phase or a locked rule in the master guide.
None of it is scope beyond the vertical slice.
