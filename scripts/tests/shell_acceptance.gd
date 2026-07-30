extends Node

## Acceptance checks for the game shell — the title/run/results loop F5 lands on.
##
##   godot --headless --path . scenes/tests/shell_acceptance.tscn
##
## This is the project's first **scene-based** suite, and the reason is a bug the
## twenty `--script` suites structurally could not see.
##
## `--script` runs a SceneTree with no main scene, which means **no autoloads are
## bound**. Every suite here therefore ran with GameSettings, SaveService and
## SceneFlow absent, and every piece of code that reaches for one had to have a
## null path just to be testable. That is fine. What is not fine is that it made
## the autoload path itself untestable — and the autoload path was broken:
##
##   Engine.has_singleton("GameSettings")  == false, always
##   /root/GameSettings                     == the autoload, in any real run
##
## Four guards were written the first way. Measured consequences: the audio
## director never picked up the volume sliders, the quality controller never read
## the graphics preference, and SceneFlow sat in BOOT for an entire run. All three
## failed silently in exactly the direction that looks like working software.
##
## So this suite runs as a scene, under --headless, with the autoloads bound, and
## asserts the wiring end to end. Anything that can be checked without a tree still
## belongs in a `--script` suite; this one exists for what cannot.

const STEP_FRAMES := 3

var _pass := 0
var _fail := 0
var _step := 0
var _frames := 0
var _shell: Node
var _save_stub: SaveStub

## Descendant counts per screen, keyed by screen name, to catch a leak across
## cycles. A shell that rebuilds the ward without freeing the last one grows here.
var _counts: Dictionary = {}


## Stands in for the SaveService autoload during the victory check. Records rather
## than persists, so a test win cannot write a bogus best time into a real save —
## and so the check can assert the win *was* recorded.
class SaveStub extends Node:
	var clear_times: Array[float] = []
	var starters: Array[String] = []

	func record_clear_time(seconds: float) -> void:
		clear_times.append(seconds)

	func discover_starter(id: String) -> void:
		starters.append(id)


func _ready() -> void:
	print("\n=== SHELL ACCEPTANCE ===\n")
	_check_autoloads()
	_check_main_scene()

	_save_stub = SaveStub.new()
	_save_stub.name = "SaveStub"
	add_child(_save_stub)

	var packed := load("res://scenes/game.tscn") as PackedScene
	if packed == null:
		_no("game scene", "cannot load res://scenes/game.tscn")
		_finish()
		return
	_shell = packed.instantiate()
	_shell.save_service_override = _save_stub
	add_child(_shell)


## The reason this suite is a scene and not a --script run.
func _check_autoloads() -> void:
	_section("Autoloads")
	for autoload_name in ["GameSettings", "SaveService", "SceneFlow"]:
		var node := AutoloadRef.node_named(autoload_name)
		if node != null:
			_ok("%s is bound" % autoload_name, node.get_path())
		else:
			_no(autoload_name, "not at /root/%s — is it still in project.godot?" % autoload_name)

	# Pinned deliberately. If a future Godot starts registering autoloads as engine
	# singletons this fails, and the right response is to read AutoloadRef again —
	# not to go back to has_singleton, which was wrong for a different reason.
	if not Engine.has_singleton("GameSettings"):
		_ok("Engine.has_singleton() does NOT see autoloads",
			"which is why AutoloadRef exists")
	else:
		_no("has_singleton", "autoloads are engine singletons now; revisit AutoloadRef")

	if AutoloadRef.settings() != null and AutoloadRef.save_service() != null \
			and AutoloadRef.scene_flow() != null:
		_ok("AutoloadRef resolves all three")
	else:
		_no("AutoloadRef", "one of the three lookups returned null with autoloads bound")

	var states: Dictionary = AutoloadRef.flow_states()
	if states.has("MENU") and states.has("RUN") and states.has("RESULTS"):
		_ok("SceneFlow states readable without the autoload", str(states.keys()))
	else:
		_no("flow states", "expected MENU/RUN/RESULTS, got %s" % str(states.keys()))


func _check_main_scene() -> void:
	_section("Entry point")
	var main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main == "res://scenes/game.tscn":
		_ok("F5 lands on the shell", main)
	else:
		_no("main scene", "expected res://scenes/game.tscn, got '%s'" % main)


# ------------------------------------------------------------------- the loop

## One check per step, three frames apart. The gaps are not padding: the slice
## builds its world in `_ready` and its nodes have no global_position until the
## first processed frame, and the focus grab on both menus is deferred.
func _process(_delta: float) -> void:
	if _shell == null:
		return
	_frames += 1
	if _frames < STEP_FRAMES:
		return
	_frames = 0

	match _step:
		0: _check_title()
		1: _check_run_started()
		2: _check_victory()
		3: _check_climb_again()
		4: _check_defeat()
		5: _check_back_to_title()
		6: _check_no_leak()
		_:
			_finish()
			return
	_step += 1


