extends SceneTree

## Phase 12 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase12_acceptance.gd
##
## The five criteria:
##   - Rally target clears when invalid.
##   - Stability cannot exceed 100 or drop below zero.
##   - Convergence cannot be retriggered while active.
##   - Red telegraphs remain visible during full Convergence.
##   - Run ends cleanly at zero Stability.

const STAFF := "res://data/weapons/conjurer_staff.tres"
const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const CRAWLER := "res://data/enemies/rift_crawler.tres"

var _pass := 0
var _fail := 0
var _stage := -1


func _initialize() -> void:
	print("\n=== PHASE 12 ACCEPTANCE ===\n")
	_check_stability_bounds()
	_check_run_ends_at_zero()
	_check_convergence_numbers()
	_check_convergence_retrigger()
	_check_render_priority()
	_stage = 0


func _state() -> RunState:
	return RunState.new(load(STAFF) as FocusWeaponData)


# ---------------------------------------------------------------- stability

func _check_stability_bounds() -> void:
	# Brief: "Stability cannot exceed 100 or drop below zero." Pushed hard from
	# both ends, including in one enormous step.
	var s := _state()
	var start := int(Balance.stability().get("start", 100))

	s.adjust_stability(500)
	var over := s.stability
	s.adjust_stability(-10_000)
	var under := s.stability
	s.adjust_stability(-50)
	var still_under := s.stability

	if over == start and under == 0 and still_under == 0:
		_ok("Stability clamps at both ends", "%d after +500, 0 after -10000" % over)
	else:
		_no("stability bounds", "+500 -> %d, -10000 -> %d, -50 -> %d" % [over, under, still_under])

	# ...and a normal adjustment in between still works, so the clamp is not
	# just freezing the value.
	var s2 := _state()
	s2.adjust_stability(-int(RiftEvent.entry_cost()))
	if s2.stability == start - RiftEvent.entry_cost():
		_ok("ordinary Stability changes still apply", "%d -> %d" % [start, s2.stability])
	else:
		_no("stability change", "%d" % s2.stability)

	# Guide §7 numbers, asserted against the JSON.
	var block := Balance.stability()
	if int(block.get("start", -1)) == 100 and int(block.get("rift_entry_cost", -1)) == 10 and int(block.get("elite_reward_restore", -1)) == 5:
		_ok("Stability balance matches the guide", "start 100, Rift 10, elite +5")
	else:
		_no("stability balance", str(block))

	# The elite restore must respect the ceiling too.
	var full := _state()
	full.adjust_stability(int(block.get("elite_reward_restore", 5)))
	if full.stability == start:
		_ok("an elite restore cannot overfill the bar", "%d/%d" % [full.stability, start])
	else:
		_no("elite restore", "%d" % full.stability)


func _check_run_ends_at_zero() -> void:
	# Brief: "Run ends cleanly at zero Stability."
	var s := _state()
	var failures: Array = []
	s.run_failed.connect(func() -> void: failures.append(1))

	s.adjust_stability(-(s.max_stability - 1))
	var before := failures.size()
	s.adjust_stability(-1)

	if before == 0 and failures.size() == 1 and s.stability_is_spent():
		_ok("the run ends when Stability reaches zero", "one failure signal at 0")
	else:
		_no("run end", "%d signals before, %d after" % [before, failures.size()])

	# Cleanly: further damage must not fire it again. A result screen that opens
	# twice is the same bug as a boss that dies twice.
	s.adjust_stability(-50)
	s.adjust_stability(-1)
	if failures.size() == 1:
		_ok("the run only ends once", "further damage fires nothing")
	else:
		_no("repeat failure", "%d signals" % failures.size())


# ---------------------------------------------------------------- convergence

