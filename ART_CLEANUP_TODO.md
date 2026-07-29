# Art Cleanup TODO

The included images are approved first-playtest assets and references. Issues found
during implementation are logged here rather than silently generating or painting
replacements.

Measurements come from `docs/generated/hero_pivot_audit.json`, produced by
`scripts/tools/build_hero_spriteframes.gd`. Regenerate that audit whenever actor art
is replaced.

| Priority | Asset | Frame/state | Problem | Temporary handling | Final cleanup |
|---|---|---|---|---|---|
| High | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `07_southeast__03_run_extension`, `07_southeast__04_run_recovery` | Ground pivot floats 15–17 px above the cell baseline. Feet sit at rows 226 and 224 where every other direction lands on row 241. Uncorrected this is ~6 px of vertical bob at the 88 px gameplay size. | Per-frame vertical offset generated into `data/characters/tower_exile_pivot_offsets.json` and applied at runtime by `scripts/actors/player.gd`. Art untouched. | Redraw the southeast run frames so the contact foot rests on the cell baseline, then delete the corresponding offsets. |
| High | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `07_southeast__00_idle`, `01_walk_contact`, `02_walk_passing` | Whole southeast column sits 10 px high (foot row 231 vs 241). The direction reads as hovering relative to its seven neighbours. | Same runtime offset table. | Re-baseline the entire southeast row against the south row. |
| Medium | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | `00_south__03_run_extension`, `00_south__04_run_recovery` | 5–7 px pivot drift within the south run cycle (rows 236 and 234 vs idle at 240), so the south run bobs against its own idle. | Same runtime offset table. | Align the south run extension/recovery contact foot to the idle baseline. |
| Low | `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png` | all cells | Opaque content height varies 192–242 px within a fixed 162×242 grid, so silhouette mass is inconsistent between directions. Not currently visible in-game because the pivot is baselined, but it will affect any future auto-cropping or outline shader. | None needed yet. | Normalise character mass across the eight directions during animation cleanup. |

## Corrections currently applied in engine

10 of 40 hero locomotion frames carry a runtime vertical offset. Residual pivot
deviation after correction is **0 px** (verified by `scripts/tests/phase1_acceptance.gd`).

`docs/ASSET_MANIFEST.json` explicitly sanctions this approach for the hero action
atlas — *"Normalize the south-facing pivot in Godot before chaining animations"* — so
the offsets are engine-side configuration, not a modification of the shipped art.
Deleting an entry from the offsets JSON reverts that frame to raw art.

## Known first-pass risks

Carried over from the package template; these remain unverified until their phases land.

- ~~Normalize foot/ground pivots before chaining hero locomotion frames.~~ **Done for
  locomotion (Phase 1).** The hero *action* atlas is not yet imported — re-check when
  Phase 2 chains dash/cast poses.
- Verify chain and bell weights stay inside each First Bell cell. *(Phase 11)*
- Confirm transparent mattes do not show green fringe under bloom. *(needs a lit
  scene; the Phase 1 sandbox is unshaded)*
- Keep friendly violet effects below hostile red telegraphs in draw priority. *(Phase 4/12)*
- Use environment art as a visual reference; build navigable geometry in 3D. *(Phase 8)*
- Rebuild generated UI screens with native Godot Controls rather than using flattened
  mockups as interactive menus. *(Phase 13)*
