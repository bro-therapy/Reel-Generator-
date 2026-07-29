class_name SummonStateMachine
extends Node

## Summon state graph (build brief Phase 3):
##
##     FOLLOW -> ACQUIRE -> WINDUP -> ATTACK -> RECOVER -> FOLLOW
##     any state -> REFORM -> FOLLOW
##
## The graph is enforced here rather than trusted to callers, so an illegal
## transition is a loud warning instead of a silent behaviour bug.

signal state_changed(to: State, from: State)

enum State { FOLLOW, ACQUIRE, WINDUP, ATTACK, RECOVER, REFORM }

const STATE_NAMES := {
	State.FOLLOW: "FOLLOW",
	State.ACQUIRE: "ACQUIRE",
	State.WINDUP: "WINDUP",
	State.ATTACK: "ATTACK",
	State.RECOVER: "RECOVER",
	State.REFORM: "REFORM",
}

## Legal edges. REFORM is reachable from anywhere and is handled separately.
const TRANSITIONS := {
	State.FOLLOW: [State.ACQUIRE],
	# A target can be lost mid-acquire or mid-windup, which drops back to FOLLOW.
	State.ACQUIRE: [State.WINDUP, State.FOLLOW],
	State.WINDUP: [State.ATTACK, State.FOLLOW],
	State.ATTACK: [State.RECOVER],
	State.RECOVER: [State.FOLLOW],
	State.REFORM: [State.FOLLOW],
}

var state: State = State.FOLLOW
var time_in_state := 0.0
## Counts rejected transitions so tests can assert the graph was never violated.
var illegal_attempts := 0
## Acceptance tests deliberately probe illegal edges to prove the guard exists;
## they clear this so the expected rejections do not spam the log.
var warn_on_illegal := true


func tick(delta: float) -> void:
	time_in_state += delta


func can_transition(to: State) -> bool:
	if to == State.REFORM:
		return state != State.REFORM
	var allowed: Array = TRANSITIONS.get(state, [])
	return allowed.has(to)


## Returns true when the transition was legal and taken.
func transition_to(to: State) -> bool:
	if to == state:
		return false
	if not can_transition(to):
		illegal_attempts += 1
		if warn_on_illegal:
			push_warning("SummonStateMachine: illegal %s -> %s" % [name_of(state), name_of(to)])
		return false
	var from := state
	state = to
	time_in_state = 0.0
	state_changed.emit(to, from)
	return true


## REFORM is always reachable — it is the recovery path when a summon is
## separated from the hero, so it must not be blocked by the current state.
func force_reform() -> bool:
	return transition_to(State.REFORM)


func is_attacking_cycle() -> bool:
	return state == State.WINDUP or state == State.ATTACK or state == State.RECOVER


static func name_of(s: State) -> String:
	return String(STATE_NAMES.get(s, "UNKNOWN"))


func state_name() -> String:
	return name_of(state)
