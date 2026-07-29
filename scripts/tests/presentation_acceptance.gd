extends SceneTree

## Acceptance checks for the presentation layer.
##
##   godot --headless --path . --script scripts/tests/presentation_acceptance.gd
##
## Two questions, and the second matters more than the first.
##
## Does the wiring fire? A sound and an effect hooked to a signal that is never
## emitted is worse than nothing, because the code looks finished. So a real boss
## fight and a real Convergence are driven here and the resulting sounds counted.
##
## Can presentation change the fight? It must not. Every number in this game is
## meant to come from LEVEL1_BALANCE.json and the combat scripts, and the whole
## argument for a separate presentation layer is that it cannot reach them. That
## is asserted by running the same fight twice — once with presentation attached
## and once without — and requiring the outcomes to be identical.

const STEP := 1.0 / 60.0
const FIGHT_SECONDS := 40.0

var _pass := 0
var _fail := 0
var _show: CombatPresentation


func _initialize() -> void:
	print("\n=== PRESENTATION ACCEPTANCE ===\n")
	_show = CombatPresentation.new()
	root.add_child(_show)


## Runs on the first processed frame: the pool's AudioStreamPlayer3D voices are not
## in the tree until then, and a positional sound cannot play before they are.
func _process(_delta: float) -> bool:
	_check_layers_exist()
	_check_boss_fight()
	_check_convergence()
	_check_enemy_wiring()
	_check_presentation_cannot_change_combat()
	_check_colour_ownership_of_wired_effects()
	_summary()
	return true


func _check_layers_exist() -> void:
	if _show.audio != null and _show.audio.slot_count() > 0:
		_ok("presentation builds its own audio layer", "%d slots" % _show.audio.slot_count())
	else:
		_no("audio layer", "no slots — run tools/make_placeholder_audio.py")

	if _show.vfx != null and _show.vfx.effect_ids().size() > 0:
		_ok("presentation builds its own effect pool",
			"%d effects" % _show.vfx.effect_ids().size())
	else:
		print("  SKIP  no effect resources in this checkout")


# ------------------------------------------------------------------ boss fight

func _check_boss_fight() -> void:
	var boss := FirstBellBoss.new()
	root.add_child(boss)
	_show.bind_boss(boss)

	var heard: Array[StringName] = []
	_show.audio.sound_played.connect(func(slot: StringName, _p: int) -> void:
		heard.append(slot))

	# A full rotation, so slams, sweeps and tolls all land at least once.
	var elapsed := 0.0
	while elapsed < FIGHT_SECONDS:
		boss.tick(STEP)
		_show.audio.tick(STEP)
		elapsed += STEP

	var want := [&"boss_slam", &"boss_chain_sweep", &"boss_toll"]
	var missing: Array[String] = []
	for slot in want:
		if not (slot in heard):
			missing.append(String(slot))
	if missing.is_empty():
		_ok("a boss rotation is audible",
			"%d sounds over %.0fs, %d slams" % [heard.size(), FIGHT_SECONDS, boss.slams_this_fight])
	else:
		_no("boss rotation", "never heard %s (got %d sounds)" % [", ".join(missing), heard.size()])

	# The stagger is the fight's readable moment, and it gets both a sound and the
	# fire effect.
	# Let the mixer drain between checks. A real run ticks continuously; a harness
	# that does not will hit the voice ceiling and measure starvation instead of
	# the wiring it meant to test.
	_drain()
	heard.clear()
	var effects: Array[StringName] = []
	_show.vfx.effect_started.connect(func(id: StringName) -> void: effects.append(id))
	boss.stagger()
	if &"boss_stagger" in heard:
		_ok("the stagger is audible")
	else:
		_no("stagger", "no boss_stagger sound (heard %s)" % str(heard))
	if _show.vfx.effect_ids().is_empty():
		pass
	elif &"fire" in effects:
		_ok("the exposed core is visible", "fire effect fired on stagger")
	else:
		_no("stagger effect", "no fire effect (fired %s)" % str(effects))

	boss.queue_free()


# ------------------------------------------------------------------ convergence

func _check_convergence() -> void:
	_drain()
	var c := ConvergenceController.new()
	root.add_child(c)
	c._ready()
	_show.bind_convergence(c)

	var heard: Array[StringName] = []
	var effects: Array[StringName] = []
	_show.audio.sound_played.connect(func(slot: StringName, _p: int) -> void: heard.append(slot))
	_show.vfx.effect_started.connect(func(id: StringName) -> void: effects.append(id))

	c.add(c.meter_max)
	var bonded: Array = [&"rune_hound", &"sword_wisp", &"gun_construct"]
	if not c.trigger(bonded):
		_no("convergence", "would not trigger on a full meter")
		c.queue_free()
		return

	if &"convergence_start" in heard:
		_ok("Convergence is audible")
	else:
		_no("convergence", "no convergence_start (heard %s)" % str(heard))

	# Guide §8: one signature per bonded summon. Three bonds, three signatures —
	# and the pool's per-effect ceiling has to be high enough to show all three,
	# or a full team's Convergence would visibly drop one.
	var lightning := 0
	for id in effects:
		if id == &"lightning":
			lightning += 1
	if _show.vfx.effect_ids().is_empty():
		pass
	elif lightning == bonded.size():
		_ok("every bonded summon's signature is visible",
			"%d signatures for %d bonds" % [lightning, bonded.size()])
	else:
		_no("signatures", "%d lightning effects for %d bonds — the pool ceiling is %d" % [
			lightning, bonded.size(), _show.vfx.max_live_per_effect])

	var species_sounds := 0
	for slot in heard:
		if slot in [&"rune_hound_crescent", &"sword_wisp_slash", &"gun_construct_burst"]:
			species_sounds += 1
	if species_sounds == bonded.size():
		_ok("each species signature has its own sound", "%d distinct" % species_sounds)
	else:
		_no("signature sounds", "%d of %d species sounds" % [species_sounds, bonded.size()])

	c.queue_free()


