class_name UpgradeCatalog
extends RefCounted

## What a level-up can offer, and how an offer is rolled.
##
## Owner-requested (Vampire Survivors shape): every level presents a small hand
## of upgrades, and the interesting ones improve a specific summon rather than
## the hero. The master guide has no leveling — see docs/PROGRESSION_DESIGN.md.
##
## Values live here rather than in LEVEL1_BALANCE.json only because they are
## *structure* (which upgrades exist, what they touch) rather than tuning. The
## magnitudes are read from the entries below and applied through UpgradeEffect,
## so a behaviour script never hardcodes a number.
##
## Two rules the roll must respect and which the checks pin down:
##
##   1. An upgrade for a summon the player has not unlocked must never appear.
##      Offering "Rune Hound: faster bite" to someone with no hound is a dead
##      card and reads as a bug.
##   2. An offer must never contain the same upgrade twice. Three identical
##      cards is not a choice.

enum Target { HERO, WEAPON, SUMMON, STABILITY }

## id -> definition. `summon` is the spirit id an entry belongs to, or &"" for
## the ones that always apply.
const ENTRIES := {
	&"hero_swiftness": {
		"target": Target.HERO, "summon": &"", "stat": &"move_speed", "amount": 0.08,
		"title": "Swiftness", "text": "+{pct}% movement speed", "repeatable": true,
	},
	&"hero_vigor": {
		"target": Target.HERO, "summon": &"", "stat": &"max_hp", "amount": 0.12,
		"title": "Vigor", "text": "+{pct}% maximum health", "repeatable": true,
	},
	&"weapon_cadence": {
		"target": Target.WEAPON, "summon": &"", "stat": &"fire_rate", "amount": 0.12,
		"title": "Cadence", "text": "Focus Weapon fires {pct}% faster", "repeatable": true,
	},
	&"weapon_force": {
		"target": Target.WEAPON, "summon": &"", "stat": &"damage", "amount": 0.15,
		"title": "Force", "text": "+{pct}% Focus Weapon damage", "repeatable": true,
	},
	&"weapon_reach": {
		"target": Target.WEAPON, "summon": &"", "stat": &"range", "amount": 0.15,
		"title": "Reach", "text": "+{pct}% Focus Weapon range", "repeatable": true,
	},
	&"stability_ward": {
		"target": Target.STABILITY, "summon": &"", "stat": &"max_stability", "amount": 0.15,
		"title": "Ward", "text": "+{pct}% maximum Stability", "repeatable": true,
	},
	# One damage and one cadence upgrade per species. Named for the creature so
	# the card reads as "upgrade my dog" rather than as a stat line.
	&"hound_fangs": {
		"target": Target.SUMMON, "summon": &"rune_hound", "stat": &"damage", "amount": 0.2,
		"title": "Rune Fangs", "text": "Rune Hound deals {pct}% more damage", "repeatable": true,
	},
	&"hound_pace": {
		"target": Target.SUMMON, "summon": &"rune_hound", "stat": &"attack_speed", "amount": 0.15,
		"title": "Hunting Pace", "text": "Rune Hound attacks {pct}% faster", "repeatable": true,
	},
	&"wisp_edge": {
		"target": Target.SUMMON, "summon": &"sword_wisp", "stat": &"damage", "amount": 0.2,
		"title": "Keen Edge", "text": "Sword Wisp deals {pct}% more damage", "repeatable": true,
	},
	&"wisp_flurry": {
		"target": Target.SUMMON, "summon": &"sword_wisp", "stat": &"attack_speed", "amount": 0.15,
		"title": "Flurry", "text": "Sword Wisp attacks {pct}% faster", "repeatable": true,
	},
	&"construct_calibre": {
		"target": Target.SUMMON, "summon": &"gun_construct", "stat": &"damage", "amount": 0.2,
		"title": "Calibre", "text": "Gun Construct deals {pct}% more damage", "repeatable": true,
	},
	&"construct_autoloader": {
		"target": Target.SUMMON, "summon": &"gun_construct", "stat": &"attack_speed", "amount": 0.15,
		"title": "Autoloader", "text": "Gun Construct attacks {pct}% faster", "repeatable": true,
	},
}

## How many cards a level-up shows. Three is the genre standard and fits the
## screen at every supported aspect ratio without scrolling.
const OFFER_SIZE := 3

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Upgrade ids that could legally be offered right now.
##
## `unlocked_summons` is the list of spirit ids the player actually has. A
## summon upgrade for an unbonded species is filtered out here rather than
## hidden in the UI, so nothing downstream has to know the rule.
func available_ids(unlocked_summons: Array, taken: Dictionary = {}) -> Array:
	var out: Array = []
	for id in ENTRIES:
		var e: Dictionary = ENTRIES[id]
		if e["target"] == Target.SUMMON and not unlocked_summons.has(e["summon"]):
			continue
		if not bool(e.get("repeatable", true)) and taken.has(id):
			continue
		out.append(id)
	out.sort()
	return out


## Rolls one offer. Never repeats an id within the offer; returns fewer than
## OFFER_SIZE only when fewer than that many upgrades are legal at all.
func roll_offer(unlocked_summons: Array, taken: Dictionary = {}) -> Array:
	var pool := available_ids(unlocked_summons, taken)
	var offer: Array = []
	while offer.size() < OFFER_SIZE and not pool.is_empty():
		var index := _rng.randi() % pool.size()
		offer.append(pool[index])
		pool.remove_at(index)
	return offer


static func entry(id: StringName) -> Dictionary:
	var e: Dictionary = ENTRIES.get(id, {})
	if e.is_empty():
		return e
	# The amount is BALANCE, and balance lives in LEVEL1_BALANCE.json — never in
	# a behaviour script (CLAUDE.md). It sat in this table because the catalog
	# was written before there was anywhere else to put it, which meant the one
	# dial the owner asked to turn — "the power scaling. I need it just a little
	# bit slower" — was buried in code.
	var out := e.duplicate()
	out["amount"] = amount_of(id)
	return out


## The tuned magnitude for one upgrade, before any per-run stacking.
##
## `upgrade_scale` is a single multiplier over every entry, so the whole curve
## can be slowed in one number without re-tuning twelve of them; per-id entries
## in `upgrade_amounts` override the catalog's default outright.
static func amount_of(id: StringName) -> float:
	var e: Dictionary = ENTRIES.get(id, {})
	if e.is_empty():
		return 0.0
	var progression := Balance.progression()
	var amounts: Dictionary = progression.get("upgrade_amounts", {})
	var base := float(amounts.get(String(id), e.get("amount", 0.0)))
	return base * float(progression.get("upgrade_scale", 1.0))


static func title_of(id: StringName) -> String:
	return String(ENTRIES.get(id, {}).get("title", String(id)))


## The card's blurb, with the percentage filled in from the tuned amount rather
## than written out beside it. A hand-written "+15%" next to a value that lives
## somewhere else is a lie waiting to happen the first time the number moves.
static func text_of(id: StringName) -> String:
	var template := String(ENTRIES.get(id, {}).get("text", ""))
	if not template.contains("{pct}"):
		return template
	return template.replace("{pct}", str(int(round(amount_of(id) * 100.0))))
