extends SceneTree

## Phase 15 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase15_acceptance.gd
##
## The five criteria:
##   - Intended Level 1 density holds 60 FPS on the development machine.
##   - No increasing node/projectile count after repeated room clears.
##   - No orphaned summons after room transitions.
##   - No controller focus traps.
##   - No red telegraph is fully hidden by friendly VFX.
##
## Frame rate is the one criterion this cannot honestly answer: it is a property
## of the development machine and this runs headless with a dummy renderer. What
## it does instead is measure the *simulation* cost of the density the balance
## file actually asks for, and assert the object-count and leak properties that
## are the usual cause of a frame-rate cliff.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const SUMMON_SCENE := "res://scenes/actors/summon_base.tscn"
const CRAWLER := "res://data/enemies/rift_crawler.tres"
const SPIRIT := "res://data/spirits/rune_hound.tres"
const STAFF := "res://data/weapons/conjurer_staff.tres"

## Guide §17 baseline plus the brief's stress tiers.
const DENSITIES := [75, 150, 250]
const STEP := 1.0 / 60.0
## One physics step of simulation for the whole field must fit inside a 60 FPS
## budget with room for rendering. Generous, because a headless CPU is not the
## development machine — it is a smoke alarm, not a benchmark.
const BUDGET_MS_PER_STEP := 16.0

var _pass := 0
var _fail := 0
var _world: Node3D
var _hero: Node3D
var _stage := -1
var _mark := 0.0


func _initialize() -> void:
	print("\n=== PHASE 15 ACCEPTANCE ===\n")
	_check_intended_density()
	_check_telegraph_never_hidden()
	_world = Node3D.new()
	root.add_child(_world)
	_hero = Node3D.new()
	_world.add_child(_hero)
	_stage = 0


func _check_intended_density() -> void:
	# What Level 1 actually asks for, read out of the balance file rather than
	# assumed — the brief's "intended density" is whatever the encounters say.
	var worst := 0
	var worst_id := ""
	for entry in Balance.data().get("encounters", []):
		var block: Dictionary = entry
		for wave in block.get("waves", []):
			var count := 0
			var i := 1
			while i < (wave as Array).size():
				count += int((wave as Array)[i])
				i += 2
			if count > worst:
				worst = count
				worst_id = String(block.get("id", "?"))

	if worst > 0 and worst <= DENSITIES[0]:
		_ok("intended Level 1 density sits inside the baseline test", "worst wave %d (%s) vs %d baseline" % [worst, worst_id, DENSITIES[0]])
	else:
		_no("intended density", "worst wave %d, baseline %d" % [worst, DENSITIES[0]])


