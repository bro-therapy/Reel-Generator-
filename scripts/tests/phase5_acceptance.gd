extends SceneTree

## Phase 5 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase5_acceptance.gd
##
## Each of the six brief criteria is exercised against a live enemy of the role
## it applies to, in a room isolated from unrelated combat.

const FIELD := "res://scenes/tests/enemy_field.tscn"
const TICK := 1.0 / 60.0

const ROLES := ["rift_crawler", "lantern_hexer", "bellguard", "nest_idol", "blade_mite", "siphon_eye"]

var _pass := 0
var _fail := 0

var _field: Node3D
var _hero: Node3D
var _enemies: Dictionary = {}

var _stage := -1
var _ticks := 0
var _mark := 0.0
var _hp_at_mark := 0
var _frontal_damage := 0
var _telegraph_seen: Dictionary = {}
var _damage_events: Array[String] = []
var _killed_at_cleanup := 0


func _initialize() -> void:
	print("\n=== PHASE 5 ACCEPTANCE ===\n")
	_check_state_graph()
	_check_role_data()

	var packed := load(FIELD) as PackedScene
	if packed == null:
		_no("enemy field loads", "cannot load %s" % FIELD)
		_summary()
		return
	_field = packed.instantiate() as Node3D
	root.add_child(_field)
	_hero = _field.get_node_or_null("Player") as Node3D


func _physics_process(delta: float) -> bool:
	if _field == null:
		_summary()
		return true
	_ticks += 1
	if _ticks < 5:
		return false

	match _stage:
		-1: _stage_bind()
		0: _stage_observe_start()
		1: _stage_observe()
		2: _stage_telegraph_report()
		3: _stage_untelegraphed_attack_is_refused()
		4: _stage_windup_cancelled_by_death()
		5: _stage_bellguard_shield()
		6: _stage_bellguard_exposed()
		7: _stage_bellguard_whiff_start()
		8: _stage_bellguard_whiff_watch()
		9: _stage_siphon_tether_start()
		10: _stage_siphon_tether_break()
		11: _stage_nest_idol_cap_start()
		12: _stage_nest_idol_cap_watch()
		13: _stage_cleanup_start()
		14: _stage_cleanup_watch()
		_:
			_summary()
			return true
	return false


func _stage_bind() -> void:
	var missing: Array[String] = []
	for role in ROLES:
		var e := _field.get_node_or_null(role) as EnemyBase
		if e == null:
			missing.append(role)
		else:
			_enemies[role] = e
	if not missing.is_empty():
		_no("field spawns all six roles", "missing: %s" % ", ".join(missing))
		_stage = 99
		return
	_ok("one EnemyBase scene drives all six roles", ", ".join(ROLES))

	# Every role must come from the same scene — the brief asks for one reusable base.
	var scenes := {}
	for role in ROLES:
		scenes[(_enemies[role] as EnemyBase).scene_file_path] = true
	if scenes.size() == 1:
		_ok("roles did not fork the base scene", scenes.keys()[0])
	else:
		_no("base scene forked", "%d distinct scenes" % scenes.size())

	for role in ROLES:
		var e := _enemies[role] as EnemyBase
		_telegraph_seen[role] = 0
		e.telegraph().telegraph_shown.connect(_on_telegraph.bind(role))
		e.attack_landed.connect(_on_attack_landed.bind(role))
		e.attack_suppressed_without_telegraph.connect(_on_suppressed.bind(role))
	_stage = 0


func _on_telegraph(_shape: StringName, _seconds: float, role: String) -> void:
	_telegraph_seen[role] = int(_telegraph_seen[role]) + 1


func _on_attack_landed(_t: Node3D, _amount: int, role: String) -> void:
	_damage_events.append(role)


func _on_suppressed(role: String) -> void:
	_damage_events.append("UNTELEGRAPHED:%s" % role)


# ---------------------------------------------------------------- stages

func _stage_observe_start() -> void:
	_mark = 0.0
	_stage = 1


func _stage_observe() -> void:
	_mark += TICK
	if _mark >= 7.0:
		_stage = 2


