class_name CombatHUD
extends Control

## The in-combat HUD. Guide §13 and brief Phase 13.
##
## Native Control nodes, per CLAUDE.md — the included HUD mockup is a layout
## reference, not a flattened interactive image.
##
## The layout rule that drives everything: the centre of the screen belongs to
## the fight. Guide §13 reserves the middle 70%, so every element anchors to an
## edge and `centre_is_clear()` is asserted rather than eyeballed.
##
## Elements are driven by signals, never polled. A HUD that reads RunState every
## frame is a HUD that quietly costs 1% of the frame budget forever.

## Guide §13: the centre 70% stays clear of HUD elements.
const CLEAR_FRACTION := 0.70
## Fraction of each edge kept free for ultrawide and TV overscan.
const SAFE_AREA_MARGIN := 0.04

var _health: ProgressBar
var _stability: ProgressBar
var _convergence: ProgressBar
var _experience: ProgressBar
var _rally: Label
## Numeric readout per bar. Requested: "those bars on the left side, they
## definitely need some numbers" — a bar alone shows a ratio, and a player
## deciding whether to risk another room needs the actual figure.
var _readouts: Dictionary = {}
var _bonds: HBoxContainer
var _bond_labels: Array[Label] = []
var _left: VBoxContainer
var _elements: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(relayout)
	relayout()


func _build() -> void:
	# Bottom-left: the hero's own state. Positioned in relayout(), not here —
	# fixed pixel offsets cannot stay outside a band defined as a percentage of
	# the viewport, which is how the first version of this intruded at 720p and
	# left the safe area at 32:9.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	add_child(left)
	_left = left

	_health = _bar(left, "Health", Color("ff5b67"))
	_stability = _bar(left, "Stability", Color("44d7e8"))
	_convergence = _bar(left, "Convergence", Color("9c6bff"))
	# Gold, because experience is a reward (guide §4 colour ownership).
	_experience = _bar(left, "Experience", Color("f0c04a"))

	# Bottom-right: the team.
	_bonds = HBoxContainer.new()
	_bonds.add_theme_constant_override("separation", 12)
	add_child(_bonds)
	for i in RunState.BOND_SLOTS:
		var slot := Label.new()
		slot.text = "[empty]"
		slot.custom_minimum_size = Vector2(130, 30)
		slot.add_theme_font_size_override("font_size", 15)
		_bonds.add_child(slot)
		_bond_labels.append(slot)
	_elements.append(_bonds)

	# Top-centre is allowed: it is outside the reserved band, and the Rally
	# readout has to be glanceable without leaving the fight.
	_rally = Label.new()
	_rally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rally.add_theme_font_size_override("font_size", 20)
	_rally.text = ""
	add_child(_rally)
	_elements.append(_rally)

	_elements.append(left)


## Places every element as a fraction of the viewport.
##
## The reserved band is 70% of both axes, so the clear space is the outer 15% on
## each edge. Everything here is pinned by that fraction rather than by pixels,
## which is what makes the layout hold from 1280x720 to 3840x1080.
func relayout() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	# Title-safe inset, taken from the height on both axes. A percentage of the
	# *width* would push elements 154 px inward on a 32:9 display for no reason.
	var inset := vp.y * SAFE_AREA_MARGIN
	var bar_width: float = minf(vp.x * 0.22, 360.0)

	# Cushion so an element that lands exactly on the safe edge is not judged by
	# a float equality.
	var cushion := 2.0

	# Bars are placed from their *measured* height upward off the bottom safe
	# edge. Asking a container to be shorter than its contents does nothing —
	# it simply overflows, which is how this first left the safe area.
	# Bar height scales with the viewport, like the inset above it. A fixed 22 px
	# is fine at 1080p and proportionally enormous at 720p — with four bars it
	# grew the panel into the reserved centre band, which is precisely the
	# fixed-pixel trap this layout is documented to avoid. Clamped so the text
	# inside stays legible at the small end and the bars do not become slabs at
	# the large one.
	var bar_h: float = clampf(vp.y * 0.020, 15.0, 24.0)
	for child in _left.get_children():
		if child is ProgressBar:
			(child as ProgressBar).custom_minimum_size = Vector2(bar_width, bar_h)
			(child as ProgressBar).size = Vector2(bar_width, bar_h)

	var bars_h: float = _left.get_combined_minimum_size().y
	_left.size = Vector2(bar_width, bars_h)
	_left.position = Vector2(inset + cushion, vp.y - inset - cushion - bars_h)

	# Width from the measurement too, not just height. A container asked to be
	# narrower than its contents overflows silently, which put the bond panel
	# 2.4 px past the safe edge at 720p.
	var bonds_min: Vector2 = _bonds.get_combined_minimum_size()
	var bond_size := Vector2(maxf(bonds_min.x, minf(vp.x * 0.32, 420.0)), bonds_min.y)
	_bonds.size = bond_size
	_bonds.position = Vector2(vp.x - inset - cushion - bond_size.x, vp.y - inset - cushion - bond_size.y)

	var rally_size := Vector2(minf(vp.x * 0.16, 220.0), 34.0)
	_rally.position = Vector2((vp.x - rally_size.x) * 0.5, inset + cushion)
	_rally.size = rally_size
	_rally.custom_minimum_size = rally_size


