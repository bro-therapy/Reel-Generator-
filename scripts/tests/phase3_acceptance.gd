extends SceneTree

## Phase 3 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase3_acceptance.gd
##
## Drives the real summon field and steps physics. Exits non-zero on failure.

const FIELD := "res://scenes/tests/summon_field.tscn"
const TICK := 1.0 / 60.0

var _pass := 0
var _fail := 0

var _field: Node3D
var _player: Player
var _hound: SummonBase
var _wisp: SummonBase
var _construct: SummonBase
var _close: Node3D
var _mid: Node3D
var _room_b: Node3D

var _stage := -1
var _ticks := 0
var _mark := 0.0
var _attacks_at_mark := 0
var _refreshes_at_mark := 0
var _seen_states: Dictionary = {}
var _player_pos_at_mark := Vector3.ZERO
var _reforms_at_mark := 0


func _initialize() -> void:
	print("\n=== PHASE 3 ACCEPTANCE ===\n")
	_check_state_graph()
	_check_global_rules()

	var packed := load(FIELD) as PackedScene
	if packed == null:
		_no("summon field loads", "cannot load %s" % FIELD)
		_summary()
		return
	_field = packed.instantiate() as Node3D
	root.add_child(_field)

	_player = _field.get_node_or_null("Player") as Player
	_close = _field.get_node_or_null("Close") as Node3D
	_mid = _field.get_node_or_null("Mid") as Node3D
	_room_b = _field.get_node_or_null("RoomB") as Node3D


## The field spawns its team in _ready, which has not run during _initialize.
## Bind on the first physics tick instead.
func _stage_bind() -> void:
	_hound = _field.get_node_or_null("rune_hound") as SummonBase
	_wisp = _field.get_node_or_null("sword_wisp") as SummonBase
	_construct = _field.get_node_or_null("gun_construct") as SummonBase

	if _player == null or _hound == null or _wisp == null or _construct == null:
		_no("field spawns player and three summons", "hound=%s wisp=%s construct=%s" % [_hound, _wisp, _construct])
		_stage = 99
		return
	_ok("field spawns the hero and all three starters")

	_check_one_base_scene()
	_check_no_physics_bodies()
	_check_invulnerable()

	# Record every state each summon visits, to prove the full cycle runs.
	for s in [_hound, _wisp, _construct]:
		_seen_states[s.name] = {}
		s.state_changed.connect(_record_state.bind(s.name))

	_stage = 0


func _record_state(to: int, _from: int, who: String) -> void:
	(_seen_states[who] as Dictionary)[to] = true


func _physics_process(delta: float) -> bool:
	if _player == null:
		_summary()
		return true
	_ticks += 1
	if _ticks < 5:
		return false

	match _stage:
		-1: _stage_bind()
		0: _stage_settle_start()
		1: _stage_lane_watch()
		2: _stage_attack_cycle_start()
		3: _stage_attack_cycle_watch()
		4: _stage_refresh_rate_start()
		5: _stage_refresh_rate_watch()
		6: _stage_rally_override()
		7: _stage_reform_start()
		8: _stage_reform_watch()
		9: _stage_threshold_below_start()
		10: _stage_threshold_below_watch()
		11: _stage_threshold_above_start()
		12: _stage_threshold_above_watch()
		13: _stage_screen_sizes()
		14: _stage_room_change_start()
		15: _stage_room_change_watch()
		16: _stage_jitter_start()
		17: _stage_jitter_watch()
		_:
			_summary()
			return true
	return false


# ---------------------------------------------------------------- stages

func _stage_settle_start() -> void:
	_player_pos_at_mark = _player.global_position
	_mark = 0.0
	_stage = 1