func _stage_telegraph_report() -> void:
	print("\nTelegraphs over %.0fs" % _mark)
	for role in ROLES:
		var e := _enemies[role] as EnemyBase
		print("  %-15s telegraphs=%-3d attacks=%-3d suppressed=%d" % [
			role, e.telegraph().telegraphs_shown, e.attacks_landed, e.attacks_suppressed,
		])
	print("")

	# No damage may ever be dealt without a telegraph having been shown.
	var untelegraphed := _damage_events.filter(func(x): return String(x).begins_with("UNTELEGRAPHED:"))
	if untelegraphed.is_empty():
		_ok("no attack landed without a telegraph", "%d damaging attacks, all announced" % _damage_events.size())
	else:
		_no("untelegraphed damage", "%d suppressed attacks: %s" % [untelegraphed.size(), ", ".join(untelegraphed)])

	# Every damaging role must actually have telegraphed at least once.
	var silent: Array[String] = []
	for role in ROLES:
		var e := _enemies[role] as EnemyBase
		# Read the controller's own counter rather than the signal tally: the
		# Siphon Eye tethers within the first few frames, before the harness has
		# finished binding, so signal-only counting missed a real telegraph.
		if e.data.is_damaging() and e.telegraph().telegraphs_shown == 0:
			silent.append(role)
	if silent.is_empty():
		_ok("every damaging role telegraphs", "5 damaging roles; the Nest Idol deals no damage by design")
	else:
		_no("roles that never telegraphed", ", ".join(silent))

	# Telegraph colour and draw order must obey the hostile contract.
	var bad_color: Array[String] = []
	var bad_priority: Array[String] = []
	for role in ROLES:
		var t := (_enemies[role] as EnemyBase).telegraph()
		if not TelegraphController.is_hostile_color(t.current_color()):
			bad_color.append("%s %s" % [role, t.current_color()])
		if t.render_priority() != RenderPriority.HOSTILE_TELEGRAPH:
			bad_priority.append("%s priority %d" % [role, t.render_priority()])
	if bad_color.is_empty():
		_ok("telegraphs stay in the hostile red/orange palette", "no violet, no cool hues")
	else:
		_no("telegraph colour", "; ".join(bad_color))
	if bad_priority.is_empty():
		_ok("telegraphs draw above every friendly effect", "priority %d vs friendly %d" % [RenderPriority.HOSTILE_TELEGRAPH, RenderPriority.FRIENDLY_EFFECT])
	else:
		_no("telegraph draw order", "; ".join(bad_priority))

	_stage = 3


## The telegraph gate is the mechanism behind "every damaging attack has a
## telegraph". Observing that nothing WAS suppressed cannot detect the gate being
## removed — with no gate, nothing is ever suppressed and the check passes
## vacuously. So drive an attack that never telegraphed and require it to land
## nothing.
func _stage_untelegraphed_attack_is_refused() -> void:
	var mite := _enemies["blade_mite"] as EnemyBase
	mite.global_position = _hero.global_position + Vector3(0.8, 0.0, 0.0)
	mite.telegraph().cancel()

	var hits_before: int = _hero.get("hit_count")
	var suppressed_before := mite.attacks_suppressed

	# Reach ATTACK through the state graph without ever calling begin_attack(),
	# so no telegraph is armed.
	mite.get_node("StateMachine").transition_to(EnemyStateMachine.State.WINDUP)
	mite.get_node("StateMachine").transition_to(EnemyStateMachine.State.ATTACK)
	mite._deal_damage()

	var hits_after: int = _hero.get("hit_count")
	if hits_after == hits_before and mite.attacks_suppressed > suppressed_before:
		_ok("an attack that never telegraphed lands nothing", "%d suppression(s), target untouched" % (mite.attacks_suppressed - suppressed_before))
	else:
		_no("telegraph gate", "hits %d->%d, suppressed %d->%d" % [hits_before, hits_after, suppressed_before, mite.attacks_suppressed])

	mite.get_node("StateMachine").transition_to(EnemyStateMachine.State.RECOVER)
	_stage = 4


