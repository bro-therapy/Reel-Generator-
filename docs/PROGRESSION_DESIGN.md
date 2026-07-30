# Progression — an owner amendment to the master guide

The master guide has no leveling and starts the player with a full team. The
owner asked for the opposite, in these words:

> "enemies need to drop experience, just like Vampire Survivors... when you
> level up, there should be a screen that gives you the option to buff certain
> things. Those buffs can be options to upgrade my dog or upgrade my robot...
> right off the gate, I shouldn't have all three of the summons. I should start
> off with just a basic shot... Then, once I reach a certain level, or get like
> a pickup from a certain mob, then I can get the dog."

Two guide decisions are therefore **overridden**, deliberately and on the
owner's instruction:

| Guide | Amended to |
|---|---|
| §5 "the starting team is one of each species" | The run starts with the Focus Weapon alone. Summons are earned. |
| No leveling system anywhere | Enemies drop experience; the hero levels; each level offers a choice of upgrades. |

Everything else in the guide still stands, including colour ownership, the
no-aim promise, and the fixed collision layers.

## How it fits together

```
enemy dies ─► ExperienceOrb dropped (worth = threat_weight x xp_per_threat)
                  │  magnet pulls it in within orb_magnet_radius_units
                  ▼
          RunState.gain_experience()
                  │  levels up as many times as the amount covers
                  ▼
          RunState.levelled_up ──► LevelUpScreen (pauses the run)
                  │                    player picks one of three
                  │                            ▼
                  │                   UpgradeEffects.take()
                  └──► summon unlock thresholds checked
```

## Where the numbers live

`docs/LEVEL1_BALANCE.json` -> `progression`. Nothing here is hardcoded in a
behaviour script, per the project's standing rule.

| Key | Meaning |
|---|---|
| `xp_per_threat` | An enemy's worth is its `threat_weight` times this. A new species is worth the right amount the moment it exists. |
| `xp_base_per_level` | Level N costs `xp_base_per_level x N`. Gentle and linear on purpose — an exponential curve makes level 5 unreachable inside an 8-12 minute slice; a flat one hands out upgrades faster than they can be read. |
| `orb_magnet_*` | Pickup feel. |
| `summon_unlock_levels` | Which level bonds which species. |
| `boss_required_level` | Gate on the boss door. |
| `escalation_*` | Difficulty drift with elapsed time. |

## Design decisions worth keeping

**Upgrades stack additively, not multiplicatively.** Three +20% damage cards
give 1.6x, not 1.73x. This keeps the tenth pick as meaningful as the first,
stops a long run running away, and makes the number printed on the card mean
what it says.

**Upgrade effects are run-scoped, never written into the data resources.**
`data/spirits/rune_hound.tres` is a shared resource loaded once; granting a
summon +20% damage by editing it in memory would carry the bonus into the next
run and into every other hound in this one. `UpgradeEffects` is a per-run table
and cannot leak.

**A summon upgrade is never offered for a species you do not have.** Filtered in
`UpgradeCatalog.available_ids()` rather than hidden in the UI, so nothing
downstream needs to know the rule.

**One screen per level gained, queued.** A kill worth three levels owes three
choices; showing them at once would collapse into one.

**The pool never loses experience.** If every orb is in flight when an enemy
dies, the XP is awarded directly instead of dropping nothing. A missing pickup
is cosmetic; missing progress is not.

## Opening balance

Measured in the acceptance soak: a level-1 hero with **no summons at all** kills
3 of 7 enemies unaided in the first 10 seconds, reaching level 3 and unlocking
the Rune Hound partway through the first encounter. The weapon-only opening is
viable rather than punishing, which was the risk of removing the starting team.

## Room flow and the boss gate

**Entering a combat room telegraphs before it spawns.** A warm light pulse from
the room's centre, then the wave. Enemies materialising the instant you cross an
invisible line reads as an ambush bug rather than a fight starting.

**The boss door needs two things at once**, both owner-requested: every combat
room on the critical path cleared, *and* a level threshold
(`boss_required_level`). Either alone leaves it shut, which is what makes
re-clearing rooms to level up a real decision rather than a suggestion. The door
says which condition is missing, once, instead of silently refusing.

The acceptance suite drives all four combinations explicitly. Its first version
only checked "refuses while rooms remain" *if* rooms remained — and the soak had
already cleared them, so it silently asserted nothing. A conditional assertion
that can skip is not an assertion.

## The dead end this nearly shipped with

`boss_required_level` was set to 7 by eye. Computed against the actual encounter
data afterwards, the critical path granted only enough experience for **level
6** — so the boss door could never open unless the player detoured through the
Rift, which guide §10 makes optional. A gate nobody can pass is worse than no
gate, and every individual part of it was correct: the encounters were fine, the
curve was fine, the gate was fine. Only the relationship between them was broken.

Phase 0 now recomputes this from the balance file on every run and fails if the
critical path cannot reach the threshold. Mutation-tested from both sides —
raising the gate to level 9, and cutting `xp_per_threat` — because the defect
can arrive from either direction.

Current margin: the critical path grants **352 xp** across **48 enemies**;
level 7 costs **252**. The Rift remains a genuine optional bonus.

## Escalation

`escalation_per_minute` (0.08) and `escalation_cap` (1.5) drift enemy **health**
upward with elapsed run time. Health only, never damage: tougher enemies
lengthen a fight, while harder-hitting ones kill a player who was coping a
minute ago — the "way too difficult" the owner ruled out. The cap means a
twenty-minute run is no worse than an eight-minute one.

