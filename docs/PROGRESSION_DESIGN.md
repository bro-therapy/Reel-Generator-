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