func _check_title() -> void:
	_section("Title screen")
	_record_count("title")
	if _shell.current_screen_name() == "title":
		_ok("shell opens on the title screen")
	else:
		_no("opening screen", "expected title, got '%s'" % _shell.current_screen_name())

	var t: TitleScreen = _shell.title()
	if t == null:
		_no("title screen", "shell.title() is null")
		return
	if t.button_count() == TitleScreen.BUTTONS.size():
		_ok("%d buttons built" % t.button_count())
	else:
		_no("buttons", "built %d of %d" % [t.button_count(), TitleScreen.BUTTONS.size()])

	# Guide §17: controller-playable throughout, so no button may be unreachable by
	# keyboard alone and something must be focused when the menu opens.
	if t.focus_chain_is_complete():
		_ok("no focus traps — every button is keyboard reachable")
	else:
		_no("focus chain", "at least one button has focus_mode NONE")
	if t.focused_index() == 0:
		_ok("first button has focus on open")
	else:
		_no("initial focus", "focused index is %d, expected 0" % t.focused_index())

	if AutoloadRef.flow_state_name() == "MENU":
		_ok("SceneFlow state is MENU")
	else:
		_no("flow state", "expected MENU, got '%s'" % AutoloadRef.flow_state_name())

	# Pressing Begin the Climb is what a player does; start_run() is what a check
	# would reach for. Press the button, so the connection is under test too.
	if t.press(&"start"):
		_ok("Begin the Climb is pressable")
	else:
		_no("start button", "press(&\"start\") found no such button")


func _check_run_started() -> void:
	_section("Run started")
	_record_count("playing")
	if _shell.current_screen_name() == "playing":
		_ok("pressing start reaches the run")
	else:
		_no("screen", "expected playing, got '%s'" % _shell.current_screen_name())

	if _shell.title() == null:
		_ok("the title screen was freed, not just hidden")
	else:
		_no("title teardown", "TitleScreen is still alive behind the run")

	var slice: PlayableSlice = _shell.run()
	if slice == null:
		_no("run", "shell.run() is null")
		return
	if slice.hero != null and slice.hero.is_inside_tree():
		_ok("hero is in the world")
	else:
		_no("hero", "no hero in the tree")
	if slice.summons.size() == 3:
		_ok("three summons bonded")
	else:
		_no("summons", "expected 3, got %d" % slice.summons.size())

	if AutoloadRef.flow_state_name() == "RUN":
		_ok("SceneFlow state is RUN")
	else:
		_no("flow state", "expected RUN, got '%s'" % AutoloadRef.flow_state_name())

	# The has_singleton fix, end to end. Both of these were null in every real run
	# while every suite was green, which is why they are asserted from a scene.
	if slice.quality != null and slice.quality.settings_source != null:
		_ok("quality controller found GameSettings")
	else:
		_no("quality settings", "settings_source is null in a run with autoloads bound")
	if slice.presentation != null and slice.presentation.audio != null \
			and slice.presentation.audio.settings_source != null:
		_ok("audio director found GameSettings — volume sliders are live")
	else:
		_no("audio settings", "settings_source is null; the volume sliders do nothing")

	var required: Array[StringName] = slice.required_encounters()
	if required.size() >= 2:
		_ok("%d encounters required to clear the stage" % required.size(), str(required))
	else:
		_no("clear condition", "only %d required encounters — a stage you clear by \
walking is not a stage" % required.size())

	# Stand in for actually fighting through the ward. The fight itself is the
	# playable suite's job; what is under test here is that the signal lands.
	slice.level_cleared.emit(212.5)


func _check_victory() -> void:
	_section("Victory")
	_record_count("results")
	if _shell.current_screen_name() == "results":
		_ok("clearing the stage reaches the results screen")
	else:
		_no("screen", "expected results, got '%s'" % _shell.current_screen_name())

	var r: RunResults = _shell.results()
	if r == null:
		_no("results", "shell.results() is null")
		return
	if r.outcome == RunResults.Outcome.VICTORY:
		_ok("outcome is Victory")
	else:
		_no("outcome", "expected Victory, got %s" % r.outcome_name())
	if r.is_open:
		_ok("the result state was opened")
	else:
		_no("results", "is_open is false")
	if is_equal_approx(r.clear_time_seconds, 212.5):
		_ok("clear time carried through", "%.1fs" % r.clear_time_seconds)
	else:
		_no("clear time", "expected 212.5, got %.1f" % r.clear_time_seconds)

	if _save_stub.clear_times.size() == 1 and is_equal_approx(_save_stub.clear_times[0], 212.5):
		_ok("a win records its clear time")
	else:
		_no("save", "expected one clear time of 212.5, got %s" % str(_save_stub.clear_times))
	if _save_stub.starters.size() == 3:
		_ok("all three starters recorded as discovered")
	else:
		_no("starters", "expected 3, got %d" % _save_stub.starters.size())

	# The counts are read off the run *before* it is torn down. Reading them after
	# is the obvious refactor and it silently reports "0 of 0".
	var detail := _find_label(_shell.results_ui(), "Detail")
	if detail != null and detail.text.contains("of 2"):
		_ok("results reports the encounters cleared", detail.text)
	else:
		_no("results detail", "expected 'of 2' in the summary, got '%s'"
			% (detail.text if detail != null else "<no Detail label>"))

	if AutoloadRef.flow_state_name() == "RESULTS":
		_ok("SceneFlow state is RESULTS")
	else:
		_no("flow state", "expected RESULTS, got '%s'" % AutoloadRef.flow_state_name())

	if _shell.run() == null:
		_ok("the run was freed on the way to results")
	else:
		_no("run teardown", "the whole ward is still alive behind the results screen")

	var buttons: Array[Button] = _shell.results_buttons()
	if buttons.size() == 2:
		_ok("results offers Climb Again and Title")
	else:
		_no("results buttons", "expected 2, got %d" % buttons.size())
		return
	# A tree left paused by the pause menu would freeze the results screen too.
	if not get_tree().paused:
		_ok("the tree is not paused on the results screen")
	else:
		_no("paused", "get_tree().paused is true — the results screen is frozen")
	buttons[0].emit_signal("pressed")


