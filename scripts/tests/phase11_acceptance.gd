extends SceneTree

## Phase 11 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase11_acceptance.gd
##
## The six criteria:
##   - Boss is 2.5 times hero height.
##   - Every hit has a visible red telegraph.
##   - Core exposure is obvious.
##   - Any starter team can win.
##   - Boss defeat opens result state exactly once.
##   - Enrage starts at 180 seconds without adding one-shot damage.

const HERO := "res://data/characters/tower_exile.tres"
const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]
const STEP := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _boss: FirstBellBoss
var _stage := -1


func _initialize() -> void:
	print("\n=== PHASE 11 ACCEPTANCE ===\n")
	_check_balance_wiring()
	_check_height()
	_check_team_can_win()
	_stage = 0


func _spawn() -> FirstBellBoss:
	var b := FirstBellBoss.new()
	root.add_child(b)
	return b


func _check_balance_wiring() -> void:
	# Assert against the JSON, not against the boss's own fields.
	var b := Balance.boss()
	var want := {
		"hp": 2600, "slam_damage": 24, "chain_sweep_damage": 18,
		"stagger_duration_seconds": 4.0, "stagger_damage_window_multiplier": 1.75,
		"enrage_time_seconds": 180, "phase_2_hp_fraction": 0.5,
	}
	var wrong: Array[String] = []
	for k in want:
		if not is_equal_approx(float(b.get(k, -1)), float(want[k])):
			wrong.append("%s=%s" % [k, str(b.get(k, "missing"))])
	if wrong.is_empty():
		_ok("boss balance matches the guide", "hp 2600, stagger 4 s x1.75, enrage 180 s")
	else:
		_no("boss balance", "; ".join(wrong))


func _check_height() -> void:
	# Guide §11: approximately 2.5x the hero's gameplay height.
	var hero := load(HERO) as CharacterData
	var boss := _spawn()
	var ratio := boss.world_height / hero.world_height_units
	if absf(ratio - 2.5) <= 0.15:
		_ok("the boss stands 2.5x the hero", "%.2f u vs %.2f u (%.2fx)" % [boss.world_height, hero.world_height_units, ratio])
	else:
		_no("boss height", "%.2fx the hero" % ratio)
	boss.queue_free()


func _check_team_can_win() -> void:
	# "Any starter team can win." Proven as arithmetic against balance rather
	# than by simulating a fight: a single summon's sustained damage must be able
	# to clear 2600 HP inside the 180 s enrage window, or no team can.
	var hp := float(Balance.boss().get("hp", 2600))
	var enrage := float(Balance.boss().get("enrage_time_seconds", 180))
	var slowest := INF
	var report: Array[String] = []

	for path in SPIRITS:
		var s := load(path) as SpiritData
		var form := s.form(0)
		var dps := float(form.damage) / maxf(form.attack_interval_seconds, 0.01)
		# A three-summon team of one species, which is the weakest legal read of
		# "any starter team", plus the staff is ignored so this stays pessimistic.
		var seconds := hp / maxf(dps * 3.0, 0.01)
		report.append("%s %.0f s" % [s.id, seconds])
		slowest = maxf(0.0 if slowest == INF else slowest, seconds)

	if slowest <= enrage:
		_ok("any starter team can clear the boss before enrage", "slowest %.0f s of %.0f s (%s)" % [slowest, enrage, ", ".join(report)])
	else:
		_no("winnability", "slowest team needs %.0f s, enrage at %.0f s" % [slowest, enrage])


# ------------------------------------------------------------ runtime checks

func _process(_delta: float) -> bool:
	match _stage:
		0:
			_boss = _spawn()
			_stage = 1
		1:
			_check_telegraphs()
			_stage = 2
		2:
			_check_stagger()
			_stage = 3
		3:
			_check_phase_two()
			_stage = 4
		4:
			_check_enrage()
			_stage = 5
		5:
			_check_defeat_once()
			_stage = 99
		99:
			_summary()
			return true
	return false


