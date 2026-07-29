class_name RewardScreen
extends Control

## The three-card reward offer. Godot-native Controls per CLAUDE.md — no
## custom drawing, and no flattened UI mockup used as an interactive menu.
##
## Guide §13 requires each card to show category, icon, rarity border, and
## whether it evolves a summon. The screen renders whatever RewardSystem hands
## it; every pity rule lives in the system, not here.
##
## Controller support is a Phase 7 acceptance criterion, so focus is real focus:
## the cards are Buttons in a focus chain, one is grabbed on open, and the
## ui_left/ui_right/ui_accept actions drive it. Nothing here depends on a mouse.

signal card_chosen(card: RewardCard, index: int)

const CARD_MIN := Vector2(320.0, 440.0)

## Guide §2 colour ownership. Rarity borders are reward colours — gold and
## violet — and never hostile red.
const RARITY_COLOUR := {
	RewardCard.Rarity.COMMON: Color("8a7a5c"),
	RewardCard.Rarity.UNCOMMON: Color("9c6bff"),
	RewardCard.Rarity.RARE: Color("f3c65c"),
}

var cards: Array[RewardCard] = []

var _buttons: Array[Button] = []
var _row: HBoxContainer
var _title: Label


func _ready() -> void:
	# Offsets as well as anchors: set_anchors_preset() alone leaves the control
	# at its minimum size, which pinned the card row to the left edge and
	# clipped the first card.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 32)
	add_child(column)

	_title = Label.new()
	_title.text = "Choose one"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 42)
	_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_title)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_row.add_theme_constant_override("separation", 28)
	column.add_child(_row)


## Renders an offer and takes focus. `usable_against` lets the screen grey out
## cards that would do nothing — the player still sees them, per the guide's
## "current-to-new comparison", but cannot land on a dead choice by accident.
func present(offer: Array[RewardCard], state: RunState = null) -> void:
	cards = offer
	for b in _buttons:
		b.queue_free()
	_buttons.clear()

	for i in cards.size():
		var card: RewardCard = cards[i]
		var button := _build_card(card, state)
		button.pressed.connect(_on_pressed.bind(i))
		_row.add_child(button)
		_buttons.append(button)

	_link_focus()
	visible = true

	# Grab the first card the player can actually take.
	for b in _buttons:
		if not b.disabled:
			b.grab_focus()
			return
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _build_card(card: RewardCard, state: RunState) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_MIN
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = false
	button.disabled = state != null and not card.is_usable(state)

	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.10, 0.10, 0.14, 0.96)
	border.border_color = RARITY_COLOUR.get(card.rarity, Color("8a7a5c"))
	border.set_border_width_all(4)
	border.set_corner_radius_all(10)
	border.set_content_margin_all(18)
	button.add_theme_stylebox_override("normal", border)

	var focused := border.duplicate() as StyleBoxFlat
	focused.bg_color = Color(0.16, 0.14, 0.22, 0.98)
	focused.set_border_width_all(6)
	button.add_theme_stylebox_override("focus", focused)
	button.add_theme_stylebox_override("hover", focused)

	# A MarginContainer, not a bare full-rect child: a Button's StyleBox content
	# margin does not inset its children, so anchoring the text to the full rect
	# ran it under the border and clipped the first character of every label.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	button.add_child(pad)

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)
	pad.add_child(body)

	var category := Label.new()
	category.text = "%s  ·  %s" % [card.kind_name().to_upper(), card.rarity_name()]
	category.add_theme_font_size_override("font_size", 18)
	category.add_theme_color_override("font_color", RARITY_COLOUR.get(card.rarity, Color("8a7a5c")))
	body.add_child(category)

	var name_label := Label.new()
	name_label.text = card.title
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 28)
	body.add_child(name_label)

	var text := Label.new()
	text.text = card.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 18)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(text)

	# Guide §13: the card states outright whether it evolves a summon.
	if card.kind == RewardCard.Kind.ECHO:
		var evolves := Label.new()
		evolves.text = "EVOLVES THIS SUMMON"
		evolves.add_theme_font_size_override("font_size", 18)
		evolves.add_theme_color_override("font_color", RARITY_COLOUR[RewardCard.Rarity.RARE])
		body.add_child(evolves)

	if button.disabled:
		var dead := Label.new()
		dead.text = "No effect right now"
		dead.add_theme_font_size_override("font_size", 16)
		body.add_child(dead)

	return button


## Explicit focus neighbours so a controller wraps around the row instead of
## falling out of the screen at either end.
func _link_focus() -> void:
	var n := _buttons.size()
	for i in n:
		var left: Button = _buttons[(i - 1 + n) % n]
		var right: Button = _buttons[(i + 1) % n]
		_buttons[i].focus_neighbor_left = left.get_path()
		_buttons[i].focus_neighbor_right = right.get_path()
		_buttons[i].focus_previous = left.get_path()
		_buttons[i].focus_next = right.get_path()


func _on_pressed(index: int) -> void:
	if index < 0 or index >= cards.size():
		return
	card_chosen.emit(cards[index], index)


## Confirms whatever the controller is sitting on. Exposed so a test can drive
## the screen without synthesising input events.
func confirm_focused() -> int:
	for i in _buttons.size():
		if _buttons[i].has_focus():
			if _buttons[i].disabled:
				return -1
			_on_pressed(i)
			return i
	return -1


func focused_index() -> int:
	for i in _buttons.size():
		if _buttons[i].has_focus():
			return i
	return -1


func focus_next_card() -> int:
	var current := focused_index()
	if _buttons.is_empty():
		return -1
	var next := (maxi(current, 0) + 1) % _buttons.size()
	_buttons[next].grab_focus()
	return next


func card_buttons() -> Array[Button]:
	return _buttons
