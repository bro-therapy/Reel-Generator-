extends SceneTree

## Phase 4 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase4_acceptance.gd
##
## "Species are recognizable from behavior without reading UI" is the headline
## criterion and cannot be eyeballed headlessly, so it is measured as three
## objective motion signatures instead:
##
##   Rune Hound     closes distance and lunges  -> large displacement toward the target
##   Sword Wisp     orbits the hero             -> large accumulated angle around the hero
##   Gun Construct  plants and shoots           -> near-zero movement while firing, emits projectiles
##
## Those three are mutually exclusive: no species can pass another's signature.

const FIELD := "res://scenes/tests/species_field.tscn"
const TICK := 1.0 / 60.0

var _pass := 0
var _fail := 0

var _field: Node3D
var _player: Player
var _hound: SummonBase
var _wisp: SummonBase
var _construct: SummonBase
var _enemies: Array[Node3D] = []
var _pool: ProjectilePool
var _effects: EffectPool

var _stage := -1
var _ticks := 0
var _mark := 0.0

# Signature accumulators.
var _orbit_angle: Dictionary = {}
var _last_bearing: Dictionary = {}
var _max_lane_departure: Dictionary = {}
var _firing_movement: Dictionary = {}
var _last_pos: Dictionary = {}
var _last_state: Dictionary = {}
var _projectiles_seen := 0
var _distinct_target_sets: Dictionary = {}


func _initialize() -> void:
	print("\n=== PHASE 4 ACCEPTANCE ===\n")
	_check_render_contract()

	var packed := load(FIELD) as PackedScene
	if packed == null:
		_no("species field loads", "cannot load %s" % FIELD)
		_summary()
		return
	_field = packed.instantiate() as Node3D
	root.add_child(_field)
	_player = _field.get_node_or_null("Player") as Player
	for n in ["EnemyA", "EnemyB", "EnemyC"]:
		var e := _field.get_node_or_null(n) as Node3D
		if e != null:
			_enemies.append(e)


func _physics_process(delta: float) -> bool:
	if _player == null:
		_summary()
		return true
	_ticks += 1
	if _ticks < 5:
		return false

	match _stage:
		-1: _stage_bind()
		0: _stage_observe_start()
		1: _stage_observe()
		2: _stage_report_signatures()
		3: _stage_separation()
		4: _stage_independent_targets()
		5: _stage_projectile_attribution_start()
		6: _stage_projectile_attribution_watch()
		7: _stage_rally_convergence()
		8: _stage_six_effects()
		_:
			_summary()
			return true
	return false


func _stage_bind() -> void:
	_hound = _field.get_node_or_null("rune_hound") as SummonBase
	_wisp = _field.get_node_or_null("sword_wisp") as SummonBase
	_construct = _field.get_node_or_null("gun_construct") as SummonBase
	_pool = _player.get_node_or_null("ProjectilePool") as ProjectilePool
	_effects = _player.get_node_or_null("EffectPool") as EffectPool

	if _hound == null or _wisp == null or _construct == null:
		_no("field spawns three species", "one or more summons missing")
		_stage = 99
		return
	if _pool == null or _effects == null:
		_no("shared pools present", "pool=%s effects=%s" % [_pool, _effects])
		_stage = 99
		return
	_ok("field spawns three species with shared projectile and effect pools")

	_check_behaviors_installed()
	_check_species_data()

	for s in [_hound, _wisp, _construct]:
		_orbit_angle[s.name] = 0.0
		_last_bearing[s.name] = _bearing(s)
		_max_lane_departure[s.name] = 0.0
		_firing_movement[s.name] = 0.0
		_last_pos[s.name] = s.global_position
		_last_state[s.name] = s.state()
	_stage = 0


func _stage_observe_start() -> void:
	_mark = 0.0
	_stage = 1


