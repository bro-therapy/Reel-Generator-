# Art Cleanup TODO

The included images are approved first-playtest assets and references. Issues found
during implementation are logged here rather than silently generating or painting
replacements.

Measurements come from `docs/generated/hero_pivot_audit.json` and
`docs/generated/summon_metrics.json`, produced by `scripts/tools/build_hero_spriteframes.gd`
and `scripts/tools/build_summon_spriteframes.gd`. Regenerate whenever actor art is replaced.

| Priority | Asset | Frame/state | Problem | Temporary handling | Final cleanup |
|---|---|---|---|---|---|
| High | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `07_southeast__03_run_extension`, `07_southeast__04_run_recovery` | Ground pivot floats 15–17 px above the cell baseline. Feet sit at rows 226 and 224 where every other direction lands on row 241. Uncorrected this is ~6 px of vertical bob at the 88 px gameplay size. | Per-frame vertical offset generated into `data/characters/tower_exile_pivot_offsets.json` and applied at runtime by `scripts/actors/player.gd`. Art untouched. | Redraw the southeast run frames so the contact foot rests on the cell baseline, then delete the corresponding offsets. |
| High | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `07_southeast__00_idle`, `01_walk_contact`, `02_walk_passing` | Whole southeast column sits 10 px high (foot row 231 vs 241). The direction reads as hovering relative to its seven neighbours. | Same runtime offset table. | Re-baseline the entire southeast row against the south row. |
| Medium | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `00_south__03_run_extension`, `00_south__04_run_recovery` | 5–7 px pivot drift within the south run cycle (rows 236 and 234 vs idle at 240), so the south run bobs against its own idle. | Same runtime offset table. | Align the south run extension/recovery contact foot to the idle baseline. |
| **High** | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | all eight idle cells | **The hero changes size when he turns, and no single scale can fix it.** Rendered and measured on screen for the first time: facing south he reads **80 px** against the guide's locked 88 px target. The drawn content per idle cell is south 213 px, southwest 203, southeast 232, and 242 for west/northwest/north/northeast/east — a 19% spread inside a fixed 242 px cell. `pixel_size` maps the *cell* to 1.8 units, so the character's on-screen height tracks that spread: scaling south up to 88 px would push the north-facing frames past 100. The `west` cell also carries a detached 8-row fragment clipped against the top edge. Supersedes the earlier "Low / not currently visible" reading of this row — it is visible, as a size pop on turning. | **None. Deliberately not rescaled** — every available correction trades one direction's error for another's, and CLAUDE.md says raise it rather than silently change it. The pivot table already handles the vertical bob; size is untouched. | Redraw the eight idle frames to one consistent character height, then set `world_height_units` from the measured content rather than the cell. Guide §2 line 79 is the target: 88 px at 1920x1080. |
| Medium | — (test, not art) | `scripts/tests/phase1_acceptance.gd` | The Phase 1 "hero reads near 88 px" check projects `world_height()`, which is the whole 1.8-unit *cell*, so it passes at 88 px while the drawn character measures 80 px. Phase 3's equivalent summon check projects `content × pixel_size()` and is the correct pattern. This is README testing-discipline rule 1 — the check asserts the implementation's notion of height rather than the specification's. | Left as-is: tightening it now would turn the art defect above into a red suite without changing any pixels. | Switch the projection to drawn content once the idle frames are re-baselined, so the check measures what the player sees. |
| Low | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | all cells | Opaque content height varies 192–242 px within a fixed 162×242 grid, so silhouette mass is inconsistent between directions. Also affects any future auto-cropping or outline shader. | None needed yet. | Normalise character mass across the eight directions during animation cleanup. |
| High | `PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png` | `rune_hound` — `aim_or_windup` (+16 px), `attack_recover` (−10 px) | Ground pivot swings 26 px between the windup and the recovery frame inside a single attack. Uncorrected the hound visibly hops each time it bites. | Per-frame offsets in `docs/generated/summon_metrics.json`, applied at runtime by `scripts/actors/summon_base.gd`. Art untouched. | Re-baseline the Rune Hound row so all seven states share one contact-foot row. |
| High | `PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png` | `sword_wisp` — `reform` (+17 px) | The reform frame sits 17 px below the rest of the row, so the wisp drops as it re-materialises. Worst single-frame deviation of any summon. | Same runtime offset table. | Align the reform frame to the wisp's hover baseline (row 297). |
| Medium | `PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png` | `gun_construct` — `move` (+13 px), `reform` (−11 px) | 24 px of pivot travel between moving and reforming; the construct sinks while walking and floats while reforming. | Same runtime offset table. | Re-baseline the Gun Construct row to row 205. |
| High | `PZC_Level1_Enemy_Action_Atlas_ALPHA_v1.png` | `rift_crawler` — `attack_windup` / `death` vs the rest | 28 px of ground-pivot drift, the largest of any actor row in the package. On the most-used enemy in Level 1, uncorrected this is a visible hop every time a crawler winds up. | Per-frame offsets in `docs/generated/enemy_metrics.json`, applied by `scripts/actors/enemies/enemy_base.gd`. Art untouched. | Re-baseline the Rift Crawler row to a single contact row. |
| Medium | `PZC_Level1_Enemy_Action_Atlas_ALPHA_v1.png` | `siphon_eye`, `nest_idol` | 17 px and 16 px of pivot drift respectively. Less visible than the crawler because both are largely stationary, but the nest idol's pulse frame visibly sinks. | Same runtime offset table. | Re-baseline both rows. |
| Medium | `PZC_Level1_Enemy_Action_Atlas_ALPHA_v1.png` | all six rows — missing `hit` cell | The enemy atlas ships six columns (idle, move_contact, move_passing, attack_windup, attack_active, death) with no dedicated hit/flinch frame, unlike the summon atlas which has one. Enemies therefore have no distinct reaction to being struck. | `build_enemy_spriteframes.gd` maps the `hit` animation onto the `attack_windup` cell, so a struck enemy briefly shows its windup pose — readable but wrong, and it can be mistaken for an incoming attack. | Sheet 8 of the eleven-sheet package was meant to close this and does not — see the off-model row below. Still open. |
| Medium | `PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png` | row baselines | The three species use three different contact rows inside the same 220×342 grid — hound 298, wisp 297, construct 205. That is defensible for a hovering wisp but the construct sitting 93 px higher than the hound reads as scale drift, not design. | None; each species is baselined independently, so it is not visible in-game. | Confirm with the artist whether the construct's row is intentional. If not, re-baseline to ~298. |

