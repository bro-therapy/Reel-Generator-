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
##
## The first version drew bare Godot Buttons on the dim, with nothing holding
## them together — "the UI as well for where you pick your buffs looks like
## garbage. I need them centered in the middle of the screen and I want like a
## fancier UI". Everything now lives inside one ornate panel that is centred by
## construction, and every rect is arithmetic rather than measured: a container's
## combined minimum is a frame stale, so a panel sized from one is a panel that
## is centred against the PREVIOUS layout.

signal chosen(upgrade_id: StringName)

## What kind of choice is on offer. The two share a layout and differ in what
## the cards mean — one spends a level on a stat, the other bonds a spirit.
enum Mode { UPGRADE, SUMMON }

const CARD_MIN_SIZE := Vector2(300.0, 190.0)
const CARD_GAP := 22.0
const PANEL_PAD := 40.0
## Heading, subtitle and rule, measured from the panel's top edge.
const HEADING_Y := 20.0
const SUBTITLE_Y := 78.0
const RULE_Y := 112.0
const HEADER_HEIGHT := 148.0
## Where the title line sits inside a card. The blurb starts just under it and
## fills the rest, so a one-line and a three-line blurb both sit under the name
## rather than drifting apart.
const TITLE_TOP := 30.0
const TITLE_BOTTOM := 74.0

## Accent per upgrade target, so a card about the hero and a card about a spirit
## are not the same object with different words. All on the friendly side of the
## palette (guide §4) — these are the player's own choices.
const ACCENT := {
	UpgradeCatalog.Target.HERO: Color(0.55, 0.86, 0.98),
	UpgradeCatalog.Target.WEAPON: Color(0.72, 0.62, 1.0),
	UpgradeCatalog.Target.SUMMON: Color(0.62, 0.92, 0.76),
	UpgradeCatalog.Target.STABILITY: Color(0.44, 0.84, 0.91),
}
const ACCENT_DEFAULT := Color(0.72, 0.62, 1.0)

var _cards: Array[Button] = []
var _ids: Array[StringName] = []
var _mode: Mode = Mode.UPGRADE
var _panel: Panel
var _ornaments: Dictionary = {}


func open(level: int, offer: Array) -> void:
	_open(Mode.UPGRADE, level, offer)


## The spirit-bonding page. Requested: "There should be a page where you can pick
## which upgrade you want. If you want the wolf or the robot or the sword. So you
## have to level up to earn that." `offer` is spirit ids, not upgrade ids.
func open_summon_choice(level: int, offer: Array) -> void:
	_open(Mode.SUMMON, level, offer)


func _open(mode: Mode, level: int, offer: Array) -> void:
	_mode = mode
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
	_ornaments.clear()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport_rect().size

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Dimmed, not opaque: the player should still see the room they are standing
	# in, so the choice reads as happening inside the run rather than as a
	# separate screen the run was interrupted for.
	dim.color = Color(0.04, 0.03, 0.09, 0.82)
	add_child(dim)

	var count: int = maxi(_ids.size(), 1)
	# Height comes from what a card actually holds — a title line and up to
	# three wrapped lines of blurb. Sized off the viewport it grew to 260 px at
	# 1080p and the bottom third of every card was empty.
	var card_size := Vector2(
		clampf(vp.x * 0.17, 240.0, CARD_MIN_SIZE.x),
		clampf(vp.y * 0.17, 150.0, 200.0))
	var panel_size := Vector2(
		count * card_size.x + (count - 1) * CARD_GAP + PANEL_PAD * 2.0,
		HEADER_HEIGHT + card_size.y + PANEL_PAD)

	# Centred by arithmetic on the viewport, not by an alignment flag inside a
	# full-rect container. The container route is what produced a block that read
	# as adrift: it centres the column's CONTENT, which leaves the panel — the
	# thing the eye actually measures against the screen — wherever its minimum
	# happened to fall.
	_panel = UiFrames.panel(&"ornate")
	_panel.name = "Panel"
	_panel.size = panel_size
	_panel.position = ((vp - panel_size) * 0.5).floor()
	add_child(_panel)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "LEVEL %d" % level if _mode == Mode.UPGRADE else "A SPIRIT ANSWERS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 44)
	# Gold: this is a reward, and rewards are gold/teal (guide §4).
	heading.add_theme_color_override("font_color", Color(0.96, 0.84, 0.45))
	heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	heading.add_theme_constant_override("shadow_offset_y", 2)
	heading.position = Vector2(0.0, HEADING_Y)
	heading.size = Vector2(panel_size.x, 54.0)
	_panel.add_child(heading)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = "Choose one" if _mode == Mode.UPGRADE else "Bond one — the others wait"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(0.68, 0.63, 0.82))
	sub.position = Vector2(0.0, SUBTITLE_Y)
	sub.size = Vector2(panel_size.x, 26.0)
	_panel.add_child(sub)

	# Under the subtitle, not between it and the heading: a rule that splits a
	# title from its own strapline separates two things that belong together.
	var rule_width := panel_size.x * 0.62
	var rule := UiFrames.rule(rule_width)
	if rule != null:
		rule.position = Vector2((panel_size.x - rule_width) * 0.5, RULE_Y)
		_panel.add_child(rule)

	var row_width := count * card_size.x + (count - 1) * CARD_GAP
	var row_x := (panel_size.x - row_width) * 0.5
	var row_y := HEADER_HEIGHT

	for i in _ids.size():
		var card := _make_card(_ids[i])
		card.position = Vector2(row_x + i * (card_size.x + CARD_GAP), row_y)
		card.size = card_size
		card.custom_minimum_size = card_size
		_panel.add_child(card)
		_cards.append(card)

	if _ids.is_empty():
		# Every upgrade exhausted. Rather than a dead screen with no way out,
		# say so and offer the dismissal.
		var none := _card_button(&"", "Nothing left to learn", "Continue",
			ACCENT_DEFAULT)
		none.name = "Card_none"
		none.position = Vector2(row_x, row_y)
		none.size = card_size
		_panel.add_child(none)
		_cards.append(none)


