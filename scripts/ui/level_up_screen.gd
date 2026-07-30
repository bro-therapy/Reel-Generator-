class_name LevelUpScreen
extends Control

## The choice a level-up presents. Owner-requested; see docs/PROGRESSION_DESIGN.md.
##
## Godot-native Control nodes, proportional layout, first card focused on open —
## the same three rules the title screen follows, for the same reasons
## (CLAUDE.md pins the UI to Control nodes, and guide §17 requires the whole
## game be controller-playable, which means no menu may open with nothing
## focused and no card may be unreachable by keyboard).
##
## The screen pauses the game while it is up. It therefore runs with
## PROCESS_MODE_ALWAYS: a paused tree stops `_process` on everything that does
## not opt out, and a menu that cannot process is a menu that cannot be
## dismissed.

signal chosen(upgrade_id: StringName)

const CARD_MIN_SIZE := Vector2(300.0, 190.0)

var _cards: Array[Button] = []
var _ids: Array[StringName] = []


func open(level: int, offer: Array) -> void:
	_ids.clear()
	for id in offer:
		_ids.append(id)
	_build(level)
	if not _cards.is_empty():
		_cards[0].grab_focus()


func _build(level: int) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Dimmed, not opaque: the player should still see the room they are standing
	# in, so the choice reads as happening inside the run rather than as a
	# separate screen the run was interrupted for.
	dim.color = Color(0.04, 0.03, 0.09, 0.82)
	add_child(dim)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "LEVEL %d" % level
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 48)
	# Gold: this is a reward, and rewards are gold/teal (guide §4).
	heading.add_theme_color_override("font_color", Color(0.96, 0.84, 0.45))
	column.add_child(heading)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = "Choose one"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.62, 0.58, 0.76))
	column.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 26.0)
	column.add_child(gap)

	var row := HBoxContainer.new()
	row.name = "Cards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)

	for id in _ids:
		var card := Button.new()
		card.name = "Card_%s" % id
		card.custom_minimum_size = CARD_MIN_SIZE
		card.add_theme_font_size_override("font_size", 22)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.text = "%s\n\n%s" % [UpgradeCatalog.title_of(id), UpgradeCatalog.text_of(id)]
		card.pressed.connect(_on_card.bind(id))
		row.add_child(card)
		_cards.append(card)

	if _ids.is_empty():
		# Every upgrade exhausted. Rather than a dead screen with no way out,
		# say so and offer the dismissal.
		var none := Button.new()
		none.name = "Card_none"
		none.custom_minimum_size = CARD_MIN_SIZE
		none.text = "Nothing left to learn\n\nContinue"
		none.pressed.connect(_on_card.bind(&""))
		row.add_child(none)
		_cards.append(none)


func _on_card(id: StringName) -> void:
	chosen.emit(id)


## Enter/Space activates the focused card even when focus arrived from a
## controller, matching TitleScreen.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and focused in _cards:
			focused.emit_signal("pressed")
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ inspection

func card_count() -> int:
	return _cards.size()


func offered_ids() -> Array[StringName]:
	return _ids.duplicate()


func focus_chain_is_complete() -> bool:
	if _cards.is_empty():
		return false
	for c in _cards:
		if c.focus_mode == Control.FOCUS_NONE:
			return false
	return true


func focused_index() -> int:
	var owner_node := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for i in _cards.size():
		if _cards[i] == owner_node:
			return i
	return -1


func press(index: int) -> bool:
	if index < 0 or index >= _cards.size():
		return false
	_cards[index].emit_signal("pressed")
	return true