func _stage_lane_watch() -> void:
	_mark += TICK
	if _mark < 1.5:
		return

	# Summons must reach distinct lanes, not stack on one point.
	var positions := [_hound.global_position, _wisp.global_position, _construct.global_position]
	var min_sep := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			min_sep = minf(min_sep, (positions[i] as Vector3).distance_to(positions[j] as Vector3))

	if min_sep > 0.6:
		_ok("three summons hold distinct lanes", "closest pair %.2f u apart" % min_sep)
	else:
		_no("lane separation", "summons stacked, closest pair %.2f u" % min_sep)

	# The hero must not have been shoved by anything.
	var drift := _player.global_position.distance_to(_player_pos_at_mark)
	if drift < 0.01:
		_ok("summons follow without pushing the player", "hero drift %.4f u over %.1fs" % [drift, _mark])
	else:
		_no("player pushed", "hero moved %.4f u with no input" % drift)

	_stage = 2


func _stage_attack_cycle_start() -> void:
	# Close sits 1.6 u away — inside the Rune Hound's 2.2 u reach.
	_attacks_at_mark = _hound.attacks_landed
	_mark = 0.0
	_stage = 3


func _stage_attack_cycle_watch() -> void:
	_mark += TICK
	if _mark < 4.0:
		return

	var landed := _hound.attacks_landed - _attacks_at_mark
	if landed > 0:
		_ok("summon attacks automatically", "Rune Hound landed %d hits in %.0fs" % [landed, _mark])
	else:
		_no("automatic attack", "Rune Hound landed no hits on a target 1.6 u away")

	var interval: float = _hound.form.attack_interval_seconds
	var expected := int(floor(_mark / interval))
	if absi(landed - expected) <= 2:
		_ok("attack cadence respects the interval", "%d hits in %.0fs at %.2fs interval (expected ~%d)" % [landed, _mark, interval, expected])
	else:
		_no("attack cadence", "%d hits, expected ~%d" % [landed, expected])

	# The full cycle must have been traversed, not short-circuited.
	var seen: Dictionary = _seen_states.get(_hound.name, {})
	var need := [
		SummonStateMachine.State.ACQUIRE,
		SummonStateMachine.State.WINDUP,
		SummonStateMachine.State.ATTACK,
		SummonStateMachine.State.RECOVER,
		SummonStateMachine.State.FOLLOW,
	]
	var missing: Array[String] = []
	for st in need:
		if not seen.has(st):
			missing.append(SummonStateMachine.name_of(st))
	if missing.is_empty():
		_ok("full cycle runs", "FOLLOW -> ACQUIRE -> WINDUP -> ATTACK -> RECOVER -> FOLLOW")
	else:
		_no("attack cycle", "never entered: %s" % ", ".join(missing))

	if _hound.illegal_transition_count() == 0:
		_ok("no illegal state transitions", "graph enforced")
	else:
		_no("state graph", "%d illegal transitions attempted" % _hound.illegal_transition_count())

	# After recovering it must be back on its lane, not parked on the enemy.
	var lane_dist := _hound.global_position.distance_to(_player.global_position)
	if lane_dist < 4.0:
		_ok("returns to its lane after attacking", "%.2f u from the hero" % lane_dist)
	else:
		_no("lane return", "hound sat %.2f u from the hero" % lane_dist)

	_stage = 4


func _stage_refresh_rate_start() -> void:
	var tc := _construct.get_node("TargetController") as SummonTargetController
	_refreshes_at_mark = tc.refresh_count()
	_mark = 0.0
	_stage = 5


func _stage_refresh_rate_watch() -> void:
	_mark += TICK
	if _mark < 2.0:
		return

	var tc := _construct.get_node("TargetController") as SummonTargetController
	var refreshes := tc.refresh_count() - _refreshes_at_mark
	var expected := int(round(_mark / SpiritData.target_refresh_seconds()))

	if absi(refreshes - expected) <= 2:
		_ok("target refresh every %.2fs" % SpiritData.target_refresh_seconds(), "%d refreshes in %.0fs (expected ~%d)" % [refreshes, _mark, expected])
	else:
		_no("target refresh rate", "%d refreshes in %.0fs, expected ~%d" % [refreshes, _mark, expected])

	_stage = 6