## Brief: "Windup can be cancelled by death."
func _stage_windup_cancelled_by_death() -> void:
	var crawler := _enemies["rift_crawler"] as EnemyBase
	# Force it into a windup, then kill it mid-telegraph.
	crawler.global_position = _hero.global_position + Vector3(1.0, 0.0, 0.0)
	crawler.begin_attack()

	if crawler.state() != EnemyStateMachine.State.WINDUP:
		_no("crawler enters windup", "state %s" % crawler.state_name())
		_stage = 5
		return

	var landed_before := crawler.attacks_landed
	var telegraph_up := crawler.telegraph().is_visible_now()
	crawler.kill()

	var dead := crawler.state() == EnemyStateMachine.State.DEATH
	var telegraph_down := not crawler.telegraph().is_visible_now()
	var no_extra_damage := crawler.attacks_landed == landed_before

	if dead and no_extra_damage:
		_ok("windup is cancelled by death", "killed mid-telegraph, no damage landed")
	else:
		_no("windup cancellation", "state=%s attacks %d->%d" % [crawler.state_name(), landed_before, crawler.attacks_landed])

	if telegraph_up and telegraph_down:
		_ok("the telegraph clears when the attacker dies", "no orphan warning left on the floor")
	else:
		_no("orphan telegraph", "visible before=%s after=%s" % [telegraph_up, telegraph_down])

	_stage = 5


## Brief: "Bellguard frontal reduction ... work."
func _stage_bellguard_shield() -> void:
	var guard := _enemies["bellguard"] as EnemyBase
	guard.vulnerability_multiplier = 1.0
	guard.hp = guard.data.max_hp

	# Face the guard at the hero, then strike from the front and from behind.
	guard.global_position = _hero.global_position + Vector3(0.0, 0.0, 4.0)
	var facing := guard.facing_target()

	var before := guard.hp
	guard.take_damage(20, guard.global_position + facing * 2.0)
	_frontal_damage = before - guard.hp

	before = guard.hp
	guard.take_damage(20, guard.global_position - facing * 2.0)
	var rear_damage := before - guard.hp

	if _frontal_damage == 10 and rear_damage == 20:
		_ok("Bellguard shield halves frontal damage", "front %d, back %d, from a 20 hit" % [_frontal_damage, rear_damage])
	else:
		_no("frontal reduction", "front %d, back %d, expected 10 and 20" % [_frontal_damage, rear_damage])

	# An unknown origin must not silently benefit from the shield.
	before = guard.hp
	guard.take_damage(20, null)
	var unknown := before - guard.hp
	if unknown == 20:
		_ok("damage with no known origin is not shielded", "%d from a 20 hit" % unknown)
	else:
		_no("unknown-origin damage", "%d, expected full 20" % unknown)

	_stage = 6


## Brief: "... and post-slam vulnerability work."
func _stage_bellguard_exposed() -> void:
	var guard := _enemies["bellguard"] as EnemyBase
	var role := guard.behavior as BellguardRole
	if role == null:
		_no("bellguard role installed", "behaviour is %s" % guard.behavior)
		_stage = 7
		return

	guard.hp = guard.data.max_hp
	role.expose()

	if role.is_exposed() and guard.vulnerability_multiplier > 1.0:
		var before := guard.hp
		guard.take_damage(20, guard.global_position + guard.facing_target() * 2.0)
		var exposed_damage := before - guard.hp
		if exposed_damage > _frontal_damage:
			_ok("post-slam exposure raises damage taken", "%d exposed vs %d shielded, from the same 20 hit" % [exposed_damage, _frontal_damage])
		else:
			_no("post-slam vulnerability", "%d exposed vs %d shielded" % [exposed_damage, _frontal_damage])
	else:
		_no("exposure state", "is_exposed=%s multiplier=%.2f" % [role.is_exposed(), guard.vulnerability_multiplier])

	guard.vulnerability_multiplier = 1.0
	_stage = 7


