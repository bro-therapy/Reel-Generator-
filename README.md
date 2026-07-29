# Project Zero Climb

Connected-room action roguelite. Godot 4.3. Building one **8–12 minute vertical
slice** for the first playtest.

Design source of truth: `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`
Build plan: `docs/CLAUDE_GODOT_BUILD_BRIEF.md` (16 numbered phases)
Art still to produce: `docs/ART_REQUIREMENTS.md`
Regenerating the three off-model sheets: `docs/ART_REGENERATION_SHEETS_3_4_8.md`
Animation recommendations: `docs/ANIMATION_GUIDE.md`
Generation prompts: `docs/ART_GENERATION_PROMPTS.md` (per sheet) and
`docs/ART_GENERATION_MASTER_PROMPT.md` (one paste, all eleven sheets)
Defects in shipped art: `ART_CLEANUP_TODO.md`

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Project foundation | **complete** — 19/19 acceptance checks |
| 1 | Hero sandbox | **complete** — 15/15 acceptance checks |
| 2 | Conjurer Staff and targeting | **complete** — 22/22 acceptance checks |
| 3 | Shared summon architecture | **complete** — 29/29 acceptance checks |
| 4 | Starter species | **complete** — 17/17 acceptance checks |
| 5 | Enemies | **complete** — 27/27 acceptance checks |
| 6 | Combat room framework | **complete** — 23/23 acceptance checks |
| 7 | Rewards, inventory, evolution | next — **art unblocked** |
| 8–15 | see the build brief | not started |

The eleven-sheet art package is installed (`tools/install_sheet_package.py`).
Sheets 1–2 give all six evolved summon forms, which was Phase 7's only art
blocker. Sheets 3, 4 and 8 are installed but deliberately not wired — they were
generated without reference images and re-invented creatures that already exist.
Finished regeneration prompts for all three are in
`docs/ART_REGENERATION_SHEETS_3_4_8.md`; the defects are logged in
`ART_CLEANUP_TODO.md`.

```bash
./tools/make_reference_sheets.py    # reference images to attach to the prompts
./tools/compare_frames.py           # side-by-side check on whatever comes back
```

## Running it

```bash
godot --path .                      # boot scene
godot --path . scenes/tests/hero_sandbox.tscn   # Phase 1 hero sandbox
godot --path . scenes/tests/focus_range.tscn    # Phase 2 targeting range
godot --path . scenes/tests/summon_field.tscn   # Phase 3 summon field
godot --path . scenes/tests/species_field.tscn  # Phase 4 species behaviours
godot --path . scenes/tests/enemy_field.tscn    # Phase 5 enemy roles
```

All seven phases: **152 checks, 0 failures.**

WASD moves, Space dashes, F3 toggles the debug overlay.

## Acceptance tests

Each phase has a headless, CI-usable harness that exits non-zero on failure.

```bash
godot --headless --path . --script scripts/tests/phase0_acceptance.gd
godot --headless --path . --script scripts/tests/phase1_acceptance.gd
godot --headless --path . --script scripts/tests/phase2_acceptance.gd
godot --headless --path . --script scripts/tests/phase3_acceptance.gd
godot --headless --path . --script scripts/tests/phase4_acceptance.gd
godot --headless --path . --script scripts/tests/phase5_acceptance.gd
godot --headless --path . --script scripts/tests/phase6_acceptance.gd
```

## Regenerating actor SpriteFrames

`data/characters/tower_exile_frames.tres` is generated from the package split
frames — do not hand-edit it. Rebuild after any actor art change:

```bash
godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
godot --headless --path . --script scripts/tools/build_vfx_spriteframes.gd
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
godot --headless --path . --script scripts/tools/build_effect_spriteframes.gd
```

These also refresh the ground-pivot audits in `docs/generated/` and the runtime
pivot correction tables. Treat baselining as required for any new actor art:
every row in the first-playtest package needed correction (13–28 px of drift),
though the eleven-sheet package lands at 0–1 px, so it is a check that can pass.

## Layout

```
assets/       prototype art from the package (LFS)
data/         Resources and generated SpriteFrames
docs/         package documentation, balance, manifest
scenes/       actors, enemies, rooms, ui, tests
scripts/      data, actors, combat, run, ui, tools, tests
```

## Testing discipline

Acceptance checks are verified by mutation testing, not trusted on green. A
deliberate wrong value is injected into the code and the suite must fail; if it
passes, the check is weak and gets rewritten. Mutants are run against every phase and are currently all killed.

Two rules came out of that and apply to every new check:

1. **Assert against the specification, never the implementation.** Expected values
   come from `docs/LEVEL1_BALANCE.json`, not from the resource under test —
   otherwise a wrong value is compared against itself and passes.
2. **Isolate the property under test.** A check that runs during unrelated
   combat measures combat noise. Every flaky check found so far was caused by this.
3. **Never depend on `_ready()` ordering.** A value copied in `_ready` may not be
   there yet for a caller running right after `add_child`. Four separate bugs this
   project have come from that assumption — read from the data resource directly.

## Working rules

See `CLAUDE.md`. The short version: don't redesign the game, don't replace or
generate art, don't expand scope, keep balance data-driven, and log art issues in
`ART_CLEANUP_TODO.md` instead of repainting.

Art and audio go through **Git LFS** (`.gitattributes`). Run `git lfs install`
after cloning.
