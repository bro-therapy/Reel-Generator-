extends SceneTree

## Phase 13 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase13_acceptance.gd
##
## The five criteria:
##   - Center 70% remains clear.
##   - HUD scales at 16:9 and ultrawide safe areas.
##   - All menus work with mouse, keyboard, and controller.
##   - Reduced shake/flashes/effect opacity settings work.
##   - Pause freezes combat but not menu navigation.

const STAFF := "res://data/weapons/conjurer_staff.tres"
## 16:9, 21:9 ultrawide, and 32:9 super-ultrawide.
const VIEWPORTS := [Vector2(1920, 1080), Vector2(2560, 1080), Vector2(3840, 1080), Vector2(1280, 720)]
const SETTINGS_SCRIPT := "res://scripts/run/game_settings.gd"

var _pass := 0
var _fail := 0
var _hud: CombatHUD
## A `--script` run binds no autoloads, so the settings node is built here
## rather than reached for globally.
var _settings: Node
var _stage := -1
var _mark := 0.0


func _initialize() -> void:
	print("\n=== PHASE 13 ACCEPTANCE ===\n")
	_settings = (load(SETTINGS_SCRIPT) as GDScript).new()
	root.add_child(_settings)
	_check_accessibility_settings()
	_check_pause_semantics()
	_stage = 0


# ---------------------------------------------------------------- settings

func _check_accessibility_settings() -> void:
	# Brief: "Reduced shake/flashes/effect opacity settings work." They have to
	# exist, hold a value, and survive a round trip through the save.
	var keys := ["reduced_screen_shake", "reduced_flashes", "effect_opacity"]
	var missing: Array[String] = []
	for k in keys:
		if not _settings.DEFAULTS.has(k):
			missing.append(k)
	if missing.is_empty():
		_ok("the three accessibility settings exist", ", ".join(keys))
	else:
		_no("accessibility settings", "missing " + ", ".join(missing))

	_settings.reset_to_defaults()
	_settings.set_setting("reduced_screen_shake", true)
	_settings.set_setting("reduced_flashes", true)
	_settings.set_setting("effect_opacity", 0.4)

	var held := (
		bool(_settings.get_setting("reduced_screen_shake"))
		and bool(_settings.get_setting("reduced_flashes"))
		and is_equal_approx(float(_settings.get_setting("effect_opacity")), 0.4)
	)
	if held:
		_ok("the settings hold the values written to them", "shake on, flashes on, opacity 0.4")
	else:
		_no("settings", "values did not stick")

	# An unknown key must not silently create itself, or a typo becomes a
	# setting nobody reads.
	_settings.set_setting("not_a_real_setting", 5)
	if _settings.get_setting("not_a_real_setting") == null:
		_ok("unknown settings are rejected", "a typo cannot invent a setting")
	else:
		_no("settings guard", "an unknown key was accepted")

	# ...and they reset.
	_settings.reset_to_defaults()
	if not bool(_settings.get_setting("reduced_screen_shake")) and is_equal_approx(float(_settings.get_setting("effect_opacity")), 1.0):
		_ok("settings reset to their defaults", "shake off, opacity 1.0")
	else:
		_no("settings reset", "defaults not restored")


func _check_pause_semantics() -> void:
	# Brief: "Pause freezes combat but not menu navigation."
	var pause := PauseController.new(self)
	root.add_child(pause)

	var combat := Node.new()
	combat.name = "Combat"
	var child := Node.new()
	combat.add_child(child)
	root.add_child(combat)
	PauseController.make_pausable(combat)

	var menu := Control.new()
	menu.name = "Menu"
	var button := Button.new()
	menu.add_child(button)
	root.add_child(menu)
	PauseController.make_menu_interactive(menu)

	if not PauseController.subtree_runs_while_paused(combat):
		_ok("combat freezes when paused", "PROCESS_MODE_PAUSABLE through the subtree")
	else:
		_no("pause", "combat keeps running while paused")

	# The whole menu subtree, not just its root: a Control whose children are
	# still pausable renders but does not respond.
	if PauseController.subtree_runs_while_paused(menu):
		_ok("the whole menu subtree stays live", "root and children both run while paused")
	else:
		_no("menu pause", "part of the menu subtree freezes with the game")

	var events: Array = []
	pause.paused_changed.connect(func(v: bool) -> void: events.append(v))
	pause.set_paused(true)
	var was := pause.is_paused()
	pause.set_paused(true)
	pause.set_paused(false)

	if was and not pause.is_paused() and events == [true, false]:
		_ok("pause toggles once per change", "a repeated set fires nothing")
	else:
		_no("pause toggle", "events %s" % str(events))

	# The controller itself must survive a pause or it could never unpause.
	if pause.process_mode == Node.PROCESS_MODE_ALWAYS:
		_ok("the pause controller runs while paused", "it can always unpause")
	else:
		_no("pause controller", "would freeze with the game")

	combat.queue_free()
	menu.queue_free()
	pause.queue_free()