## Calling expose() directly proves the mechanic but not the trigger. Make the
## guard genuinely whiff — target far outside the wedge — and require exposure
## to follow on its own.
func _stage_bellguard_whiff_start() -> void:
	var guard := _enemies["bellguard"] as EnemyBase
	var role := guard.behavior as BellguardRole
	role._exposed_left = 0.0
	guard.vulnerability_multiplier = 1.0
	# Far enough that the slam cannot connect, but a target still exists so the
	# windup is not cancelled outright.
	guard.global_position = _hero.global_position + Vector3(0.0, 0.0, 30.0)
	guard.begin_attack()
	_mark = 0.0
	_stage = 8


func _stage_bellguard_whiff_watch() -> void:
	_mark += TICK
	var guard := _enemies["bellguard"] as EnemyBase
	var role := guard.behavior as BellguardRole
	if _mark < 2.5:
		return
	if role.is_exposed() or guard.vulnerability_multiplier > 1.0:
		_ok("a slam that whiffs exposes the Bellguard", "exposure triggered by the miss, not set by hand")
	else:
		_no("post-slam exposure trigger", "guard whiffed but never exposed (state %s)" % guard.state_name())
	role._exposed_left = 0.0
	guard.vulnerability_multiplier = 1.0
	_stage = 9


## Brief: "Siphon tether breaks at eight units."
func _stage_siphon_tether_start() -> void:
	var eye := _enemies["siphon_eye"] as EnemyBase
	var role := eye.behavior as SiphonEyeRole
	if role == null:
		_no("siphon role installed", "behaviour is %s" % eye.behavior)
		_stage = 11
		return
	eye.global_position = _hero.global_position + Vector3(2.0, 0.0, 0.0)
	role.attach_tether(_hero)
	if role.is_tethered():
		_ok("Siphon Eye attaches a tether", "at 2 u, break distance %.0f u" % role.tether_break_distance)
	else:
		_no("tether attach", "no tether formed at 2 u")
	_mark = 0.0
	_stage = 10


func _stage_siphon_tether_break() -> void:
	var eye := _enemies["siphon_eye"] as EnemyBase
	var role := eye.behavior as SiphonEyeRole
	var break_at: float = role.tether_break_distance

	# Just inside the break distance the tether must hold.
	eye.global_position = _hero.global_position + Vector3(break_at - 1.0, 0.0, 0.0)
	_mark += TICK
	if _mark < 0.3:
		return
	var held := role.is_tethered()

	# Just outside it, the tether must snap.
	eye.global_position = _hero.global_position + Vector3(break_at + 1.0, 0.0, 0.0)
	var breaks_before := role.tether_breaks
	var guard := 0
	while role.is_tethered() and guard < 30:
		role._tick_tether(TICK, eye.global_position.distance_to(_hero.global_position))
		guard += 1

	if held and not role.is_tethered() and role.tether_breaks > breaks_before:
		_ok("tether holds inside %0.f u and breaks past it" % break_at, "held at %.0f u, snapped at %.0f u" % [break_at - 1.0, break_at + 1.0])
	else:
		_no("tether break distance", "held_inside=%s still_tethered=%s breaks=%d" % [held, role.is_tethered(), role.tether_breaks])

	if not is_equal_approx(break_at, float(Balance.get_value("enemies/siphon_eye/tether_break_distance", -1.0))):
		_no("tether distance source", "%.1f does not match the balance JSON" % break_at)
	else:
		_ok("tether distance comes from the balance JSON", "%.0f u" % break_at)

	_stage = 11


## Brief: "Nest Idol respects child cap."
func _stage_nest_idol_cap_start() -> void:
	var idol := _enemies["nest_idol"] as EnemyBase
	var role := idol.behavior as NestIdolRole
	if role == null:
		_no("nest idol role installed", "behaviour is %s" % idol.behavior)
		_stage = 13
		return
	# Force rapid pulses so the cap is reached inside the test window. The setter
	# also shortens the countdown already in flight.
	role.set_spawn_interval(0.15)
	_mark = 0.0
	_stage = 12