func _check_convergence_numbers() -> void:
	var c := ConvergenceController.new()
	root.add_child(c)
	var o := Balance.overdrive()

	var ok := (
		is_equal_approx(c.meter_max, float(o.get("meter_max", 100)))
		and is_equal_approx(c.duration(), float(o.get("duration_seconds", 4.0)))
	)
	if ok and is_equal_approx(c.meter_max, 100.0) and is_equal_approx(c.duration(), 4.0):
		_ok("Convergence meter and duration match balance", "%.0f meter, %.0f s" % [c.meter_max, c.duration()])
	else:
		_no("convergence numbers", "meter %.0f, %.1f s" % [c.meter_max, c.duration()])

	# Multipliers apply only while active — an inactive Convergence must be
	# invisible to the rest of the game.
	var idle_move := c.move_multiplier()
	var idle_attack := c.attack_multiplier()
	var idle_dash := c.dash_cooldown_multiplier()

	c.add(c.meter_max)
	c.trigger([])

	var want_move := float(o.get("move_speed_multiplier", 1.15))
	var want_attack := float(o.get("attack_speed_multiplier", 1.3))
	var want_dash := float(o.get("dash_cooldown_multiplier", 0.65))

	if is_equal_approx(idle_move, 1.0) and is_equal_approx(idle_attack, 1.0) and is_equal_approx(idle_dash, 1.0):
		_ok("an idle Convergence changes nothing", "all multipliers 1.0")
	else:
		_no("idle multipliers", "%.2f / %.2f / %.2f" % [idle_move, idle_attack, idle_dash])

	if (is_equal_approx(c.move_multiplier(), want_move)
			and is_equal_approx(c.attack_multiplier(), want_attack)
			and is_equal_approx(c.dash_cooldown_multiplier(), want_dash)):
		_ok("an active Convergence applies the balance multipliers", "+15%% move, +30%% attack, x%.2f dash" % want_dash)
	else:
		_no("active multipliers", "%.2f / %.2f / %.2f" % [c.move_multiplier(), c.attack_multiplier(), c.dash_cooldown_multiplier()])

	# It ends on its own and the multipliers go with it.
	c.tick(c.duration() + 0.1)
	if not c.active and is_equal_approx(c.move_multiplier(), 1.0):
		_ok("Convergence ends and its multipliers lift", "%.0f s" % c.duration())
	else:
		_no("convergence end", "active=%s" % c.active)

	c.queue_free()


func _check_convergence_retrigger() -> void:
	# Brief: "Convergence cannot be retriggered while active."
	var c := ConvergenceController.new()
	root.add_child(c)

	var fires: Array = []
	c.triggered.connect(func(_s: float) -> void: fires.append(1))

	if not c.trigger([]):
		_ok("an empty meter cannot trigger", "%.0f/%.0f" % [c.meter, c.meter_max])
	else:
		_no("empty trigger", "triggered at %.0f meter" % c.meter)

	c.add(c.meter_max)
	var first := c.trigger([])

	# Every way a second trigger could arrive, including a full meter handed
	# back mid-Convergence.
	var repeats := 0
	for _i in 5:
		if c.trigger([]):
			repeats += 1
	c.add(c.meter_max)
	if c.trigger([]):
		repeats += 1

	if first and repeats == 0 and fires.size() == 1:
		_ok("Convergence cannot be retriggered while active", "6 further attempts refused")
	else:
		_no("retrigger", "%d repeats, %d trigger signals" % [repeats, fires.size()])

	# Charge earned during a Convergence is dropped, so it cannot end and
	# immediately restart.
	if c.meter <= 0.0:
		_ok("charge earned mid-Convergence is not banked", "meter %.0f" % c.meter)
	else:
		_no("meter banking", "meter %.0f during Convergence" % c.meter)

	# One signature per bonded summon.
	var c2 := ConvergenceController.new()
	root.add_child(c2)
	var signatures: Array = []
	c2.signature_fired.connect(func(id: StringName) -> void: signatures.append(id))
	c2.add(c2.meter_max)
	c2.trigger([&"rune_hound", &"sword_wisp", &"gun_construct"])
	if signatures.size() == 3:
		_ok("one signature fires per bonded summon", "%d summons, %d signatures" % [3, signatures.size()])
	else:
		_no("signatures", "%d fired for 3 summons" % signatures.size())

	c.queue_free()
	c2.queue_free()


