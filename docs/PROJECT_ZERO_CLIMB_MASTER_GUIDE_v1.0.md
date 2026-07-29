# Project Zero Climb — Complete Game and First Playtest Production Guide

**Version 1.0 | July 2026**

> Transcribed from `PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.pdf` into version control.
> Content is reproduced faithfully from the source; no design decisions were added,
> removed, or reinterpreted. Figure callouts from the PDF (turnaround sheets,
> production sheets, route map, HUD mockups) are noted inline as `[figure]` — the
> images themselves live in the source PDF and the asset package.

Project Zero Climb is a connected-room action roguelite about a Tower Exile who fights
with one mystical Focus Weapon and bonds with an evolving team of autonomous spirits,
living weapons, undead, and machines.

The first playtest is not a full game. It is one polished 8–12 minute vertical slice that
proves the hero scale, automatic summon combat, optional aiming, route rhythm, build
variation, controller feel, and visual readability.

---

## 1. The pitch

**Move, dodge, and guide one Focus Weapon while three collectible summons fight
automatically, evolve visibly, and combine into screen-filling anime team attacks during a
dangerous climb through a collapsing tower.**

### Player fantasy

- Explore a place, not a disconnected arena menu.
- Find original creature-like spirits with distinct personalities and jobs.
- Let the team auto-attack while you concentrate on movement, positioning, dash timing, and build decisions.
- Aim only when you want to prioritize an elite, boss, hazard, or marked target.
- Turn small companions into striking evolved forms during a run.
- Push into optional Rifts for rewards that can define the build.
- Return to a persistent hub with new species, lore, starting choices, and restored spaces.

### Design pillars

1. **Never stop moving.** Core combat never requires paused tactical micromanagement.
2. **Every summon matters.** A summon owns a silhouette, role, attack cadence, temperament, trait, element, and evolution.
3. **Every build evolves.** Upgrades change bodies, attacks, behavior, and team reactions, not only percentages.
4. **Greed shapes the route.** Dangerous branches reveal their reward category before commitment.
5. **The hub remembers.** Meta-progression unlocks options and story more than permanent raw power.

---

## 2. Locked creative identity

### Hero

The Tower Exile is a young male Shardbound Runner with:

- Black hair and a white front streak.
- A burnt-orange scarf visible from every direction.
- A dark indigo layered coat with restrained purple accents.
- Heavy boots and simplified anime proportions.
- An asymmetric Shard Core gauntlet glowing violet.
- A Conjurer Staff as the first Focus Weapon.

The coat, scarf, gauntlet, boots, and hair streak must survive the 88 px gameplay target.
Outfit changes are limited to Resonance accents tied to the Focus Weapon family. The
character does not become a different person for every pickup.

`[figure: Tower Exile turnaround]`

### Art direction

- Bold 16-bit-inspired anime actors.
- Thick near-black contour.
- Large color blocks.
- Four or five shades per material.
- Hard cel shadows and restrained internal texture.
- 2D pixel-built characters/effects inside dimensional 3D environments.
- Warm architecture, real depth, soft environmental lighting, fog, shadows, and selective bloom.
- No smooth painterly characters and no micro-detailed clothing at gameplay scale.

### Gameplay scale

- Target the hero at **88 px tall at 1920x1080** in normal combat.
- Camera may pull back 10–15% for bosses, elites, dense objectives, and heavy swarms.
- Summon visual targets: Rune Hound roughly 52 px at shoulder, Sword Wisp 58 px vertical, Gun Construct 46 px tall.
- Readability takes priority over literal world scale.

`[figure: Gameplay scale benchmark]`

### Color ownership

| Meaning | Primary colors | Rule |
|---|---|---|
| Friendly attacks and summoning | Violet, indigo, blue-white | Violet shape with a narrow bright core |
| Hostile attacks and telegraphs | Red, orange, warm white | Never use large violet hostile circles |
| Rewards and interactables | Gold, teal, soft green | Must read during combat cleanup |
| Hero identity | Burnt orange, indigo, violet | Orange scarf stays the strongest warm accent |
| Environment | Sandstone, terracotta, wood, green plants | Keep the combat floor less saturated than actors |

