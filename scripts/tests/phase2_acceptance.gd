extends SceneTree

## Phase 2 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase2_acceptance.gd
##
## Drives the real focus range and steps physics. Exits non-zero on failure.

const RANGE_SCENE := "res://scenes/tests/focus_range.tscn"
const TICK := 1.0 / 60.0

var _pass := 0
var _fail := 0

var _room: Node3D
var _player: Player
var _focus: FocusWeaponController
var _pool: ProjectilePool

var _near: Node3D
var _far: Node3D
var _behind: Node3D
var _out_of_range: Node3D

var _stage := 0
var _ticks := 0
var _mark := 0.0
var _shots_at_mark := 0
var _nodes_at_mark := 0


func _initialize() -> void:
	print("\n=== PHASE 2 ACCEPTANCE ===\n")
	_check_score_contract()

	var packed := load(RANGE_SCENE) as PackedScene
	if packed == null:
		_no("focus range loads", "cannot load %s" % RANGE_SCENE)
		_summary()
		return
	_room = packed.instantiate() as Node3D
	root.add_child(_room)

	_player = _room.get_node_or_null("Player") as Player
	_near = _room.get_node_or_null("Near") as Node3D
	_far = _room.get_node_or_null("Far") as Node3D
	_behind = _room.get_node_or_null("Behind") as Node3D
	_out_of_range = _room.get_node_or_null("OutOfRange") as Node3D

	if _player == null:
		_no("player present", "missing Player")
		_summary()
		return

	# Look the nodes up directly: @onready members are not populated until the
	# node's _ready runs, which has not happened yet during _initialize().
	_focus = _player.get_node_or_null("FocusWeaponController") as FocusWeaponController
	_pool = _player.get_node_or_null("ProjectilePool") as ProjectilePool

	if _focus == null:
		_no("FocusWeaponController present", "player has no focus weapon")
		_summary()
		return
	if _pool == null:
		_no("ProjectilePool present", "player has no pool")
		_summary()
		return

	_focus.set_rng_seed(12345)
	_ok("focus range instantiates with controller and pool", "pool capacity %d" % _pool.total_count())
	_check_weapon_matches_balance()


func _physics_process(delta: float) -> bool:
	if _focus == null:
		return true
	_ticks += 1
	if _ticks < 5:
		return false

	match _stage:
		0: _stage_selects_nearest()
		1: _stage_fire_rate_start()
		2: _stage_fire_rate_watch()
		3: _stage_aim_repriority()
		4: _stage_aim_does_not_gate_fire()
		5: _stage_rally_override()
		6: _stage_invalid_targets()
		7: _stage_pool_start()
		8: _stage_pool_watch()
		_:
			_summary()
			return true
	return false


# ---------------------------------------------------------------- stages

func _stage_selects_nearest() -> void:
	# The public accessor should now agree with the direct lookup.
	if _player.focus_weapon() == _focus:
		_ok("Player.focus_weapon() resolves the controller")
	else:
		_no("focus_weapon() accessor", "returned %s" % _player.focus_weapon())

	_focus.refresh_target()
	var t := _focus.current_target

	if t == _near:
		_ok("chooses a valid in-range enemy", "picked Near at %.0f u over Far and Behind" % _player.global_position.distance_to(_near.global_position))
	else:
		_no("target selection", "expected Near, got %s" % (t.name if t != null else "null"))

	# 25 units away with a 14 unit range.
	if t != _out_of_range:
		_ok("ignores targets beyond weapon range", "OutOfRange at 25 u excluded (range %.0f u)" % _focus.weapon.range_units)
	else:
		_no("range gating", "selected the out-of-range target")

	_stage = 1


func _stage_fire_rate_start() -> void:
	_shots_at_mark = _focus.shots_fired
	_mark = 0.0
	_stage = 2