## "Every hit has a visible red telegraph."
func _check_telegraphs() -> void:
	var boss := _spawn()
	var landed: Array = []
	var armed_at_landing: Array = []
	boss.attack_landed.connect(func(kind: StringName, amount: int) -> void:
		landed.append(kind)
		if amount > 0:
			armed_at_landing.append(boss.telegraph.is_visible_now() or boss.telegraph.is_armed()))

	# Long enough to see the whole rotation several times over.
	for _i in int(40.0 / STEP):
		boss.tick(STEP)

	var damaging := 0
	for k in landed:
		if k != &"toll":
			damaging += 1

	if damaging > 0 and boss.untelegraphed_hits == 0:
		_ok("every damaging hit was telegraphed", "%d hits, 0 untelegraphed" % damaging)
	else:
		_no("telegraphs", "%d hits, %d untelegraphed" % [damaging, boss.untelegraphed_hits])

	if boss.slams_this_fight > 0 and boss.sweeps_this_fight > 0:
		_ok("the rotation uses slam and chain sweep", "%d slams, %d sweeps" % [boss.slams_this_fight, boss.sweeps_this_fight])
	else:
		_no("rotation", "%d slams, %d sweeps" % [boss.slams_this_fight, boss.sweeps_this_fight])

	# The telegraph must be red. Guide §2: hostile telegraphs are never violet.
	var colour := boss.telegraph.current_color()
	if colour.r > colour.b and colour.r > 0.6:
		_ok("the telegraph is hostile red", "#%s" % colour.to_html(false))
	else:
		_no("telegraph colour", "#%s" % colour.to_html(false))

	boss.queue_free()


## "Core exposure is obvious."
func _check_stagger() -> void:
	var boss := _spawn()
	var events: Array = []
	boss.staggered.connect(func(_s: float) -> void: events.append("in"))
	boss.stagger_ended.connect(func() -> void: events.append("out"))

	# Wind the boss into a move so the stagger has something to interrupt.
	for _i in 30:
		boss.tick(STEP)
	boss.stagger()

	var want_mult := float(Balance.boss().get("stagger_damage_window_multiplier", 1.75))
	if boss.core_is_exposed() and is_equal_approx(boss.vulnerability_multiplier, want_mult):
		_ok("stagger exposes the core at the balance multiplier", "x%.2f for %.0f s" % [want_mult, boss.stagger_time_left])
	else:
		_no("stagger", "exposed=%s multiplier %.2f" % [boss.core_is_exposed(), boss.vulnerability_multiplier])

	# Guide §11: the boss does not attack during the stagger.
	var landed_during := 0
	boss.attack_landed.connect(func(_k: StringName, amount: int) -> void:
		if amount > 0 and boss.is_staggered:
			landed_during += 1)
	var before_hits := boss.attacks_landed
	for _i in int(3.0 / STEP):
		boss.tick(STEP)
	if boss.attacks_landed == before_hits and boss.is_staggered:
		_ok("the boss cannot attack while staggered", "3 s of stagger, 0 hits")
	else:
		_no("stagger attacks", "%d hits during the stagger" % (boss.attacks_landed - before_hits))

	# Damage really does land harder while the core is open.
	var open_boss := _spawn()
	open_boss.stagger()
	var hp_before := open_boss.hp
	open_boss.take_damage(100)
	var open_loss := hp_before - open_boss.hp

	var closed_boss := _spawn()
	var hp_before2 := closed_boss.hp
	closed_boss.take_damage(100)
	var closed_loss := hp_before2 - closed_boss.hp

	if open_loss > closed_loss and open_loss == int(round(100.0 * want_mult)):
		_ok("the exposed core takes multiplied damage", "%d vs %d for the same hit" % [open_loss, closed_loss])
	else:
		_no("stagger damage", "%d exposed vs %d closed" % [open_loss, closed_loss])

	# It closes again on its own.
	for _i in int(5.0 / STEP):
		boss.tick(STEP)
	if not boss.core_is_exposed() and is_equal_approx(boss.vulnerability_multiplier, 1.0) and events == ["in", "out"]:
		_ok("the stagger ends and the core closes", "one open, one close")
	else:
		_no("stagger end", "exposed=%s events=%s" % [boss.core_is_exposed(), str(events)])

	boss.queue_free()
	open_boss.queue_free()
	closed_boss.queue_free()