---

## 3. Core controls

### Controller

| Input | Action |
|---|---|
| Left stick | Move |
| Right stick | Influence Focus Weapon aim |
| South face button | Dash |
| East face button | Interact / cancel |
| West face button | Rally mark |
| North face button | Hold for team command |
| Right trigger | Optional manual Focus fire |
| Left trigger | Convergence when full |
| D-pad | UI navigation or quick information |
| Start | Pause |

### Keyboard and mouse

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Influence Focus aim |
| Space | Dash |
| E | Interact |
| Q | Rally |
| Right mouse | Team command |
| Left mouse | Optional manual Focus fire |
| R | Convergence |
| Escape | Pause |

### No-aim promise

If the player never touches the right stick or mouse, the Focus Weapon and all equipped
summons still attack effectively. Aiming improves priority and accuracy; it does not unlock
basic functionality.

---

## 4. Combat loadout

### One Focus Weapon

The hero carries one visible weapon. In the vertical slice this is the Conjurer Staff.

- Auto-targets the closest valid enemy weighted by threat and facing.
- Optional right-stick/mouse input rotates the aim preference.
- Manual fire may be held, but auto-fire remains active by default.
- Rally-marked targets receive the highest priority when in range.
- Focus upgrades affect damage, attack speed, pierce, projectile size, critical chance, chain behavior, or staff/summon reactions.

### Three Bond slots

Each persistent summon:

- Maintains a follow lane around the hero.
- Selects and attacks valid targets automatically.
- Respects the Rally target when safe.
- Ignores body collision with the player and other summons.
- Uses simple steering rather than expensive full-room pathfinding.
- Teleports back in violet particles when separated.
- Is invulnerable during the prototype.
- Briefly disperses and reforms if hit by a boss anti-summon pulse.

### Rally

- Tap marks an elite, boss, priority enemy, or objective for six seconds.
- Marked target gains a clear red diamond with a violet friendly outline.
- Summons finish safe recovery before changing targets.
- Marking empty ground clears the mark.
- Holding Rally may later recall the team, but that is not required in the first slice.

### Dash

- Distance: **4.3 world units**
- Duration: **0.18 seconds**
- Cooldown: **1.35 seconds**
- Invulnerability: **0.20 seconds**
- No damage by default.
- A successful dash-through dodge grants Overdrive.

### Convergence

Convergence is the Overdrive state.

- Meter maximum: **100**
- Duration: **four seconds**
- Move speed: **+15%**
- Attack speed: **+30%**
- Dash cooldown multiplier: **0.65**
- Every bonded summon performs one synchronized signature attack.
- The hero gains an intensified violet aura, brighter gauntlet core, and longer scarf trail.
- Effects must preserve hostile red telegraphs beneath them.

---

## 5. Starter summons

`[figure: Starter summon production sheet]`

### Rune Hound

- **Role:** melee burst and target chasing
- **Temperament:** eager, protective, impatient
- **Base attack:** lunges and bites/slashes the nearest valid enemy
- **Follow lane:** forward-left
- **Bound form:** one quick bite with a short recovery
- **Awakened form:** every fourth strike creates a crescent slash
- **Ascendant form:** Tempest Fenrir chains its lunge through two nearby targets
- **Convergence attack:** crosses the arena in a lightning-wolf streak

### Sword Wisp

- **Role:** mobile cleave and projectile interception
- **Temperament:** disciplined, silent, loyal
- **Base attack:** orbits, tilts toward a target, lunges, slices, and returns
- **Follow lane:** overhead/right
- **Bound form:** single blade slash
- **Awakened form:** a delayed second blade repeats the arc
- **Ascendant form:** Halo Blade Seraph gains three blades and intercepts one hostile projectile every four seconds
- **Convergence attack:** draws a large circular cut around the Rally target

### Gun Construct