func _stage_rally_override() -> void:
	# Gun Construct reaches 12 u, so both targets are candidates. Without Rally
	# it prefers the closer one; Rally must flip that.
	var tc := _construct.get_node("TargetController") as SummonTargetController
	tc.rally_target = null
	tc.refresh(_construct.global_position)
	var natural := tc.current_target

	_construct.set_rally_target(_mid)
	tc.refresh(_construct.global_position)
	var rallied := tc.current_target

	if rallied == _mid:
		_ok("rally target overrides normal score", "%s -> Mid" % (natural.name if natural != null else "none"))
	else:
		_no("rally override", "expected Mid, got %s" % (rallied.name if rallied != null else "null"))

	_construct.set_rally_target(null)
	_stage = 7


func _stage_reform_start() -> void:
	_reforms_at_mark = _wisp.reform_count
	# Strand the wisp well past the 10 u teleport threshold.
	_wisp.global_position = _player.global_position + Vector3(40.0, 0.0, 0.0)
	_mark = 0.0
	_stage = 8


func _stage_reform_watch() -> void:
	_mark += TICK
	if _mark < 1.5:
		return

	var reforms := _wisp.reform_count - _reforms_at_mark
	var dist := _wisp.global_position.distance_to(_player.global_position)

	if reforms > 0:
		_ok("reforms when separated", "stranded 40 u, reformed %d time(s)" % reforms)
	else:
		_no("reform", "wisp did not reform after being stranded 40 u away")

	if dist < 5.0:
		_ok("reform teleports rather than pathfinding", "back within %.2f u after %.1fs" % [dist, _mark])
	else:
		_no("reform distance", "still %.2f u from the hero" % dist)

	# 40 u at 9.5 u/s would take >4s to walk; reform completes in ~0.35s.
	var walk_time := 40.0 / _wisp.data.follow_speed_units_per_second
	if _mark < walk_time:
		_ok("reform beat the walk time", "%.1fs elapsed vs %.1fs to steer 40 u" % [_mark, walk_time])
	else:
		_no("reform speed", "took as long as walking would have")

	_stage = 9


## The brief pins reform to "more than 10 units away". Stranding a summon at 40 u
## only proves it reforms *eventually* — a threshold of 39 u would pass that just
## as happily. These two stages bracket the real value: no reform just under it,
## a reform just over it.
func _stage_threshold_below_start() -> void:
	# Isolate the reform mechanism. With enemies present the summon is somewhere
	# in its attack cycle, which changes whether it steers or holds and made this
	# check flaky. Hiding them removes the confound entirely — the property under
	# test is separation distance, not combat.
	_set_enemies_visible(false)
	_reforms_at_mark = _construct.reform_count
	var below: float = SpiritData.teleport_back_distance() - 1.0
	_construct.global_position = _player.global_position + Vector3(below, 0.0, 0.0)
	_mark = 0.0
	_stage = 10


func _stage_threshold_below_watch() -> void:
	_mark += TICK
	if _mark < 1.2:
		return
	var below: float = SpiritData.teleport_back_distance() - 1.0
	var reforms := _construct.reform_count - _reforms_at_mark
	if reforms == 0:
		_ok("does not reform inside the threshold", "held at %.0f u for %.1fs, 0 reforms" % [below, _mark])
	else:
		_no("premature reform", "reformed %d time(s) at %.0f u, under the %.0f u threshold" % [reforms, below, SpiritData.teleport_back_distance()])
	_stage = 11


func _stage_threshold_above_start() -> void:
	_reforms_at_mark = _construct.reform_count
	var above: float = SpiritData.teleport_back_distance() + 1.0
	_construct.global_position = _player.global_position + Vector3(above, 0.0, 0.0)
	_mark = 0.0
	_stage = 12


