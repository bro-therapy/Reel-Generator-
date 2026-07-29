class_name RewardSystem
extends RefCounted

## Builds three-card offers. Guide §6 "Reward card categories", "Prototype
## rarity" and "Pity rules".
##
## Every pity rule in the guide is enforced here rather than in the UI, so the
## screen only has to render whatever it is handed:
##
##   1. By the second reward, offer a missing summon if a Bond slot is empty.
##   2. By the Spirit Well, offer an Echo for an equipped summon.
##   3. Never show three unusable cards.
##   4. Never offer a fourth summon.
##   5. When every bond is Ascendant, Echo offers become relics or Focus
##      upgrades instead.
##
## Rules 1 and 2 are *floors*, not schedules — an offer may contain a summon
## earlier. What the rule guarantees is that it cannot still be missing by then.

const CARDS_PER_OFFER := 3

## Relic names are slice content, not balance. They carry no numbers yet; Phase
## 7 only has to prove the list exists and fills. Effects land with their phases.
const SUMMON_RELICS := [
	{"id": &"storm_hunt_sigil", "title": "Storm Hunt Sigil", "text": "The team's melee strikes leave a lingering charge."},
	{"id": &"crossfire_oath", "title": "Crossfire Oath", "text": "Blades passing through friendly fire carry it onward."},
	{"id": &"guardian_circuit", "title": "Guardian Circuit", "text": "Constructs steady themselves while a blade covers them."},
]

const GENERAL_RELICS := [
	{"id": &"exiles_ledger", "title": "Exile's Ledger", "text": "Records the climb. Currency finds you more often."},
	{"id": &"cracked_hourglass", "title": "Cracked Hourglass", "text": "Dashes recover a little sooner."},
	{"id": &"ward_lantern", "title": "Ward Lantern", "text": "Hostile telegraphs read a fraction longer."},
]

const FOCUS_UPGRADES = [
	{"id": &"focus_channel_bore", "title": "Channel Bore", "text": "The Conjurer Staff bolt punches a little deeper."},
	{"id": &"focus_split_prism", "title": "Split Prism", "text": "The staff's bolt fractures on impact."},
]

var rng := RandomNumberGenerator.new()

## Every starter the slice can offer. Guide §5 locks this to three.
var catalog: Array[SpiritData] = []


func _init(starters: Array[SpiritData] = [], seed_value: int = 0) -> void:
	catalog = starters
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## The three cards for the next reward screen.
func build_offer(state: RunState) -> Array[RewardCard]:
	var cards: Array[RewardCard] = []
	if state == null:
		return cards

	# ---- pity floors, taken first so they cannot be crowded out -------------
	if _summon_pity_due(state):
		var summon := _make_summon_card(state)
		if summon != null:
			cards.append(summon)

	if _echo_pity_due(state):
		var echo := _make_echo_card(state)
		if echo != null:
			cards.append(echo)

	# ---- fill the rest from the weighted pool ------------------------------
	var guard := 0
	while cards.size() < CARDS_PER_OFFER and guard < 64:
		guard += 1
		var card := _roll_card(state, cards)
		if card != null:
			cards.append(card)

	# Pool exhausted (every relic owned, team full and maxed). Recovery always
	# applies, so it is the backstop that keeps an offer from coming up short.
	while cards.size() < CARDS_PER_OFFER:
		cards.append(_make_recovery_card())

	# ---- rule 3: never three unusable cards --------------------------------
	if not _any_usable(cards, state):
		cards[cards.size() - 1] = _make_recovery_card()

	return cards


## Resolves a taken card and advances the reward counter.
func take(state: RunState, card: RewardCard) -> bool:
	if state == null or card == null:
		return false
	var applied := card.apply(state)
	state.rewards_taken += 1
	return applied


# ---------------------------------------------------------------- pity rules

## Rule 1. `rewards_taken` counts *resolved* offers, so the offer the player is
## about to see is number `rewards_taken + 1`; the floor bites from the second.
func _summon_pity_due(state: RunState) -> bool:
	return state.rewards_taken + 1 >= 2 and state.has_empty_slot() and not _missing_starters(state).is_empty()


## Rule 2, narrowed by rule 5 — once everything is Ascendant there is no Echo
## to offer and the pool sends relics instead.
func _echo_pity_due(state: RunState) -> bool:
	return state.reached_spirit_well and not state.all_bonds_maxed() and not state.evolvable_ids().is_empty()


func _missing_starters(state: RunState) -> Array[SpiritData]:
	var out: Array[SpiritData] = []
	for s in catalog:
		if s != null and not state.is_bonded(s.id):
			out.append(s)
	return out


