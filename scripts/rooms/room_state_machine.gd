class_name RoomStateMachine
extends Node

## Room lifecycle (build brief Phase 6):
##
##     INACTIVE -> INTRO -> LOCKED -> WAVES -> CLEARING -> REWARD -> COMPLETE
##
## Strictly forward. A room cannot re-lock, re-reward, or reopen a wave, which is
## what keeps "reward appears once" and "exit never remains locked" true by
## construction rather than by careful sequencing.

signal state_changed(to: State, from: State)

enum State { INACTIVE, INTRO, LOCKED, WAVES, CLEARING, REWARD, COMPLETE }

const STATE_NAMES := {
	State.INACTIVE: "INACTIVE", State.INTRO: "INTRO", State.LOCKED: "LOCKED",
	State.WAVES: "WAVES", State.CLEARING: "CLEARING", State.REWARD: "REWARD",
	State.COMPLETE: "COMPLETE",
}

const ORDER := [State.INACTIVE, State.INTRO, State.LOCKED, State.WAVES, State.CLEARING, State.REWARD, State.COMPLETE]

var state: State = State.INACTIVE
var time_in_state := 0.0
var illegal_attempts := 0
var warn_on_illegal := true


func tick(delta: float) -> void:
	time_in_state += delta


## Only the immediate next state is legal — no skipping, no going back.
func can_transition(to: State) -> bool:
	var here := ORDER.find(state)
	var there := ORDER.find(to)
	return there == here + 1


func transition_to(to: State) -> bool:
	if to == state:
		return false
	if not can_transition(to):
		illegal_attempts += 1
		if warn_on_illegal:
			push_warning("RoomStateMachine: illegal %s -> %s" % [name_of(state), name_of(to)])
		return false
	var from := state
	state = to
	time_in_state = 0.0
	state_changed.emit(to, from)
	return true


func advance() -> bool:
	var here := ORDER.find(state)
	if here < 0 or here + 1 >= ORDER.size():
		return false
	return transition_to(ORDER[here + 1])


func is_at_least(other: State) -> bool:
	return ORDER.find(state) >= ORDER.find(other)


func is_complete() -> bool:
	return state == State.COMPLETE


static func name_of(s: State) -> String:
	return String(STATE_NAMES.get(s, "UNKNOWN"))


func state_name() -> String:
	return name_of(state)
