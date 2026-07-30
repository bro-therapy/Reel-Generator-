extends SceneTree

## Phase 1 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase1_acceptance.gd
##
## Drives the real hero sandbox and steps physics, rather than asserting on
## configuration. Exits non-zero if any check fails.

const SANDBOX := "res://scenes/tests/hero_sandbox.tscn"
const PIVOT_AUDIT := "res://docs/generated/hero_pivot_audit.json"
const OFFSETS := "res://data/characters/tower_exile_pivot_offsets.json"

const TICK := 1.0 / 60.0
const HERO_TARGET_PX := 88.0
const HERO_TOLERANCE_PX := 6.0

var _pass := 0
var _fail := 0

var _sandbox: Node3D
var _player: Player
var _camera: Camera3D

var _stage := 0
var _ticks := 0
var _mark := 0.0
var _mark_vec := Vector3.ZERO
var _dash_start := Vector3.ZERO
var _dash_ticks := 0
var _dash_anim_checked := false
var _accel_ticks := 0
var _reach_ticks := 0
var _decel_ticks := 0


func _initialize() -> void:
	print("\n=== PHASE 1 ACCEPTANCE ===\n")

	_check_facing_math()
	_check_pivot_correction()

	var packed := load(SANDBOX) as PackedScene
	if packed == null:
		_no("sandbox loads", "cannot load %s" % SANDBOX)
		_summary()
		return
	_sandbox = packed.instantiate() as Node3D
	root.add_child(_sandbox)
	_player = _sandbox.get_node_or_null("Player") as Player
	_camera = _sandbox.get_node_or_null("Camera3D") as Camera3D

	if _player == null:
		_no("player present in sandbox", "Player node missing or wrong type")
		_summary()
		return
	_ok("sandbox instantiates with Player and Camera")


func _physics_process(delta: float) -> bool:
	if _player == null:
		return true
	_ticks += 1
	# Let the scene settle before driving input.
	if _ticks < 5:
		return false

	match _stage:
		0: _stage_accel_start()
		1: _stage_accel_watch()
		2: _stage_decel_watch()
		3: _stage_dash_start()
		4: _stage_dash_watch()
		5: _stage_dash_cooldown()
		6: _stage_damage_grace()
		7: _stage_screen_height()
		_:
			_summary()
			return true
	return false


# ---------------------------------------------------------------- stages

func _stage_accel_start() -> void:
	# Runs on the first physics tick, so Player._ready() has already applied
	# balance to the resource. Checking this in _initialize() reads the raw
	# .tres and misses any drift introduced at load time.
	_check_data_matches_balance(_player)
	Input.action_press("move_right")
	_accel_ticks = 0
	_stage = 1


func _stage_accel_watch() -> void:
	_accel_ticks += 1
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	# Read the target from the JSON, never from the resource under test —
	# otherwise a wrong resource value is compared against itself and passes.
	var target: float = float(Balance.get_value("player/move_speed_units_per_second", 6.2))

	if _reach_ticks == 0 and speed >= target - 0.02:
		_reach_ticks = _accel_ticks

	# Hold well past saturation so the settled speed can be measured. Stopping
	# the moment speed crosses the target would accept any higher top speed.
	if _accel_ticks * TICK < 0.6:
		return

	if _reach_ticks > 0:
		var expected := target / float(Balance.get_value("player/acceleration", 35.0))
		var actual := float(_reach_ticks) * TICK
		if absf(actual - expected) <= TICK * 2.5:
			_ok("reaches full speed smoothly", "%.3fs to %.2f u/s (expected ~%.3fs)" % [actual, target, expected])
		else:
			_no("reaches full speed smoothly", "took %.3fs, expected ~%.3fs" % [actual, expected])
	else:
		_no("reaches full speed", "never reached %.2f u/s in 0.6s (peaked %.2f)" % [target, speed])

	if absf(speed - target) <= 0.05:
		_ok("top speed settles at the balance value", "%.3f u/s vs %.2f in JSON" % [speed, target])
	else:
		_no("top speed", "settled at %.3f u/s, JSON says %.2f" % [speed, target])

	Input.action_release("move_right")
	_decel_ticks = 0
	_stage = 2


