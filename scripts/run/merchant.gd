class_name Merchant
extends RefCounted

## The Spirit Well's shop. Guide §9 Space 3 and brief Phase 9.
##
##   - heal 20% of max HP, once per run
##   - restore 15 Stability for 35 currency
##   - five offers, one purchase each
##   - first reroll free, then 15 / 25 / 40
##   - one offer can be locked and survives a reroll
##
## Every price and amount comes from LEVEL1_BALANCE.json where the file has one.
## The reroll ladder does not exist there, so it is a constant here and the
## acceptance test asserts it against the brief rather than against this file.

signal offers_changed()
signal purchased(index: int, offer: Offer)
signal rerolled(cost: int, remaining_free: int)

## Brief Phase 9: "One free reroll, then 15/25/40."
const REROLL_COSTS := [0, 15, 25, 40]
const OFFER_COUNT := 5
## Guide §9: the well heals a fifth of the hero's health, once.
const HEAL_FRACTION := 0.20


class Offer:
	var id: StringName
	var title: String
	var description: String
	var price: int
	var kind: RewardCard.Kind
	var sold: bool = false
	var locked: bool = false

	func _init(p_id: StringName, p_title: String, p_text: String, p_price: int, p_kind: RewardCard.Kind) -> void:
		id = p_id
		title = p_title
		description = p_text
		price = p_price
		kind = p_kind

	func affordable(currency: int) -> bool:
		return not sold and currency >= price

	## Why the offer cannot be taken, for the UI to show. Empty when it can.
	func blocked_reason(currency: int) -> String:
		if sold:
			return "Sold"
		if currency < price:
			return "Need %d" % price
		return ""


var offers: Array[Offer] = []
var rerolls_used: int = 0
var rng := RandomNumberGenerator.new()

var _state: RunState
var _catalog: Array = []


func _init(state: RunState, seed_value: int = 0) -> void:
	_state = state
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_build_catalog()
	offers = _roll_offers([])


func _build_catalog() -> void:
	# Stock is drawn from the same relic pools the reward screen uses, so an item
	# means the same thing wherever the player meets it.
	_catalog.clear()
	for entry in RewardSystem.SUMMON_RELICS:
		_catalog.append({"id": entry["id"], "title": entry["title"], "text": entry["text"], "price": 55, "kind": RewardCard.Kind.SUMMON_RELIC})
	for entry in RewardSystem.GENERAL_RELICS:
		_catalog.append({"id": entry["id"], "title": entry["title"], "text": entry["text"], "price": 45, "kind": RewardCard.Kind.GENERAL_RELIC})
	for entry in RewardSystem.FOCUS_UPGRADES:
		_catalog.append({"id": entry["id"], "title": entry["title"], "text": entry["text"], "price": 60, "kind": RewardCard.Kind.FOCUS_UPGRADE})


func _roll_offers(keep: Array[Offer]) -> Array[Offer]:
	var out: Array[Offer] = []
	var used: Array = []
	for o in keep:
		out.append(o)
		used.append(o.id)

	var pool: Array = []
	for entry in _catalog:
		# Never stock something already owned, and never the same item twice.
		if _state != null and _state.has_relic(entry["id"]):
			continue
		if used.has(entry["id"]):
			continue
		pool.append(entry)

	while out.size() < OFFER_COUNT and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		var entry: Dictionary = pool[i]
		pool.remove_at(i)
		out.append(Offer.new(entry["id"], entry["title"], entry["text"], int(entry["price"]), entry["kind"]))

	# A thin stock still has to fill the counter, or the screen has holes in it.
	while out.size() < OFFER_COUNT:
		var n := out.size()
		out.append(Offer.new(
			&"spirit_salts_%d" % n,
			"Spirit Salts",
			"A restorative draught. Restores a little Stability.",
			20,
			RewardCard.Kind.RECOVERY,
		))
	return out


# ---------------------------------------------------------------- purchasing

func next_reroll_cost() -> int:
	if rerolls_used >= REROLL_COSTS.size():
		return REROLL_COSTS[REROLL_COSTS.size() - 1]
	return int(REROLL_COSTS[rerolls_used])


func can_reroll() -> bool:
	return _state != null and _state.currency >= next_reroll_cost()


## Rerolls the unlocked offers. The locked one is carried through untouched —
## that is the whole point of locking it.
func reroll() -> bool:
	if not can_reroll():
		return false
	var cost := next_reroll_cost()
	if cost > 0 and not _state.spend_currency(cost):
		return false

	var keep: Array[Offer] = []
	for o in offers:
		if o.locked:
			keep.append(o)

	rerolls_used += 1
	offers = _roll_offers(keep)
	rerolled.emit(cost, maxi(0, 1 - rerolls_used))
	offers_changed.emit()
	return true


## Only one offer can be held at a time; locking a second releases the first.
func set_locked(index: int, value: bool) -> bool:
	if index < 0 or index >= offers.size():
		return false
	if value:
		for o in offers:
			o.locked = false
	offers[index].locked = value
	offers_changed.emit()
	return true


func locked_index() -> int:
	for i in offers.size():
		if offers[i].locked:
			return i
	return -1


## Buys an offer. Returns false without charging if it cannot be bought.
##
## The sold flag is set before the currency leaves, and `affordable()` checks it,
## so a double-click or a repeated signal cannot charge twice for one selection —
## which is the first thing Phase 9 acceptance looks for.
func buy(index: int) -> bool:
	if index < 0 or index >= offers.size():
		return false
	var offer := offers[index]
	if not offer.affordable(_state.currency):
		return false

	offer.sold = true
	if not _state.spend_currency(offer.price):
		offer.sold = false
		return false

	if offer.kind == RewardCard.Kind.RECOVERY:
		_state.adjust_stability(int(Balance.stability().get("spirit_well_restore_amount", 15)))
	else:
		_state.add_relic(offer.id)

	purchased.emit(index, offer)
	offers_changed.emit()
	return true


# ---------------------------------------------------------------- well services

func heal_cost() -> int:
	return 0


func can_heal() -> bool:
	return _state != null and not _state.well_heal_used


## Returns the HP restored, or 0 when the well has already been used.
func heal(current_hp: int, max_hp: int) -> int:
	if not can_heal():
		return 0
	_state.well_heal_used = true
	var amount := int(round(float(max_hp) * HEAL_FRACTION))
	return mini(amount, maxi(0, max_hp - current_hp))


func stability_price() -> int:
	return int(Balance.stability().get("spirit_well_restore_cost_currency", 35))


func stability_amount() -> int:
	return int(Balance.stability().get("spirit_well_restore_amount", 15))


func can_buy_stability() -> bool:
	return _state != null and _state.currency >= stability_price() and _state.stability < _state.max_stability


func buy_stability() -> bool:
	if not can_buy_stability():
		return false
	if not _state.spend_currency(stability_price()):
		return false
	_state.adjust_stability(stability_amount())
	return true
