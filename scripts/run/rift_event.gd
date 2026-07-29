class_name RiftEvent
extends RefCounted

## The optional Rift: protect a fragile Spirit Core for 45 seconds.
##
## Guide §9 and brief Phase 10:
##   - entry costs 10 Stability
##   - the reward category is previewed before entry
##   - failure ejects the player at one HP, with no reward, Stability still spent
##   - success grants a rare Echo
##
## Deliberately a plain object with an explicit `tick()` rather than a Node with
## `_process`: the resolution rules are the part that must be right, and they are
## far easier to prove at 45 seconds a step than in real time.

signal core_damaged(health: int)
signal succeeded()
signal failed()
signal ejected(at_hp: int)

enum State { PREVIEW, ACTIVE, SUCCESS, FAILURE }

## Guide §9: "protect a fragile Spirit Core for 45 seconds".
const DURATION_SECONDS := 45.0
const CORE_MAX_HEALTH := 100
## Brief: "Failure ejects player with one HP".
const EJECT_HP := 1

var state: State = State.PREVIEW
var time_left: float = DURATION_SECONDS
var core_health: int = CORE_MAX_HEALTH
var reward_granted: bool = false
var stability_spent: bool = false

var _run: RunState
var _resolved := false


func _init(run: RunState) -> void:
	_run = run
	reset()


## Puts the event back to its pre-entry state. Brief Phase 10 requires timer,
## core health and reward state to reset on a new run.
func reset() -> void:
	state = State.PREVIEW
	time_left = DURATION_SECONDS
	core_health = CORE_MAX_HEALTH
	reward_granted = false
	stability_spent = false
	_resolved = false


static func entry_cost() -> int:
	return int(Balance.stability().get("rift_entry_cost", 10))


## What the player is told they are playing for, before they commit. Guide §9:
## "rare Echo with a visible category preview before entry."
func reward_preview() -> String:
	return "Rare Echo"


func can_enter() -> bool:
	# Entering at or below the cost would end the run on the doorstep, which is
	# not a choice — it is a trap.
	return state == State.PREVIEW and _run != null and _run.stability > entry_cost()


## Pays the Stability and starts the clock.
func enter() -> bool:
	if not can_enter():
		return false
	_run.adjust_stability(-entry_cost())
	stability_spent = true
	state = State.ACTIVE
	return true


func damage_core(amount: int) -> int:
	if state != State.ACTIVE or amount <= 0:
		return core_health
	core_health = maxi(0, core_health - amount)
	core_damaged.emit(core_health)
	if core_health == 0:
		_resolve(false)
	return core_health


## Advances the clock. Returns true while the event is still running.
func tick(delta: float) -> bool:
	if state != State.ACTIVE:
		return false
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_resolve(true)
		return false
	return true


func _resolve(won: bool) -> void:
	# Once only: a core destroyed on the same frame the timer expires must not
	# both grant and deny the reward.
	if _resolved:
		return
	_resolved = true
	state = State.SUCCESS if won else State.FAILURE
	if won:
		succeeded.emit()
	else:
		failed.emit()


## The Echo the player earned, or null. Only ever returns something once, and
## only on a win.
func claim_reward(catalog: Array) -> RewardCard:
	if state != State.SUCCESS or reward_granted:
		return null
	var evolvable := _run.evolvable_ids()
	if evolvable.is_empty():
		return null
	reward_granted = true

	var id: StringName = evolvable[0]
	var data := _run.spirit(id)
	var next_form := data.form(_run.tier_of(id) + 1)
	var card := RewardCard.make(
		RewardCard.Kind.ECHO,
		RewardCard.Rarity.RARE,
		"Echo: %s" % (next_form.display_name if next_form != null else data.display_name),
		next_form.passive_description if next_form != null else "",
	)
	card.spirit = data
	return card


## What the player leaves with. Failure ejects at one HP; success leaves health
## alone. Either way the Stability stays spent and the route stays open — brief
## Phase 10: "Player cannot be trapped after failure."
func exit_hp(current_hp: int) -> int:
	if state == State.FAILURE:
		return EJECT_HP
	return current_hp


func eject(current_hp: int) -> int:
	var hp := exit_hp(current_hp)
	ejected.emit(hp)
	return hp