func _stage_decel_watch() -> void:
	_decel_ticks += 1
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed <= 0.001:
		var expected: float = float(Balance.get_value("player/move_speed_units_per_second", 6.2)) / float(Balance.get_value("player/deceleration", 42.0))
		var actual := float(_decel_ticks) * TICK
		if absf(actual - expected) <= TICK * 2.5:
			_ok("stops without sliding", "%.3fs to rest (expected ~%.3fs)" % [actual, expected])
		else:
			_no("stops without sliding", "took %.3fs, expected ~%.3fs" % [actual, expected])
		_stage = 3
	elif _decel_ticks > 120:
		_no("stops without sliding", "still moving at %.3f u/s after 2s" % speed)
		_stage = 3


func _stage_dash_start() -> void:
	if not _player.can_dash():
		_no("dash available", "can_dash() false at rest with no cooldown")
		_stage = 6
		return
	_player.facing_index = 6  # east, so the dash runs along +X
	_dash_start = _player.global_position
	_dash_ticks = 0
	if not _player.try_dash():
		_no("dash triggers", "try_dash() returned false")
		_stage = 6
		return
	_stage = 4


func _stage_dash_watch() -> void:
	_dash_ticks += 1
	if _player.is_dashing():
		# Mid-dash is the only window where the dash animation can be observed.
		# Checked once, on the second dashing tick (the first tick's animation
		# update may not have run yet when the stage saw the state flip).
		if _dash_ticks == 2 and not _dash_anim_checked:
			_dash_anim_checked = true
			var frames := _player.sprite_frames_or_null()
			if frames != null and frames.has_animation("dash"):
				if _player.current_animation() == "dash":
					_ok("dash plays its own animation", "the action-atlas lunge")
				else:
					_no("dash animation", "dashing but showing '%s'" % _player.current_animation())
			else:
				print("        - no dash animation in SpriteFrames (action frames not installed)")
		if _dash_ticks > 60:
			_no("dash ends", "still dashing after 1s")
			_stage = 5
		return

	var duration := float(_dash_ticks) * TICK
	var travelled := _player.global_position.distance_to(_dash_start)
	# Both expectations come from LEVEL1_BALANCE.json, so a resource that drifts
	# from the spec fails instead of quietly moving the goalposts.
	var expected_duration: float = float(Balance.get_value("player/dash_duration_seconds", 0.18))
	var expected_distance: float = float(Balance.get_value("player/dash_distance_units", 4.3))

	# One physics tick of quantisation is unavoidable at 60 Hz.
	if absf(duration - expected_duration) <= TICK * 1.5:
		_ok("dash duration", "%.3fs (target %.2fs)" % [duration, expected_duration])
	else:
		_no("dash duration", "%.3fs, expected %.2fs" % [duration, expected_duration])

	if absf(travelled - expected_distance) <= 0.25:
		_ok("dash distance", "%.3f units (target %.1f)" % [travelled, expected_distance])
	else:
		_no("dash distance", "%.3f units, expected %.1f" % [travelled, expected_distance])

	_mark = 0.0
	_stage = 5


func _stage_dash_cooldown() -> void:
	_mark += TICK
	if _mark < 0.05:
		if _player.can_dash():
			_no("dash respects cooldown", "dash available immediately after dashing")
			_stage = 6
		return

	var remaining := _player.dash_cooldown_remaining()
	if remaining > 0.0 and not _player.can_dash():
		_ok("dash respects cooldown", "%.2fs remaining of %.2fs" % [remaining, float(Balance.get_value("player/dash_cooldown_seconds", 1.35))])
	else:
		_no("dash respects cooldown", "can_dash()=%s remaining=%.2f" % [_player.can_dash(), remaining])
	_stage = 6