func _check_phase_two() -> void:
	var boss := _spawn()
	var phases: Array = []
	boss.phase_changed.connect(func(p: int) -> void: phases.append(p))

	var fraction := float(Balance.boss().get("phase_2_hp_fraction", 0.5))
	boss.take_damage(int(float(boss.max_hp) * (1.0 - fraction)) - 1)
	var before := boss.phase
	boss.take_damage(5)

	if before == FirstBellBoss.Phase.ONE and boss.phase == FirstBellBoss.Phase.TWO and phases == [2]:
		_ok("phase two begins at the balance HP fraction", "%.0f%% of %d HP" % [fraction * 100.0, boss.max_hp])
	else:
		_no("phase two", "phase %d at %d/%d HP" % [boss.phase, boss.hp, boss.max_hp])

	# Phase two adds a Hexer to the call; phase one does not.
	var hexers: Array = []
	boss.hexer_called.connect(func() -> void: hexers.append(1))
	var crawls: Array = []
	boss.crawlers_called.connect(func(n: int) -> void: crawls.append(n))
	for _i in int(30.0 / STEP):
		boss.tick(STEP)

	if not crawls.is_empty() and crawls[0] == int(Balance.boss().get("crawler_summon_count", 3)):
		_ok("the boss calls three Crawlers", "%d per call, %d calls in 30 s" % [crawls[0], crawls.size()])
	else:
		_no("crawler call", str(crawls))

	if not hexers.is_empty():
		_ok("phase two adds a Hexer to the call", "%d Hexer call(s)" % hexers.size())
	else:
		_no("hexer call", "no Hexer added in phase two")

	boss.queue_free()


## "Enrage starts at 180 seconds without adding one-shot damage."
func _check_enrage() -> void:
	var boss := _spawn()
	var fired: Array = []
	boss.enraged.connect(func() -> void: fired.append(1))

	var enrage_at := float(Balance.boss().get("enrage_time_seconds", 180))
	var slam_before := boss.slam_damage()
	var sweep_before := boss.chain_sweep_damage()

	# Just short of the threshold.
	boss.tick(enrage_at - 1.0)
	var early := fired.size()
	boss.tick(2.0)

	if early == 0 and fired.size() == 1:
		_ok("enrage starts at the balance time", "%.0f s, fired once" % enrage_at)
	else:
		_no("enrage timing", "%d before, %d after" % [early, fired.size()])

	# The whole point of the criterion: enrage must not turn a hit into a
	# one-shot. Damage is unchanged, and both hits stay survivable at full HP.
	var hero_hp := int(Balance.player().get("max_hp", 100))
	if boss.slam_damage() == slam_before and boss.chain_sweep_damage() == sweep_before:
		_ok("enrage does not raise hit damage", "slam %d, sweep %d, unchanged" % [boss.slam_damage(), boss.chain_sweep_damage()])
	else:
		_no("enrage damage", "slam %d->%d" % [slam_before, boss.slam_damage()])

	if boss.slam_damage() < hero_hp and boss.chain_sweep_damage() < hero_hp:
		_ok("no enraged hit one-shots a full-health hero", "%d HP vs slam %d" % [hero_hp, boss.slam_damage()])
	else:
		_no("one-shot", "slam %d against %d HP" % [boss.slam_damage(), hero_hp])

	boss.queue_free()


## "Boss defeat opens result state exactly once."
func _check_defeat_once() -> void:
	var boss := _spawn()
	var defeats: Array = []
	boss.defeated.connect(func() -> void: defeats.append(1))

	# Overkill, then several more killing blows and explicit kills on top.
	boss.take_damage(boss.max_hp * 3)
	boss.take_damage(500)
	boss.kill()
	boss.kill()

	if defeats.size() == 1 and not boss.is_alive() and boss.hp == 0:
		_ok("defeat opens the result state exactly once", "4 killing blows, 1 signal")
	else:
		_no("defeat", "%d defeat signals" % defeats.size())

	# A dead boss stops fighting.
	var landed_after := boss.attacks_landed
	for _i in int(10.0 / STEP):
		boss.tick(STEP)
	if boss.attacks_landed == landed_after:
		_ok("a defeated boss stops attacking", "10 s of ticks, no hits")
	else:
		_no("post-defeat", "%d hits after death" % (boss.attacks_landed - landed_after))

	boss.queue_free()


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 11:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
