class_name EnemyStateMachine
extends Node

## Enemy state graph (master guide §15):
##
##     SPAWN -> SEEK -> WINDUP -> ATTACK -> RECOVER -> SEEK
##     any state -> STAGGER or DEATH
##
## DEATH is terminal. STAGGER always returns to SEEK. As with the summon graph,
## illegal edges are rejected and counted rather than silently taken.

signal state_changed(to: State, from: State)

enum State { SPAWN, SEEK, WINDUP, ATTACK, RECOVER, STAGGER, DEATH }

const STATE_NAMES := {
	State.SPAWN: "SPAWN", State.SEEK: "SEEK", State.WINDUP: "WINDUP",
	State.ATTACK: "ATTACK", State.RECOVER: "RECOVER",
	State.STAGGER: "STAGGER", State.DEATH: "DEATH",
}

const TRANSITIONS := {
	State.SPAWN: [State.SEEK],
	State.SEEK: [State.WINDUP],
	# A target lost mid-windup drops back to seeking rather than swinging at air.
	State.WINDUP: [State.ATTACK, State.SEEK],
	State.ATTACK: [State.RECOVER],
	State.RECOVER: [State.SEEK],
	State.STAGGER: [State.SEEK],
	State.DEATH: [],
}

var state: State = State.SPAWN
var time_in_state := 0.0
var illegal_attempts := 0
var warn_on_illegal := true


func tick(delta: float) -> void:
	time_in_state += delta


func can_transition(to: State) -> bool:
	if state == State.DEATH:
		return false
	if to == State.DEATH:
		return true
	if to == State.STAGGER:
		return state != State.STAGGER
	var allowed: Array = TRANSITIONS.get(state, [])
	return allowed.has(to)


func transition_to(to: State) -> bool:
	if to == state:
		return false
	if not can_transition(to):
		illegal_attempts += 1
		if warn_on_illegal:
			push_warning("EnemyStateMachine: illegal %s -> %s" % [name_of(state), name_of(to)])
		return false
	var from := state
	state = to
	time_in_state = 0.0
	state_changed.emit(to, from)
	return true


## Death outranks everything, including a windup already in progress. This is
## what makes "windup can be cancelled by death" true by construction.
func kill() -> bool:
	return transition_to(State.DEATH)


func is_dead() -> bool:
	return state == State.DEATH


func is_attacking_cycle() -> bool:
	return state == State.WINDUP or state == State.ATTACK or state == State.RECOVER


static func name_of(s: State) -> String:
	return String(STATE_NAMES.get(s, "UNKNOWN"))


func state_name() -> String:
	return name_of(state)