## Accumulates the three motion signatures over a window of live combat.
func _stage_observe() -> void:
	_mark += TICK

	for s: SummonBase in [_hound, _wisp, _construct]:
		var key := s.name
		var pos: Vector3 = s.global_position

		# NET signed angle swept around the hero. Absolute accumulation is the
		# wrong metric: a lunger swinging out and back racks up huge |delta|
		# without ever orbiting. An orbiter travels consistently one way and
		# nets a large signed total; a lunger nets ~zero.
		# Samples taken very close to the hero are skipped — bearing is
		# ill-conditioned near the origin and produces false rotation.
		var bearing := _bearing(s)
		var radius := Vector2(pos.x - _player.global_position.x, pos.z - _player.global_position.z).length()
		if radius > 0.5:
			var d := wrapf(bearing - float(_last_bearing[key]), -PI, PI)
			_orbit_angle[key] = float(_orbit_angle[key]) + d
		_last_bearing[key] = bearing

		# Furthest the summon ever gets from the hero (lunge reach).
		var from_hero := pos.distance_to(_player.global_position)
		_max_lane_departure[key] = maxf(float(_max_lane_departure[key]), from_hero)

		# Movement accrued across the whole attack cycle. WINDUP and ATTACK have
		# no default movement, so a species that merely declines to move there is
		# indistinguishable from one that is held still. RECOVER *does* steer back
		# to the lane by default, which is what makes "planted" measurable.
		# Only count a tick when the state did not change during it. A position
		# delta spans the whole tick, so on a transition tick it belongs partly to
		# the previous state — attributing it to the new one credited the planted
		# construct with a single tick of the steering it did while following.
		var st := s.state()
		var same_state: bool = _last_state.get(key, st) == st
		if same_state and (st == SummonStateMachine.State.WINDUP or st == SummonStateMachine.State.ATTACK or st == SummonStateMachine.State.RECOVER):
			_firing_movement[key] = float(_firing_movement[key]) + pos.distance_to(_last_pos[key] as Vector3)
		_last_state[key] = st
		_last_pos[key] = pos

	if _pool.in_flight_count() > 0:
		_projectiles_seen = maxi(_projectiles_seen, _pool.in_flight_count())

	# Record which enemies the team is engaging, to prove independent targeting.
	var names: Array[String] = []
	for s: SummonBase in [_hound, _wisp, _construct]:
		var t := s.current_target()
		names.append(t.name if t != null else "-")
	_distinct_target_sets[", ".join(names)] = true

	if _mark >= 6.0:
		_stage = 2


func _stage_report_signatures() -> void:
	var hound_deg := absf(rad_to_deg(float(_orbit_angle[_hound.name])))
	var wisp_deg := absf(rad_to_deg(float(_orbit_angle[_wisp.name])))
	var construct_deg := absf(rad_to_deg(float(_orbit_angle[_construct.name])))

	print("\nSpecies signatures over %.0fs of live combat" % _mark)
	print("  %-15s %14s %14s %16s" % ["species", "net orbit(deg)", "max reach(u)", "move in attack cycle"])
	for s: SummonBase in [_hound, _wisp, _construct]:
		print("  %-15s %14.0f %14.2f %16.3f" % [
			s.name, rad_to_deg(float(_orbit_angle[s.name])),
			float(_max_lane_departure[s.name]), float(_firing_movement[s.name]),
		])
	print("")

	# --- Sword Wisp: orbits ---
	if wisp_deg > 300.0 and wisp_deg > hound_deg * 3.0:
		_ok("Sword Wisp reads as an orbiter", "net %.0f deg around the hero vs hound %.0f, construct %.0f" % [wisp_deg, hound_deg, construct_deg])
	else:
		_no("wisp orbit signature", "net %.0f deg; hound %.0f, construct %.0f" % [wisp_deg, hound_deg, construct_deg])

	# --- Gun Construct: plants to fire ---
	var construct_move := float(_firing_movement[_construct.name])
	var hound_move := float(_firing_movement[_hound.name])
	if construct_move < 0.05:
		_ok("Gun Construct plants to fire", "moved %.3f u across every windup and attack" % construct_move)
	else:
		_no("construct plant signature", "moved %.3f u while firing, expected ~0" % construct_move)

	# --- Rune Hound: lunges ---
	if hound_move > construct_move * 4.0 and hound_move > 0.5:
		_ok("Rune Hound reads as a lunger", "moved %.2f u while attacking vs construct %.3f" % [hound_move, construct_move])
	else:
		_no("hound lunge signature", "moved %.2f u while attacking, construct %.3f" % [hound_move, construct_move])

	# --- Mutual exclusivity: no species matches another's signature ---
	var overlaps: Array[String] = []
	if construct_move > 0.5:
		overlaps.append("construct moves like the hound")
	if hound_deg > 300.0:
		overlaps.append("hound orbits like the wisp")
	if float(_firing_movement[_wisp.name]) < 0.05:
		overlaps.append("wisp plants like the construct")
	if overlaps.is_empty():
		_ok("the three signatures are mutually exclusive", "no species matches another's read")
	else:
		_no("signature overlap", "; ".join(overlaps))

	# --- Ranged vs melee ---
	_stage = 3