- **Role:** ranged sustained damage
- **Temperament:** literal, stubborn, reliable
- **Base attack:** plants, aims, and fires a short violet burst
- **Follow lane:** rear-right
- **Bound form:** single cannon burst
- **Awakened form:** every sixth projectile pierces
- **Ascendant form:** Arsenal Titan fires a three-missile volley every four seconds
- **Convergence attack:** deploys a temporary multi-cannon barrage

`[figure: Starter evolution paths]`

### Evolution rules

- New summon: **Bound**
- First duplicate Echo during a run: **Awakened**
- Second duplicate Echo: **Ascendant**
- Further duplicates become a species-specific overflow upgrade or currency.
- Evolution changes the visible body and one behavior.
- Stat gain alone is never enough to qualify as an evolution.
- The first playtest allows all three starters to evolve but does not include branching evolutions.

---

## 6. Build system

### Reward cadence

- First summon within 30 seconds.
- First three-card reward by 2:00.
- Three-summon team by 5:00.
- One reliable evolution opportunity before the boss.
- Merchant/Spirit Well at approximately 5:00–6:00.
- Boss entered by 8:00 in a normal route.

### Reward card categories

1. Recruit a missing starter summon.
2. Gain a duplicate Echo and evolve a bonded summon.
3. Upgrade the Conjurer Staff.
4. Gain a summon-family relic.
5. Gain a general relic.
6. Restore health, Stability, or currency as a recovery offer.

### Prototype rarity

| Rarity | Weight | Offer |
|---|---|---|
| Common | 60 | basic stat or utility |
| Uncommon | 30 | conditional behavior or strong stat bundle |
| Rare | 10 | evolution Echo, reaction unlock, or defining relic |

### Pity rules

- By the second reward, offer at least one missing summon if a Bond slot is empty.
- By the Spirit Well, offer at least one Echo for an equipped summon.
- Never show three unusable cards.
- Do not offer a fourth summon in the vertical slice.
- When all three summons are Ascendant, replace Echo offers with relics or Focus upgrades.

### Example team reactions

- **Storm Hunt:** Rune Hound striking a staff-shocked target releases a small chain bolt.
- **Crossfire Oath:** Sword Wisp passing through Gun Construct fire adds pierce to the next burst.
- **Guardian Circuit:** Gun Construct gains attack speed while Sword Wisp is intercepting.
- Only one reaction is required for the first playtest; the others may remain data entries.

---

## 7. Stability and run failure

- Start at **100 Stability**.
- Entering the optional Rift costs 10 Stability.
- Normal rooms do not passively drain Stability in the first slice.
- An elite reward restores five.
- The Spirit Well may restore 15 for 35 currency.
- Reaching zero ends the run.
- Player death ends the first-playtest run immediately.
- Voluntary extraction is backlog, not part of Level 1.

The first build should make Stability understandable but not oppressive. It exists mainly to
demonstrate future route pressure.

---

## 8. First biome — Sunfall Ward

Sunfall Ward is a warm lived-in market district built into the tower. It contains sandstone,
terracotta roofs, market awnings, planters, balconies, fountains, alleys, bells, and old civic
gates. Rift corruption appears as violet crystals, blackened stone, sealed gates, and broken
ceremonial machinery.

### Environment rules

- Combat floors are broad and lower-contrast.
- Market props remain around edges rather than cluttering the playable center.
- Doorways and paths are readable without a minimap.
- Warm sunlight creates long soft shadows.
- Violet corruption is localized so friendly effects remain readable.
- Red enemy telegraphs never overlap a red environmental floor pattern.
- Breakable props are cosmetic only in the first slice.

`[figure: Sunfall Ward modular kit]`

### Required modules

- Three cobblestone floor variants.
- Straight wall plus inner and outer corners.
- Stone arch.
- Stairs.
- Low combat wall.
- Red/cream and blue/cream market stalls.
- House facade.
- Roof and balcony.
- Crate, barrel, bench, planters, lantern, signpost, fountain, broken cart.
- Rift crystals.
- Sealed combat gate.
- Spirit Well.
- Merchant kiosk.
- Elite gate.
- Boss floor emblem.

For the first playtest, build these as **3D primitives, simple meshes, decals, and repeated
props**. The environment sheet is the visual reference. The alpha extraction may be used for
temporary billboards but is not a substitute for final 3D geometry.