# ---------------------------------------------------------------------- enemies

## Two different species, not one.
##
## The first version of this check used only rift_crawler — whose correct slot was
## also the fallback the resolver used for everything it did not recognise. Forcing
## the resolver to always return the fallback did not fail a single check. Two
## species with different ids is what makes the mapping testable at all.
func _check_enemy_wiring() -> void:
	var packed := load("res://scenes/enemies/enemy_base.tscn") as PackedScene
	var problems: Array[String] = []
	var confirmed: Array[String] = []

	for id in ["rift_crawler", "lantern_hexer"]:
		_drain()
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		if data == null:
			problems.append("%s: no data resource" % id)
			continue
		var enemy := packed.instantiate() as EnemyBase
		enemy.data = data
		root.add_child(enemy)
		_show.bind_enemy(enemy)

		var heard: Array[StringName] = []
		var handle := func(slot: StringName, _p: int) -> void: heard.append(slot)
		_show.audio.sound_played.connect(handle)

		enemy.take_damage(1)
		enemy.take_damage(999999)
		_show.audio.sound_played.disconnect(handle)

		var want_hit := StringName("enemy_%s_hit" % id)
		var want_death := StringName("enemy_%s_death" % id)
		if want_hit in heard and want_death in heard:
			confirmed.append(id)
		else:
			problems.append("%s: expected %s and %s, heard %s" % [
				id, want_hit, want_death, str(heard)])
		if is_instance_valid(enemy):
			enemy.queue_free()

	if problems.is_empty():
		_ok("each enemy species gets its own sounds", ", ".join(confirmed))
	else:
		_no("enemy wiring", "; ".join(problems))


# ------------------------------------------------- the property that matters

## Presentation must be incapable of changing the fight.
##
## The same scripted fight is run twice, with and without a presentation layer
## bound, and every outcome the boss reports has to match. If a listener ever
## reaches back into combat — a stray tick, a signal that mutates, an ordering
## dependency — this is what catches it, and it catches it without needing to
## guess which of those happened.
func _check_presentation_cannot_change_combat() -> void:
	var results: Array[Dictionary] = []

	for attach in [false, true]:
		var boss := FirstBellBoss.new()
		root.add_child(boss)
		var show: CombatPresentation = null
		if attach:
			show = CombatPresentation.new()
			root.add_child(show)
			show._ready()
			show.bind_boss(boss)

		var elapsed := 0.0
		var damage_at := 12.0
		var damaged := false
		while elapsed < FIGHT_SECONDS:
			boss.tick(STEP)
			if not damaged and elapsed >= damage_at:
				# Enough to cross the phase-two threshold, so the comparison covers
				# a phase change and not just the opening rotation.
				boss.take_damage(int(boss.max_hp * 0.6))
				damaged = true
			elapsed += STEP

		results.append({
			"hp": boss.hp,
			"phase": int(boss.phase),
			"landed": boss.attacks_landed,
			"suppressed": boss.attacks_suppressed,
			"untelegraphed": boss.untelegraphed_hits,
			"slams": boss.slams_this_fight,
			"sweeps": boss.sweeps_this_fight,
			"alive": boss.is_alive(),
		})
		boss.queue_free()
		if show != null:
			show.queue_free()

	var without: Dictionary = results[0]
	var with: Dictionary = results[1]
	var diffs: Array[String] = []
	for key in without:
		if without[key] != with[key]:
			diffs.append("%s: %s vs %s" % [key, without[key], with[key]])

	if diffs.is_empty():
		_ok("presentation cannot change the fight",
			"identical over %.0fs: %d landed, %d slams, phase %d, %d hp" % [
				FIGHT_SECONDS, without["landed"], without["slams"],
				without["phase"], without["hp"]])
	else:
		_no("presentation changed combat", ", ".join(diffs))


## Every effect this layer can fire still has to obey the palette. Checked here
## and not only in the VFX suite, because this file is what decides *which* effect
## goes on *which* event — the place a hostile effect could get attached to a
## friendly one.
func _check_colour_ownership_of_wired_effects() -> void:
	if _show.vfx == null or _show.vfx.effect_ids().is_empty():
		return
	var problems: Array[String] = []

	# Boss moves are hostile. Anything warm is fine; anything violet is not.
	for kind in CombatPresentation.BOSS_MOVES:
		var id: StringName = CombatPresentation.BOSS_MOVES[kind]["effect"]
		if id == &"":
			continue
		var d := _show.vfx.data_for(id)
		if d != null and not d.is_hostile():
			problems.append("boss %s uses friendly effect '%s'" % [kind, id])

	# The Convergence signature is the player's. It must be friendly, and it must
	# sort below a red telegraph however bright it is.
	var sig := _show.vfx.data_for(&"lightning")
	if sig != null:
		if sig.is_hostile():
			problems.append("the Convergence signature is a hostile effect")
		if sig.render_priority() >= RenderPriority.HOSTILE_TELEGRAPH:
			problems.append("the Convergence signature draws at or above a telegraph")

	if problems.is_empty():
		_ok("wired effects keep colour ownership",
			"boss effects hostile, Convergence signature friendly at priority %d" % [
				sig.render_priority() if sig != null else 0])
	else:
		_no("colour ownership", ", ".join(problems))


## Runs the mixer forward until every voice is free, so the next check starts from
## an empty pool rather than inheriting the previous one's.
func _drain() -> void:
	var guard := 0
	while _show.audio.active_voices() > 0 and guard < 3000:
		_show.audio.tick(STEP)
		guard += 1


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PRESENTATION:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