# ---------------------------------------------------------------- HUD layout

func _process(delta: float) -> bool:
	match _stage:
		0:
			_build_hud()
			_mark = 0.0
			_stage = 1
		1:
			# One frame for the container layout to settle before measuring.
			_mark += delta
			if _mark >= 0.1:
				_check_layout()
				_stage = 2
		2:
			_check_menu_input()
			_stage = 99
		99:
			_summary()
			return true
	return false


func _build_hud() -> void:
	_hud = CombatHUD.new()
	root.add_child(_hud)
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	_hud.bind(state, null, null)


func _check_layout() -> void:
	# Guide §13: the centre 70% belongs to the fight.
	if is_equal_approx(CombatHUD.CLEAR_FRACTION, 0.70):
		_ok("the reserved band is the guide's 70%", "centre 70%% kept clear")
	else:
		_no("clear fraction", "%.2f" % CombatHUD.CLEAR_FRACTION)

	var rects := _hud.element_rects()
	if rects.is_empty():
		_no("HUD layout", "no HUD elements to measure")
		return

	# Measured at every aspect the game claims to support, not just 16:9 — the
	# ultrawide cases are where an edge-anchored element drifts inward.
	var intruding: Array[String] = []
	var outside: Array[String] = []
	for vp in VIEWPORTS:
		_hud.size = vp
		_hud.relayout()
		var reserved := CombatHUD.clear_rect(vp)
		var safe := CombatHUD.safe_rect(vp)
		for r in _hud.element_rects():
			if r.intersects(reserved):
				intruding.append("%dx%d" % [int(vp.x), int(vp.y)])
				break
		for r in _hud.element_rects():
			if not safe.encloses(r):
				outside.append("%dx%d" % [int(vp.x), int(vp.y)])
				break

	if intruding.is_empty():
		_ok("the centre stays clear at every aspect", "16:9, 21:9, 32:9, 720p")
	else:
		_no("centre clear", "HUD intrudes at " + ", ".join(intruding))

	if outside.is_empty():
		_ok("the HUD stays inside the safe area", "%.0f%% inset on every edge" % (CombatHUD.SAFE_AREA_MARGIN * 100.0))
	else:
		_no("safe area", "HUD leaves the safe area at " + ", ".join(outside))

	# The check is only meaningful if the reserved band is where we think.
	var probe := CombatHUD.clear_rect(Vector2(1000, 1000))
	if is_equal_approx(probe.size.x, 700.0) and is_equal_approx(probe.position.x, 150.0):
		_ok("the reserved band is centred", "700x700 at (150,150) in a 1000x1000 view")
	else:
		_no("clear rect", str(probe))


func _check_menu_input() -> void:
	# Brief: "All menus work with mouse, keyboard, and controller." Mouse needs
	# a hit-testable control, keyboard and controller need focus.
	var screen := RewardScreen.new()
	root.add_child(screen)
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	state.rewards_taken = 1
	var catalog: Array[SpiritData] = []
	for path in ["res://data/spirits/rune_hound.tres", "res://data/spirits/sword_wisp.tres"]:
		catalog.append(load(path) as SpiritData)
	screen.present(RewardSystem.new(catalog, 5).build_offer(state), state)

	var buttons := screen.card_buttons()
	var focusable := 0
	var clickable := 0
	for b in buttons:
		if b.focus_mode == Control.FOCUS_ALL:
			focusable += 1
		if b.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			clickable += 1

	if focusable == buttons.size() and buttons.size() > 0:
		_ok("every menu control takes keyboard and controller focus", "%d controls" % buttons.size())
	else:
		_no("menu focus", "%d of %d focusable" % [focusable, buttons.size()])

	if clickable == buttons.size():
		_ok("every menu control is mouse-hittable", "%d controls accept the pointer" % clickable)
	else:
		_no("menu mouse", "%d of %d hittable" % [clickable, buttons.size()])

	# Focus survives being opened, which is what a controller depends on.
	if screen.focused_index() >= 0:
		_ok("a menu grabs focus when it opens", "index %d" % screen.focused_index())
	else:
		_no("menu focus", "nothing focused on open")

	screen.queue_free()


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 13:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
