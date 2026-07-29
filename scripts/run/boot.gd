extends Node

## Phase 0 boot scene.
##
## Verifies the foundation loads: balance JSON parses, autoloads are alive,
## collision layers are named, and the input map is populated. Later phases
## replace this with the title screen.


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.BOOT)
	_report()


func _report() -> void:
	var player := Balance.player()
	print("[boot] Project Zero Climb — Phase 0 foundation")
	print("[boot] balance version: %s" % Balance.get_value("version", "MISSING"))
	print("[boot] hero move speed: %s u/s, dash %s u over %ss" % [
		player.get("move_speed_units_per_second", "?"),
		player.get("dash_distance_units", "?"),
		player.get("dash_duration_seconds", "?"),
	])
	print("[boot] input actions: %d" % _game_actions().size())
	print("[boot] debug overlay: press F3 (or controller Back) to toggle")

	# A checkout without assets is a supported state, not a broken one. Say so in
	# one paragraph rather than leaving Godot's 72 "Resource file not found" lines
	# as the only explanation for a game with nothing visible in it.
	var assets := AssetCheck.report()
	if assets != "":
		print(assets)


## Project-defined actions only — excludes Godot's built-in ui_* set.
static func _game_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			actions.append(action)
	return actions