Scaling is applied per spawned instance (`EnemyBase.health_scale`), never
written back into the shared `EnemyData` resource, for the same reason upgrade
effects are run-scoped: a shared `.tres` mutated in place compounds across
spawns and leaks into the next run.

## The boss that could not be fought

The First Bell was built in Phase 11, passed nineteen acceptance checks, and was
**impossible to hit**. Every one of those checks called `take_damage()`
directly, while the boss itself was a bare `Node3D` with no hurtbox and no group
membership — and a `FocusProjectile` looks for a body or area on the
EnemyHurtbox layer owned by something in the `enemies` group. It found neither.
Walking to the far room found an empty arena, exactly as the playtest reported.

Two things were missing and both are now checked:

1. **A hurtbox.** A capsule Area3D on layer 5, sized from the boss's own
   `world_height` so the two cannot drift apart, plus `add_to_group("enemies")`.
2. **A trigger.** `_runs_encounter()` deliberately excludes the boss room so
   walking in never starts a mob wave, and a check pins that behaviour. Rather
   than loosen a rule that is doing its job, the boss got its own trigger.

The check that proves it asks the **physics server** the same question a
projectile asks — a shape query at body height with the friendly-attack mask —
because "the hurtbox exists" and "a shot can reach it" are different claims and
only the second one matters. Mutation-tested by deleting the hurtbox again.

One subtlety worth keeping: an `Area3D` added this frame is not in the physics
world until the next tick, so a query run immediately after spawning reports
"unhittable" about a perfectly good boss. The suite spawns it a second before it
measures.

Killing the boss ends the run. Clearing every combat room no longer does — it
opens the boss door and says so.

## Re-clearable rooms

Requested directly: "you have to revisit some of the rooms a couple times and
kill mobs to level up to get into the room". Without it a room clears exactly
once, so a player short of the boss threshold would have no way at all to earn
the difference — the grind loop would silently not exist.

Three decisions, each with a reason:

**A re-fight runs the LAST wave, not the whole encounter.** Replaying a
four-wave fight from the top to farm one level is tedious, and the final wave is
where the interesting enemies are.

**`_cleared` is never unset.** The room stays cleared for the boss gate.
Un-clearing on re-entry would let a player lock themselves back out of the boss
door by going back to grind — a trap that punishes exactly the behaviour the
feature is meant to encourage.

**The exit radius is wider than the entry radius.** Standing on the boundary
would otherwise flicker a room open and shut every frame.

Time escalation still applies, so a late re-clear pays the same experience
against tougher enemies — the grind gets slower the longer a run goes, which
bounds it without a hard cap.

## Choosing a spirit instead of being handed one

Requested: "There should be a page where you can pick which upgrade you want.
If you want the wolf or the robot or the sword. So you have to level up to earn
that."

`progression.summon_unlock_levels` in the balance file still lists a level per
species, but it is now read as **the Nth slot opens at the Nth level** rather
than **this species arrives at this level**. Sorting the levels gives the slot
schedule; who fills each slot is the player's call. Pacing is byte-for-byte
unchanged — the only thing that moved is the decision, out of the data and into
the player's hands.

Bonding is offered **before** upgrading when a level owes both. A level that
grants a spirit almost always owes an upgrade choice too, and asking for the
upgrade first means choosing from a list that does not yet contain the spirit
the same level just handed over.

Pages queue rather than stack: a second level gained while a page is open waits
for an answer instead of opening a second screen.

## Owner overrides of locked guide values

CLAUDE.md locks the guide's decisions and says to raise concerns rather than
silently change them. These were raised and then explicitly directed by the
owner, so they are recorded here rather than argued in a comment.

| Guide | Original | Now | Why |
|---|---|---|---|
| §5 starting team | all three spirits bonded | Focus Weapon only | "right off the gate, I shouldn't have all three of the summons" |
| §11 boss height | 2.5x hero | 4.4x hero | "I need the boss to be scaled up much larger towards the end" |
| §11 slam damage | 24 | 32 | "the boss didn't really feel like a boss ... a little bit more difficult" |
| §11 sweep damage | 18 | 24 | as above |
| §11 slam tell | 1.25 s | 1.05 s | as above |
| §11 sweep tell | 0.95 s | 0.80 s | as above |
| (none) | no leveling | XP, levels, upgrades | "enemies need to drop experience, just like vampire survivors" |

Two things did **not** move with them.

**The stagger window, the enrage clock and the phase-two threshold** are
structure, not difficulty. Making a fight harder by shortening its openings
changes what the fight *is*; making it harder by hitting harder does not.

**Telegraphs have a floor.** Phase 11 fails any tell under 0.75 s. Human
reaction to a visual cue is around a quarter of a second and the rest is the
time to stop, turn, and leave the shape — under that, a telegraph is decoration
and guide §11's "every hit has a visible red telegraph" is satisfied on paper
only. The owner-requested shortening is exactly what put this at risk, which is
why the floor is asserted instead of assumed.

## The boss has to announce itself

"The final room, the boss, didn't really feel like a boss ... I couldn't even
tell I was at the last room."

The boss had no health bar and no arrival announcement. It was scaled up in the
same pass, but a bigger sprite alone does not tell a player the game changed —
there was nothing on screen that was not also there for a rift crawler.

The bar and its frame are warm, like everything else that belongs to the enemy.
The arrival card is exempt from the reserved-centre rule because it is
transient, and Phase 13 drives the clock past its lifetime and fails if it is
still up — so "it is transient" is proven rather than claimed.