func _check_render_priority() -> void:
	# Brief: "Red telegraphs remain visible during full Convergence."
	#
	# Convergence signatures are the brightest friendly VFX in the game, so this
	# is where the colour-ownership rule is most likely to break. The ordering is
	# a hard invariant, not a tuning value.
	var c := ConvergenceController.new()
	root.add_child(c)
	c.add(c.meter_max)
	c.trigger([&"rune_hound", &"sword_wisp", &"gun_construct"])

	if c.effect_render_priority() < RenderPriority.HOSTILE_TELEGRAPH:
		_ok("Convergence effects draw below hostile telegraphs", "%d vs %d" % [c.effect_render_priority(), RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("render priority", "effects at %d, telegraphs at %d" % [c.effect_render_priority(), RenderPriority.HOSTILE_TELEGRAPH])

	if RenderPriority.FRIENDLY_EFFECT < 0 and RenderPriority.HOSTILE_TELEGRAPH > 0:
		_ok("the priority split is unambiguous", "friendly %d, hostile %d" % [RenderPriority.FRIENDLY_EFFECT, RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("priority split", "friendly %d, hostile %d" % [RenderPriority.FRIENDLY_EFFECT, RenderPriority.HOSTILE_TELEGRAPH])

	c.queue_free()


# ---------------------------------------------------------------- rally stage

func _process(_delta: float) -> bool:
	match _stage:
		0:
			_check_rally()
			_stage = 99
		99:
			_summary()
			return true
	return false


func _spawn_enemy() -> EnemyBase:
	var packed := load(ENEMY_SCENE) as PackedScene
	var e := packed.instantiate() as EnemyBase
	e.data = load(CRAWLER) as EnemyData
	root.add_child(e)
	return e


func _check_rally() -> void:
	var rally := RallyController.new()
	root.add_child(rally)

	var p := Balance.player()
	if (is_equal_approx(rally.duration(), float(p.get("rally_mark_duration_seconds", 6.0)))
			and is_equal_approx(rally.cooldown(), float(p.get("rally_cooldown_seconds", 4.0)))
			and is_equal_approx(rally.duration(), 6.0)
			and is_equal_approx(rally.cooldown(), 4.0)):
		_ok("Rally timings match balance", "%.0f s mark, %.0f s cooldown" % [rally.duration(), rally.cooldown()])
	else:
		_no("rally timings", "%.1f s / %.1f s" % [rally.duration(), rally.cooldown()])

	var want_bonus := float(Balance.get_value("summons/global/rally_damage_bonus", -1.0))
	if is_equal_approx(rally.damage_bonus(), want_bonus) and is_equal_approx(want_bonus, 0.15):
		_ok("Rally grants the balance damage bonus", "+%.0f%%" % (want_bonus * 100.0))
	else:
		_no("rally bonus", "%.2f, balance says %.2f" % [rally.damage_bonus(), want_bonus])

	# Shared priority: the marked target scores far above an unmarked one, so
	# every summon reading the same controller converges on it.
	var a := _spawn_enemy()
	var b := _spawn_enemy()
	a.global_position = Vector3(3, 0, 0)
	b.global_position = Vector3(3.2, 0, 0)
	rally.mark(a)

	var scored_a := TargetScorer.score(a, Vector3.ZERO, Vector3.FORWARD, null, rally.target)
	var scored_b := TargetScorer.score(b, Vector3.ZERO, Vector3.FORWARD, null, rally.target)
	if scored_a > scored_b:
		_ok("the marked target outranks its neighbours", "%.0f vs %.0f" % [scored_a, scored_b])
	else:
		_no("rally priority", "%.0f vs %.0f" % [scored_a, scored_b])

	if is_equal_approx(rally.damage_multiplier_for(a), 1.0 + want_bonus) and is_equal_approx(rally.damage_multiplier_for(b), 1.0):
		_ok("only the marked target takes bonus damage", "x%.2f vs x1.00" % rally.damage_multiplier_for(a))
	else:
		_no("rally damage", "x%.2f vs x%.2f" % [rally.damage_multiplier_for(a), rally.damage_multiplier_for(b)])

	# Cooldown: a second mark inside four seconds is refused.
	var remarked := rally.mark(b)
	if not remarked and rally.target == a:
		_ok("Rally cannot be re-placed on cooldown", "%.1f s left" % rally.cooldown_left)
	else:
		_no("rally cooldown", "re-marked with %.1f s left" % rally.cooldown_left)

	# The mark expires on its own.
	var reasons: Array = []
	rally.cleared.connect(func(reason: StringName) -> void: reasons.append(reason))
	rally.tick(rally.duration() + 0.1)
	if not rally.has_target() and reasons == [&"expired"]:
		_ok("the mark expires after its duration", "%.0f s" % rally.duration())
	else:
		_no("rally expiry", "target=%s reasons=%s" % [rally.has_target(), str(reasons)])

	# The criterion itself: an invalid target clears the mark.
	rally.cooldown_left = 0.0
	var doomed := _spawn_enemy()
	rally.mark(doomed)
	doomed.kill()
	rally.tick(0.1)
	if not rally.has_target():
		_ok("a dead target clears the mark", "cleared as invalid")
	else:
		_no("rally invalid", "the mark survived its target's death")

	# ...and so does a freed one, which is the case that crashes rather than
	# merely misbehaving.
	rally.cooldown_left = 0.0
	var freed := _spawn_enemy()
	rally.mark(freed)
	freed.free()
	rally.tick(0.1)
	if not rally.has_target():
		_ok("a freed target clears the mark", "no dangling reference")
	else:
		_no("rally freed", "the mark held a freed node")

	a.queue_free()
	b.queue_free()
	doomed.queue_free()
	rally.queue_free()


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 12:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
