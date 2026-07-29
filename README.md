# Project Zero Climb

Connected-room action roguelite. Godot 4.3. Building one **8–12 minute vertical
slice** for the first playtest.

Design source of truth: `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`
Build plan: `docs/CLAUDE_GODOT_BUILD_BRIEF.md` (16 numbered phases)

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Project foundation | **complete** — 19/19 acceptance checks |
| 1 | Hero sandbox | **complete** — 15/15 acceptance checks |
| 2 | Conjurer Staff and targeting | **complete** — 22/22 acceptance checks |
| 3 | Shared summon architecture | **complete** — 29/29 acceptance checks |
| 4 | Starter species | **complete** — 17/17 acceptance checks |
| 5 | Enemies | next |
| 6–15 | see the build brief | not started |

## Running it

```bash
godot --path .                      # boot scene
godot --path . scenes/tests/hero_sandbox.tscn   # Phase 1 hero sandbox
godot --path . scenes/tests/focus_range.tscn    # Phase 2 targeting range
godot --path . scenes/tests/summon_field.tscn   # Phase 3 summon field
godot --path . scenes/tests/species_field.tscn  # Phase 4 species behaviours
```

All five phases: **102 checks, 0 failures.**

WASD moves, Space dashes, F3 toggles the debug overlay.

## Acceptance tests

Each phase has a headless, CI-usable harness that exits non-zero on failure.

```bash
godot --headless --path . --script scripts/tests/phase0_acceptance.gd
godot --headless --path . --script scripts/tests/phase1_acceptance.gd
godot --headless --path . --script scripts/tests/phase2_acceptance.gd
godot --headless --path . --script scripts/tests/phase3_acceptance.gd
godot --headless --path . --script scripts/tests/phase4_acceptance.gd
```

## Regenerating actor SpriteFrames

`data/characters/tower_exile_frames.tres` is generated from the package split
frames — do not hand-edit it. Rebuild after any actor art change:

```bash
godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
godot --headless --path . --script scripts/tools/build_vfx_spriteframes.gd
```

These also refresh the ground-pivot audits in `docs/generated/` and the runtime
pivot correction tables. Every actor row shipped so far has needed correction —
treat baselining as required for any new actor art.

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
passes, the check is weak and gets rewritten. Twelve mutants across the five
phases are currently all killed.

Two rules came out of that and apply to every new check:

1. **Assert against the specification, never the implementation.** Expected values
   come from `docs/LEVEL1_BALANCE.json`, not from the resource under test —
   otherwise a wrong value is compared against itself and passes.
2. **Isolate the property under test.** A check that runs during unrelated
   combat measures combat noise. Both flaky checks found so far were caused by
   this.

## Working rules

See `CLAUDE.md`. The short version: don't redesign the game, don't replace or
generate art, don't expand scope, keep balance data-driven, and log art issues in
`ART_CLEANUP_TODO.md` instead of repainting.

Art and audio go through **Git LFS** (`.gitattributes`). Run `git lfs install`
after cloning.