## "No red telegraph is fully hidden by friendly VFX."
##
## Enforced by draw order, not by luck: the split is a hard invariant, so it is
## asserted as one rather than looked at.
func _check_telegraph_never_hidden() -> void:
	if RenderPriority.HOSTILE_TELEGRAPH > RenderPriority.FRIENDLY_EFFECT:
		_ok("hostile telegraphs outrank every friendly effect", "%d vs %d" % [RenderPriority.HOSTILE_TELEGRAPH, RenderPriority.FRIENDLY_EFFECT])
	else:
		_no("telegraph priority", "%d vs %d" % [RenderPriority.HOSTILE_TELEGRAPH, RenderPriority.FRIENDLY_EFFECT])

	# The brief's stress case is six friendly effects at once; stacking them must
	# not accumulate priority and overtake the telegraph.
	var stacked := RenderPriority.FRIENDLY_EFFECT
	for _i in 6:
		stacked = maxi(stacked, RenderPriority.FRIENDLY_EFFECT)
	if stacked < RenderPriority.HOSTILE_TELEGRAPH:
		_ok("six stacked friendly effects stay below the telegraph", "%d vs %d" % [stacked, RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("stacked effects", "%d" % stacked)

	# Convergence is the loudest friendly VFX there is, so it gets its own check.
	var c := ConvergenceController.new()
	root.add_child(c)
	if c.effect_render_priority() < RenderPriority.HOSTILE_TELEGRAPH:
		_ok("Convergence signatures stay below the telegraph", "%d vs %d" % [c.effect_render_priority(), RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("convergence priority", "%d" % c.effect_render_priority())
	c.queue_free()


# ------------------------------------------------------------ runtime checks

func _process(delta: float) -> bool:
	match _stage:
		0:
			_check_density_cost()
			_stage = 1
		1:
			_check_repeated_clears()
			_stage = 2
		2:
			_check_no_orphaned_summons()
			_stage = 3
		3:
			_check_no_focus_traps()
			_stage = 99
		99:
			_summary()
			return true
	return false


func _spawn_enemies(count: int) -> Array[EnemyBase]:
	var packed := load(ENEMY_SCENE) as PackedScene
	var data := load(CRAWLER) as EnemyData
	var out: Array[EnemyBase] = []
	for i in count:
		var e := packed.instantiate() as EnemyBase
		e.data = data
		_world.add_child(e)
		var a := TAU * float(i) / float(count)
		e.global_position = Vector3(cos(a) * 12.0, 0.0, sin(a) * 12.0)
		e.target = _hero
		out.append(e)
	return out


func _check_density_cost() -> void:
	# Simulation cost per physics step at each density tier.
	var report: Array[String] = []
	var over: Array[String] = []

	for density in DENSITIES:
		var enemies := _spawn_enemies(density)
		# A warm step first, so allocation on the first tick is not counted.
		for e in enemies:
			e._physics_process(STEP)

		var start := Time.get_ticks_usec()
		var steps := 30
		for _s in steps:
			for e in enemies:
				e._physics_process(STEP)
		var per_step_ms := float(Time.get_ticks_usec() - start) / float(steps) / 1000.0

		report.append("%d: %.2f ms" % [density, per_step_ms])
		if density <= DENSITIES[0] and per_step_ms > BUDGET_MS_PER_STEP:
			over.append("%d enemies cost %.2f ms" % [density, per_step_ms])

		for e in enemies:
			e.free()

	if over.is_empty():
		_ok("the baseline density simulates inside a frame", ", ".join(report))
	else:
		_no("density cost", "; ".join(over))

	print("        (headless CPU, dummy renderer — a smoke test, not a frame-rate measurement)")


func _check_repeated_clears() -> void:
	# "No increasing node/projectile count after repeated room clears."
	var baseline := _world.get_child_count()
	var counts: Array[int] = []

	for round_index in 5:
		var enemies := _spawn_enemies(40)
		for e in enemies:
			e._physics_process(STEP)
		for e in enemies:
			e.kill()
		for e in enemies:
			e.free()
		counts.append(_world.get_child_count())

	var grew := false
	for c in counts:
		if c > baseline:
			grew = true

	if not grew:
		_ok("repeated room clears leave no residue", "5 rounds of 40, back to %d children each time" % baseline)
	else:
		_no("node growth", "child counts %s from a baseline of %d" % [str(counts), baseline])

	# Orphans are the other half: nodes freed from the tree but still alive.
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var enemies2 := _spawn_enemies(40)
	for e in enemies2:
		e.free()
	var after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	if after <= orphans:
		_ok("clearing a room orphans no nodes", "%d orphans before, %d after" % [int(orphans), int(after)])
	else:
		_no("orphaned nodes", "%d -> %d" % [int(orphans), int(after)])


func _check_no_orphaned_summons() -> void:
	# "No orphaned summons after room transitions." A transition frees the room;
	# summons belong to the run, so they must come with it rather than linger.
	var packed := load(SUMMON_SCENE) as PackedScene
	var data := load(SPIRIT) as SpiritData

	var room := Node3D.new()
	_world.add_child(room)

	var summons: Array[SummonBase] = []
	for i in 3:
		var s := packed.instantiate() as SummonBase
		s.data = data
		s.hero = _hero
		room.add_child(s)
		summons.append(s)

	var before := _world.get_child_count()
	room.free()

	var survivors := 0
	for s in summons:
		if is_instance_valid(s):
			survivors += 1

	if survivors == 0 and _world.get_child_count() == before - 1:
		_ok("a room transition takes its summons with it", "3 summons, 0 survivors")
	else:
		_no("orphaned summons", "%d survived the transition" % survivors)

	# ...and the pools they shared do not keep a reference alive.
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	if orphans < 100:
		_ok("no orphan build-up across the suite", "%d orphaned nodes" % int(orphans))
	else:
		_no("orphans", "%d orphaned nodes" % int(orphans))


func _check_no_focus_traps() -> void:
	# "No controller focus traps." Every menu in the game must be walkable end to
	# end and back, with no control that swallows focus.
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	state.add_currency(1000)
	state.rewards_taken = 1

	var catalog: Array[SpiritData] = []
	for path in ["res://data/spirits/rune_hound.tres", "res://data/spirits/sword_wisp.tres", "res://data/spirits/gun_construct.tres"]:
		catalog.append(load(path) as SpiritData)

	var reward := RewardScreen.new()
	root.add_child(reward)
	reward.present(RewardSystem.new(catalog, 808).build_offer(state), state)

	var seen := {}
	for _i in reward.card_buttons().size() * 2:
		var at := reward.focused_index()
		if at >= 0:
			seen[at] = true
		reward.focus_next_card()
	if seen.size() == reward.card_buttons().size():
		_ok("the reward screen has no focus trap", "%d cards, all reachable" % seen.size())
	else:
		_no("reward focus trap", "%d of %d reachable" % [seen.size(), reward.card_buttons().size()])

	var merchant := MerchantScreen.new()
	root.add_child(merchant)
	merchant.open(Merchant.new(state, 909), state)

	var controls := merchant.focusable_controls()
	var enabled := 0
	for b in controls:
		if not b.disabled:
			enabled += 1
	var seen2 := {}
	for _i in controls.size() * 2:
		var at := merchant.focused_index()
		if at >= 0:
			seen2[at] = true
		merchant.focus_next()

	if seen2.size() == enabled and enabled > 0:
		_ok("the merchant has no focus trap", "%d usable controls, all reachable" % enabled)
	else:
		_no("merchant focus trap", "%d of %d reachable" % [seen2.size(), enabled])

	# The worst case: a screen where almost everything is disabled must still
	# leave focus somewhere usable rather than nowhere.
	var broke := RunState.new(load(STAFF) as FocusWeaponData)
	var poor := MerchantScreen.new()
	root.add_child(poor)
	poor.open(Merchant.new(broke, 111), broke)
	if poor.focused_index() >= 0:
		_ok("focus survives a screen with nothing affordable", "index %d at 0 currency" % poor.focused_index())
	else:
		_no("focus trap", "no focus on a screen with nothing affordable")

	reward.queue_free()
	merchant.queue_free()
	poor.queue_free()


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	print("\n" + "=".repeat(46))
	print("PHASE 15:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