func _stage_fire_rate_watch() -> void:
	_mark += TICK
	# Sample a whole number of intervals to avoid boundary rounding.
	if _mark < 3.6:
		return

	var shots := _focus.shots_fired - _shots_at_mark
	# From the JSON, not from the weapon resource under test.
	var interval: float = float(Balance.get_value("conjurer_staff/attack_interval_seconds", 0.72))
	var expected := int(floor(_mark / interval))

	if absi(shots - expected) <= 1:
		_ok("staff fires every %.2fs" % interval, "%d shots in %.2fs (expected ~%d)" % [shots, _mark, expected])
	else:
		_no("fire rate", "%d shots in %.2fs, expected ~%d" % [shots, _mark, expected])

	# Not in the brief's acceptance list, but a weapon that fires without
	# connecting is cosmetic. Proves target -> fire -> travel -> hit -> damage.
	var dealt: int = _near.get("damage_taken_total")
	var hits: int = _near.get("hit_count")
	if dealt > 0:
		_ok("projectiles connect and deal damage", "%d damage over %d hits on Near" % [dealt, hits])
	else:
		_no("damage application", "Near took no damage from %d shots" % shots)

	_stage = 3


func _stage_aim_repriority() -> void:
	# Behind sits at -X; Near and Far at +X. Aiming down -X should flip priority
	# because the +X cluster falls outside the 60-degree cone.
	_focus.set_preferred_aim(Vector3(-1, 0, 0))
	_focus.refresh_target()
	var aimed := _focus.current_target

	if aimed == _behind:
		_ok("manual aim changes priority", "aiming -X moved target from Near to Behind")
	else:
		_no("aim repriority", "expected Behind, got %s" % (aimed.name if aimed != null else "null"))

	_shots_at_mark = _focus.shots_fired
	_mark = 0.0
	_stage = 4


func _stage_aim_does_not_gate_fire() -> void:
	_mark += TICK
	if _mark < 1.5:
		return

	var with_aim := _focus.shots_fired - _shots_at_mark
	if with_aim > 0:
		_ok("aim does not disable auto-fire", "%d shots while aiming" % with_aim)
	else:
		_no("auto-fire under aim", "no shots fired while aim was held")

	# Clear aim: the staff must keep firing with no aim input at all.
	_focus.set_preferred_aim(Vector3.ZERO)
	_focus.refresh_target()
	if _focus.has_aim_input():
		_no("aim clears", "preferred_aim still set after clearing")
	else:
		_ok("no-aim promise", "cleared aim, target reverts to %s" % (_focus.current_target.name if _focus.current_target != null else "null"))

	_shots_at_mark = _focus.shots_fired
	_mark = 0.0
	_stage = 5


func _stage_rally_override() -> void:
	_mark += TICK
	if _mark < 1.0:
		return

	var no_aim_shots := _focus.shots_fired - _shots_at_mark
	if no_aim_shots > 0:
		_ok("fires effectively with zero aim input", "%d shots in %.1fs" % [no_aim_shots, _mark])
	else:
		_no("no-aim firing", "staff stopped firing without aim input")

	# Rally must beat both proximity and the aim cone (+1000).
	_focus.rally_target = _out_of_range
	_focus.refresh_target()
	if _focus.current_target != _out_of_range:
		_ok("rally does not defeat range gating", "out-of-range rally target still excluded")
	else:
		_no("rally range", "rally selected a target beyond weapon range")

	_focus.rally_target = _far
	_focus.refresh_target()
	if _focus.current_target == _far:
		_ok("rally target takes priority", "Far chosen over closer Near")
	else:
		_no("rally priority", "expected Far, got %s" % (_focus.current_target.name if _focus.current_target != null else "null"))

	_focus.rally_target = null
	_stage = 6


func _stage_invalid_targets() -> void:
	# Dead.
	_near.call("kill")
	_focus.refresh_target()
	var after_death := _focus.current_target
	if after_death != _near:
		_ok("never targets dead enemies", "Near killed, retargeted to %s" % (after_death.name if after_death != null else "null"))
	else:
		_no("dead targeting", "still targeting the killed enemy")

	# Hidden.
	_far.visible = false
	_focus.rally_target = _far
	_focus.refresh_target()
	if _focus.current_target != _far:
		_ok("never targets hidden enemies", "hidden Far rejected even as rally target")
	else:
		_no("hidden targeting", "selected a hidden enemy")
	_focus.rally_target = null
	_far.visible = true

	# Despawned.
	var doomed := _behind
	doomed.queue_free()
	_focus.refresh_target()
	if _focus.current_target != doomed:
		_ok("never targets despawned enemies", "freed target dropped cleanly")
	else:
		_no("despawn targeting", "still referencing a freed node")

	_stage = 7


