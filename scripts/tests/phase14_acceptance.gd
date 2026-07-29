extends SceneTree

## Phase 14 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase14_acceptance.gd
##
## The four criteria:
##   - Settings survive restart.
##   - Corrupt or missing save creates defaults without crashing.
##   - Victory and defeat both return to a result screen.
##   - Restarting creates a clean RunState.

const SAVE_SCRIPT := "res://scripts/run/save_service.gd"
const SETTINGS_SCRIPT := "res://scripts/run/game_settings.gd"
const STAFF := "res://data/weapons/conjurer_staff.tres"
const SPIRIT := "res://data/spirits/rune_hound.tres"

var _pass := 0
var _fail := 0
## Built by hand: a `--script` run binds no autoloads.
var _settings: Node
var _save: Node


func _initialize() -> void:
	print("\n=== PHASE 14 ACCEPTANCE ===\n")
	var made: Variant = (load(SETTINGS_SCRIPT) as GDScript).new()
	_settings = made as Node
	_settings.name = "GameSettings"
	root.add_child(_settings)

	_check_settings_round_trip()
	_check_corrupt_save()
	_check_missing_save()
	_check_results()
	_check_clean_restart()
	_summary()


func _fresh_save() -> Node:
	# GDScript.new() returns Variant, so the type is stated rather than inferred.
	var s: Node = (load(SAVE_SCRIPT) as GDScript).new()
	s.name = "SaveService"
	s.settings_source = _settings
	root.add_child(s)
	return s


func _save_path() -> String:
	var path: Variant = (load(SAVE_SCRIPT) as GDScript).get("SAVE_PATH")
	return String(path)


func _check_settings_round_trip() -> void:
	# Brief: "Settings survive restart." Simulated by writing, discarding the
	# service entirely, and building a new one — which is what a restart is.
	var save := _fresh_save()
	_settings.reset_to_defaults()
	_settings.set_setting("reduced_screen_shake", true)
	_settings.set_setting("effect_opacity", 0.35)
	save.set_value("best_clear_time_seconds", 0.0)
	save.record_clear_time(412.5)
	save.discover_starter("rune_hound")

	var wrote: bool = bool(save.save_game())
	if not wrote:
		_no("save", "save_game() failed")
		return
	save.queue_free()

	# Restart: new service, settings wiped first so a pass cannot come from
	# values that simply never changed.
	_settings.reset_to_defaults()
	var reloaded := _fresh_save()
	var ok: bool = bool(reloaded.load_game())

	var shake := bool(_settings.get_setting("reduced_screen_shake"))
	var opacity := float(_settings.get_setting("effect_opacity"))
	if ok and shake and is_equal_approx(opacity, 0.35):
		_ok("settings survive a restart", "shake on, opacity 0.35 after reload")
	else:
		_no("settings persistence", "loaded=%s shake=%s opacity=%.2f" % [ok, shake, opacity])

	if is_equal_approx(float(reloaded.get_value("best_clear_time_seconds", -1.0)), 412.5):
		_ok("the best clear time survives a restart", "412.5 s")
	else:
		_no("clear time", str(reloaded.get_value("best_clear_time_seconds", "missing")))

	var found_raw: Variant = reloaded.get_value("discovered_starters", [])
	var found: Array = found_raw if found_raw is Array else []
	if found.has("rune_hound"):
		_ok("discovered starters survive a restart", str(found))
	else:
		_no("discovered starters", str(found))

	# Only an improvement replaces the record.
	reloaded.record_clear_time(500.0)
	var kept := float(reloaded.get_value("best_clear_time_seconds", -1.0))
	reloaded.record_clear_time(300.0)
	var improved := float(reloaded.get_value("best_clear_time_seconds", -1.0))
	if is_equal_approx(kept, 412.5) and is_equal_approx(improved, 300.0):
		_ok("only a faster run replaces the record", "412.5 kept over 500, replaced by 300")
	else:
		_no("clear time record", "%.1f then %.1f" % [kept, improved])

	reloaded.queue_free()


