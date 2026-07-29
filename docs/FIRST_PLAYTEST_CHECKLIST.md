# Project Zero Climb - First Playtest Checklist

Use this as the release gate for the first 8-12 minute vertical slice.

## Package intake

- [ ] README, Claude brief, master guide, manifest, and balance JSON were read.
- [ ] Included art was copied into `res://assets/` without renaming source files.
- [ ] Pixel textures use nearest-neighbor filtering and preserved alpha.
- [ ] Split frames were preferred over fragile atlas-region assumptions.
- [ ] Any visual inconsistency was written to `ART_CLEANUP_TODO.md`.

## Foundation

- [ ] Project boots with zero errors.
- [ ] 1920x1080 reference resolution and aspect-safe stretch are configured.
- [ ] Keyboard/mouse and controller actions exist in Input Map.
- [ ] Debug overlay shows FPS, enemy count, projectile count, target, and room state.
- [ ] Graphics, accessibility, and audio settings have stable defaults.

## Hero and Focus Weapon

- [ ] Hero reads near 88 px tall at 1080p in normal combat.
- [ ] Eight facings select correctly.
- [ ] Ground pivot does not bob between idle and run.
- [ ] Dash is 4.3 units over 0.18 seconds with a 1.35-second cooldown.
- [ ] Focus Weapon auto-fires effectively with no aim input.
- [ ] Manual aim influences priority without disabling auto-fire.
- [ ] Dead, hidden, or invalid enemies are never targeted.

## Summons

- [ ] Rune Hound, Sword Wisp, and Gun Construct use one shared base architecture.
- [ ] Each summon occupies a distinct follow lane.
- [ ] Summons do not push the hero or one another.
- [ ] Separated summons reform instead of pathfinding through the full level.
- [ ] Rally overrides target priority safely.
- [ ] Bound, Awakened, and Ascendant changes are visible and behavioral.

## Enemies and rooms

- [ ] All six enemy roles are data-driven.
- [ ] Every damaging attack has a red/orange telegraph.
- [ ] Nest Idol respects its child cap.
- [ ] Siphon tether breaks at eight units.
- [ ] Bellguard frontal reduction and recovery vulnerability work.
- [ ] Gates, waves, cleanup, reward, and exit states cannot softlock.
- [ ] Projectiles and telegraphs are removed on room clear.

## Level route

- [ ] Arrival teaches movement, staff, and first summon.
- [ ] Combat A introduces Crawlers and Hexers.
- [ ] Optional Rift previews reward category and costs 10 Stability.
- [ ] Rift success, failure, and skip all return to a completable main route.
- [ ] Spirit Well and merchant work with controller focus.
- [ ] Combat B introduces tank, spawner, hazard, and elite.
- [ ] Boss gate opens exactly once.

## Boss

- [ ] The First Bell reads at roughly 2.5 times hero height.
- [ ] Slam, chain sweep, toll, add call, stagger, and phase change work.
- [ ] Core exposure lasts four seconds with 1.75 damage multiplier.
- [ ] Phase 2 begins at 50% HP.
- [ ] Red telegraphs remain visible during Convergence.
- [ ] Every starter combination can beat the boss.
- [ ] Defeat and victory each fire once and cannot softlock.

## UI, save, and accessibility

- [ ] HUD keeps the center 70% clear.
- [ ] Reward, merchant, Spirit Well, pause, settings, and results are native Controls.
- [ ] Mouse, keyboard, and controller can reach every interactive element.
- [ ] Reduced shake, reduced flashes, effect opacity, and aim assist work.
- [ ] Settings and input bindings survive restart.
- [ ] Missing or corrupt save creates defaults safely.

## Performance and readability

- [ ] Intended Level 1 density holds 60 FPS on the development machine.
- [ ] 75-enemy test is stable.
- [ ] 150- and 250-enemy tests are recorded as stress results, not content targets.
- [ ] Node/projectile counts do not grow after repeated clears.
- [ ] Six simultaneous friendly effects do not hide hostile telegraphs.
- [ ] No summon remains orphaned after a room transition.

## Playtest results

- [ ] Three complete runs were recorded.
- [ ] Average run time is 8-12 minutes.
- [ ] At least two distinct builds appeared.
- [ ] No-aim play remained viable.
- [ ] Rally felt useful against at least one elite or boss.
- [ ] The player could explain why a summon evolved.
- [ ] The route felt connected rather than like unrelated arenas.
- [ ] Top three gameplay findings were added to `BUILD_NOTES.md`.