func _stage_threshold_above_watch() -> void:
	_mark += TICK
	if _mark < 1.2:
		return
	var above: float = SpiritData.teleport_back_distance() + 1.0
	var reforms := _construct.reform_count - _reforms_at_mark
	if reforms > 0:
		_ok("reforms just past the threshold", "%.0f u triggered a reform (threshold %.0f u)" % [above, SpiritData.teleport_back_distance()])
	else:
		_no("reform threshold too high", "no reform at %.0f u; the %.0f u threshold is not being honoured" % [above, SpiritData.teleport_back_distance()])
	_set_enemies_visible(true)
	_stage = 13


## Master guide §2 gives each summon an on-screen height target. Verified by
## projecting the drawn content through the live camera, the same way Phase 1
## verifies the hero's 88 px.
func _stage_screen_sizes() -> void:
	var cam := _field.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		_no("summon screen sizes", "no camera in the field")
		_stage = 14
		return

	var metrics_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/generated/summon_metrics.json"))
	if typeof(metrics_raw) != TYPE_DICTIONARY:
		_no("summon metrics", "docs/generated/summon_metrics.json unreadable")
		_stage = 14
		return
	var species: Dictionary = (metrics_raw as Dictionary).get("species", {})

	var targets := {"rune_hound": 52.0, "sword_wisp": 58.0, "gun_construct": 46.0}
	var vp := root.get_viewport().get_visible_rect().size
	var off: Array[String] = []
	var report: Array[String] = []

	for s: SummonBase in [_hound, _wisp, _construct]:
		var id := String(s.data.id)
		var entry: Dictionary = species.get(id, {})
		var content := float(entry.get("median_content_height_px", 0.0))
		if content <= 0.0:
			off.append("%s (no metrics)" % id)
			continue
		var world_h: float = content * s.form.pixel_size()
		var base: Vector3 = s.global_position
		var top: Vector3 = base + Vector3(0.0, world_h, 0.0)
		var px := absf(cam.unproject_position(base).y - cam.unproject_position(top).y) * (1080.0 / maxf(vp.y, 1.0))
		var tgt: float = targets[id]
		report.append("%s %.0f/%.0f" % [id, px, tgt])
		if absf(px - tgt) > 3.0:
			off.append("%s %.1f px vs %.0f target" % [id, px, tgt])

	if off.is_empty():
		_ok("summons meet their §2 on-screen size targets", ", ".join(report))
	else:
		_no("summon screen sizes", "; ".join(off))

	_stage = 14


## Follow smoothness. The hero is walked at a constant velocity and the hound's
## per-tick step length is recorded.
##
## This exists because 29 checks passed while the summons visibly shook. Every
## one of them asked "is it in the right PLACE" — none asked "did it get there
## smoothly". The old steering was bang-bang: the follow speed (9.5 u/s) is
## above the hero's top speed (6.2), so a moving hero produced overshoot into a
## 0.25 u deadzone, a dead stop, a fall behind, then a sprint — alternating
## every tick. Position was always within tolerance, so position-based checks
## saw nothing wrong.
##
## The measure is the spread of step lengths once moving. Bang-bang alternates
## near-zero and near-max, so max/mean lands around 2. Smooth steering holds a
## near-constant step and lands near 1.
const JITTER_SETTLE_TICKS := 90
const JITTER_TICKS := 90
## Below the 9.5 u/s follow speed, so a steady state exists at all. If the hero
## outran the summon there would be no oscillation to detect — it would simply
## run flat out forever, which is what made the first version of this check
## vacuous.
const HERO_STEP_PER_TICK := 0.06

var _jitter_steps: Array[float] = []
var _jitter_last := Vector3.ZERO
var _jitter_settle := 0


func _stage_jitter_start() -> void:
	var hound := _summon_named("rune_hound")
	if hound == null:
		_no("follow smoothness", "no rune hound to measure")
		_stage = 99
		return
	_jitter_steps.clear()
	_jitter_settle = 0
	_jitter_last = hound.global_position
	_stage = 17