func _stage_nest_idol_cap_watch() -> void:
	_mark += TICK
	var idol := _enemies["nest_idol"] as EnemyBase
	var role := idol.behavior as NestIdolRole

	# Sample continuously: the cap must never be exceeded, not merely end correct.
	var live := role.live_child_count()
	if live > role.spawn_cap:
		_no("nest idol child cap", "%d live children exceeds the cap of %d" % [live, role.spawn_cap])
		_stage = 13
		return

	if _mark < 6.0:
		return

	if role.spawned_total >= role.spawn_cap:
		_ok("Nest Idol spawns up to its cap", "%d spawned, %d live, cap %d" % [role.spawned_total, role.live_child_count(), role.spawn_cap])
	else:
		_no("nest idol spawning", "only %d spawned in %.0fs" % [role.spawned_total, _mark])

	if role.spawns_refused_at_cap > 0:
		_ok("further spawns are refused at the cap", "%d refusals over %.0fs" % [role.spawns_refused_at_cap, _mark])
	else:
		_no("cap enforcement", "the cap was never actually hit, so it was never tested")

	if role.spawn_cap == int(Balance.get_value("enemies/nest_idol/spawn_cap", -1)):
		_ok("spawn cap comes from the balance JSON", "%d" % role.spawn_cap)
	else:
		_no("spawn cap source", "%d does not match the balance JSON" % role.spawn_cap)

	_stage = 13


## Brief: "Enemy cleanup cannot block room completion."
func _stage_cleanup_start() -> void:
	# Kill everything still standing and confirm nothing lingers in the group
	# that a room-completion check would count.
	# Kill everything in the group, not just the six named roles — the Nest Idol's
	# spawned crawlers are live enemies too, and an earlier version of this stage
	# mistook them for corpses that had failed to deregister.
	var tree := root.get_tree()
	var before := tree.get_nodes_in_group("enemies").size()
	# Two passes: a Nest Idol can spawn a child in the same frame as the sweep,
	# and that child is a live enemy rather than a corpse.
	for pass_index in 2:
		for n in tree.get_nodes_in_group("enemies"):
			if n is EnemyBase and (n as EnemyBase).is_alive():
				(n as EnemyBase).kill()
	_killed_at_cleanup = before

	# The property is that a CORPSE never lingers in the group. A freshly spawned
	# live enemy is not a corpse, so count only the dead.
	var still_grouped := 0
	for n in tree.get_nodes_in_group("enemies"):
		if n is EnemyBase and not (n as EnemyBase).is_alive():
			still_grouped += 1
	if still_grouped == 0:
		_ok("a corpse leaves the enemies group immediately", "%d killed, 0 still grouped" % _killed_at_cleanup)
	else:
		_no("corpses block room completion", "%d still in the enemies group after dying" % still_grouped)
	_mark = 0.0
	_stage = 14


func _stage_cleanup_watch() -> void:
	_mark += TICK
	if _mark < 1.5:
		return
	var tree := root.get_tree()
	var grouped := 0
	for n in tree.get_nodes_in_group("enemies"):
		if n is EnemyBase and not (n as EnemyBase).is_alive():
			grouped += 1
	var live_nodes := 0
	for role in ROLES:
		var e: Variant = _enemies[role]
		if e != null and is_instance_valid(e):
			live_nodes += 1

	if grouped == 0:
		_ok("no corpse re-enters the group after death", "0 dead-but-grouped after %.1fs" % _mark)
	else:
		_no("enemies group leak", "%d corpses still grouped %.1fs after death" % [grouped, _mark])

	if live_nodes == 0:
		_ok("dead enemies free themselves", "all %d nodes released within %.1fs" % [ROLES.size(), _mark])
	else:
		_no("enemy node leak", "%d of %d still allocated after %.1fs" % [live_nodes, ROLES.size(), _mark])

	_stage = 99


# ---------------------------------------------------------------- static