# ---------------------------------------------------------------- generation

func _roll_card(state: RunState, taken: Array[RewardCard]) -> RewardCard:
	var kinds: Array[int] = []

	# Rule 4: a summon card only exists while a slot is open and one is missing.
	if state.has_empty_slot() and not _missing_starters(state).is_empty() and not _has_kind(taken, RewardCard.Kind.SUMMON):
		kinds.append(RewardCard.Kind.SUMMON)
	# Rule 5: no Echo cards once every bond is maxed.
	if not state.evolvable_ids().is_empty() and not _has_kind(taken, RewardCard.Kind.ECHO):
		kinds.append(RewardCard.Kind.ECHO)
	if state.filled_slot_count() > 0 and not _unowned(SUMMON_RELICS, state).is_empty():
		kinds.append(RewardCard.Kind.SUMMON_RELIC)
	if not _unowned(GENERAL_RELICS, state).is_empty():
		kinds.append(RewardCard.Kind.GENERAL_RELIC)
	if state.focus_weapon != null and not _unowned(FOCUS_UPGRADES, state).is_empty():
		kinds.append(RewardCard.Kind.FOCUS_UPGRADE)
	kinds.append(RewardCard.Kind.RECOVERY)

	var pick: int = kinds[rng.randi_range(0, kinds.size() - 1)]
	match pick:
		RewardCard.Kind.SUMMON:
			return _make_summon_card(state)
		RewardCard.Kind.ECHO:
			return _make_echo_card(state)
		RewardCard.Kind.SUMMON_RELIC:
			return _make_relic_card(RewardCard.Kind.SUMMON_RELIC, SUMMON_RELICS, state)
		RewardCard.Kind.GENERAL_RELIC:
			return _make_relic_card(RewardCard.Kind.GENERAL_RELIC, GENERAL_RELICS, state)
		RewardCard.Kind.FOCUS_UPGRADE:
			return _make_relic_card(RewardCard.Kind.FOCUS_UPGRADE, FOCUS_UPGRADES, state)
		_:
			return _make_recovery_card()


func _make_summon_card(state: RunState) -> RewardCard:
	var missing := _missing_starters(state)
	if missing.is_empty():
		return null
	var data: SpiritData = missing[rng.randi_range(0, missing.size() - 1)]
	var card := RewardCard.make(
		RewardCard.Kind.SUMMON,
		RewardCard.Rarity.UNCOMMON,
		"Bond: %s" % data.display_name,
		data.temperament if data.temperament != "" else "A spirit answers the staff.",
	)
	card.spirit = data
	return card


func _make_echo_card(state: RunState) -> RewardCard:
	var ids := state.evolvable_ids()
	if ids.is_empty():
		return null
	var id: StringName = ids[rng.randi_range(0, ids.size() - 1)]
	var data := state.spirit(id)
	var next_form := data.form(state.tier_of(id) + 1)
	var name_text: String = next_form.display_name if next_form != null else data.display_name
	var card := RewardCard.make(
		RewardCard.Kind.ECHO,
		RewardCard.Rarity.RARE,
		"Echo: %s" % name_text,
		next_form.passive_description if next_form != null else "",
	)
	card.spirit = data
	return card


func _make_relic_card(kind: RewardCard.Kind, pool: Array, state: RunState) -> RewardCard:
	var options := _unowned(pool, state)
	if options.is_empty():
		return null
	var entry: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	var rarity: RewardCard.Rarity = RewardCard.Rarity.UNCOMMON if kind == RewardCard.Kind.SUMMON_RELIC else RewardCard.Rarity.COMMON
	var card := RewardCard.make(kind, rarity, String(entry["title"]), String(entry["text"]))
	card.relic_id = entry["id"]
	return card


func _make_recovery_card() -> RewardCard:
	var amount := rng.randi_range(15, 40)
	var card := RewardCard.make(
		RewardCard.Kind.RECOVERY,
		RewardCard.Rarity.COMMON,
		"Salvage",
		"Recovered currency from the ward.",
	)
	card.currency_amount = amount
	return card


# ---------------------------------------------------------------- helpers

func _unowned(pool: Array, state: RunState) -> Array:
	var out: Array = []
	for entry in pool:
		if not state.has_relic(entry["id"]):
			out.append(entry)
	return out


func _has_kind(cards: Array[RewardCard], kind: RewardCard.Kind) -> bool:
	for c in cards:
		if c != null and c.kind == kind:
			return true
	return false


func _any_usable(cards: Array[RewardCard], state: RunState) -> bool:
	for c in cards:
		if c != null and c.is_usable(state):
			return true
	return false