func _stage_damage_grace() -> void:
	var start_hp: int = _player.hp

	# Dash i-frames may still be running; clear them by waiting them out.
	if _player.is_invulnerable():
		_mark += TICK
		if _mark > 2.0:
			_no("grace window", "player stuck invulnerable")
			_stage = 7
		return

	var first := _player.take_damage(10)
	var second := _player.take_damage(10)
	var third := _player.take_damage(10)

	if first and not second and not third:
		_ok("cannot take two hits inside contact grace", "1 of 3 landed within %.2fs" % _player.data.contact_grace_seconds)
	else:
		_no("contact grace", "landed=[%s, %s, %s]" % [first, second, third])

	if _player.hp == start_hp - 10:
		_ok("only one hit applied to HP", "%d -> %d" % [start_hp, _player.hp])
	else:
		_no("HP after grace burst", "%d -> %d, expected %d" % [start_hp, _player.hp, start_hp - 10])

	_mark = 0.0
	_stage = 7


func _stage_screen_height() -> void:
	# Wait for the viewport to have a real size before projecting.
	_mark += TICK
	if _mark < 0.1:
		return

	if _camera == null:
		_no("hero screen height", "no Camera3D in sandbox")
		_stage = 99
		return

	var vp_size := root.get_viewport().get_visible_rect().size
	var feet := _player.global_position
	var head := feet + Vector3(0.0, _player.world_height(), 0.0)
	var feet_px := _camera.unproject_position(feet)
	var head_px := _camera.unproject_position(head)
	var px := absf(feet_px.y - head_px.y)

	# Normalise to a 1080-tall viewport in case headless reports another size.
	var scaled := px * (1080.0 / maxf(vp_size.y, 1.0))

	if absf(scaled - HERO_TARGET_PX) <= HERO_TOLERANCE_PX:
		_ok("hero reads near 88 px at 1080p", "%.1f px (viewport %dx%d)" % [scaled, int(vp_size.x), int(vp_size.y)])
	else:
		_no("hero screen height", "%.1f px at 1080p, target %.0f +/- %.0f" % [scaled, HERO_TARGET_PX, HERO_TOLERANCE_PX])
	_stage = 99


# ---------------------------------------------------------------- static checks

func _check_facing_math() -> void:
	print("Eight-direction facing")
	# +X is screen-right (east), +Z is toward the camera (south).
	var cases := {
		"south": Vector3(0, 0, 1),
		"southwest": Vector3(-1, 0, 1),
		"west": Vector3(-1, 0, 0),
		"northwest": Vector3(-1, 0, -1),
		"north": Vector3(0, 0, -1),
		"northeast": Vector3(1, 0, -1),
		"east": Vector3(1, 0, 0),
		"southeast": Vector3(1, 0, 1),
	}
	var wrong: Array[String] = []
	for expected_name in cases:
		var idx: int = Player.direction_index_from_vector(cases[expected_name])
		var got: String = Player.DIRECTION_NAMES[idx]
		if got != expected_name:
			wrong.append("%s -> %s" % [expected_name, got])
	if wrong.is_empty():
		_ok("all 8 octants map to the manifest row order")
	else:
		_no("octant mapping", "; ".join(wrong))

	# Every direction needs an idle and a run animation.
	var frames := load("res://data/characters/tower_exile_frames.tres") as SpriteFrames
	if frames == null:
		_no("locomotion SpriteFrames", "failed to load")
		return
	var missing: Array[String] = []
	for dir_name in Player.DIRECTION_NAMES:
		for prefix in ["idle", "run"]:
			var anim := "%s_%s" % [prefix, dir_name]
			if not frames.has_animation(anim):
				missing.append(anim)
	if missing.is_empty():
		_ok("16 animations present (idle + run x 8)")
	else:
		_no("animations", "missing: %s" % ", ".join(missing))