func _stage_separation() -> void:
	var positions := [_hound.global_position, _wisp.global_position, _construct.global_position]
	var min_sep := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			min_sep = minf(min_sep, (positions[i] as Vector3).distance_to(positions[j] as Vector3))
	var names := [_hound.name, _wisp.name, _construct.name]
	var detail := ""
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			detail += "%s-%s %.2f  " % [names[i], names[j], (positions[i] as Vector3).distance_to(positions[j] as Vector3)]
	var tg := ""
	for s2: SummonBase in [_hound, _wisp, _construct]:
		var t2 := s2.current_target()
		tg += "%s->%s(%s) " % [s2.name, (t2.name if t2 != null else "-"), s2.state_name()]
	if min_sep > 0.6:
		_ok("three summons do not stack on one location", "closest pair %.2f u apart mid-combat" % min_sep)
	else:
		_no("summon stacking", "%s | %s" % [detail.strip_edges(), tg.strip_edges()])
	_stage = 4


func _stage_independent_targets() -> void:
	# Over the observation window the team should have engaged more than one
	# enemy at once at least once. A single combination for six seconds would
	# mean they are locked together without Rally.
	var split_seen := false
	for combo in _distinct_target_sets:
		var parts := String(combo).split(", ")
		var unique := {}
		for p in parts:
			if p != "-":
				unique[p] = true
		if unique.size() > 1:
			split_seen = true
			break
	if split_seen:
		_ok("summons may attack separate enemies", "%d distinct target combinations observed" % _distinct_target_sets.size())
	else:
		_no("independent targeting", "the team never split across enemies: %s" % ", ".join(_distinct_target_sets.keys()))
	_stage = 5


## The Focus Weapon and the Gun Construct share one projectile pool, so a raw
## pool count cannot tell whose shot it is — counting the pool credited the
## hero's staff to the construct. Silence the staff, drain the pool, then any
## projectile that appears belongs to the construct.
func _stage_projectile_attribution_start() -> void:
	var focus := _player.focus_weapon()
	if focus != null:
		focus.use_group_scan = false
		focus.current_target = null
	_pool.release_all()
	_projectiles_seen = 0
	_mark = 0.0
	_stage = 6


func _stage_projectile_attribution_watch() -> void:
	_mark += TICK
	# in_flight, not active: a slot checked out but never launched is not a
	# projectile the player can see, and counting it hid a real failure.
	_projectiles_seen = maxi(_projectiles_seen, _pool.in_flight_count())
	if _mark < 2.5:
		return

	if _projectiles_seen > 0:
		_ok("Gun Construct fires projectiles", "%d in flight with the staff silenced" % _projectiles_seen)
	else:
		_no("construct projectiles", "no projectile appeared in %.1fs with the staff silenced" % _mark)

	var focus := _player.focus_weapon()
	if focus != null:
		focus.use_group_scan = true
	_stage = 7


