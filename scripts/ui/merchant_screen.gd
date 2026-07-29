class_name MerchantScreen
extends Control

## The Spirit Well counter. Godot-native Controls, same as the reward screen.
##
## Two Phase 9 criteria are really one requirement — the controller must never be
## stranded. Focus is grabbed on open, moved off any control that becomes
## disabled, and restored after a reroll rebuilds every card.

signal closed()
signal bought(index: int)

const CARD_MIN := Vector2(260.0, 300.0)
const RARITY_COLOUR := {
	RewardCard.Kind.SUMMON_RELIC: Color("9c6bff"),
	RewardCard.Kind.GENERAL_RELIC: Color("8a7a5c"),
	RewardCard.Kind.FOCUS_UPGRADE: Color("f3c65c"),
	RewardCard.Kind.RECOVERY: Color("44d7e8"),
}

var merchant: Merchant
var state: RunState

var _row: HBoxContainer
var _actions: HBoxContainer
var _status: Label
var _offer_buttons: Array[Button] = []
var _action_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 26)
	add_child(column)

	var title := Label.new()
	title.text = "Spirit Well"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(title)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_row.add_theme_constant_override("separation", 18)
	column.add_child(_row)

	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_actions.add_theme_constant_override("separation", 18)
	column.add_child(_actions)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_status)


func open(m: Merchant, s: RunState) -> void:
	merchant = m
	state = s
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	closed.emit()


# ---------------------------------------------------------------- rendering

func _rebuild(keep_index: int = -1) -> void:
	for b in _offer_buttons:
		b.queue_free()
	for b in _action_buttons:
		b.queue_free()
	_offer_buttons.clear()
	_action_buttons.clear()

	for i in merchant.offers.size():
		var button := _build_offer(merchant.offers[i], i)
		_row.add_child(button)
		_offer_buttons.append(button)

	_add_action("Reroll (%d)" % merchant.next_reroll_cost(), merchant.can_reroll(), reroll)
	_add_action("Restore %d Stability (%d)" % [merchant.stability_amount(), merchant.stability_price()],
		merchant.can_buy_stability(), buy_stability)
	_add_action("Heal 20%", merchant.can_heal(), heal)
	_add_action("Leave", true, close)

	_link_focus()
	_refresh_status()
	_restore_focus(keep_index)


func _build_offer(offer: Merchant.Offer, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_MIN
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not offer.affordable(state.currency)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15, 0.96)
	style.border_color = Color("f3c65c") if offer.locked else RARITY_COLOUR.get(offer.kind, Color("8a7a5c"))
	style.set_border_width_all(6 if offer.locked else 3)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	var focused := style.duplicate() as StyleBoxFlat
	focused.bg_color = Color(0.17, 0.16, 0.23, 0.98)
	focused.set_border_width_all(6)
	button.add_theme_stylebox_override("focus", focused)
	button.add_theme_stylebox_override("hover", focused)
	button.add_theme_stylebox_override("disabled", style)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 14)
	button.add_child(pad)

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	pad.add_child(body)

	var name_label := Label.new()
	name_label.text = offer.title
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 22)
	body.add_child(name_label)

	var text := Label.new()
	text.text = offer.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 15)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(text)

	# The disabled state has to say *why*, not just look dim.
	var price := Label.new()
	var reason := offer.blocked_reason(state.currency)
	price.text = reason if reason != "" else "%d" % offer.price
	price.add_theme_font_size_override("font_size", 20)
	price.add_theme_color_override("font_color", Color("f3c65c") if reason == "" else Color("ff8a3d"))
	body.add_child(price)

	if offer.locked:
		var held := Label.new()
		held.text = "HELD"
		held.add_theme_font_size_override("font_size", 15)
		held.add_theme_color_override("font_color", Color("f3c65c"))
		body.add_child(held)

	button.pressed.connect(func() -> void: buy(index))
	return button


func _add_action(text: String, enabled: bool, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(220, 52)
	b.pressed.connect(handler)
	_actions.add_child(b)
	_action_buttons.append(b)


func _refresh_status() -> void:
	_status.text = "Currency %d    ·    Stability %d/%d    ·    Rerolls used %d" % [
		state.currency, state.stability, state.max_stability, merchant.rerolls_used,
	]


# ---------------------------------------------------------------- focus

func focusable_controls() -> Array[Button]:
	var out: Array[Button] = []
	out.append_array(_offer_buttons)
	out.append_array(_action_buttons)
	return out


func focused_index() -> int:
	var all := focusable_controls()
	for i in all.size():
		if all[i].has_focus():
			return i
	return -1


func focused_is_disabled() -> bool:
	var i := focused_index()
	var all := focusable_controls()
	return i < 0 or all[i].disabled


func focus_next() -> int:
	var all := focusable_controls()
	if all.is_empty():
		return -1
	var start := maxi(focused_index(), 0)
	# Skip disabled controls; landing on one is how a controller gets stuck.
	for step in range(1, all.size() + 1):
		var i := (start + step) % all.size()
		if not all[i].disabled:
			all[i].grab_focus()
			return i
	all[start].grab_focus()
	return start


func _link_focus() -> void:
	var all := focusable_controls()
	var n := all.size()
	for i in n:
		var left: Button = all[(i - 1 + n) % n]
		var right: Button = all[(i + 1) % n]
		all[i].focus_neighbor_left = left.get_path()
		all[i].focus_neighbor_right = right.get_path()
		all[i].focus_previous = left.get_path()
		all[i].focus_next = right.get_path()


## Puts focus back after a rebuild, preferring where it was.
##
## Rebuilding frees every button, which drops focus on the floor — the player
## would be left with a live screen and no cursor. Preferring the old index keeps
## the position stable across a reroll; falling forward keeps it off a control
## that has just been disabled.
func _restore_focus(preferred: int) -> void:
	var all := focusable_controls()
	if all.is_empty():
		return
	if preferred >= 0 and preferred < all.size() and not all[preferred].disabled:
		all[preferred].grab_focus()
		return
	for b in all:
		if not b.disabled:
			b.grab_focus()
			return
	all[0].grab_focus()


# ---------------------------------------------------------------- actions

func buy(index: int) -> bool:
	var ok := merchant.buy(index)
	if ok:
		bought.emit(index)
	# Rebuild either way: a failed purchase still means the prices on screen may
	# no longer match the currency the player has.
	_rebuild(index)
	return ok


func buy_focused() -> bool:
	var i := focused_index()
	if i < 0 or i >= _offer_buttons.size():
		return false
	return buy(i)


func reroll() -> bool:
	var keep := focused_index()
	var ok := merchant.reroll()
	_rebuild(keep)
	return ok


func buy_stability() -> bool:
	var keep := focused_index()
	var ok := merchant.buy_stability()
	_rebuild(keep)
	return ok


func heal() -> int:
	var keep := focused_index()
	var healed := merchant.heal(50, 100)
	_rebuild(keep)
	return healed


func toggle_lock_focused() -> bool:
	var i := focused_index()
	if i < 0 or i >= _offer_buttons.size():
		return false
	var ok := merchant.set_locked(i, merchant.locked_index() != i)
	_rebuild(i)
	return ok
