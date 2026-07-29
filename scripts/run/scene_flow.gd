extends Node

## Autoload. Boot, menu, run, results transitions.
##
## Keeps the debug overlay alive across scene changes so it can be toggled
## anywhere, which Phase 0 acceptance requires.

signal state_changed(new_state: State)

enum State { BOOT, MENU, RUN, RESULTS }

const DEBUG_OVERLAY_SCENE := preload("res://scenes/ui/debug_overlay.tscn")

var state: State = State.BOOT

var _debug_overlay: CanvasLayer


func _ready() -> void:
	# Overlay lives on the autoload so it survives scene changes.
	_debug_overlay = DEBUG_OVERLAY_SCENE.instantiate()
	add_child(_debug_overlay)
	_debug_overlay.visible = bool(GameSettings.get_setting("debug_overlay_visible"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay_toggle"):
		toggle_debug_overlay()
		get_viewport().set_input_as_handled()


func toggle_debug_overlay() -> bool:
	return set_debug_overlay_visible(not is_debug_overlay_visible())


func set_debug_overlay_visible(value: bool) -> bool:
	if _debug_overlay != null:
		_debug_overlay.visible = value
	GameSettings.set_setting("debug_overlay_visible", value)
	return value


func is_debug_overlay_visible() -> bool:
	return _debug_overlay != null and _debug_overlay.visible


func debug_overlay() -> CanvasLayer:
	return _debug_overlay


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


func goto_scene(path: String, new_state: State) -> void:
	set_state(new_state)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneFlow: failed to change to %s (err %d)" % [path, err])