---

## 9. Level 1 route

`[figure: Sunfall Ward route]`

### Space 1 — Arrival path

- **Purpose:** movement, camera, Focus Weapon, and first summon
- **Enemies:** three Rift Crawlers
- **Reward:** starter selection if no starter is preselected
- **Target duration:** 30–45 seconds

### Space 2 — Combat Zone A

- **Purpose:** teach a ranged threat and automatic team separation
- **Wave 1:** six Rift Crawlers
- **Wave 2:** four Rift Crawlers and two Lantern Hexers
- **Reward:** three-card choice
- **Target duration:** 45–60 seconds

### Optional branch — Rift

- **Rule:** protect a fragile Spirit Core for 45 seconds
- **Cost:** 10 Stability
- **Enemies:** Crawlers, Blade Mites, Hexers, one Siphon Eye
- **Reward:** rare Echo with a visible category preview before entry
- **Failure:** eject to main route at one health; no reward; Stability remains spent

### Space 3 — Spirit Well and merchant

Functions:

- Heal 20% once.
- Restore 15 Stability for 35 currency.
- Buy one of five items.
- Reroll once free, then increasing cost.
- Evolve or swap summons.
- Show the first evolution preview.

### Space 4 — Combat Zone B

- **Purpose:** combine tank, spawner, and arena hazard
- **Wave 1:** six Crawlers and one Bellguard
- **Wave 2:** one Nest Idol and three Lantern Hexers
- **Wave 3:** one Gilded Bellguard elite
- **Local hazard:** warning bell creates two red circular floor zones before a falling debris strike
- **Reward:** boss gate key and one high-tier choice
- **Target duration:** 90–120 seconds

### Space 5 — The First Bell arena

Circular market-belfry plaza with gates, broken bell tower, arena emblem, and props pushed
to edges.

`[figure: Boss encounter target]`

---

## 10. Enemy roster

`[figure: Level 1 enemy lineup]`

### Rift Crawler

- Chaser.
- Low profile and quick movement.
- Short red slash telegraph.
- Dies in roughly two staff hits or one Rune Hound hit.
- Used to create pressure, not damage spikes.

### Lantern Hexer

- Ranged shooter.
- Stops at preferred range.
- Lantern brightens during windup.
- Fires a slow red orb or three-shot spread.
- High target priority for Gun Construct and Rally.

### Bellguard

- Tank and space-maker.
- Shield reduces frontal damage by 50%.
- Slams a red wedge into the ground.
- Exposes its back after a failed slam.

### Nest Idol

- Spawner.
- Plants itself and creates Crawlers.
- Spawn cap: four active children.
- Visible purple-red nest pulse before spawning.
- Rally logic treats it as high threat.

### Blade Mite

- Dasher.
- Draws a thin red line before lunging.
- Vulnerable during recovery.
- Used sparingly until the optional Rift or late Combat B.

### Siphon Eye

- Leech and debuffer.
- Creates a red tether.
- Tether breaks by moving eight units away, dashing through it, or killing the Eye.
- Never spawns more than two in the first slice.

### Gilded Bellguard

- Elite Bellguard.
- Gold silhouette and twin red cores.
- Adds a circular shockwave after the slam.
- Drops a high-tier reward and restores five Stability.

---

## 11. Boss — The First Bell

`[figure: The First Bell production sheet]`

The prototype also includes `PZC_First_Bell_Action_Atlas_ALPHA_GRID_v1.png` and eight split
frames covering idle, move, slam windup, slam impact, chain windup, bell toll, stagger/core-open,
and defeat. **Use those frames before attempting substitute art.**

### Identity

The First Bell is a corrupted civic guardian fused to a cracked ceremonial bell. It is
approximately **2.5 times the hero's gameplay height** and uses bronze, black armor, chains, a
red core, and restrained violet Rift cracks.

### Phase 1