## Eleven-sheet package (`Project_Zero_Climb_All_11_Sheets_v1.0`)

Installed by `tools/install_sheet_package.py`. Every file matched the package
`SHA256SUMS` (142/142). Sheets 1, 2, 5, 6, 7, 9, 10 and 11 are clean and wired up.
Three sheets are **installed but deliberately not wired**, because merging them would
make the game look worse than it does now. All three share one root cause: the sheets
were generated from text descriptions with no reference image of the existing art, so
the generator re-invented creatures that already exist.

**Ready-to-run fixes for all three are in `docs/ART_REGENERATION_SHEETS_3_4_8.md`** —
prompts with the reference images attached, plus `tools/make_reference_sheets.py` to
build those references and `tools/compare_frames.py` to check what comes back.

| Priority | Asset | Frame/state | Problem | Temporary handling | Final cleanup |
|---|---|---|---|---|---|
| High | Sheet 4 — `boss_action_frames/00_the_first_bell__08..11` | `chain_sweep_active`, `hit`, `phase_two`, `enrage` | **Off-model redesign, not extra frames.** The shipped First Bell is a squat warm-bronze bell body with a small cross-topped cap, red core mid-bell and stubby legs, drawn ~300 px tall in the 724 px cell. These four are a slender *blue-grey* tower with a large ornate belfry, the core low on the bell and long segmented gold legs, drawn 520 px tall. Different palette, silhouette and proportion — not a uniform scale, so no import-time transform can reconcile them. Merged into one animation set the boss would change species mid-fight. | Files installed; **excluded from the boss SpriteFrames.** `build_enemy_spriteframes.gd` is untouched, so the boss still uses only its original eight frames. | Regenerate sheet 4 with the existing boss atlas supplied as a reference image, or repaint the original eight to match the new design. Either direction works; mixing does not. |
| High | Sheet 8 — `enemy_action_frames/*__06_hit` | all six rows | **All six hit frames are off-model.** Verified frame by frame against each creature's idle: the Rift Crawler becomes a violet plated armadillo with one large eye instead of a dark horned boulder; the Lantern Hexer becomes a masked caped figure with a small hand lantern instead of a robed lamp-post caster; the Bellguard becomes a brass diving-suit figure beside a free-standing bell instead of a horned tank behind a cracked round disc shield; the Nest Idol grows legs and a face; the Siphon Eye gains a segmented bronze dome. Blade Mite is closest but changes from an upright biped to a low wide beetle. | Files installed; **excluded from the enemy SpriteFrames.** `build_enemy_spriteframes.gd` still has six columns and its metrics are byte-identical to before the package landed. The `hit` animation continues to map onto `attack_windup`. | Regenerate sheet 8 with each creature's own idle frame supplied as a reference. Until then the row above stays open — a shader flash is the better interim answer. |
| Medium | Sheet 3 — `elite_action_frames/00_gilded_bellguard__*` | all six | Silhouette-family mismatch. The brief asked for an elite that keeps the base Bellguard's silhouette; the base reads as a large cracked round disc shield filling most of the cell, while the elite reads as a gold humanoid knight standing beside a bell-shaped object. The two specified red cores and the gold plating are correct, and the row is internally consistent (1 px baseline spread) — it simply does not read as the same species. | Installed, not wired. It is a distinct actor rather than frames merged into an existing set, so nothing is broken by leaving it in place. Elites are also beyond the vertical slice. | Decide whether this becomes its own enemy or gets regenerated from the Bellguard reference. Needs an on-screen size target either way — guide §2 gives none for elites. |
| Low | Sheets 1–2 vs `PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png` | row baselines | The new tiers hold a **0–1 px** contact baseline across all seven states; the shipped Bound tier drifts **13–17 px**. The old art is now the outlier, which makes the existing re-baseline items above more worth doing rather than less. | None — each tier is its own SpriteFrames with its own baseline, so the drift stays contained. | Re-baseline the three Bound rows to match the standard the new sheets already hit. |