func _make_card(id: StringName) -> Button:
	if _mode == Mode.SUMMON:
		# Name and pitch come from the species resource, not a second table here.
		# A blurb duplicated in the UI is a blurb that goes stale the first time
		# a spirit is rebalanced.
		var spirit := load("res://data/spirits/%s.tres" % id) as SpiritData
		var title := spirit.display_name if spirit != null else String(id)
		var pitch := ""
		if spirit != null and spirit.form(0) != null:
			pitch = spirit.form(0).passive_description
		return _card_button(id, title, pitch, ACCENT[UpgradeCatalog.Target.SUMMON])
	var target: int = int(UpgradeCatalog.entry(id).get("target",
		UpgradeCatalog.Target.HERO))
	return _card_button(id, UpgradeCatalog.title_of(id), UpgradeCatalog.text_of(id),
		ACCENT.get(target, ACCENT_DEFAULT))


## One card: framed, accented, with a real type hierarchy between name and
## effect. The Button carries no text of its own — a single string cannot be two
## sizes, and "Ward\n\n+15% maximum Stability" set at one size in one colour is
## most of why the old screen read as placeholder.
func _card_button(id: StringName, title: String, blurb: String,
		accent: Color) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % id
	card.clip_contents = false
	card.pressed.connect(_on_card.bind(id))

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, _card_box(accent, state))

	# The ornament sits on top of the button's own stylebox and brightens with
	# focus, which is how a controller player can tell where they are.
	var trim := NinePatchRect.new()
	trim.name = "Trim"
	trim.texture = UiFrames.texture("plain_border.png")
	trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trim.patch_margin_left = UiFrames.MARGIN
	trim.patch_margin_top = UiFrames.MARGIN
	trim.patch_margin_right = UiFrames.MARGIN
	trim.patch_margin_bottom = UiFrames.MARGIN
	trim.self_modulate = Color(accent.r, accent.g, accent.b, 0.55)
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if trim.texture != null:
		card.add_child(trim)
		_ornaments[card] = trim
		card.focus_entered.connect(_on_card_focus.bind(card, accent, true))
		card.focus_exited.connect(_on_card_focus.bind(card, accent, false))

	var name_label := Label.new()
	name_label.name = "Title"
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", accent)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_label.offset_left = 14
	name_label.offset_right = -14
	name_label.offset_top = TITLE_TOP
	name_label.offset_bottom = TITLE_BOTTOM
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)

	var body := Label.new()
	body.name = "Blurb"
	body.text = blurb
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(0.84, 0.82, 0.92))
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 20
	body.offset_right = -20
	body.offset_top = TITLE_BOTTOM + 8
	body.offset_bottom = -18
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(body)

	return card


func _card_box(accent: Color, state: String) -> StyleBox:
	# Focus lifts LESS than hover. A focused card is announced by its ornament
	# going to full brightness; lifting the body as hard as well washed the card
	# to a pale grey that read as disabled rather than as selected.
	var lift := {"normal": 0.0, "hover": 0.10, "pressed": 0.16, "focus": 0.06,
		"disabled": -0.04}.get(state, 0.0) as float
	var tex := UiFrames.texture("plain_panel.png")
	if tex != null:
		var body := UiFrames.BODY_DEEP.lightened(lift)
		# A trace of the accent in the body, so a card is tinted by what it does
		# without ever leaving the near-black the panel needs to stay readable.
		# The weight is FIXED: folding `lift` into it made the accent bloom with
		# the state and turned a highlight into a colour change.
		body = body.lerp(Color(accent.r, accent.g, accent.b, body.a), 0.12)
		return UiFrames.boxed(tex, body)

	var flat := StyleBoxFlat.new()
	flat.bg_color = UiFrames.BODY_DEEP.lightened(lift)
	flat.set_corner_radius_all(5)
	flat.set_border_width_all(2)
	flat.border_color = Color(accent.r, accent.g, accent.b, 0.5 + lift * 2.0)
	return flat


func _on_card_focus(card: Button, accent: Color, focused: bool) -> void:
	var trim: NinePatchRect = _ornaments.get(card)
	if trim == null:
		return
	trim.self_modulate = Color(accent.r, accent.g, accent.b, 1.0 if focused else 0.55)


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


func mode() -> Mode:
	return _mode


## The panel's rect, for asserting it is actually centred.
func panel_rect() -> Rect2:
	if _panel == null:
		return Rect2()
	return Rect2(_panel.position, _panel.size)


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