func _stage_jitter_watch() -> void:
	var hound := _summon_named("rune_hound")
	if hound == null:
		_stage = 99
		return
	# Constant-velocity walk, driven directly rather than through Input so the
	# hero's acceleration curve does not confound the measurement.
	_player.global_position += Vector3(HERO_STEP_PER_TICK, 0.0, 0.0)
	_player.velocity = Vector3(HERO_STEP_PER_TICK * 60.0, 0.0, 0.0)

	var step := hound.global_position.distance_to(_jitter_last)
	_jitter_last = hound.global_position

	# Settle FIRST. The first version recorded from tick one and measured the
	# catch-up, during which even the bang-bang steering ran at a constant max
	# speed — so the mutant passed. The oscillation only exists once the summon
	# has closed to its lane and is holding station.
	if _jitter_settle < JITTER_SETTLE_TICKS:
		_jitter_settle += 1
		return
	if _jitter_steps.size() < JITTER_TICKS:
		_jitter_steps.append(step)
		return

	var total := 0.0
	var peak := 0.0
	var floor_step := INF
	for v in _jitter_steps:
		total += v
		peak = maxf(peak, v)
		floor_step = minf(floor_step, v)
	var mean := total / float(_jitter_steps.size())
	if mean <= 0.0001:
		_no("follow smoothness", "the summon never moved while the hero walked")
		_stage = 99
		return
	# The metric is the SMALLEST step, not the spread.
	#
	# peak/mean was tried first and was nearly vacuous: the bang-bang mutant
	# measured 0.0000..0.1583 u — an unmistakable stall-then-sprint — yet came to
	# only 1.45x the mean, under a 1.5 threshold, because averaging a square wave
	# hides it. What the defect actually IS: a summon holding station behind a
	# hero at constant velocity should travel the SAME distance every tick. A tick
	# where it does not move at all is a stall, and stalls are what the eye reads
	# as shaking. So the floor is the measurement, and it is unambiguous:
	# smooth steering holds floor/mean at 1.00, bang-bang drops it to 0.00.
	var floor_ratio := floor_step / mean
	if floor_ratio >= 0.5:
		_ok("summons follow smoothly",
			"steady-state step %.4f..%.4f u, never stalls (floor %.2fx the mean)"
			% [floor_step, peak, floor_ratio])
	else:
		_no("follow jitter", "steady-state step swings %.4f..%.4f u — the summon "
			% [floor_step, peak]
			+ "stalls on %.0f%% of ticks and sprints on the rest, which reads as shaking"
			% ((1.0 - floor_ratio) * 100.0))
	_stage = 99


func _summon_named(id: String) -> Node3D:
	for child in _field.get_children():
		if child is SummonBase and String(child.name) == id:
			return child
	return null


func _stage_room_change_start() -> void:
	_reforms_at_mark = _hound.reform_count
	# Simulate a room transition: reparent the hero into another node and move
	# it far away, exactly what a scene swap does to the summons' frame.
	_player.get_parent().remove_child(_player)
	_room_b.add_child(_player)
	_player.global_position = _room_b.global_position
	_mark = 0.0
	_stage = 15


func _stage_room_change_watch() -> void:
	_mark += TICK
	if _mark < 2.0:
		return

	var dist := _hound.global_position.distance_to(_player.global_position)
	if dist < 5.0:
		_ok("changes rooms without getting stranded", "hound rejoined within %.2f u after reparent" % dist)
	else:
		_no("room change", "hound stranded %.2f u from the hero" % dist)

	var all_rejoined := true
	for s in [_hound, _wisp, _construct]:
		if s.global_position.distance_to(_player.global_position) > 5.0:
			all_rejoined = false
	if all_rejoined:
		_ok("whole team survives the transition", "all three within 5 u")
	else:
		_no("team transition", "at least one summon stranded")

	var illegal := _hound.illegal_transition_count() + _wisp.illegal_transition_count() + _construct.illegal_transition_count()
	if illegal == 0:
		_ok("no illegal transitions across the whole run", "0 rejected")
	else:
		_no("state graph integrity", "%d illegal transitions" % illegal)

	# Into the follow-smoothness measurement rather than straight to the summary.
	_stage = 16


