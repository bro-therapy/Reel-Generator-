# Project Zero Climb

Connected-room action roguelite. Godot 4.3. Building one **8–12 minute vertical
slice** for the first playtest.

Design source of truth: `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`
Build plan: `docs/CLAUDE_GODOT_BUILD_BRIEF.md` (16 numbered phases)

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Project foundation | **complete** — 19/19 acceptance checks |
| 1 | Hero sandbox | **complete** — 13/13 acceptance checks |
| 2 | Conjurer Staff and targeting | **complete** — 20/20 acceptance checks |
| 3 | Shared summon architecture | **complete** — 26/26 acceptance checks |
| 4 | Starter species | next |
| 5–15 | see the build brief | not started |

## Running it

```bash
godot --path .                      # boot scene
godot --path . scenes/tests/hero_sandbox.tscn   # Phase 1 hero sandbox
godot --path . scenes/tests/focus_range.tscn    # Phase 2 targeting range
godot --path . scenes/tests/summon_field.tscn   # Phase 3 summon field
```

WASD moves, Space dashes, F3 toggles the debug overlay.

## Acceptance tests

Each phase has a headless, CI-usable harness that exits non-zero on failure.

```bash
godot --headless --path . --script scripts/tests/phase0_acceptance.gd
godot --headless --path . --script scripts/tests/phase1_acceptance.gd
godot --headless --path . --script scripts/tests/phase2_acceptance.gd
godot --headless --path . --script scripts/tests/phase3_acceptance.gd
```

## Regenerating actor SpriteFrames

`data/characters/tower_exile_frames.tres` is generated from the package split
frames — do not hand-edit it. Rebuild after any actor art change:

```bash
godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
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

## Working rules

See `CLAUDE.md`. The short version: don't redesign the game, don't replace or
generate art, don't expand scope, keep balance data-driven, and log art issues in
`ART_CLEANUP_TODO.md` instead of repainting.

Art and audio go through **Git LFS** (`.gitattributes`). Run `git lfs install`
after cloning.
