class_name RunState
extends RefCounted

## Everything one run owns: Bond slots, the Focus Weapon, relics and currency.
##
## Deliberately a RefCounted rather than an autoload — CLAUDE.md allows only
## GameSettings, SaveService and SceneFlow to be global, and a run's inventory
## must not outlive the run. SceneFlow holds the live one; tests construct
## their own.

## Master guide §4: three Bond slots, and the slice never offers a fourth.
const BOND_SLOTS := 3

signal bonded(spirit_id: StringName, slot: int)
signal evolved(spirit_id: StringName, tier: int)
signal currency_changed(total: int)
signal relic_gained(relic_id: StringName)
signal stability_changed(value: int)
## Emitted once when Stability reaches zero. Guide §7: zero ends the run.
signal run_failed()

## One entry per slot. Empty slots hold null so slot indices stay stable.
var bonds: Array[SpiritData] = [null, null, null]
## Evolution tier per bonded spirit id: 0 Bound, 1 Awakened, 2 Ascendant.
var tiers: Dictionary = {}
var focus_weapon: FocusWeaponData
var relics: Array[StringName] = []
var currency: int = 0

## How many reward screens the player has resolved. Drives the pity rules.
var rewards_taken: int = 0
## Set when the run reaches the Spirit Well (guide §6 cadence, ~5:00-6:00).
var reached_spirit_well: bool = false

## Guide §7. Every value comes from LEVEL1_BALANCE.json rather than being
## written here, so a balance pass does not need a code change.
var stability: int = 100
var max_stability: int = 100
## The Spirit Well's heal is once per run (guide §9 Space 3).
var well_heal_used: bool = false
var _failed := false


func _init(weapon: FocusWeaponData = null) -> void:
	focus_weapon = weapon
	var block := Balance.stability()
	max_stability = int(block.get("start", 100))
	stability = max_stability


# ---------------------------------------------------------------- stability

## Adds or removes Stability, clamped to 0..max. Returns the new value.
##
## Clamping here rather than at the call sites is deliberate: Phase 12 requires
## that Stability can never exceed 100 or drop below zero, and there are several
## sources — Rift entry, elite rewards, the Spirit Well — that would each have to
## remember to clamp.
func adjust_stability(delta: int) -> int:
	var before := stability
	stability = clampi(stability + delta, 0, max_stability)
	if stability != before:
		stability_changed.emit(stability)
	if stability == 0 and not _failed:
		_failed = true
		run_failed.emit()
	return stability


func stability_is_spent() -> bool:
	return stability <= 0


# ---------------------------------------------------------------- bond slots

func filled_slot_count() -> int:
	var n := 0
	for b in bonds:
		if b != null:
			n += 1
	return n


func has_empty_slot() -> bool:
	return filled_slot_count() < BOND_SLOTS


func first_empty_slot() -> int:
	for i in bonds.size():
		if bonds[i] == null:
			return i
	return -1


func is_bonded(spirit_id: StringName) -> bool:
	for b in bonds:
		if b != null and b.id == spirit_id:
			return true
	return false


func bonded_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for b in bonds:
		if b != null:
			out.append(b.id)
	return out


func spirit(spirit_id: StringName) -> SpiritData:
	for b in bonds:
		if b != null and b.id == spirit_id:
			return b
	return null


## Bonds a spirit into the first empty slot. Returns the slot, or -1 if the
## team is full or the spirit is already bonded — the slice never runs a
## fourth summon, and a duplicate arrives as an Echo instead.
func bond(data: SpiritData) -> int:
	if data == null or is_bonded(data.id) or not has_empty_slot():
		return -1
	var slot := first_empty_slot()
	# GDScript indexes arrays from the end for negatives, so a -1 here would
	# quietly overwrite the last slot instead of failing. Refuse it outright.
	if slot < 0:
		return -1
	bonds[slot] = data
	tiers[data.id] = 0
	bonded.emit(data.id, slot)
	return slot


# ---------------------------------------------------------------- evolution

func tier_of(spirit_id: StringName) -> int:
	return int(tiers.get(spirit_id, 0))


func can_evolve(spirit_id: StringName) -> bool:
	var data := spirit(spirit_id)
	if data == null:
		return false
	return tier_of(spirit_id) < data.max_form_index()


## Consumes an Echo: advances one tier. Returns the new tier, or -1 if the
## spirit is not bonded or is already Ascendant.
func apply_echo(spirit_id: StringName) -> int:
	if not can_evolve(spirit_id):
		return -1
	var next := tier_of(spirit_id) + 1
	tiers[spirit_id] = next
	evolved.emit(spirit_id, next)
	return next


## True when every bonded summon is at its final form. Guide §6 pity rule:
## from here Echo offers are replaced by relics or Focus upgrades.
func all_bonds_maxed() -> bool:
	if filled_slot_count() == 0:
		return false
	for b in bonds:
		if b != null and tier_of(b.id) < b.max_form_index():
			return false
	return true


## Bonded spirits that could still take an Echo.
func evolvable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for b in bonds:
		if b != null and can_evolve(b.id):
			out.append(b.id)
	return out


# ---------------------------------------------------------------- inventory

func add_currency(amount: int) -> int:
	currency = maxi(0, currency + amount)
	currency_changed.emit(currency)
	return currency


func spend_currency(amount: int) -> bool:
	if amount <= 0 or currency < amount:
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true


func add_relic(relic_id: StringName) -> bool:
	if relic_id == &"" or relics.has(relic_id):
		return false
	relics.append(relic_id)
	relic_gained.emit(relic_id)
	return true


func has_relic(relic_id: StringName) -> bool:
	return relics.has(relic_id)
