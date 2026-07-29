# Project Zero Climb

Connected-room action roguelite. Godot 4.x. The current goal is **one 8–12 minute
vertical slice** for the first playtest — not a full game.

Design source of truth: `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`.
Read it before making any gameplay, art, or architecture decision.

## Hard rules

These come from the owner's build instructions. They override any instinct to improve things.

- **Do not redesign the game.** The guide's decisions are locked. If something looks
  wrong, raise it — do not silently change it.
- **Do not replace or generate art.** The package ships transparent split frames for
  actors, enemies, boss, effects, and icons. Use them. Record every visual
  inconsistency in `ART_CLEANUP_TODO.md` instead of repainting or generating substitutes.
- **Do not expand scope.** No extra biomes, bosses, summons, or systems beyond the slice.
- **Do not start with the full level.** Work the numbered build phases in
  `docs/CLAUDE_GODOT_BUILD_BRIEF.md`, in order, and stop at the phase boundary.
- **Keep balance data-driven.** Values live in `docs/LEVEL1_BALANCE.json` and Godot
  custom Resources, never hardcoded in behavior scripts.

## Technical direction

- **UI:** Godot-native `Control` nodes. Not custom-drawn.
- **Environment:** simple 3D blockout geometry for Sunfall Ward — primitives, simple
  meshes, decals, repeated props. The environment sheet is reference, not a texture source.
- **Actors:** billboarded `AnimatedSprite3D` driven by `SpriteFrames` built from the
  split PNGs. 2D pixel actors inside a 3D world.
- **Sprite import:** filtering off, nearest-neighbor, alpha preserved, stable ground
  pivot per species. Use the manifest's exact grids. `SpriteFrames` + split PNGs is the
  safest route — do not assume a 2D atlas importer works for Sprite3D without testing.
- **Autoloads:** only `GameSettings`, `SaveService`, `SceneFlow`. Combat managers are
  not global unless they must survive a scene change.
- **Collision layers** are fixed 1–10 as listed in guide §15. Summons never physically
  collide with the player, each other, or normal enemy bodies.

## Non-negotiable feel constraints

- **No-aim promise.** If the player never touches the right stick or mouse, the Focus
  Weapon and all summons still fight effectively. Aiming adjusts priority, never unlocks
  basic function.
- **Color ownership.** Violet/indigo/blue-white = friendly. Red/orange/warm-white =
  hostile. Gold/teal/soft-green = rewards. Never a large violet hostile circle.
- **Red telegraphs stay visible under everything**, including Convergence effects.
- **Hero reads at 88 px tall at 1920x1080.** Coat, scarf, gauntlet, boots, and the white
  hair streak must survive at that size.
- Camera never rotates during gameplay. No sudden zoom steps — interpolate 0.35–0.6s.

## Audio

No audio ships with the package. Use clearly-named silent or synthesized placeholders
behind the documented bus/slot names. Never download unverified audio, and never block
gameplay work waiting on sound.

## Repo conventions

- Art, audio, models, and fonts go through **Git LFS** (see `.gitattributes`). Run
  `git lfs install` before committing assets. This repo previously hit 556MB of history
  by committing binaries directly — don't repeat it.
- Never commit exports, build output, or `export_presets.cfg`.
- Godot rewrites `project.godot` and regenerates resource UIDs on first open; that diff
  is expected.

## Original work

All creatures, names, designs, and systems are original to this project. Creature-collection
and summoning influences stay structural — never reproduce protected characters, names,
interfaces, or assets from other games.
