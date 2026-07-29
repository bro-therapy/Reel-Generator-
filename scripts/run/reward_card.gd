class_name RewardCard
extends RefCounted

## One card in a three-card offer. Guide §6 lists six categories and three
## rarities.
##
## A card is generated from the run's state rather than authored, so it always
## knows whether it can actually be taken — `is_usable()` is what the "never
## show three unusable cards" pity rule is checked against.

enum Kind { SUMMON, ECHO, FOCUS_UPGRADE, SUMMON_RELIC, GENERAL_RELIC, RECOVERY }
enum Rarity { COMMON, UNCOMMON, RARE }

## Guide §6 prototype rarity weights.
const RARITY_WEIGHTS := {Rarity.COMMON: 60, Rarity.UNCOMMON: 30, Rarity.RARE: 10}

var kind: Kind = Kind.RECOVERY
var rarity: Rarity = Rarity.COMMON
var title: String = ""
var description: String = ""

## Set for SUMMON and ECHO cards.
var spirit: SpiritData
## Set for the two relic kinds.
var relic_id: StringName = &""
## Set for RECOVERY.
var currency_amount: int = 0


static func make(
	card_kind: Kind,
	card_rarity: Rarity,
	card_title: String,
	card_description: String,
) -> RewardCard:
	var c := RewardCard.new()
	c.kind = card_kind
	c.rarity = card_rarity
	c.title = card_title
	c.description = card_description
	return c


## Whether taking this card would actually change anything.
##
## This is the predicate behind the "never three unusable cards" rule, so it is
## strict: a summon offer with the team full is unusable, and an Echo for an
## Ascendant summon is unusable, even though both would render fine.
func is_usable(state: RunState) -> bool:
	if state == null:
		return false
	match kind:
		Kind.SUMMON:
			return spirit != null and not state.is_bonded(spirit.id) and state.has_empty_slot()
		Kind.ECHO:
			return spirit != null and state.can_evolve(spirit.id)
		Kind.SUMMON_RELIC:
			return not state.has_relic(relic_id) and state.filled_slot_count() > 0
		Kind.GENERAL_RELIC:
			return not state.has_relic(relic_id)
		Kind.FOCUS_UPGRADE:
			return state.focus_weapon != null
		Kind.RECOVERY:
			return currency_amount > 0
	return false


## Applies the card. Returns false when it was not usable, leaving state alone.
func apply(state: RunState) -> bool:
	if not is_usable(state):
		return false
	match kind:
		Kind.SUMMON:
			return state.bond(spirit) >= 0
		Kind.ECHO:
			return state.apply_echo(spirit.id) >= 0
		Kind.SUMMON_RELIC, Kind.GENERAL_RELIC:
			return state.add_relic(relic_id)
		Kind.FOCUS_UPGRADE:
			state.add_relic(relic_id if relic_id != &"" else &"focus_upgrade")
			return true
		Kind.RECOVERY:
			state.add_currency(currency_amount)
			return true
	return false


func kind_name() -> String:
	match kind:
		Kind.SUMMON:
			return "Summon"
		Kind.ECHO:
			return "Echo"
		Kind.FOCUS_UPGRADE:
			return "Focus"
		Kind.SUMMON_RELIC:
			return "Summon Relic"
		Kind.GENERAL_RELIC:
			return "Relic"
		_:
			return "Recovery"


func rarity_name() -> String:
	match rarity:
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		_:
			return "Common"