1. **Core slam:** 1.25-second concentric red telegraph, 24 damage.
2. **Chain sweep:** 0.95-second arc telegraph, 18 damage.
3. **Bell toll:** knocks summons into brief disperse/reform without damaging the player.
4. **Crawler call:** summons three Rift Crawlers every 12 seconds.

### Stagger

- After two missed slams or enough Rally damage, the front bell cracks open.
- Red core becomes exposed for four seconds.
- Damage multiplier: **1.75**
- Boss does not attack during the stagger.
- Camera eases inward slightly but never hides the outer arena.

### Phase 2 at 50% HP

- One extra ring is added to the slam.
- Chain sweep reverses once.
- Crawler call may include one Lantern Hexer.
- The core remains visibly brighter.
- No new mechanic that has not appeared elsewhere in the stage.

### Failure protection

- First boss attempt should be beatable with any three starter combinations.
- No attack chains directly into an unavoidable second hit.
- Red telegraphs remain visible beneath all Convergence effects.
- Enrage at 180 seconds increases cadence but not damage.

---

## 12. Camera and presentation

### Camera states

| State | Use | Scale |
|---|---|---|
| Exploration | arrival, travel, utility | normal J-style framing |
| Normal combat | Combat A/B | 88 px hero target |
| Heavy combat | elite, dense Rift | 10% pullback |
| Boss | The First Bell | 10–15% pullback |
| Reward | post-combat | slight ease-in, no rotation |

### Rules

- Camera follows a weighted midpoint between hero and Rally target.
- Maximum target influence is limited so the player remains on screen.
- No sudden zoom step; interpolate over 0.35–0.6 seconds.
- Camera does not rotate during gameplay.
- Summons do not control camera framing.
- Screen shake is short and layered: small for staff, medium for slam, large only for boss break/Convergence.

---

## 13. HUD and menus

`[figure: Gameplay HUD target]`

### HUD

- **Top left:** hero portrait, health, Stability.
- **Top center in encounters:** progress bar.
- **Bottom center:** three summon portraits, cooldown ring, bond pips.
- **Bottom left:** Focus Weapon.
- **Bottom right:** dash, Rally, command, and Convergence.
- Center 70% remains clear.
- Marked priority targets use a small diamond.

`[figure: Reward, Spirit Well, and merchant]`
`[figure: Title, pause/accessibility, and results flow]`

### Reward cards

- Three large cards.
- Controller selection defaults to center.
- Each card shows category, icon, rarity border, current-to-new comparison, and whether it evolves a summon.
- Pauses combat only after room clear.

### Merchant

- Five offers.
- One free reroll, then 15, 25, 40 currency.
- Player can lock one offer.
- No selling in the vertical slice.

### Spirit Well

- Three Bond slots.
- Clear Bound/Awakened/Ascendant pips.
- Preview the visible form and behavior change.
- No large stat spreadsheet.

---

## 14. Audio brief

No audio files are included, so placeholders should be used with buses/slots exposed.

### Music

- `music_sunfall_explore`: warm plucked strings, soft hand percussion, distant tower bells.
- `music_sunfall_combat`: faster percussion, distorted bell rhythm, subtle synth pulse.
- `music_first_bell`: heavy bell strikes, chain percussion, choir-like pads.

### Required SFX families

- Hero steps, dash, hurt, staff shot, staff impact, Rally mark, Convergence start/end.
- Rune Hound growl, lunge, bite, crescent.
- Sword Wisp hover, lunge, slash, return.
- Gun Construct servo, aim, shot, burst.
- Six enemy windups, attacks, hits, deaths.
- Boss slam, chain sweep, toll, stagger, core break, defeat.
- Pickup, reward card, purchase, reroll, evolve, gate, Rift entry.

### Mix priority

1. Player damage warning.
2. Boss/elite telegraph.
3. Rally/Convergence.
4. Summon signatures.
5. Normal attacks.
6. Environment.

### Placeholder policy

The package intentionally does not ship licensed music, voice acting, or third-party sound
effects. For the first internal playtest, use clearly named silent or synthesized placeholders
and keep every sound behind the documented bus/slot. Do not download unverified audio or
block gameplay implementation on final sound.

---

## 15. Godot architecture