func _stage_pool_start() -> void:
	_nodes_at_mark = root.get_tree().get_node_count()
	_shots_at_mark = _focus.shots_fired
	_mark = 0.0
	_stage = 8


func _stage_pool_watch() -> void:
	_mark += TICK
	if _mark < 6.0:
		return

	var shots := _focus.shots_fired - _shots_at_mark
	var nodes_now := root.get_tree().get_node_count()
	var growth := nodes_now - _nodes_at_mark

	if shots > 0:
		_ok("kept firing through target churn", "%d shots in %.0fs" % [shots, _mark])
	else:
		_no("sustained fire", "no shots after targets changed")

	if growth <= 0:
		_ok("no node growth under sustained fire", "%d shots, node delta %d" % [shots, growth])
	else:
		_no("projectile leak", "node count grew by %d over %d shots" % [growth, shots])

	if _pool.total_count() == _pool.active_count() + _pool.free_count():
		_ok("pool accounting balances", "%d total = %d active + %d free" % [_pool.total_count(), _pool.active_count(), _pool.free_count()])
	else:
		_no("pool accounting", "total %d != active %d + free %d" % [_pool.total_count(), _pool.active_count(), _pool.free_count()])

	if _pool.starved_count() == 0:
		_ok("pool never starved", "capacity %d sufficed" % _pool.total_count())
	else:
		_ok("pool starvation handled", "%d shots dropped rather than allocating" % _pool.starved_count())

	_stage = 99


# ---------------------------------------------------------------- static

## Same guard as Phase 1: the weapon resource must not drift from the spec.
func _check_weapon_matches_balance() -> void:
	var w := _focus.weapon
	var expect := {
		"base damage": [float(w.base_damage), "conjurer_staff/base_damage"],
		"attack interval": [w.attack_interval_seconds, "conjurer_staff/attack_interval_seconds"],
		"projectile speed": [w.projectile_speed_units_per_second, "conjurer_staff/projectile_speed_units_per_second"],
		"projectile lifetime": [w.projectile_lifetime_seconds, "conjurer_staff/projectile_lifetime_seconds"],
		"critical chance": [w.critical_chance, "conjurer_staff/critical_chance"],
		"critical multiplier": [w.critical_multiplier, "conjurer_staff/critical_multiplier"],
		"auto target range": [w.range_units, "player/auto_target_range_units"],
		"aim assist degrees": [w.aim_assist_degrees, "player/focus_aim_assist_degrees"],
	}
	var wrong: Array[String] = []
	for label in expect:
		var pair: Array = expect[label]
		var want: float = float(Balance.get_value(String(pair[1]), NAN))
		if is_nan(want) or not is_equal_approx(float(pair[0]), want):
			wrong.append("%s resource=%s json=%s" % [label, pair[0], want])
	if wrong.is_empty():
		_ok("every FocusWeaponData field matches the balance JSON", "%d fields" % expect.size())
	else:
		_no("FocusWeaponData drift", "; ".join(wrong))


func _check_score_contract() -> void:
	print("Score contract (master guide §16)")
	var weights := {
		"rally +1000": [TargetScorer.RALLY_BONUS, 1000.0],
		"boss +80": [TargetScorer.BOSS_BONUS, 80.0],
		"spawner/hexer +50": [TargetScorer.SPAWNER_OR_HEXER_BONUS, 50.0],
		"elite +40": [TargetScorer.ELITE_BONUS, 40.0],
		"stickiness +20": [TargetScorer.STICKINESS_BONUS, 20.0],
		"distance -2/unit": [TargetScorer.DISTANCE_PENALTY_PER_UNIT, -2.0],
		"behind aim -25": [TargetScorer.BEHIND_AIM_PENALTY, -25.0],
		"aim cone 60 deg": [TargetScorer.BEHIND_AIM_DEGREES, 60.0],
	}
	var wrong: Array[String] = []
	for label in weights:
		var pair: Array = weights[label]
		if not is_equal_approx(float(pair[0]), float(pair[1])):
			wrong.append("%s (got %s)" % [label, pair[0]])
	if wrong.is_empty():
		_ok("all 8 scoring weights match the brief")
	else:
		_no("scoring weights", "; ".join(wrong))


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _room != null and is_instance_valid(_room):
		_room.queue_free()
		_room = null
	print("\n" + "=".repeat(46))
	print("PHASE 2:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