## A bare bar, no caption.
##
## Three captioned rows come to 164 px of forced minimum height, and the gap
## between the reserved band and the safe margin is only 79 px at 720p. Colour
## carries the meaning instead: red health, teal Stability, violet Convergence,
## which is the guide's own ownership scheme.
func _bar(parent: Control, label: String, colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "Bar_%s" % label
	bar.custom_minimum_size = Vector2(300, 22)
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.tooltip_text = label

	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(3)
	# A lighter top edge reads as a lit surface; it is most of what "fancier"
	# costs here, for one line and no extra height.
	fill.border_width_top = 2
	fill.border_color = colour.lightened(0.45)
	bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.09, 0.9)
	bg.set_corner_radius_all(3)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.32, 0.30, 0.42, 0.95)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)

	# Name and figure are drawn ON the bar rather than on a caption line above
	# it. Captions were the first attempt and they cost ~16 px of height each:
	# with a fourth bar added, the panel grew tall enough to reach the reserved
	# centre band and Phase 13 failed at every aspect ratio. Overlaying costs
	# nothing, and it is what most games do anyway.
	var overlay := HBoxContainer.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_constant_override("separation", 6)
	# Must not eat clicks meant for anything underneath.
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(overlay)

	var pad_left := Control.new()
	pad_left.custom_minimum_size = Vector2(7, 0)
	overlay.add_child(pad_left)

	var name_label := Label.new()
	name_label.text = label.to_upper()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(spacer)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "0"
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	value_label.add_theme_constant_override("shadow_offset_y", 1)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(value_label)
	_readouts[label] = value_label

	var pad_right := Control.new()
	pad_right.custom_minimum_size = Vector2(7, 0)
	overlay.add_child(pad_right)

	return bar


func _set_readout(label: String, text: String) -> void:
	var node: Label = _readouts.get(label)
	if node != null:
		node.text = text


# ---------------------------------------------------------------- binding

## Connects to the run's signals. Event-driven, so nothing polls per frame.
func bind(state: RunState, convergence: ConvergenceController = null, rally: RallyController = null) -> void:
	if state != null:
		state.stability_changed.connect(set_stability)
		state.bonded.connect(func(_id: StringName, _slot: int) -> void: refresh_bonds(state))
		state.evolved.connect(func(_id: StringName, _tier: int) -> void: refresh_bonds(state))
		set_stability(state.stability)
		refresh_bonds(state)

	if convergence != null:
		convergence.charged.connect(set_convergence)
		convergence.triggered.connect(func(_s: float) -> void: set_convergence(0.0))

	if rally != null:
		rally.marked.connect(func(_t: Node3D, seconds: float) -> void: _rally.text = "RALLY %.0fs" % seconds)
		rally.cleared.connect(func(_reason: StringName) -> void: _rally.text = "")


func set_health(current: int, maximum: int) -> void:
	_health.max_value = maxi(1, maximum)
	_health.value = clampi(current, 0, maximum)
	_set_readout("Health", "%d / %d" % [clampi(current, 0, maximum), maxi(1, maximum)])


func set_stability(value: int) -> void:
	_stability.value = clampi(value, 0, int(_stability.max_value))
	_set_readout("Stability", "%d / %d" % [int(_stability.value), int(_stability.max_value)])


func set_convergence(meter: float) -> void:
	_convergence.value = clampf(meter, 0.0, float(_convergence.max_value))
	# A percentage, because Convergence is a charge the player is waiting to
	# spend rather than a pool being drained.
	_set_readout("Convergence", "%d%%" % int(round(_convergence.value)))


## Level and progress toward the next one.
func set_experience(level: int, current: int, needed: int) -> void:
	if _experience == null:
		return
	_experience.max_value = maxi(1, needed)
	_experience.value = clampi(current, 0, maxi(1, needed))
	_set_readout("Experience", "LV %d   %d / %d" % [level, current, maxi(1, needed)])


func refresh_bonds(state: RunState) -> void:
	for i in _bond_labels.size():
		var data: SpiritData = state.bonds[i] if i < state.bonds.size() else null
		if data == null:
			_bond_labels[i].text = "[empty]"
			continue
		var form := data.form(state.tier_of(data.id))
		_bond_labels[i].text = form.display_name if form != null else data.display_name


# ---------------------------------------------------------------- layout rules

## The rectangle the HUD must stay out of. Guide §13.
static func clear_rect(viewport: Vector2) -> Rect2:
	var size := viewport * CLEAR_FRACTION
	return Rect2((viewport - size) * 0.5, size)


## The rectangle the HUD must stay inside, for ultrawide and overscan.
##
## Inset from the *height* on both axes, which is the title-safe convention and
## the same number relayout() uses. Taking a percentage of each axis separately
## would demand a 154 px left margin on a 32:9 display and disagree with the
## layout, which is exactly how this first failed.
static func safe_rect(viewport: Vector2) -> Rect2:
	var inset := viewport.y * SAFE_AREA_MARGIN
	return Rect2(Vector2(inset, inset), viewport - Vector2(inset, inset) * 2.0)


## Every HUD element's rectangle, in viewport space.
func element_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for e in _elements:
		if e != null and is_instance_valid(e):
			out.append(Rect2(e.global_position, e.size))
	return out


## True when nothing overlaps the reserved centre band.
func centre_is_clear(viewport: Vector2) -> bool:
	var reserved := clear_rect(viewport)
	for r in element_rects():
		if r.intersects(reserved):
			return false
	return true


## True when every element sits inside the safe area.
func inside_safe_area(viewport: Vector2) -> bool:
	var safe := safe_rect(viewport)
	for r in element_rects():
		if not safe.encloses(r):
			return false
	return true