Use Godot custom Resources for serialized, Inspector-editable content. Resources are data
containers and can be nested and saved; AnimatedSprite2D/SpriteFrames can drive frame
animation, and InputMap should own rebindable action names.

### Autoloads

- **GameSettings:** accessibility, audio, graphics, input display.
- **SaveService:** settings and lightweight meta save.
- **SceneFlow:** boot, menu, run, results.

Do not make combat managers global unless they must survive scene changes.

### Data Resources

| Resource | Required fields |
|---|---|
| `CharacterData` | id, max_hp, move speed, dash values, visuals, Focus Weapon |
| `FocusWeaponData` | damage, interval, range, projectile, aim assist, tags |
| `SpiritData` | id, role, origin, element, temperament, icon, scene, forms |
| `SpiritFormData` | tier, visuals, stats, attacks, passive, Convergence |
| `EnemyData` | id, hp, speed, contact damage, threat, scene, drops |
| `AttackData` | damage, cooldown, range, windup, recovery, projectile/VFX |
| `RelicData` | id, rarity, tags, modifiers, icon |
| `EncounterData` | waves, spawn points, completion, reward |
| `RoomData` | room scene, encounter, gates, exits, camera bounds |
| `StageData` | ordered graph, optional branches, boss, environment |
| `RunState` | hp, Stability, currency, Focus, Bond slots, relics, route |
| `SaveData` | settings, unlocked starters, discoveries, best run |

### Core scene trees

```
Player (CharacterBody3D)
|- VisualPivot (Node3D)
|  |- AnimatedSprite3D
|  `- StaffSocket
|- CollisionShape3D
|- Hurtbox (Area3D)
|- TargetSensor (Area3D)
|- FocusWeaponController
|- DashController
|- RallyController
|- ConvergenceController
`- Audio

SummonBase (Node3D)
|- VisualPivot
|  `- AnimatedSprite3D
|- TargetSensor (Area3D)
|- AttackOrigin
|- FollowController
|- TargetController
|- StateMachine
`- Audio

EnemyBase (CharacterBody3D)
|- VisualPivot
|  `- AnimatedSprite3D
|- CollisionShape3D
|- Hurtbox
|- AttackOrigin
|- NavigationAgent3D
|- StateMachine
|- TelegraphController
`- Audio

CombatRoom (Node3D)
|- Environment
|- NavigationRegion3D
|- CameraBounds
|- SpawnPoints
|- EncounterController
|- GateController
|- PickupContainer
`- RoomAudio
```

### State machines

- **Player:** `MOVE -> DASH -> MOVE`, plus `HURT`, `CAST`, `DEFEAT`.
- **Summon:** `FOLLOW -> ACQUIRE -> WINDUP -> ATTACK -> RECOVER -> FOLLOW`; any state may enter `REFORM`.
- **Enemy:** `SPAWN -> SEEK -> WINDUP -> ATTACK -> RECOVER -> SEEK`; any state may enter `STAGGER` or `DEATH`.
- **Boss:** `INTRO -> PHASE_1 -> STAGGER -> PHASE_2 -> DEFEAT`.

### Collision layers

| Layer | Name |
|---|---|
| 1 | World |
| 2 | Player body |
| 3 | Enemy body |
| 4 | Player hurtbox |
| 5 | Enemy hurtbox |
| 6 | Friendly attack |
| 7 | Hostile attack |
| 8 | Pickup/interactable |
| 9 | Navigation blocker |
| 10 | Camera trigger |

Summons should not collide physically with the player, one another, or normal enemy bodies.

### Sprite import

- Disable filtering for actor, effect, and icon textures.
- Use nearest-neighbor sampling.
- Preserve alpha.
- Use the manifest's exact grids or provided split frames.
- Set a stable ground pivot per species.
- Use billboarded `AnimatedSprite3D` for actors in the 3D world.
- Do not use a 2D texture-atlas importer for 3D Sprite3D assumptions without testing;
  `SpriteFrames` with split PNGs is the safest prototype route.

---

## 16. Target selection

Score each valid target every **0.20 seconds**:

```
score = distance_weight
      + threat_weight
      + facing_weight
      + damaged_target_weight
      + rally_bonus
      - blocked_penalty
