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
var _rally: Label
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
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.tooltip_text = label
	parent.add_child(row)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(300, 14)
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.11, 0.9)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	return bar


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


func set_stability(value: int) -> void:
	_stability.value = clampi(value, 0, int(_stability.max_value))


func set_convergence(meter: float) -> void:
	_convergence.value = clampf(meter, 0.0, float(_convergence.max_value))


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
