class_name UpgradeEffects
extends RefCounted

## The multipliers every taken upgrade adds up to, and where they get applied.
##
## Kept as *multipliers held in one place* rather than by mutating the hero's
## and summons' data resources, for a reason the project has already been bitten
## by: those resources are shared `.tres` files loaded once. Editing
## `data/spirits/rune_hound.tres` in memory to grant +20% damage would carry
## that bonus into the NEXT run, and into every other summon of the same species
## in this one. A run-scoped table cannot leak.
##
## Everything reads through `multiplier()`, so a system that wants the current
## value asks at the point of use rather than caching a number that a later
## upgrade would invalidate.

## stat key -> accumulated multiplier. 1.0 means untouched.
var _hero: Dictionary = {}
var _weapon: Dictionary = {}
var _stability: Dictionary = {}
## spirit id -> {stat -> multiplier}
var _summons: Dictionary = {}

var _taken: Dictionary = {}
var _order: Array[StringName] = []


## Applies one upgrade by id. Unknown ids are ignored with a warning rather
## than crashing a run mid-level-up.
func take(id: StringName) -> bool:
	var e := UpgradeCatalog.entry(id)
	if e.is_empty():
		push_warning("UpgradeEffects: unknown upgrade '%s'" % id)
		return false

	var stat: StringName = e["stat"]
	var amount: float = float(e["amount"])
	match int(e["target"]):
		UpgradeCatalog.Target.HERO:
			_bump(_hero, stat, amount)
		UpgradeCatalog.Target.WEAPON:
			_bump(_weapon, stat, amount)
		UpgradeCatalog.Target.STABILITY:
			_bump(_stability, stat, amount)
		UpgradeCatalog.Target.SUMMON:
			var who: StringName = e["summon"]
			if not _summons.has(who):
				_summons[who] = {}
			_bump(_summons[who], stat, amount)

	_taken[id] = int(_taken.get(id, 0)) + 1
	_order.append(id)
	return true


## Additive stacking, not multiplicative.
##
## Three +20% damage upgrades give 1.6x here, where compounding would give
## 1.73x. Additive keeps the tenth upgrade as meaningful as the first and keeps
## a long run from running away — the standard choice for this genre, and the
## one that makes the numbers on the cards mean what they say.
func _bump(table: Dictionary, stat: StringName, amount: float) -> void:
	table[stat] = float(table.get(stat, 1.0)) + amount


func hero(stat: StringName) -> float:
	return float(_hero.get(stat, 1.0))


func weapon(stat: StringName) -> float:
	return float(_weapon.get(stat, 1.0))


func stability(stat: StringName) -> float:
	return float(_stability.get(stat, 1.0))


func summon(spirit_id: StringName, stat: StringName) -> float:
	var table: Dictionary = _summons.get(spirit_id, {})
	return float(table.get(stat, 1.0))


func taken() -> Dictionary:
	return _taken.duplicate()


func taken_count() -> int:
	return _order.size()


func history() -> Array[StringName]:
	return _order.duplicate()