func _stage_rally_convergence() -> void:
	# Rally is +1000 in the shared scorer, so it must beat every species' own
	# proximity preference and pull the whole team onto one enemy.
	var rally := _enemies[2] if _enemies.size() > 2 else _enemies[0]
	for s: SummonBase in [_hound, _wisp, _construct]:
		s.set_rally_target(rally)
		var tc := s.get_node("TargetController") as SummonTargetController
		tc.refresh(s.global_position)

	var on_rally := 0
	var picked: Array[String] = []
	for s: SummonBase in [_hound, _wisp, _construct]:
		var t := s.current_target()
		picked.append(t.name if t != null else "-")
		if t == rally:
			on_rally += 1

	if on_rally == 3:
		_ok("Rally converges the whole team", "all three switched to %s" % rally.name)
	else:
		_no("rally convergence", "%d of 3 on the rally target (%s)" % [on_rally, ", ".join(picked)])

	for s: SummonBase in [_hound, _wisp, _construct]:
		s.set_rally_target(null)
	_stage = 8


func _stage_six_effects() -> void:
	# The brief asks that six simultaneous friendly effects not hide red
	# telegraphs. Headless Godot has a dummy renderer, so this cannot be
	# confirmed by sampling pixels. What IS verifiable, and what actually
	# guarantees the property, is the draw-order contract plus the ability to
	# hold six friendly effects at once.
	var telegraph := _field.get_node_or_null("HostileTelegraph") as MeshInstance3D
	if telegraph == null:
		_no("hostile telegraph present", "test room has no telegraph")
		_stage = 99
		return

	# The brief asks about SIX SIMULTANEOUS friendly effects, so the property to
	# assert is the live count, not how many extra the pool can take. Combat
	# leaves a varying number already active; topping up to at least six is both
	# more faithful and not dependent on how busy the fight happens to be.
	var target_live := 6
	var guard := 0
	while _effects.active_count() < target_live and guard < 32:
		var e := _effects.spawn(_player.global_position + Vector3(float(guard) * 0.4, 0.5, 0.0), &"friendly_a", 1.0)
		guard += 1
		if e == null:
			break

	var live := _effects.active_count()
	if live >= target_live:
		_ok("six simultaneous friendly effects sustained", "%d active, %d free of %d" % [live, _effects.free_count(), _effects.total_count()])
	else:
		_no("six simultaneous effects", "only %d active (pool %d, starved %d)" % [live, _effects.total_count(), _effects.starved_count()])

	var mat := telegraph.get_surface_override_material(0) as StandardMaterial3D
	var telegraph_priority := mat.render_priority if mat != null else -999

	var offenders: Array[String] = []
	var checked := 0
	for node in _walk(_effects):
		if node is AnimatedSprite3D:
			var spr := node as AnimatedSprite3D
			if not spr.visible:
				continue
			checked += 1
			if spr.render_priority >= telegraph_priority:
				offenders.append("%s priority %d" % [spr.name, spr.render_priority])

	if offenders.is_empty() and checked > 0:
		_ok("no friendly effect can draw over the telegraph", "%d live effects at priority %d, telegraph at %d" % [checked, RenderPriority.FRIENDLY_EFFECT, telegraph_priority])
	elif checked == 0:
		_no("effect priority check", "no live effects to inspect")
	else:
		_no("friendly effects occlude telegraphs", "; ".join(offenders))

	_stage = 99


# ---------------------------------------------------------------- static

