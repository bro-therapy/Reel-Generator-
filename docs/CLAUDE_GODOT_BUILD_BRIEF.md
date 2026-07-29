# Claude Build Brief - Project Zero Climb Vertical Slice

You are building a Godot 4.x PC-first vertical slice from the attached Project Zero Climb package. Read `README_START_HERE.md`, `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`, `docs/ASSET_MANIFEST.json`, and `docs/LEVEL1_BALANCE.json` before writing code.

Do not redesign the game. Do not add systems outside the vertical-slice boundary. Use placeholder 3D geometry where final meshes do not exist. Preserve the asset filenames and visual identity.

## Non-negotiable outcome

Deliver one playable 8-12 minute run containing:

- Tower Exile at the 88 px gameplay target.
- Conjurer Staff with effective auto-targeting and optional manual aim.
- Rune Hound, Sword Wisp, and Gun Construct.
- Arrival path, Combat A, optional Rift, Spirit Well/merchant, Combat B, boss.
- Six enemy roles, one elite, and The First Bell.
- Dash, Rally, Convergence, Stability, rewards, evolution, currency, death, victory.
- Keyboard/mouse and controller.
- 60 FPS target at intended Level 1 density.

## Work protocol

1. Implement one numbered phase at a time.
2. Run the phase acceptance checks.
3. Fix failures before moving on.
4. Keep gameplay values in Resources or JSON-backed data, not scattered constants.
5. Keep actor visuals swappable.
6. Never generate substitute art when an included asset exists.
7. If an included prototype frame is inconsistent, use the closest valid frame and record the issue in `ART_CLEANUP_TODO.md`.

## Phase 0 - Project foundation

Create:

```text
res://
  assets/
    actors/
    enemies/
    environment/
    ui/
    vfx/
  data/
    characters/
    spirits/
    enemies/
    encounters/
    rooms/
    relics/
  scenes/
    actors/
    enemies/
    rooms/
    ui/
    tests/
  scripts/
    data/
    actors/
    combat/
    run/
    ui/
  audio/
  docs/
```

Configure:

- 1920x1080 reference resolution.
- Stretch mode that preserves aspect ratio.
- Nearest-neighbor texture sampling for pixel actors/icons/effects.
- Physics tick 60.
- Input actions from the master guide.
- Collision layers from the master guide.
- Debug overlay toggle showing FPS, active enemies, projectiles, current target, room state.

Acceptance:

- Empty boot scene opens without errors.
- Keyboard and controller actions appear in the Input Map.
- Texture filtering is disabled on imported pixel atlases.
- Debug overlay can be toggled.

## Phase 1 - Hero sandbox

Build `Player.tscn` as a `CharacterBody3D` with billboarded animated sprite, fixed ground pivot, movement acceleration/deceleration, dash, hurtbox, and camera target.

Use:

- `PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png`, or provided split frames.
- `PZC_Tower_Exile_Action_Atlas_ALPHA_GRID_v1.png`, or provided split frames.
- `LEVEL1_BALANCE.json` values.

The hero should display near 88 px tall at 1080p in the test camera.

Acceptance:

- Eight directional facings select correctly.
- Player reaches full speed smoothly and stops without sliding.
- Dash covers 4.3 units, lasts 0.18 seconds, and respects cooldown.
- Hero cannot take two hits inside the contact grace window.
- Character remains visually grounded with no pivot bob between idle/run.

## Phase 2 - Conjurer Staff and targeting

Implement one `FocusWeaponController`.

Auto-target score:

- Rally target +1000.
- Boss +80.
- Spawner/Hexer +50.
- Elite +40.
- Current target +20.
- Distance -2 per world unit.
- More than 60 degrees behind preferred aim -25.

Right stick/mouse changes preferred aim. If no aim input exists, staff still fires effectively.

Acceptance:

- Staff fires every 0.72 seconds.
- It chooses valid in-range enemies.
- Manual aim changes priority without disabling auto-fire.
- It never targets dead, despawned, or hidden enemies.
- Projectiles return to a pool or cleanly free without leaks.

## Phase 3 - Shared summon architecture

Create:

- `SpiritData.gd`
- `SpiritFormData.gd`
- `SummonBase.tscn`
- `FollowController.gd`
- `SummonTargetController.gd`
- `SummonStateMachine.gd`

Summon states:

```text
FOLLOW -> ACQUIRE -> WINDUP -> ATTACK -> RECOVER -> FOLLOW
any state -> REFORM -> FOLLOW
```

Rules:

- No physical collision with player, summons, or normal enemies.
- Invulnerable for the prototype.
- Reforms if more than 10 units away.
- Target refresh every 0.20 seconds.
- Rally target overrides normal score.

Acceptance:

- One generic base scene drives all three species.
- A summon follows without pushing the player.
- It attacks, recovers, and returns to its lane.
- It changes rooms without getting stranded.
- It reforms rather than pathfinding across the whole room.

## Phase 4 - Starter species

Implement species modules/data:

### Rune Hound

- Melee lunge.
- 18 damage.
- 1.05 second interval.
- Forward-left follow lane.

### Sword Wisp

- Orbit/lunge/return.
- 11 damage.
- 0.62 second interval.
- Overhead-right follow lane.

### Gun Construct

- Plant/aim/burst.
- 8 damage.
- 0.38 second interval.
- Rear-right follow lane.

Acceptance:

- Species are recognizable from behavior without reading UI.
- Three summons do not stack on one location.
- They may attack separate enemies unless Rally is active.
- Six simultaneous friendly effects do not hide red telegraphs in the test room.

## Phase 5 - Enemies

Create one reusable `EnemyBase` and six data-driven role modules:

- Rift Crawler.
- Lantern Hexer.
- Bellguard.
- Nest Idol.
- Blade Mite.
- Siphon Eye.

Use the included atlas and split frames. Implement visible windup, active attack, recovery, hit, and death states.

Acceptance:

- Every damaging attack has a red/orange telegraph.
- Windup can be cancelled by death.
- Nest Idol respects child cap.
- Siphon tether breaks at eight units.
- Bellguard frontal reduction and post-slam vulnerability work.
- Enemy cleanup cannot block room completion.

## Phase 6 - Combat room framework

Create:

- `EncounterData`.
- `EncounterController`.
- Spawn point groups.
- Gate open/close state.
- Room completion signal.
- Reward spawn.

Room state:

```text
INACTIVE -> INTRO -> LOCKED -> WAVES -> CLEARING -> REWARD -> COMPLETE
```

Acceptance:

- Gates lock only after the player enters.
- Each wave begins only when its condition is met.
- Room clear waits for all living encounter enemies.
- Projectiles and telegraphs clean up on clear.
- Reward appears once.
- Exit never remains locked after reward selection.

## Phase 7 - Rewards, inventory, and evolution

Implement:

- Three-card reward UI.
- Three Bond slots.
- One Focus Weapon.
- Relic list.
- Currency.
- Echo evolution.
- Offer pity rules.

Evolution:

- Bound -> first duplicate -> Awakened.
- Awakened -> second duplicate -> Ascendant.
- Update portrait, visual scene/frames, stats, and behavior.

Acceptance:

- Empty Bond slots receive a summon offer by the second reward.
- Equipped summon gets an Echo offer by the Spirit Well.
- No three-card offer is fully unusable.
- Evolution visibly changes the summon and one behavior.
- Controller can select and confirm every card.

## Phase 8 - Sunfall Ward blockout

Build the exact route from `PZC_Sunfall_Ward_Route_Map_v1.svg`.

Use simple 3D geometry:

- Warm sandstone floors/walls.
- Terracotta roofs and wood.
- Props around perimeter.
- Violet Rift crystals/gates.
- Broad clean combat floors.

Use GridMap or modular packed scenes as appropriate. The included environment kit is a visual target, not a requirement to create final meshes.

Acceptance:

- Main path is readable without a minimap.
- Optional Rift branch is visible and clearly optional.
- Camera cannot see missing world geometry.
- Combat centers are uncluttered.
- Navigation works across all required rooms.

## Phase 9 - Spirit Well and merchant

Implement:

- Heal 20% once.
- Restore 15 Stability for 35 currency.
- Five merchant offers.
- One free reroll, then 15/25/40.
- Lock one item.
- Summon evolution/inspection.

Acceptance:

- Merchant cannot charge twice for one selection.
- Locked offer survives reroll.
- Unaffordable item communicates disabled state.
- Exiting returns control cleanly.
- Controller focus never disappears.

## Phase 10 - Optional Rift

Implement 45-second protect-the-core event.

- Entry costs 10 Stability.
- Reward category is previewed.
- Failure ejects player with one HP and no reward.
- Success grants a rare Echo.

Acceptance:

- Player cannot be trapped after failure.
- Timer, core health, and reward state reset on a new run.
- Main route remains completable after skipping or failing the Rift.

## Phase 11 - The First Bell

Build boss from the production sheet.

Use `PZC_First_Bell_Action_Atlas_ALPHA_GRID_v1.png` or the eight files in
`boss_action_frames/` for the prototype states. Keep the production sheet as
the higher-detail identity reference.

Phase 1:

- Slam.
- Chain sweep.
- Toll/reform pulse.
- Three-Crawler call.

Stagger:

- Four seconds.
- 1.75 damage multiplier.

Phase 2:

- Begins at 50% HP.
- Additional slam ring.
- Reversing chain sweep.
- Summon may add one Hexer.

Acceptance:

- Boss is 2.5 times hero height.
- Every hit has a visible red telegraph.
- Core exposure is obvious.
- Any starter team can win.
- Boss defeat opens result state exactly once.
- Enrage starts at 180 seconds without adding one-shot damage.

## Phase 12 - Rally, Stability, and Convergence

Rally:

- Six-second mark.
- Four-second cooldown.
- Shared priority.
- +15% summon damage to marked target.

Stability:

- Start 100.
- Rift cost 10.
- Elite restore five.
- Zero ends run.

Convergence:

- Meter 100.
- Four seconds.
- +15% speed, +30% attack speed.
- Dash cooldown multiplier 0.65.
- One signature attack per bonded summon.

Acceptance:

- Rally target clears when invalid.
- Stability cannot exceed 100 or drop below zero.
- Convergence cannot be retriggered while active.
- Red telegraphs remain visible during full Convergence.
- Run ends cleanly at zero Stability.

## Phase 13 - HUD and menus

Recreate the hierarchy of the included HUD and menu references with native Godot `Control` nodes. Do not use the mockup as a single flattened interactive UI.

Acceptance:

- Center 70% remains clear.
- HUD scales at 16:9 and ultrawide safe areas.
- All menus work with mouse, keyboard, and controller.
- Reduced shake/flashes/effect opacity settings work.
- Pause freezes combat but not menu navigation.

## Phase 14 - Save and results

Save:

- Audio/graphics/accessibility settings.
- Input bindings.
- Best clear time.
- Discovered starter species.
- No complex meta-progression yet.

Acceptance:

- Settings survive restart.
- Corrupt or missing save creates defaults without crashing.
- Victory and defeat both return to a result screen.
- Restarting creates a clean new `RunState`.

## Phase 15 - Performance and QA

Add test scenes for:

- 75 enemies.
- 150 enemies.
- 250 enemies.
- Six simultaneous friendly effects.
- Boss plus adds.

Profile before optimizing. Pool repeated projectiles/pickups/enemies if object churn is visible. Expose quality toggles for shadows, particles, and volumetrics.

Acceptance:

- Intended Level 1 density holds 60 FPS on the development machine.
- No increasing node/projectile count after repeated room clears.
- No orphaned summons after room transitions.
- No controller focus traps.
- No red telegraph is fully hidden by friendly VFX.

## Final delivery

Return:

- Complete Godot project.
- `BUILD_NOTES.md`.
- `ART_CLEANUP_TODO.md`.
- `KNOWN_ISSUES.md`.
- One desktop export if possible.
- Test results for every acceptance phase.
- A short list of the three most important gameplay findings after the first internal run.

Do not build a hub, additional biome, multiplayer, crafting, branching evolutions, or more summons until the vertical slice is played and approved.