```

Recommended values:

- Rally target: **+1000**
- Boss: **+80**
- Spawner or Hexer: **+50**
- Elite: **+40**
- Current target stickiness: **+20**
- Each world unit of distance: **-2**
- More than 60 degrees behind preferred aim: **-25**

Summons may use species-specific distance/facing terms, but all use the shared scoring
contract.

---

## 17. Performance and accessibility

### Performance

- PC first.
- Stable 60 FPS at 1080p.
- Test 75, 150, and 250 active enemies.
- Prototype goal is 75; larger counts are stress tests, not Level 1 encounter targets.
- Pool repeated projectiles, damage numbers, pickups, and simple enemies after profiling shows churn.
- Avoid one heavy node tree per cosmetic particle.
- Use instancing for repeated environmental geometry.
- Quality settings: shadows, particles, volumetrics.
- Preserve readability with six simultaneous friendly weapon effects.

### Accessibility

- Rebindable controls.
- Controller and keyboard/mouse parity.
- Reduced screen shake.
- Reduced flashes.
- Effect opacity slider.
- Aim assist strength.
- High-contrast telegraphs.
- Separate friendly/hostile color alternatives.
- Damage numbers toggle.
- Hold/toggle options for manual Focus fire.

---

## 18. First-playtest success criteria

The slice is successful when:

- A new player understands movement, dash, auto-attacks, Rally, and rewards without explanation.
- No-aim play is viable.
- Optional aim improves elite/boss focus without becoming mandatory.
- At least two noticeably different builds appear across three runs.
- Every summon can be identified by silhouette during heavy combat.
- Red hostile telegraphs remain visible under Convergence.
- The boss is beatable with any starter combination.
- The run averages 8–12 minutes.
- Controller navigation reaches every menu element.
- There are no softlocks after room clear, death, Rift failure, or boss defeat.
- 60 FPS holds in the target encounter density.

### Required playtest questions

1. Did you feel like you were controlling the hero, the team, or neither?
2. Did Rally feel useful?
3. Which summon felt most valuable and why?
4. Could you tell why a summon evolved?
5. Were hostile attacks easy to separate from friendly effects?
6. Did the route feel like a journey or a string of arenas?
7. Was the boss readable?
8. Would you immediately start another run?

---

## 19. Asset readiness

### Prototype-ready

- Hero locomotion atlas and 40 split frames.
- Hero action atlas and 16 split frames.
- Starter summon atlas and 21 split frames.
- Enemy action atlas and 36 split frames.
- Boss action atlas and eight split frames.
- VFX atlas and 32 split cells.
- Pickup/relic atlas and 32 split cells.

### Production references

- Hero turnaround and directional sheet.
- Summon production and evolution sheets.
- Enemy lineup.
- Boss production sheet and gameplay keyframe.
- Boss action atlas and eight split prototype frames.
- Sunfall Ward environment kit.
- HUD, reward, Spirit Well, merchant, title, pause/accessibility, and results screens.
- Level route map.

### Not included

- Final hand-authored animation cleanup.
- Final 3D environment meshes/materials.
- Final shaders.
- Music and SFX files.
- Voice acting.
- Full hub.
- Additional biomes or bosses.
- Networked co-op.

These omissions are deliberate and do not block the first playtest.

---

## 20. Source notes

The technical handoff follows current official Godot concepts:

- Custom Resources: https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html
- AnimatedSprite2D and SpriteFrames: https://docs.godotengine.org/en/stable/tutorials/2d/2d_sprite_animation.html
- Sprite3D: https://docs.godotengine.org/en/stable/classes/class_sprite3d.html
- InputMap: https://docs.godotengine.org/en/stable/classes/class_inputmap.html
- GridMap: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
- CPU optimization and pooling: https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html

All creatures, characters, names, visual designs, and gameplay systems in this package are
original project concepts. Creature-collection and summoning inspirations should remain
structural; do not reproduce protected characters, names, interfaces, or assets from other
games.
