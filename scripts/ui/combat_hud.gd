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
var _left: Control
## Ornate frames drawn behind the two corner clusters. These go INTO `_elements`
## with everything else: a frame is inflated outward from the cluster it wraps,
## so it — not the cluster — is the thing that can reach the safe margin or the
## reserved centre band, and exempting it would be exempting the only part that
## can break the rule.
var _left_frame: Panel
var _bond_frame: Panel
## How far the frame is inflated past the content it wraps, so the ornament sits
## outside the bars instead of on top of them.
##
## Two values because the two axes are not alike. The corner ornament is ~24 px
## across, and at a 10 px pad it sat on top of the first bond label and the ends
## of the bars; horizontally there is room to simply move out of its way. The
## vertical budget has no such slack — at 720p the whole cluster gets 77 px —
## so FRAME_PAD is a MAXIMUM there and the pad shrinks to whatever is left.
const FRAME_PAD_X := 18.0
const FRAME_PAD := 10.0
## Gap between stacked bars. A constant rather than a theme lookup now that the
## stack is hand-placed.
const BAR_SEPARATION := 4.0
## Boss furniture: bar, its frame, its name, and the arrival card. The first
## three go into `_elements` — they are persistent HUD once a boss is up. The
## banner does not; see _build.
var _boss_bar: ProgressBar
var _boss_frame: Panel
var _boss_name: Label
var _banner: Label
var _banner_age := 0.0
## How long the arrival card is on screen, and how much of that is the hold
## before it starts leaving.
const BANNER_SECONDS := 2.6
const BANNER_HOLD := 0.55
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
	# The bars sit inside an ornate frame rather than floating on the world.
	# Requested: the HUD "just feel[s] like it's too generic... I want it to look
	# more game like". The frame is a sibling behind the stack, not a parent, so
	# the layout maths in relayout() still positions the VBox directly and is
	# unaffected by container padding.
	_left_frame = UiFrames.panel(&"plain")
	_left_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_frame)

	# A plain Control, NOT a VBoxContainer.
	#
	# Control.set_size() clamps to get_combined_minimum_size(), and a container's
	# combined minimum is whatever it last SORTED at — which is a frame behind
	# its children. So asking the stack to shrink for a smaller viewport quietly
	# did nothing, and the cluster was placed using the previous viewport's
	# height. Four bars in a column is not worth a layout engine; the rest of
	# this HUD is hand-placed for the same reason.
	var left := Control.new()
	left.name = "Bars"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	_left = left

	_health = _bar(left, "Health", Color("ff5b67"))
	_stability = _bar(left, "Stability", Color("44d7e8"))
	_convergence = _bar(left, "Convergence", Color("9c6bff"))
	# Gold, because experience is a reward (guide §4 colour ownership).
	_experience = _bar(left, "Experience", Color("f0c04a"))

	# Bottom-right: the team.
	_bond_frame = UiFrames.panel(&"plain")
	_bond_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bond_frame)

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

	# The boss's own bar and frame, hidden until something bosslike turns up.
	#
	# The report this answers: "the final room, the boss, didn't really feel
	# like a boss ... I couldn't even tell I was at the last room." There was no
	# boss bar and no announcement — the arena just had a bigger sprite in it,
	# and a bigger sprite alone does not tell a player the game changed.
	#
	# Red, because the boss is hostile and guide §4 gives red to the enemies
	# without exception. A violet boss bar would be the single largest violet
	# hostile element on the screen, which is the exact thing that rule forbids.
	# The frame is tinted warm too, not left the house violet. Everything about
	# this cluster belongs to the enemy, and a violet surround on a red bar is
	# the two sides of the palette arguing inside one widget.
	_boss_frame = UiFrames.panel(&"plain", UiFrames.BODY,
		Color(0.86, 0.42, 0.30, 1.0))
	_boss_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_frame.visible = false
	add_child(_boss_frame)

	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossHealth"
	_boss_bar.min_value = 0
	_boss_bar.max_value = 100
	_boss_bar.value = 100
	_boss_bar.show_percentage = false
	_boss_bar.visible = false
	_boss_bar.add_theme_stylebox_override("fill", UiFrames.bar_fill(Color("e8442f")))
	_boss_bar.add_theme_stylebox_override("background", UiFrames.bar_track())
	add_child(_boss_bar)

	_boss_name = Label.new()
	_boss_name.name = "BossName"
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.82))
	_boss_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_boss_name.add_theme_constant_override("shadow_offset_y", 1)
	_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(_boss_name)

	# The arrival card. Deliberately NOT in `_elements`: it is not a HUD
	# element, it is a title card that removes itself, and the reserved-centre
	# rule exists so the persistent HUD cannot obstruct a fight. A card that is
	# gone before the boss's first attack obstructs nothing. `banner_is_live()`
	# and the Phase 13 check that drives it to zero are what stop this argument
	# from quietly becoming a permanent exemption.
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 72)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55))
	_banner.add_theme_color_override("font_shadow_color", Color(0.1, 0.0, 0.0, 0.9))
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	# Top-centre is allowed: it is outside the reserved band, and the Rally
	# readout has to be glanceable without leaving the fight.
	_rally = Label.new()
	_rally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rally.add_theme_font_size_override("font_size", 20)
	_rally.text = ""
	add_child(_rally)
	_elements.append(_rally)

	_elements.append(left)
	_elements.append(_left_frame)
	_elements.append(_bond_frame)
	_elements.append(_boss_frame)
	_elements.append(_boss_bar)


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
	# The FRAME is what has to fit the budget, and the bars live inside it. So
	# the cluster's outer width is the budget and the bars get what is left after
	# the ornament takes its margin. Inflating the frame outward from a
	# full-width bar stack instead pushed 20 px into the reserved centre band.
	var cluster_width: float = minf(vp.x * 0.22, 360.0)
	var bar_width: float = cluster_width - FRAME_PAD_X * 2.0

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

	# The vertical budget is fixed by the guide: the cluster lives between the
	# reserved band's bottom edge and the safe margin, and at 720p that gap is
	# only 77 px for four bars. So the ornament gets whatever is left over rather
	# than a constant — a flat 10 px pad fits at 1080p and overflows at 720p.
	var budget: float = (vp.y - inset - cushion) - clear_rect(vp).end.y - cushion
	var bars: Array[ProgressBar] = []
	for child in _left.get_children():
		if child is ProgressBar:
			bars.append(child as ProgressBar)
	var bars_h: float = bars.size() * bar_h + maxf(bars.size() - 1, 0) * BAR_SEPARATION
	var pad_y: float = clampf((budget - bars_h) * 0.5, 0.0, FRAME_PAD)

	# Placed by hand. See _build: a container clamps to a stale minimum, so the
	# only way the stack is guaranteed to match the numbers computed here is to
	# set every rect directly.
	var y := 0.0
	for bar in bars:
		bar.custom_minimum_size = Vector2(bar_width, bar_h)
		bar.position = Vector2(0.0, y)
		bar.size = Vector2(bar_width, bar_h)
		y += bar_h + BAR_SEPARATION

	var cluster_h := bars_h + pad_y * 2.0
	_left_frame.position = Vector2(inset + cushion, vp.y - inset - cushion - cluster_h)
	_left_frame.size = Vector2(cluster_width, cluster_h)
	_left.size = Vector2(bar_width, bars_h)
	_left.position = _left_frame.position + Vector2(FRAME_PAD_X, pad_y)

	# Width from the measurement too, not just height. A container asked to be
	# narrower than its contents overflows silently, which put the bond panel
	# 2.4 px past the safe edge at 720p.
	var bonds_min: Vector2 = _bonds.get_combined_minimum_size()
	var bond_size := Vector2(maxf(bonds_min.x, minf(vp.x * 0.32, 420.0)), bonds_min.y)
	var bond_frame_size := bond_size + Vector2(FRAME_PAD_X, FRAME_PAD) * 2.0
	_bond_frame.size = bond_frame_size
	_bond_frame.position = Vector2(
		vp.x - inset - cushion - bond_frame_size.x,
		vp.y - inset - cushion - bond_frame_size.y)
	_bonds.size = bond_size
	_bonds.position = _bond_frame.position + Vector2(FRAME_PAD_X, FRAME_PAD)

	var rally_size := Vector2(minf(vp.x * 0.16, 220.0), 34.0)
	_rally.position = Vector2((vp.x - rally_size.x) * 0.5, inset + cushion)
	_rally.size = rally_size
	_rally.custom_minimum_size = rally_size

	# Under the Rally readout, still above the reserved band. The gap between
	# the top safe edge and the band is 117 px at 1080p and 77 px at 720p, and
	# Rally has already taken 34 of it — so the bar takes what is left, framed,
	# rather than a fixed height that fits one resolution.
	var boss_top := inset + cushion + rally_size.y + 6.0
	var boss_budget: float = clear_rect(vp).position.y - boss_top - cushion
	var boss_h: float = clampf(boss_budget - FRAME_PAD * 2.0, 12.0, 26.0)
	var boss_width: float = minf(vp.x * 0.46, 820.0)
	_boss_frame.size = Vector2(boss_width, boss_h + FRAME_PAD * 2.0)
	_boss_frame.position = Vector2((vp.x - boss_width) * 0.5, boss_top)
	_boss_bar.size = Vector2(boss_width - FRAME_PAD_X * 2.0, boss_h)
	_boss_bar.position = _boss_frame.position + Vector2(FRAME_PAD_X, FRAME_PAD)
	_boss_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_banner.size = Vector2(vp.x, vp.y * 0.16)
	_banner.position = Vector2(0.0, vp.y * 0.30)


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

	# Shared with every other meter in the game, so the level-up screen and the
	# HUD cannot drift apart.
	bar.add_theme_stylebox_override("fill", UiFrames.bar_fill(colour))
	bar.add_theme_stylebox_override("background", UiFrames.bar_track())
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