# ---------------------------------------------------------------- static

func _check_state_graph() -> void:
	print("State graph")
	var fsm := SummonStateMachine.new()
	fsm.warn_on_illegal = false

	# The documented cycle must be walkable end to end.
	var cycle := [
		SummonStateMachine.State.ACQUIRE,
		SummonStateMachine.State.WINDUP,
		SummonStateMachine.State.ATTACK,
		SummonStateMachine.State.RECOVER,
		SummonStateMachine.State.FOLLOW,
	]
	var walked := true
	for st in cycle:
		if not fsm.transition_to(st):
			walked = false
			break
	if walked:
		_ok("documented cycle is walkable")
	else:
		_no("cycle", "blocked at %s" % fsm.state_name())

	# REFORM must be reachable from every state.
	var unreachable: Array[String] = []
	for st in [SummonStateMachine.State.FOLLOW, SummonStateMachine.State.ACQUIRE, SummonStateMachine.State.WINDUP, SummonStateMachine.State.ATTACK, SummonStateMachine.State.RECOVER]:
		var probe := SummonStateMachine.new()
		probe.warn_on_illegal = false
		probe.state = st
		if not probe.force_reform():
			unreachable.append(SummonStateMachine.name_of(st))
		probe.free()
	if unreachable.is_empty():
		_ok("REFORM reachable from any state")
	else:
		_no("REFORM reachability", "blocked from: %s" % ", ".join(unreachable))

	# And REFORM must only exit to FOLLOW.
	var r := SummonStateMachine.new()
	r.warn_on_illegal = false
	r.state = SummonStateMachine.State.REFORM
	var bad: Array[String] = []
	for st in [SummonStateMachine.State.ACQUIRE, SummonStateMachine.State.WINDUP, SummonStateMachine.State.ATTACK, SummonStateMachine.State.RECOVER]:
		var probe := SummonStateMachine.new()
		probe.warn_on_illegal = false
		probe.state = SummonStateMachine.State.REFORM
		if probe.transition_to(st):
			bad.append(SummonStateMachine.name_of(st))
		probe.free()
	if bad.is_empty():
		_ok("REFORM exits only to FOLLOW")
	else:
		_no("REFORM exits", "also allowed: %s" % ", ".join(bad))
	r.free()
	fsm.free()


func _check_global_rules() -> void:
	print("\nGlobal summon rules (LEVEL1_BALANCE.json)")
	var checks := {
		"teleport back at 10 u": [SpiritData.teleport_back_distance(), 10.0],
		"reform delay 0.35s": [SpiritData.reform_delay(), 0.35],
		"target refresh 0.20s": [SpiritData.target_refresh_seconds(), 0.20],
		"rally damage bonus 0.15": [SpiritData.rally_damage_bonus(), 0.15],
	}
	var wrong: Array[String] = []
	for label in checks:
		var pair: Array = checks[label]
		if not is_equal_approx(float(pair[0]), float(pair[1])):
			wrong.append("%s (got %s)" % [label, pair[0]])
	if wrong.is_empty():
		_ok("all four global rules read from balance JSON")
	else:
		_no("global rules", "; ".join(wrong))


