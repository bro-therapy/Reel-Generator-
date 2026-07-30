extends Node

## The outer loop: title -> play -> results -> title.
##
## This is what F5 runs. Until it existed the main scene was the playable build
## itself, which meant the game started mid-run with no way to begin it, no way to
## finish it, and no way to play it twice — you relaunched the executable instead.
##
## Every screen here already existed and was already tested in isolation.
## TitleScreen, RunResults and the playable build were all built and green; nothing
## put them in sequence. That is the same gap that made F5 show a Phase 0
## diagnostic for sixteen phases, appearing one layer further out.
##
## The shell owns transitions and nothing else. It never touches combat, balance or
## presentation, so the suites for those keep testing them without knowing this
## exists.

const PLAYABLE := preload("res://scenes/playable.tscn")

enum Screen { TITLE, PLAYING, RESULTS }

var screen: Screen = Screen.TITLE

var _title: TitleScreen
var _slice: PlayableSlice
## RunResults is a RefCounted, not a Node — it is the *model* of a finished run,
## and Phase 14 tests it without a tree. So it is held, never added as a child.
var _results: RunResults
var _results_ui: Control

## Where a finished run records its best time. Left null in the game, where
## RunResults finds the SaveService autoload on its own. The acceptance suite
## injects a stub, because a test victory must not write a bogus clear time into
## the player's real save — and because asserting the stub was called is a
## stronger check than asserting nothing happened.
var save_service_override: Node = null


func _ready() -> void:
	_show_title()


# ---------------------------------------------------------------------- title

func _show_title() -> void:
	_teardown()
	screen = Screen.TITLE
	AutoloadRef.set_flow_state("MENU")

	_title = TitleScreen.new()
	_title.name = "Title"
	add_child(_title)
	_title.start_requested.connect(start_run)
	_title.quit_requested.connect(_on_quit)
	print("[shell] title")


func _on_quit() -> void:
	# quit() rather than a hard exit, so Godot flushes and the editor stops cleanly.
	get_tree().quit()


# --------------------------------------------------------------------- playing

## Begins a run. Public so a check can drive the whole loop without synthesising
## button presses through the viewport.
func start_run() -> void:
	_teardown()
	screen = Screen.PLAYING
	# No set_flow_state("RUN") here: the slice's own _ready does it, because the
	# slice must also work launched directly (scenes/playable.tscn). A duplicate
	# call here was a mutant the shell suite could not kill — dead code, so gone.

	_slice = PLAYABLE.instantiate() as PlayableSlice
	_slice.name = "Run"
	add_child(_slice)
	_slice.level_cleared.connect(_on_level_cleared)
	# A dead hero ends the run too. Without this the only outcome is victory, and a
	# run you cannot lose is not a run.
	var hero := _slice.hero as Player
	if hero != null:
		hero.died.connect(_on_hero_died)
	print("[shell] run started")


func _on_level_cleared(seconds: float) -> void:
	_show_results(RunResults.Outcome.VICTORY, seconds)


func _on_hero_died() -> void:
	_show_results(RunResults.Outcome.DEFEAT,
		_slice.elapsed_seconds() if _slice != null else 0.0)


# --------------------------------------------------------------------- results

func _show_results(outcome: RunResults.Outcome, seconds: float) -> void:
	if screen == Screen.RESULTS:
		return
	# Read everything off the run before tearing it down. Doing this after the free
	# is how a results screen ends up reporting 0 of 0 encounters.
	var state: RunState = _slice.run if _slice != null else null
	var cleared: int = _slice.cleared_encounters().size() if _slice != null else 0
	var required: int = _slice.required_encounters().size() if _slice != null else 0
	_teardown()
	screen = Screen.RESULTS
	AutoloadRef.set_flow_state("RESULTS")

	# The tested results model still does the recording; this only presents it.
	_results = RunResults.new()
	_results.save_service = save_service_override
	_results.open(outcome, seconds, state)

	_results_ui = _build_results_ui(outcome, seconds, cleared, required)
	add_child(_results_ui)
	print("[shell] results: %s — %d/%d encounters in %.1fs"
		% [_results.outcome_name(), cleared, required, seconds])


