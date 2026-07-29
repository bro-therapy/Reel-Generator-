class_name RunResults
extends RefCounted

## What a finished run reports, and what survives it. Brief Phase 14.
##
## Both endings come here: victory and defeat both open a result state, exactly
## once, and restarting mints a clean RunState rather than reusing this one.

enum Outcome { VICTORY, DEFEAT }

signal opened(outcome: Outcome)

var outcome: Outcome = Outcome.DEFEAT
var clear_time_seconds := 0.0
var rooms_cleared := 0
var bonds: Array[String] = []
var is_open := false

var _opened_once := false

## Set to persist somewhere other than the SaveService autoload. Left null in
## the game; the acceptance harness injects its own, because a `--script` run
## has no autoloads bound and reaching for the global would abort the test.
var save_service: Node = null


func _save_service() -> Node:
	if save_service != null:
		return save_service
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/SaveService")
	return null


## Opens the result state. Latched: a boss defeat and a Stability wipe arriving
## together must not open two screens, which is the same class of bug as a boss
## that dies twice.
func open(result: Outcome, seconds: float, state: RunState = null) -> bool:
	if _opened_once:
		return false
	_opened_once = true
	is_open = true
	outcome = result
	clear_time_seconds = maxf(0.0, seconds)

	if state != null:
		for b in state.bonds:
			if b != null:
				bonds.append(String(b.id))

	# Only a win writes a clear time, and only if it beats the record.
	if result == Outcome.VICTORY:
		var save := _save_service()
		if save != null:
			save.record_clear_time(clear_time_seconds)
			for id in bonds:
				save.discover_starter(id)

	opened.emit(outcome)
	return true


func outcome_name() -> String:
	return "Victory" if outcome == Outcome.VICTORY else "Defeat"


## A fresh run. Deliberately returns a new object rather than resetting this one:
## brief Phase 14 asks that restarting creates a clean RunState, and reusing an
## object is how a stale relic list survives into the next run.
static func restart(weapon: FocusWeaponData = null) -> RunState:
	return RunState.new(weapon)