func _check_one_base_scene() -> void:
	print("\nShared architecture")
	var paths: Array[String] = []
	for s in [_hound, _wisp, _construct]:
		paths.append(s.scene_file_path)
	var unique := {}
	for p in paths:
		unique[p] = true
	if unique.size() == 1 and paths[0] == "res://scenes/actors/summon_base.tscn":
		_ok("one generic base scene drives all three species", paths[0])
	else:
		_no("shared base scene", "distinct scenes: %s" % ", ".join(unique.keys()))

	# Distinct data, distinct stats, distinct lanes.
	var ids := [String(_hound.data.id), String(_wisp.data.id), String(_construct.data.id)]
	var lanes := [_hound.data.lane_offset, _wisp.data.lane_offset, _construct.data.lane_offset]
	var damages := [_hound.form.damage, _wisp.form.damage, _construct.form.damage]
	if ids.size() == 3 and lanes[0] != lanes[1] and lanes[1] != lanes[2] and lanes[0] != lanes[2]:
		_ok("species differ by data alone", "%s | lanes distinct | damage %s" % [", ".join(ids), str(damages)])
	else:
		_no("species differentiation", "lanes or ids collide")

	# Balance values must have reached the forms.
	var expected := {"rune_hound": [18, 1.05, 2.2], "sword_wisp": [11, 0.62, 7.5], "gun_construct": [8, 0.38, 12.0]}
	var wrong: Array[String] = []
	for s in [_hound, _wisp, _construct]:
		var e: Array = expected[String(s.data.id)]
		if s.form.damage != int(e[0]) or not is_equal_approx(s.form.attack_interval_seconds, float(e[1])) or not is_equal_approx(s.form.range_units, float(e[2])):
			wrong.append("%s got %d/%.2f/%.1f" % [s.data.id, s.form.damage, s.form.attack_interval_seconds, s.form.range_units])
	if wrong.is_empty():
		_ok("form stats match LEVEL1_BALANCE.json", "damage/interval/range for all three")
	else:
		_no("form stats", "; ".join(wrong))

	# Windup + recovery must fit inside the interval or cadence breaks.
	var incoherent: Array[String] = []
	for s in [_hound, _wisp, _construct]:
		if not s.form.timing_is_coherent():
			incoherent.append("%s (%.2f+%.2f >= %.2f)" % [s.data.id, s.form.windup_seconds, s.form.recover_seconds, s.form.attack_interval_seconds])
	if incoherent.is_empty():
		_ok("windup + recovery fit inside every attack interval")
	else:
		_no("attack timing", "; ".join(incoherent))


func _check_no_physics_bodies() -> void:
	# The brief forbids physical collision with the player, other summons, and
	# normal enemies. A summon with no physics body cannot collide at all.
	var offenders: Array[String] = []
	for s in [_hound, _wisp, _construct]:
		for node in _walk(s):
			if node is PhysicsBody3D:
				offenders.append("%s/%s" % [s.name, node.name])
			elif node is Area3D:
				var a := node as Area3D
				# A sensor is fine, but it must not be monitorable by bodies.
				if a.collision_layer != 0:
					offenders.append("%s/%s (layer %d)" % [s.name, a.name, a.collision_layer])
	if offenders.is_empty():
		_ok("no physics bodies on any summon", "cannot push the player, each other, or enemies")
	else:
		_no("physical collision", "; ".join(offenders))


func _check_invulnerable() -> void:
	var failures: Array[String] = []
	for s in [_hound, _wisp, _construct]:
		if not s.is_invulnerable():
			failures.append("%s reports vulnerable" % s.name)
		if s.take_damage(999):
			failures.append("%s accepted damage" % s.name)
	if failures.is_empty():
		_ok("summons are invulnerable in the prototype", "take_damage() refused on all three")
	else:
		_no("invulnerability", "; ".join(failures))


## Hides or restores every test target, so a stage can exclude combat.
func _set_enemies_visible(value: bool) -> void:
	var tree := root.get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("enemies"):
		if n is Node3D:
			(n as Node3D).visible = value


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out


# ---------------------------------------------------------------- reporting

func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
		_field = null
	print("\n" + "=".repeat(46))
	print("PHASE 3:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