func _build_results_ui(outcome: RunResults.Outcome, seconds: float,
		cleared: int, required: int) -> Control:
	var root_ui := Control.new()
	root_ui.name = "ResultsScreen"
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.043, 0.11)
	root_ui.add_child(bg)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	root_ui.add_child(column)

	var won := outcome == RunResults.Outcome.VICTORY
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "SUNFALL WARD CLEARED" if won else "THE CLIMB ENDS HERE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 52)
	# Colour ownership holds even here: gold for a reward, warm for a loss. Never
	# violet on the failure line — violet is the player's own colour.
	heading.add_theme_color_override("font_color",
		Color(0.95, 0.82, 0.45) if won else Color(0.9, 0.5, 0.4))
	column.add_child(heading)

	var detail := Label.new()
	detail.name = "Detail"
	detail.text = "%d of %d encounters   ·   %d:%02d" % [
		cleared, required, int(seconds) / 60, int(seconds) % 60]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 24)
	detail.add_theme_color_override("font_color", Color(0.6, 0.56, 0.75))
	column.add_child(detail)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	column.add_child(gap)

	_results_buttons.clear()
	for entry in RESULT_BUTTONS:
		var b := Button.new()
		b.name = "Button_%s" % entry["id"]
		b.text = entry["text"]
		b.custom_minimum_size = Vector2(300, 52)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 20)
		if entry["id"] == &"again":
			b.pressed.connect(start_run)
		else:
			b.pressed.connect(_show_title)
		column.add_child(b)
		_results_buttons.append(b)

	# Deferred: grab_focus on a Control that is not in the tree yet does nothing,
	# and this whole subtree is built before it is added.
	if not _results_buttons.is_empty():
		_results_buttons[0].call_deferred("grab_focus")

	return root_ui


const RESULT_BUTTONS := [
	{"id": &"again", "text": "Climb Again"},
	{"id": &"title", "text": "Title"},
]

var _results_buttons: Array[Button] = []


# ---------------------------------------------------------------------- shared

## Drops whatever screen is up.
##
## This started out as `free()` — deliberately, so a transition would not leave the
## outgoing screen alive for a frame. That is impossible, and the shell suite said
## so on its first run: *Attempted to free a locked object (calling or emitting)*.
## Every transition here is driven by a signal from the screen being torn down —
## the title's `pressed`, the run's `level_cleared`, the hero's `died` — so the
## outgoing node is always mid-emit and always locked. `free()` did not fail
## loudly and stop; it failed, logged, and left the whole ward alive behind the
## results screen.
##
## So: unparent now, free at idle. Removing the child is not blocked by the lock,
## which means the shell's child list and `title()`/`run()` are correct
## immediately, and the actual delete happens when nothing is on the stack.
func _teardown() -> void:
	# A run that ends while paused must not hand a frozen tree to the results
	# screen. Pausing lives inside the slice, so nothing else would clear it.
	if is_inside_tree():
		get_tree().paused = false

	var doomed: Array[Node] = []
	for node in [_title, _slice, _results_ui]:
		if node != null and is_instance_valid(node):
			doomed.append(node)
	_title = null
	_slice = null
	_results_ui = null
	_results_buttons.clear()
	# RefCounted: dropping the reference is the free.
	_results = null

	for node in doomed:
		remove_child(node)
		node.queue_free()


# ------------------------------------------------------------------ inspection

func current_screen_name() -> String:
	return ["title", "playing", "results"][int(screen)]


func run() -> PlayableSlice:
	return _slice


func title() -> TitleScreen:
	return _title


func results() -> RunResults:
	return _results


func results_buttons() -> Array[Button]:
	return _results_buttons


func results_ui() -> Control:
	return _results_ui