func _check_render_contract() -> void:
	print("Draw-order contract (guide §2, §11)")
	if RenderPriority.friendly_stays_below_hostile():
		_ok("friendly effects rank below hostile telegraphs", "friendly %d < hostile %d" % [RenderPriority.FRIENDLY_EFFECT, RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("draw-order contract", "friendly %d is not below hostile %d" % [RenderPriority.FRIENDLY_EFFECT, RenderPriority.HOSTILE_TELEGRAPH])


func _check_behaviors_installed() -> void:
	print("\nSpecies modules")
	var expect := {
		"rune_hound": "melee lunge",
		"sword_wisp": "orbit lunge return",
		"gun_construct": "plant aim burst",
	}
	var wrong: Array[String] = []
	for s: SummonBase in [_hound, _wisp, _construct]:
		if s.behavior == null:
			wrong.append("%s has no behaviour" % s.name)
			continue
		var want: String = expect.get(String(s.data.id), "")
		if s.behavior_signature() != want:
			wrong.append("%s signature '%s' expected '%s'" % [s.name, s.behavior_signature(), want])
	if wrong.is_empty():
		_ok("all three species have distinct behaviour modules", ", ".join(expect.values()))
	else:
		_no("behaviour modules", "; ".join(wrong))

	# The plant flag is a contract, not just an emergent motion pattern. Assert it
	# directly so flipping it fails even where the motion happens to look the same.
	var plant_wrong: Array[String] = []
	if _construct.behavior == null or not _construct.behavior.plants_to_attack():
		plant_wrong.append("gun_construct should plant")
	for s: SummonBase in [_hound, _wisp]:
		if s.behavior != null and s.behavior.plants_to_attack():
			plant_wrong.append("%s should not plant" % s.name)
	if plant_wrong.is_empty():
		_ok("only the Gun Construct declares itself planted", "hound and wisp close distance, construct does not")
	else:
		_no("plant contract", "; ".join(plant_wrong))

	# Still one base scene, exactly as Phase 3 required.
	var scenes := {}
	for s: SummonBase in [_hound, _wisp, _construct]:
		scenes[s.scene_file_path] = true
	if scenes.size() == 1:
		_ok("species behaviours did not fork the base scene", scenes.keys()[0])
	else:
		_no("base scene forked", "%d distinct scenes" % scenes.size())


func _check_species_data() -> void:
	# Brief Phase 4 restates damage, interval, and follow lane per species.
	var expect := {
		"rune_hound": {"damage": 18, "interval": 1.05, "lane_x": -1.3, "lane_z": 1.5},
		"sword_wisp": {"damage": 11, "interval": 0.62, "lane_x": 1.3, "lane_z": 0.3},
		"gun_construct": {"damage": 8, "interval": 0.38, "lane_x": 1.5, "lane_z": -1.4},
	}
	var wrong: Array[String] = []
	for s: SummonBase in [_hound, _wisp, _construct]:
		var e: Dictionary = expect[String(s.data.id)]
		var json_damage := int(Balance.get_value("summons/%s/damage" % s.data.id, -1))
		var json_interval := float(Balance.get_value("summons/%s/attack_interval_seconds" % s.data.id, -1.0))
		if s.form.damage != int(e["damage"]) or s.form.damage != json_damage:
			wrong.append("%s damage %d (brief %d, json %d)" % [s.name, s.form.damage, int(e["damage"]), json_damage])
		if not is_equal_approx(s.form.attack_interval_seconds, float(e["interval"])) or not is_equal_approx(s.form.attack_interval_seconds, json_interval):
			wrong.append("%s interval %.2f (brief %.2f, json %.2f)" % [s.name, s.form.attack_interval_seconds, float(e["interval"]), json_interval])
		if not is_equal_approx(s.data.lane_offset.x, float(e["lane_x"])) or not is_equal_approx(s.data.lane_offset.z, float(e["lane_z"])):
			wrong.append("%s lane %s expected x=%s z=%s" % [s.name, s.data.lane_offset, e["lane_x"], e["lane_z"]])
	if wrong.is_empty():
		_ok("species stats and lanes match both the brief and the balance JSON")
	else:
		_no("species data", "; ".join(wrong))

	# Lane sides must match the guide: hound forward-left, wisp right and
	# overhead, construct rear-right.
	var lane_wrong: Array[String] = []
	if not (_hound.data.lane_offset.x < 0.0 and _hound.data.lane_offset.z > 0.0):
		lane_wrong.append("hound lane is not forward-left")
	if not (_wisp.data.lane_offset.x > 0.0 and _wisp.data.lane_offset.y > 0.0):
		lane_wrong.append("wisp lane is not overhead-right")
	if not (_construct.data.lane_offset.x > 0.0 and _construct.data.lane_offset.z < 0.0):
		lane_wrong.append("construct lane is not rear-right")
	if lane_wrong.is_empty():
		_ok("follow lanes match guide §5", "forward-left, overhead-right, rear-right")
	else:
		_no("follow lanes", "; ".join(lane_wrong))


func _bearing(s: SummonBase) -> float:
	var d := s.global_position - _player.global_position
	return atan2(d.z, d.x)


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out


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
	print("PHASE 4:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