# ------------------------------------------------------------------- the boss

## Puts the boss bar up and plays the arrival card.
func show_boss(display_name: String, maximum: int) -> void:
	_boss_bar.max_value = maxi(1, maximum)
	_boss_bar.value = _boss_bar.max_value
	_boss_name.text = display_name.to_upper()
	_boss_bar.visible = true
	_boss_frame.visible = true
	_banner.text = display_name.to_upper()
	_banner.visible = true
	_banner_age = 0.0
	relayout()


func set_boss_health(current: int) -> void:
	if _boss_bar == null:
		return
	_boss_bar.value = clampi(current, 0, int(_boss_bar.max_value))


func hide_boss() -> void:
	if _boss_bar == null:
		return
	_boss_bar.visible = false
	_boss_frame.visible = false


## Drives the arrival card only. Everything else in this HUD is signal-driven;
## a fade is the one thing that genuinely needs a clock.
func _process(delta: float) -> void:
	if _banner == null or not _banner.visible:
		return
	_banner_age += delta
	if _banner_age >= BANNER_SECONDS:
		_banner.visible = false
		return
	var t := _banner_age / BANNER_SECONDS
	# Snaps in, holds, then leaves. A symmetric fade reads as a mistake at this
	# size — the name has to land like the boss did.
	var alpha := 1.0
	if t < 0.08:
		alpha = t / 0.08
	elif t > BANNER_HOLD:
		alpha = clampf((1.0 - t) / (1.0 - BANNER_HOLD), 0.0, 1.0)
	_banner.modulate.a = alpha
	# Drifts up as it goes, so it reads as an announcement rather than a
	# still frame someone left on.
	_banner.position.y = size.y * 0.30 - size.y * 0.03 * t


func banner_is_live() -> bool:
	return _banner != null and _banner.visible


func boss_bar_is_up() -> bool:
	return _boss_bar != null and _boss_bar.visible


func boss_health_fraction() -> float:
	if _boss_bar == null or _boss_bar.max_value <= 0.0:
		return 0.0
	return float(_boss_bar.value) / float(_boss_bar.max_value)


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