## Guards against the resource silently diverging from the balance file. Phase 3
## had this check and survived mutation testing; Phases 1 and 2 did not.
func _check_data_matches_balance(p: Player) -> void:
	print("\nCharacterData vs LEVEL1_BALANCE.json")
	var expect := {
		"max_hp": [float(p.data.max_hp), "player/max_hp"],
		"move speed": [p.data.move_speed_units_per_second, "player/move_speed_units_per_second"],
		"acceleration": [p.data.acceleration, "player/acceleration"],
		"deceleration": [p.data.deceleration, "player/deceleration"],
		"dash distance": [p.data.dash_distance_units, "player/dash_distance_units"],
		"dash duration": [p.data.dash_duration_seconds, "player/dash_duration_seconds"],
		"dash cooldown": [p.data.dash_cooldown_seconds, "player/dash_cooldown_seconds"],
		"dash i-frames": [p.data.dash_invulnerability_seconds, "player/dash_invulnerability_seconds"],
		"contact grace": [p.data.contact_grace_seconds, "player/contact_grace_seconds"],
	}
	var wrong: Array[String] = []
	for label in expect:
		var pair: Array = expect[label]
		var want: float = float(Balance.get_value(String(pair[1]), NAN))
		if is_nan(want) or not is_equal_approx(float(pair[0]), want):
			wrong.append("%s resource=%s json=%s" % [label, pair[0], want])
	if wrong.is_empty():
		_ok("every CharacterData field matches the balance JSON", "%d fields" % expect.size())
	else:
		_no("CharacterData drift", "; ".join(wrong))


func _check_pivot_correction() -> void:
	print("\nGround pivot")
	if not FileAccess.file_exists(PIVOT_AUDIT) or not FileAccess.file_exists(OFFSETS):
		_no("pivot data", "run scripts/tools/build_hero_spriteframes.gd first")
		return

	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PIVOT_AUDIT))
	var offsets_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OFFSETS))
	var offsets: Dictionary = offsets_doc.get("offsets", {})
	var baseline := int(offsets_doc.get("baseline_foot_row", 0))
	var frames: Dictionary = audit.get("frames", {})

	var raw_spread := int(audit.get("baseline_spread_px", 0))

	# Apply each correction to its source frame and confirm every foot row
	# lands on the shared baseline.
	var residuals: Array[String] = []
	var worst := 0

	# The gait layout comes from the generated file, not from a copy typed here.
	# A hardcoded [1,2,3,4] -> run_* mapping is what broke when walk was split out
	# of run: the check went on verifying corrections against frames that had been
	# renumbered underneath it, and reported the mismatch as pivot bob.
	var gaits: Dictionary = offsets_doc.get("gaits", {})
	var col_names: Array = offsets_doc.get("column_names", [])
	if gaits.is_empty() or col_names.is_empty():
		_no("pivot layout", "the offsets file publishes no gait layout — rebuild with "
			+ "scripts/tools/build_hero_spriteframes.gd")
		return

	var checked := 0
	for dir_index in Player.DIRECTION_NAMES.size():
		var dir_name: String = Player.DIRECTION_NAMES[dir_index]
		for gait in gaits.keys():
			var columns: Array = gaits[gait]
			for i in columns.size():
				var col := int(columns[i])
				if col >= col_names.size():
					continue
				var key := "%02d_%s__%02d_%s" % [dir_index, dir_name, col, col_names[col]]
				worst = maxi(worst, _residual(
					frames, offsets, key, "%s_%s/%d" % [gait, dir_name, i],
					baseline, residuals))
				checked += 1

	if residuals.is_empty():
		_ok("no pivot bob after correction", "raw art spread was %d px, residual 0 px across %d animation frames" % [raw_spread, checked])
	else:
		_no("pivot bob", "worst residual %d px on %d frames: %s" % [worst, residuals.size(), ", ".join(residuals.slice(0, 4))])

	var corrected := int(offsets_doc.get("corrected_frame_count", 0))
	if corrected > 0:
		_ok("pivot corrections generated", "%d of %d frames need offsetting" % [corrected, frames.size()])


func _residual(frames: Dictionary, offsets: Dictionary, frame_key: String, offset_key: String, baseline: int, out: Array[String]) -> int:
	var m: Dictionary = frames.get(frame_key, {})
	if not m.has("foot_row"):
		return 0
	var corrected: int = int(m["foot_row"]) + int(offsets.get(offset_key, 0))
	var residual: int = absi(corrected - baseline)
	if residual > 0:
		out.append("%s(%dpx)" % [frame_key, residual])
	return residual


# ---------------------------------------------------------------- reporting

func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _sandbox != null and is_instance_valid(_sandbox):
		_sandbox.queue_free()
		_sandbox = null
	print("\n" + "=".repeat(46))
	print("PHASE 1:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
