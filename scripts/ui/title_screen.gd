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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# The first button takes focus immediately. Guide §17 requires the whole game
	# be playable on a controller, and a menu that opens with nothing focused is a
	# dead end for anyone not holding a mouse.
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


const KEY_ART := "res://assets/ui/title_key_art.png"


func _build() -> void:
	# Key art behind everything. Generated for this project (anime key visual of
	# the Tower Exile with all three summons in Sunfall Ward) and installed by
	# tools/fetch_free_assets.sh, so a checkout without it still gets a readable
	# menu rather than a broken one.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.043, 0.11)
	add_child(bg)

	var art_path := "res://assets/ui/title_key_art.png"
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.name = "KeyArt"
		art.texture = load(art_path) as Texture2D
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		# COVER, not STRETCH: the art is 16:9 and the window may not be, and a
		# stretched hero is worse than a cropped background.
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(art)

		# Scrim: the art is bright warm sandstone and the buttons are light text.
		# A vertical gradient keeps the hero visible up top while giving the menu
		# something dark to sit on.
		var scrim := TextureRect.new()
		scrim.name = "Scrim"
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scrim.stretch_mode = TextureRect.STRETCH_SCALE
		var grad := Gradient.new()
		grad.set_color(0, Color(0.03, 0.02, 0.07, 0.15))
		grad.set_color(1, Color(0.03, 0.02, 0.07, 0.92))
		var grad_tex := GradientTexture2D.new()
		grad_tex.gradient = grad
		grad_tex.fill_from = Vector2(0.0, 0.0)
		grad_tex.fill_to = Vector2(0.0, 1.0)
		scrim.texture = grad_tex
		add_child(scrim)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "PROJECT ZERO CLIMB"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 78)
	_title.add_theme_color_override("font_color", Color(0.97, 0.93, 1.0))
	# Heavy outline plus a drop shadow so the wordmark survives whatever pixels
	# happen to sit behind it — the art is busy and light in places.
	_title.add_theme_color_override("font_outline_color", Color(0.10, 0.04, 0.22))
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	_title.add_theme_constant_override("shadow_offset_y", 5)
	_title.add_theme_constant_override("shadow_offset_x", 0)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = "S U N F A L L   W A R D"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.92, 0.80, 0.45))
	_subtitle.add_theme_color_override("font_outline_color", Color(0.10, 0.04, 0.18))
	_subtitle.add_theme_constant_override("outline_size", 8)
	column.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	column.add_child(spacer)

	for entry in BUTTONS:
		var b := Button.new()
		b.name = "Button_%s" % entry["id"]
		b.text = entry["text"]
		b.custom_minimum_size = Vector2(340, 58)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 24)
		_style_button(b)
		b.pressed.connect(_on_pressed.bind(entry["id"]))
		column.add_child(b)
		_buttons.append(b)

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 26)
	column.add_child(tail)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "WASD move   ·   Space dash   ·   hold fire   ·   Esc pause   ·   F3 debug"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.84))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.10))
	_hint.add_theme_constant_override("outline_size", 6)
	column.add_child(_hint)

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 40)
	column.add_child(bottom)

	# An assetless checkout is a supported state; say so here rather than letting
	# the player discover it as invisible actors.
	var missing := AssetCheck.missing_groups()
	if not missing.is_empty():
		var warn := Label.new()
		warn.name = "AssetWarning"
		warn.text = "art not installed (%s) — see docs/ASSET_DELIVERY.md" % ", ".join(missing)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 14)
		warn.add_theme_color_override("font_color", Color(0.95, 0.66, 0.38))
		column.add_child(warn)


## Buttons as translucent violet plates rather than Godot's default grey, with a
## brighter border on focus so a controller user can see where they are — the
## default focus ring is nearly invisible over bright key art.
func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.08, 0.24, 0.86)
	normal.set_corner_radius_all(4)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.45, 0.36, 0.72, 0.9)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.15, 0.42, 0.94)
	hover.border_color = Color(0.72, 0.60, 1.0)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.95, 0.82, 0.45)
	focus.set_border_width_all(3)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.30, 0.20, 0.52, 0.96)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(0.94, 0.92, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.94, 0.78))


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