func _check_state_graph() -> void:
	print("Enemy state graph (guide §15)")
	var fsm := EnemyStateMachine.new()
	fsm.warn_on_illegal = false
	var cycle := [
		EnemyStateMachine.State.SEEK, EnemyStateMachine.State.WINDUP,
		EnemyStateMachine.State.ATTACK, EnemyStateMachine.State.RECOVER,
		EnemyStateMachine.State.SEEK,
	]
	var walked := true
	for st in cycle:
		if not fsm.transition_to(st):
			walked = false
			break
	if walked:
		_ok("documented cycle is walkable", "SPAWN -> SEEK -> WINDUP -> ATTACK -> RECOVER -> SEEK")
	else:
		_no("cycle", "blocked at %s" % fsm.state_name())
	fsm.free()

	# DEATH must be reachable from everywhere and terminal once entered.
	var unreachable: Array[String] = []
	for st in [EnemyStateMachine.State.SPAWN, EnemyStateMachine.State.SEEK, EnemyStateMachine.State.WINDUP, EnemyStateMachine.State.ATTACK, EnemyStateMachine.State.RECOVER, EnemyStateMachine.State.STAGGER]:
		var probe := EnemyStateMachine.new()
		probe.warn_on_illegal = false
		probe.state = st
		if not probe.kill():
			unreachable.append(EnemyStateMachine.name_of(st))
		probe.free()
	if unreachable.is_empty():
		_ok("DEATH reachable from every state", "including mid-windup")
	else:
		_no("DEATH reachability", "blocked from: %s" % ", ".join(unreachable))

	var terminal := EnemyStateMachine.new()
	terminal.warn_on_illegal = false
	terminal.state = EnemyStateMachine.State.DEATH
	var escaped: Array[String] = []
	for st in [EnemyStateMachine.State.SEEK, EnemyStateMachine.State.WINDUP, EnemyStateMachine.State.ATTACK, EnemyStateMachine.State.STAGGER]:
		var probe := EnemyStateMachine.new()
		probe.warn_on_illegal = false
		probe.state = EnemyStateMachine.State.DEATH
		if probe.transition_to(st):
			escaped.append(EnemyStateMachine.name_of(st))
		probe.free()
	if escaped.is_empty():
		_ok("DEATH is terminal", "no state can follow it")
	else:
		_no("DEATH escapes", "can still reach: %s" % ", ".join(escaped))
	terminal.free()


func _check_role_data() -> void:
	print("\nRole data vs LEVEL1_BALANCE.json")
	var wrong: Array[String] = []
	for role in ROLES:
		var d := load("res://data/enemies/%s.tres" % role) as EnemyData
		if d == null:
			wrong.append("%s missing resource" % role)
			continue
		d.apply_balance()
		var hp := int(Balance.get_value("enemies/%s/hp" % role, -1))
		var speed := float(Balance.get_value("enemies/%s/speed" % role, -1.0))
		if d.max_hp != hp:
			wrong.append("%s hp %d vs json %d" % [role, d.max_hp, hp])
		if not is_equal_approx(d.speed_units_per_second, speed):
			wrong.append("%s speed %.2f vs json %.2f" % [role, d.speed_units_per_second, speed])
		if d.is_damaging() and d.windup_seconds <= 0.0:
			wrong.append("%s is damaging with no windup" % role)
	if wrong.is_empty():
		_ok("all six roles match the balance JSON", "hp and speed, and every damaging role has a windup")
	else:
		_no("role data", "; ".join(wrong))

	# Threat classes must line up with the shared scorer's weights.
	var hexer := load("res://data/enemies/lantern_hexer.tres") as EnemyData
	var idol := load("res://data/enemies/nest_idol.tres") as EnemyData
	var threat_wrong: Array[String] = []
	if hexer.threat_class != TargetScorer.THREAT_HEXER:
		threat_wrong.append("hexer is '%s'" % hexer.threat_class)
	if idol.threat_class != TargetScorer.THREAT_SPAWNER:
		threat_wrong.append("nest idol is '%s'" % idol.threat_class)
	if threat_wrong.is_empty():
		_ok("Hexer and Nest Idol carry priority threat classes", "+%d each in the shared scorer" % int(TargetScorer.SPAWNER_OR_HEXER_BONUS))
	else:
		_no("threat classes", "; ".join(threat_wrong))


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
	print("PHASE 5:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