func _check_climb_again() -> void:
	_section("Climb Again")
	if _shell.current_screen_name() == "playing":
		_ok("Climb Again starts a second run")
	else:
		_no("screen", "expected playing, got '%s'" % _shell.current_screen_name())

	var before: int = int(_counts.get("playing", -1))
	var now := _descendants(_shell)
	if before == now:
		_ok("second run has the same node count as the first", "%d nodes" % now)
	else:
		_no("leak", "first run built %d nodes, second built %d" % [before, now])

	if _shell.results() == null:
		_ok("the previous result was dropped")
	else:
		_no("results teardown", "the old RunResults is still held")

	# Kill the hero rather than clearing the stage, to reach the other outcome.
	var slice: PlayableSlice = _shell.run()
	if slice == null or slice.hero == null:
		_no("hero", "no hero to defeat")
		return
	var hero := slice.hero as Player
	hero.died.emit()


func _check_defeat() -> void:
	_section("Defeat")
	if _shell.current_screen_name() == "results":
		_ok("a dead hero ends the run")
	else:
		_no("screen", "expected results, got '%s'" % _shell.current_screen_name())

	var r: RunResults = _shell.results()
	if r != null and r.outcome == RunResults.Outcome.DEFEAT:
		_ok("outcome is Defeat")
	else:
		_no("outcome", "expected Defeat, got %s" % (r.outcome_name() if r != null else "null"))

	# Only a win writes a time. A defeat that recorded one would put a loss on the
	# leaderboard.
	if _save_stub.clear_times.size() == 1:
		_ok("a defeat records no clear time")
	else:
		_no("save", "clear times after a loss: %s" % str(_save_stub.clear_times))

	var buttons: Array[Button] = _shell.results_buttons()
	if buttons.size() == 2:
		buttons[1].emit_signal("pressed")
	else:
		_no("results buttons", "expected 2, got %d" % buttons.size())


func _check_back_to_title() -> void:
	_section("Back to title")
	if _shell.current_screen_name() == "title":
		_ok("Title returns to the title screen")
	else:
		_no("screen", "expected title, got '%s'" % _shell.current_screen_name())

	var before: int = int(_counts.get("title", -1))
	var now := _descendants(_shell)
	if before == now:
		_ok("the title screen is rebuilt clean", "%d nodes" % now)
	else:
		_no("leak", "first title had %d nodes, second has %d" % [before, now])

	var t: TitleScreen = _shell.title()
	if t != null and t.focused_index() == 0:
		_ok("focus is back on the first button")
	else:
		_no("focus", "focused index is %d" % (t.focused_index() if t != null else -1))

	if AutoloadRef.flow_state_name() == "MENU":
		_ok("SceneFlow state is back to MENU")
	else:
		_no("flow state", "expected MENU, got '%s'" % AutoloadRef.flow_state_name())


## Three full cycles' worth of screens have now been built and freed. If any of
## them leaked, the shell's own child list is the place it shows.
func _check_no_leak() -> void:
	_section("No accumulation")
	if _shell.get_child_count() == 1:
		_ok("the shell holds exactly one screen at a time")
	else:
		var names: Array[String] = []
		for c in _shell.get_children():
			names.append(c.name)
		_no("screens", "shell has %d children: %s" % [_shell.get_child_count(), str(names)])


# ------------------------------------------------------------------- plumbing

func _find_label(root_node: Node, node_name: String) -> Label:
	if root_node == null:
		return null
	var found := root_node.find_child(node_name, true, false)
	return found as Label


func _descendants(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _descendants(c)
	return total


func _record_count(key: String) -> void:
	if not _counts.has(key):
		_counts[key] = _descendants(_shell)


func _section(title_text: String) -> void:
	print("\n-- %s" % title_text)


func _ok(what: String, detail: String = "") -> void:
	_pass += 1
	print("  ok   %s%s" % [what, "" if detail == "" else "  (%s)" % detail])


func _no(what: String, why: String) -> void:
	_fail += 1
	print("  FAIL %s: %s" % [what, why])


func _finish() -> void:
	print("\n%d passed, %d failed\n" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