## Corrections currently applied in engine

**Hero:** 10 of 40 locomotion frames carry a runtime vertical offset. Residual pivot
deviation after correction is **0 px** (verified by `scripts/tests/phase1_acceptance.gd`).

**Enemies:** 22 of 36 frames carry an offset, generated into
`docs/generated/enemy_metrics.json` by `scripts/tools/build_enemy_spriteframes.gd`.
The Rift Crawler's 28 px spread is the worst in the package.

**Summons:** 17 of 21 Bound-tier frames carry an offset — 6 on the Rune Hound, 5 on the
Sword Wisp, 6 on the Gun Construct. Offsets are generated into
`docs/generated/summon_metrics.json` by `scripts/tools/build_summon_spriteframes.gd` and
applied by `scripts/actors/summon_base.gd`.

**Awakened and Ascendant summons:** 3 of 42 frames carry an offset. The six new rows hold
a 0–1 px baseline unaided, so correction is almost entirely unnecessary — the first art in
this project that did not need the workaround.

Every actor row in the *first-playtest* package needed pivot correction. The eleven-sheet
package shows that is a property of that art, not of the pipeline: baselining is still a
required check for new actor art, but it is now a check that can pass.

`docs/ASSET_MANIFEST.json` explicitly sanctions this approach for the hero action
atlas — *"Normalize the south-facing pivot in Godot before chaining animations"* — so
the offsets are engine-side configuration, not a modification of the shipped art.
Deleting an entry from the offsets JSON reverts that frame to raw art.

## Known first-pass risks

Carried over from the package template; these remain unverified until their phases land.

- ~~Normalize foot/ground pivots before chaining hero locomotion frames.~~ **Done for hero
  locomotion (Phase 1) and all three summon rows (Phase 3).** The hero *action* atlas is
  still not imported — re-check when dash/cast poses are chained.
- Verify chain and bell weights stay inside each First Bell cell. *(Phase 11)*
- Confirm transparent mattes do not show green fringe under bloom. *(needs a lit
  scene; the Phase 1 sandbox is unshaded)* — **partly answered.** The eleven-sheet
  package ships its cells with the `#00ff00` chroma still baked in, so
  `tools/install_sheet_package.py` keys them on import. It clears exact chroma, then
  clears green-dominant pixels that touch the cleared region — 49,750 halo pixels
  across 118 frames, about 1 px of outline each. Residual green in the installed
  frames is zero by construction. The first-playtest package shipped pre-keyed and has
  not been re-measured.
- Keep friendly violet effects below hostile red telegraphs in draw priority. *(Phase 4/12)*
- Summon silhouettes must stay distinguishable in heavy combat (guide §18). Enemies now
  exist, but this needs a human eye on real hardware — headless Godot cannot render.
- ~~Keep friendly violet effects below hostile red telegraphs in draw priority.~~
  **Enforced in code (Phase 4/5).** `RenderPriority` pins friendly effects to -20 and
  hostile telegraphs to +40, and both suites assert it. Still worth one visual
  confirmation under bloom, which headless cannot provide.
- Use environment art as a visual reference; build navigable geometry in 3D. *(Phase 8)*
- Rebuild generated UI screens with native Godot Controls rather than using flattened
  mockups as interactive menus. *(Phase 13)*
