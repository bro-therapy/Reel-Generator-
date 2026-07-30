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