func _check_corrupt_save() -> void:
	# Brief: "Corrupt or missing save creates defaults without crashing."
	var path: String = _save_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json at all ][ ")
	f.close()

	var save := _fresh_save()
	var loaded: bool = bool(save.load_game())

	# Returning false is correct — it means "no usable save" — and the defaults
	# have to be there anyway.
	var best := float(save.get_value("best_clear_time_seconds", -1.0))
	if not loaded and is_equal_approx(best, 0.0):
		_ok("a corrupt save falls back to defaults", "load reported failure, defaults intact")
	else:
		_no("corrupt save", "loaded=%s best=%.1f" % [loaded, best])

	# And it can be written over, so the player is not stuck with a broken file.
	var rewrote: bool = bool(save.save_game())
	var reread: bool = bool(_fresh_save().load_game())
	if rewrote and reread:
		_ok("a corrupt save can be overwritten", "the next write recovers it")
	else:
		_no("corrupt recovery", "could not rewrite the save")
	save.queue_free()

	# A save from a future version is refused rather than half-read.
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(JSON.stringify({"version": 999, "best_clear_time_seconds": 7.0}))
	f2.close()
	var future := _fresh_save()
	var future_loaded: bool = bool(future.load_game())
	if not future_loaded and is_equal_approx(float(future.get_value("best_clear_time_seconds", -1.0)), 0.0):
		_ok("a future save version is refused", "defaults rather than a half-read file")
	else:
		_no("version guard", "accepted version 999")
	future.queue_free()


func _check_missing_save() -> void:
	var path: String = _save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var save := _fresh_save()
	var loaded: bool = bool(save.load_game())
	if not loaded and is_equal_approx(float(save.get_value("best_clear_time_seconds", -1.0)), 0.0):
		_ok("a missing save creates defaults", "no file, no crash")
	else:
		_no("missing save", "loaded=%s" % loaded)
	save.queue_free()


func _check_results() -> void:
	# Brief: "Victory and defeat both return to a result screen."
	var save := _fresh_save()

	for outcome in [RunResults.Outcome.VICTORY, RunResults.Outcome.DEFEAT]:
		var state := RunState.new(load(STAFF) as FocusWeaponData)
		state.bond(load(SPIRIT) as SpiritData)
		var results := RunResults.new()
		results.save_service = save

		var opened: Array = []
		results.opened.connect(func(o: int) -> void: opened.append(o))
		var did: bool = results.open(outcome, 240.0, state)

		if did and results.is_open and opened.size() == 1:
			_ok("%s opens the result screen" % results.outcome_name().to_lower(), "one open signal")
		else:
			_no("result screen", "%s did not open cleanly" % results.outcome_name())

		# Latched, exactly like boss defeat: a Stability wipe landing on the same
		# frame as a killing blow must not open two screens.
		results.open(RunResults.Outcome.DEFEAT, 1.0, state)
		results.open(RunResults.Outcome.VICTORY, 1.0, state)
		if opened.size() == 1:
			_ok("the result screen opens exactly once", "3 attempts, 1 signal")
		else:
			_no("result latch", "%d open signals" % opened.size())

	# Only a win writes the record.
	save.set_value("best_clear_time_seconds", 0.0)
	var lost := RunResults.new()
	lost.save_service = save
	lost.open(RunResults.Outcome.DEFEAT, 90.0, null)
	var after_loss := float(save.get_value("best_clear_time_seconds", -1.0))

	var won := RunResults.new()
	won.save_service = save
	won.open(RunResults.Outcome.VICTORY, 95.0, null)
	var after_win := float(save.get_value("best_clear_time_seconds", -1.0))

	if is_equal_approx(after_loss, 0.0) and is_equal_approx(after_win, 95.0):
		_ok("only a victory writes a clear time", "loss left it at 0, win wrote 95 s")
	else:
		_no("clear time on loss", "%.1f after loss, %.1f after win" % [after_loss, after_win])

	save.queue_free()


func _check_clean_restart() -> void:
	# Brief: "Restarting creates a clean RunState."
	var dirty := RunState.new(load(STAFF) as FocusWeaponData)
	dirty.bond(load(SPIRIT) as SpiritData)
	dirty.apply_echo(&"rune_hound")
	dirty.add_currency(500)
	dirty.add_relic(&"exiles_ledger")
	dirty.adjust_stability(-60)
	dirty.rewards_taken = 4
	dirty.reached_spirit_well = true
	dirty.well_heal_used = true

	var fresh := RunResults.restart(load(STAFF) as FocusWeaponData)

	var clean := (
		fresh.filled_slot_count() == 0
		and fresh.currency == 0
		and fresh.relics.is_empty()
		and fresh.stability == fresh.max_stability
		and fresh.rewards_taken == 0
		and not fresh.reached_spirit_well
		and not fresh.well_heal_used
		and fresh.tiers.is_empty()
	)
	if clean:
		_ok("restarting creates a clean run", "no bonds, relics, currency or spent Stability")
	else:
		_no("restart", "bonds %d, currency %d, relics %d, stability %d" % [
			fresh.filled_slot_count(), fresh.currency, fresh.relics.size(), fresh.stability])

	# The old run must be untouched — a restart that mutates the finished run in
	# place would corrupt the result screen still showing it.
	if dirty.filled_slot_count() == 1 and dirty.currency == 500 and fresh != dirty:
		_ok("the finished run is left intact", "the result screen can still read it")
	else:
		_no("restart isolation", "the previous run was mutated")

	# Two restarts must not share state either.
	var a := RunResults.restart(load(STAFF) as FocusWeaponData)
	a.add_currency(75)
	var b := RunResults.restart(load(STAFF) as FocusWeaponData)

	# Identity, not equality: two empty bond arrays compare equal by value, so
	# `a.bonds != b.bonds` would pass even if both runs shared one array. Writing
	# into one and reading the other is the only thing that proves they are
	# separate.
	a.bonds[0] = load(SPIRIT) as SpiritData
	if b.currency == 0 and a.currency == 75 and b.bonds[0] == null:
		_ok("separate restarts do not share state", "writing into one leaves the other empty")
	else:
		_no("restart sharing", "b.currency=%d, b.bonds[0]=%s" % [b.currency, str(b.bonds[0])])


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 14:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
