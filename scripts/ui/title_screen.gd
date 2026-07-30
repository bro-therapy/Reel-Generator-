class_name TitleScreen
extends Control

## The start screen. Guide §13's menu surface, minus the settings pages.
##
## Godot-native Control nodes throughout — CLAUDE.md is explicit that UI is not
## custom-drawn, and the generated UI mockups in the package are reference art,
## not interactive menus.
##
## Layout is proportional, for the same reason the HUD's is: the project targets
## 1920x1080 but has to survive being resized, and the Phase 13 lesson was that a
## fixed-pixel menu cannot stay inside a percentage-defined safe area across four
## aspect ratios. Everything here is anchored or measured, never placed at a
## literal pixel.

signal start_requested()
signal quit_requested()

## Kept out of the scene file so the buttons and their order live in one readable
## place. Continue is absent on purpose — there is no mid-run save to continue
## from yet, and a button that does nothing is worse than a button that is missing.
const BUTTONS := [
	{"id": &"start", "text": "Begin the Climb"},
	{"id": &"quit", "text": "Quit"},
]

var _buttons: Array[Button] = []
var _title: Label
var _subtitle: Label
var _hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	# The first button takes focus immediately. Guide §17 requires the whole game
	# be playable on a controller, and a menu that opens with nothing focused is a
	# dead end for anyone not holding a mouse.
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The palette's deep indigo. Violet is the player's colour and this is the
	# player's screen.
	bg.color = Color(0.055, 0.043, 0.11)
	add_child(bg)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "PROJECT ZERO CLIMB"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color(0.86, 0.82, 1.0))
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = "Sunfall Ward"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(0.55, 0.5, 0.72))
	column.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	column.add_child(spacer)

	for entry in BUTTONS:
		var b := Button.new()
		b.name = "Button_%s" % entry["id"]
		b.text = entry["text"]
		b.custom_minimum_size = Vector2(320, 56)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_pressed.bind(entry["id"]))
		column.add_child(b)
		_buttons.append(b)

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 30)
	column.add_child(tail)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "WASD move   ·   Space dash   ·   hold fire   ·   Esc pause   ·   F3 debug"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.45, 0.42, 0.56))
	column.add_child(_hint)

	# An assetless checkout is a supported state; say so here rather than letting
	# the player discover it as invisible actors.
	var missing := AssetCheck.missing_groups()
	if not missing.is_empty():
		var warn := Label.new()
		warn.name = "AssetWarning"
		warn.text = "art not installed (%s) — see docs/ASSET_DELIVERY.md" % ", ".join(missing)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 14)
		warn.add_theme_color_override("font_color", Color(0.9, 0.62, 0.35))
		column.add_child(warn)


func _on_pressed(id: StringName) -> void:
	match id:
		&"start":
			start_requested.emit()
		&"quit":
			quit_requested.emit()


## Enter or Space activates the focused button even when focus came from a
## controller. Godot's default only does this for ui_accept on some themes.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null:
			focused.emit_signal("pressed")
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ inspection

func button_count() -> int:
	return _buttons.size()


func buttons() -> Array[Button]:
	return _buttons


func focused_index() -> int:
	var owner_node := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for i in _buttons.size():
		if _buttons[i] == owner_node:
			return i
	return -1


## Every button reachable by keyboard alone. Guide §17: no focus traps.
func focus_chain_is_complete() -> bool:
	if _buttons.is_empty():
		return false
	for b in _buttons:
		if b.focus_mode == Control.FOCUS_NONE:
			return false
	return true


func press(id: StringName) -> bool:
	for i in BUTTONS.size():
		if BUTTONS[i]["id"] == id:
			_buttons[i].emit_signal("pressed")
			return true
	return false
