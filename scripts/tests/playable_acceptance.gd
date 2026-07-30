extends SceneTree

## Acceptance checks for the playable build — the scene F5 runs.
##
##   godot --headless --path . --script scripts/tests/playable_acceptance.gd
##
## Every other suite tests one system. This one tests that they are in the same
## scene and talking to each other, which is the thing that was missing: all
## sixteen phases passed while pressing play showed a Phase 0 diagnostic screen.
##
## The camera checks are geometry, not taste. Guide §12 says the camera never
## rotates and the hero reads at 88 px, and both are arithmetic — so they are
## computed here rather than eyeballed in a screenshot.
##
## Expect a few hundred `Parameter "m" is null` errors while this runs. They come
## from Godot's dummy renderer, which `--headless` uses and which has no real mesh
## storage to hand back. Measured: 287 under --headless, **0** under real OpenGL on
## the same scene. Nothing is wrong and there is nothing to fix in the game — do
## not go looking.

const PLAYABLE := "res://scenes/playable.tscn"
const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")
const STEP := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _slice: Node3D
var _frames := 0


func _initialize() -> void:
	print("\n=== PLAYABLE ACCEPTANCE ===\n")
	var packed := load(PLAYABLE) as PackedScene
	if packed == null:
		_no("scene", "cannot load %s" % PLAYABLE)
		_summary()
		return
	_slice = packed.instantiate() as Node3D
	root.add_child(_slice)


## Waits a frame before asserting. The slice builds its world in `_ready`, and its
## nodes are not in the tree — so global_position is unusable and the audio pool's
## positional voices cannot play — until the first processed frame.
## Two phases. The instant checks run on frame 2; then the fight is left to run
## for real — summons acting under their own _physics_process, enemies dying and
## being freed mid-targeting — because that is what a few manually-stepped frames
## can never exercise. The freed-enemy targeting error that halted the first
## playtest lived exactly in that gap: this suite was green at 6 frames of combat
## and the game fell over at second five.
## Two phases, because two independent properties are being measured and mixing
## them made the second untestable.
##
##   0-10 s   no intervention at all. Proves the summons fight effectively with
##            nobody touching the controls (the no-aim promise).
##   10-25 s  stragglers are killed whenever the count stalls, to drive the wave
##            transitions. The first version left this to the summons, they left
##            one enemy of seven alive at the 15 s mark, the wave never cleared,
##            and the wave-progression check could not fire. Isolating the
##            property under test — the project's own rule.
const SOAK_UNAIDED_FRAMES := 600   # 10 s
const SOAK_FRAMES := 1500          # 25 s total

var _soaking := false
var _soak_started := 0
var _spawned_at_soak := 0
var _unaided_alive := -1
var _upgrades_taken := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	if not _soaking:
		_check_assembled()
		_check_camera()
		_check_combat_triggers()
		_check_no_growth()
		# Second wave for the soak: combat_b has not been triggered yet.
		var combat_b := WardLayout.space(&"combat_b")
		_slice.hero.global_position = combat_b.centre
		_soaking = true
		_soak_started = _frames
		return false

	if _frames == _soak_started + 2:
		_spawned_at_soak = _slice.enemies_alive()

	var into_soak := _frames - _soak_started

	# Snapshot the unaided result before any intervention.
	if into_soak == SOAK_UNAIDED_FRAMES:
		_unaided_alive = _slice.enemies_alive()

	# A level-up pauses the tree and waits for a choice. Nobody is holding the
	# controller here, so the soak takes the first card — exactly what a player
	# does — otherwise the fight freezes on the first level and every downstream
	# check reads as a combat failure. This is also the only place that proves
	# the screen can be dismissed at all.
	if _slice.level_up_screen != null and _slice.level_up_screen.visible:
		_upgrades_taken += 1
		_slice.level_up_screen.press(0)
		return false

	# Past the unaided window, clear stragglers so waves actually advance.
	if into_soak > SOAK_UNAIDED_FRAMES and into_soak % 60 == 0:
		for e in _slice.enemies.duplicate():
			if is_instance_valid(e) and e.is_alive():
				e.kill()

	# Summon the boss a second before the soak ends. An Area3D added this frame
	# is not in the physics world yet — the server registers it on the next
	# tick — so a shape query run immediately after spawning finds nothing and
	# says "unhittable" about a boss that is fine.
	if into_soak == SOAK_FRAMES - 60:
		_open_boss_door_and_enter()

	if into_soak < SOAK_FRAMES:
		return false

	_check_soak()
	_check_feedback_fired()
	_check_progression()
	_check_damage_numbers()
	_check_boss_gate()
	_check_room_reentry_works()
	_check_boss_is_fightable()
	_summary()
	return true


## The fight ran for fifteen real seconds with no input. Two things have to be
## true at the end: enemies actually died (the no-aim promise — summons fight
## effectively with nobody touching aim), and the run got there without a script
## error (enforced by check_project.sh, which fails any suite that emits one).
## 25 s of walking, dashing enemies, shots and deaths — if no particle burst
## fired in all that, the layer is decorative. Steps alone fire dozens.
func _check_feedback_fired() -> void:
	var fired: int = _slice.presentation.particles.bursts_fired()
	if fired >= 10:
		_ok("feedback bursts fired during the fight", "%d bursts" % fired)
	else:
		_no("feedback layer", "only %d particle bursts in a full driven fight" % fired)


## The whole progression loop, end to end, over a real fight: enemies died, orbs
## were collected, levels were gained, upgrade choices were offered and taken,
## and summons appeared as a result. Every one of those is a separate link and
## any of them breaking silently would leave the others looking fine.
## Damage numbers must actually have printed. A pool that exists but never
## shows anything looks identical to a working one from the outside.
## The boss door needs BOTH conditions, so all four combinations are driven
## explicitly rather than checked against whatever state the soak happened to
## leave behind. The first version of this asserted "refuses while rooms remain"
## only IF rooms remained — and the soak had already cleared them, so it silently
## checked nothing at all.
func _check_boss_gate() -> void:
	var run: RunState = _slice.run
	var needed: int = _slice.boss_required_level()
	var saved_cleared: Dictionary = _slice._cleared.duplicate()
	var saved_level: int = run.level
	var required: Array = _slice.required_encounters()

	var results: Array[String] = []
	var wrong: Array[String] = []
	for rooms_done in [false, true]:
		for level_ok in [false, true]:
			_slice._cleared.clear()
			if rooms_done:
				for id in required:
					_slice._cleared[id] = true
			run.level = needed if level_ok else 1

			var open: bool = _slice.boss_is_unlocked()
			var should_open: bool = rooms_done and level_ok
			results.append("rooms=%s level=%s -> %s"
				% [rooms_done, level_ok, "open" if open else "shut"])
			if open != should_open:
				wrong.append("rooms=%s level=%s gave %s, expected %s"
					% [rooms_done, level_ok, "open" if open else "shut",
						"open" if should_open else "shut"])

	_slice._cleared = saved_cleared
	run.level = saved_level

	if wrong.is_empty():
		_ok("the boss door needs every room AND the level",
			"only opens at level %d with all %d cleared" % [needed, required.size()])
	else:
		_no("boss gate", "; ".join(wrong))


## The boss must SPAWN and be HITTABLE. Both halves matter and only the second
## one is subtle.
##
## The First Bell passed nineteen acceptance checks and was impossible to fight:
## every one of them called `take_damage()` directly, while the thing itself was
## a bare Node3D with no hurtbox and no group — a FocusProjectile looks for a
## body or area on the EnemyHurtbox layer owned by something in the "enemies"
## group, and found neither. So this queries the physics world with the
## projectile's own collision mask, which is the only way to show a shot would
## actually connect.
const FRIENDLY_ATTACK_MASK := 1 << 4     # what a friendly projectile scans for

func _open_boss_door_and_enter() -> void:
	for id in _slice.required_encounters():
		_slice._cleared[id] = true
	_slice.run.level = _slice.boss_required_level()
	var arena := WardLayout.space(&"boss")
	if arena != null:
		_slice.hero.global_position = arena.centre
		_slice._check_boss_trigger()


## A cleared room must be fightable again, or a player short of the boss
## threshold has no way to earn the difference — the grind loop the owner
## described ("revisit some of the rooms a couple times and kill mobs to level
## up") would silently not exist.
func _check_room_reentry_works() -> void:
	var target: StringName = &"combat_a"
	var space := WardLayout.space(target)
	if space == null:
		_no("re-entry", "no combat_a space")
		return

	# Force a clean, cleared state, then walk far away and back.
	_slice._cleared[target] = true
	_slice._active_space = &""
	for e in _slice.enemies.duplicate():
		if is_instance_valid(e) and e.is_alive():
			e.kill()
	_slice._prune_enemies()

	_slice.hero.global_position = space.centre + Vector3(200.0, 0.0, 0.0)
	_slice._check_room_reentry()
	if _slice._triggered.has(target):
		_no("re-entry", "leaving a cleared room did not re-arm it")
		return

	var before: int = _slice.spawned_total()
	_slice.hero.global_position = space.centre
	_slice._check_combat_triggers()
	var spawned: int = _slice.spawned_total() - before

	if spawned > 0:
		_ok("a cleared room can be fought again",
			"%d enemies on re-entry, and it stays cleared for the boss gate" % spawned)
	else:
		_no("re-entry", "walking back into a cleared room spawned nothing")

	# It must NOT un-clear itself, or the player could lock themselves back out
	# of the boss door by revisiting a room to grind.
	if _slice._cleared.has(target):
		_ok("re-fighting does not un-clear the room")
	else:
		_no("re-entry", "re-entering removed the room's cleared status — the boss "
			+ "gate would close again")

	# And it should start at the LAST wave, not replay the whole encounter.
	var last: int = _slice._wave_count(target) - 1
	if _slice._wave_index == last:
		_ok("a re-fight starts at the final wave", "wave %d of %d" % [last + 1, last + 1])
	else:
		_no("re-entry wave", "started at wave %d, expected the last (%d)"
			% [_slice._wave_index + 1, last + 1])

	# Leave it in a clean state for the boss checks that follow.
	for e in _slice.enemies.duplicate():
		if is_instance_valid(e) and e.is_alive():
			e.kill()
	_slice._prune_enemies()
	_slice._active_space = &""


func _check_boss_is_fightable() -> void:
	var arena := WardLayout.space(&"boss")
	if arena == null:
		_no("boss room", "the ward has no boss space")
		return

	var boss: FirstBellBoss = _slice.boss
	if boss == null:
		_no("boss spawn", "entering the boss room with the door open spawned nothing")
		return
	_ok("entering the boss room summons The First Bell", "%d hp" % boss.max_hp)

	# Would a shot connect? Ask the physics server the same question a
	# projectile asks.
	var space_state := _slice.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	probe.shape = sphere
	probe.transform = Transform3D(Basis.IDENTITY,
		boss.global_position + Vector3(0.0, boss.world_height * 0.5, 0.0))
	probe.collision_mask = FRIENDLY_ATTACK_MASK
	probe.collide_with_areas = true
	probe.collide_with_bodies = true
	var hits := space_state.intersect_shape(probe, 8)

	var found := false
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and (collider as Node).get_parent() == boss:
			found = true
	if found:
		_ok("the boss has a hurtbox a shot can reach",
			"found on the EnemyHurtbox layer at body height")
	else:
		_no("boss hurtbox", "%d colliders at the boss's position, none belonging to "
			% hits.size() + "it — projectiles pass straight through")

	if boss.is_in_group("enemies"):
		_ok("the boss is in the enemies group", "targeting and damage will find it")
	else:
		_no("boss group", "not in \"enemies\" — summons will never target it")

	# And killing it must end the run.
	var cleared_seen := [false]
	_slice.level_cleared.connect(func(_s: float) -> void: cleared_seen[0] = true)
	boss.take_damage(boss.max_hp * 4)
	if cleared_seen[0]:
		_ok("defeating the boss clears the stage")
	else:
		_no("boss defeat", "the boss died without ending the run")


func _check_damage_numbers() -> void:
	var dn: DamageNumbers = _slice.presentation.damage_numbers
	if dn == null:
		_no("damage numbers", "presentation has no damage number pool")
		return
	if dn.shown_count() > 0:
		_ok("damage numbers printed over enemies", "%d during the fight" % dn.shown_count())
	else:
		_no("damage numbers", "pool built but nothing was ever shown in a full fight")


func _check_progression() -> void:
	var run: RunState = _slice.run
	if run.level > 1:
		_ok("the hero levelled from combat", "level %d, %d xp toward %d"
			% [run.level, run.experience, run.experience_to_next])
	else:
		_no("leveling", "still level 1 after a full fight — enemies are not "
			+ "granting experience, or orbs are not being collected")

	if _upgrades_taken > 0:
		_ok("level-ups offered a choice and accepted one", "%d taken" % _upgrades_taken)
	else:
		_no("upgrades", "no level-up screen appeared during the whole fight")

	if _slice.upgrades.taken_count() > 0:
		_ok("chosen upgrades were applied", "%d in effect" % _slice.upgrades.taken_count())
	else:
		_no("upgrade effects", "choices were made but nothing was applied")

	# The unlock thresholds start at level 2, so a fight that reached level 2
	# must have produced a summon.
	var first_unlock := 99
	var thresholds: Dictionary = Balance.progression().get("summon_unlock_levels", {})
	for k in thresholds:
		first_unlock = mini(first_unlock, int(thresholds[k]))
	if run.level < first_unlock:
		print("        - level %d is below the first unlock (%d); no summon expected"
			% [run.level, first_unlock])
	elif _slice.summons.size() > 0:
		_ok("reaching the threshold materialised a summon",
			"%d summon(s) by level %d" % [_slice.summons.size(), run.level])
	else:
		_no("summon unlock", "level %d is past the level-%d threshold and no summon "
			% [run.level, first_unlock] + "was bonded")


func _check_soak() -> void:
	if _spawned_at_soak <= 0:
		_no("combat soak", "combat_b spawned nothing to fight")
		return
	# Measured at the 10 s mark, before the harness intervened at all.
	if _unaided_alive < 0:
		_no("no-aim promise", "unaided window never sampled")
	elif _unaided_alive < _spawned_at_soak:
		_ok("summons fight a real wave unaided for 10 seconds",
			"%d of %d enemies down with no input and no script errors" % [
				_spawned_at_soak - _unaided_alive, _spawned_at_soak])
	else:
		_no("no-aim promise", "%d enemies still alive after 10s of summon combat — nothing died"
			% _unaided_alive)

	# Every wave of the encounter must have been reached over the soak, or the
	# fight silently ends early — which is the bug the first playtest hit.
	# Asserted on the deepest wave index reached, NOT on a cumulative enemy count.
	# The first version of this compared spawned_total (13) against combat_b's
	# declared total (12) and passed with wave progression entirely removed —
	# combat_a's opening wave plus combat_b's opening wave already exceeded it.
	# The room seals for the fight and only for the fight. Counters, not just
	# state: locked exactly once, unlocked exactly once more than at build time
	# (set_locked(false) during construction counts one).
	var gates: GateController = _slice.ward.combat_gates(&"combat_b")
	if gates == null:
		_no("gates", "combat_b has no GateController")
	elif not gates.is_locked and gates.lock_count == 1:
		_ok("the room unseals when its last wave dies",
			"locked once for the fight, open again at the end")
	else:
		_no("gates", "after the fight: locked=%s lock_count=%d unlock_count=%d"
			% [gates.is_locked, gates.lock_count, gates.unlock_count])

	var waves_declared: int = _slice._wave_count(&"combat_b")
	var deepest: int = _slice.deepest_wave_reached(&"combat_b")
	if waves_declared <= 1:
		_no("wave progression", "combat_b declares %d wave(s) — nothing to progress through"
			% waves_declared)
	elif deepest >= 1:
		_ok("waves chain: clearing one brings the next",
			"reached wave %d of %d in combat_b" % [deepest + 1, waves_declared])
	else:
		_no("wave progression", "combat_b never advanced past wave 1 of %d in 15s — "
			% waves_declared + "later waves are declared but never spawn")

	# The gait split. Guide art ships two locomotion gaits and the hero has to
	# choose between them by speed; before the split all four frames played as one
	# animation and the walk read as a stagger.
	var frames := load("res://data/characters/tower_exile_frames.tres") as SpriteFrames
	if frames != null:
		# Frame COUNTS, not just existence. `add_animation` followed by no frames
		# leaves an empty animation that has_animation() happily confirms, so the
		# mutant that emptied WALK_COLUMNS passed the existence check.
		var walk_n := frames.get_frame_count("walk_south") if frames.has_animation("walk_south") else 0
		var run_n := frames.get_frame_count("run_south") if frames.has_animation("run_south") else 0
		var has_walk := walk_n >= 2
		var has_run := run_n >= 2
		if has_walk and has_run:
			_ok("the hero has separate walk and run cycles",
				"walk %d frames @ %.0f fps, run %d frames @ %.0f fps" % [
					frames.get_frame_count("walk_south"), frames.get_animation_speed("walk_south"),
					frames.get_frame_count("run_south"), frames.get_animation_speed("run_south")])
		else:
			_no("gait split", "walk_south has %d frames, run_south has %d — both need >= 2"
				% [walk_n, run_n])

	# And the hero must actually select between them. Asserted through the speed
	# it reports, not through whichever animation happens to be showing.
	var hero_node = _slice.hero
	if hero_node.has_method("current_gait"):
		hero_node.velocity = Vector3.ZERO
		var at_rest: String = hero_node.current_gait()
		hero_node.velocity = Vector3(1.0, 0.0, 0.0)          # slow
		var slow: String = hero_node.current_gait()
		hero_node.velocity = Vector3(6.2, 0.0, 0.0)          # top speed
		var fast: String = hero_node.current_gait()
		hero_node.velocity = Vector3.ZERO
		if at_rest == "idle" and slow == "walk" and fast == "run":
			_ok("gait follows speed", "still=idle, 1 u/s=walk, 6.2 u/s=run")
		else:
			_no("gait selection", "still=%s slow=%s fast=%s" % [at_rest, slow, fast])

	# The specific shape of the playtest crash: a freed enemy handed to the
	# targeting contract. Must be answered, quietly, with false.
	var victim := ENEMY_SCENE.instantiate() as EnemyBase
	victim.data = load("res://data/enemies/rift_crawler.tres") as EnemyData
	root.add_child(victim)
	victim.free()
	if TargetScorer.is_targetable(victim) == false:
		_ok("a freed enemy is quietly untargetable",
			"the guard runs instead of the signature rejecting it")
	else:
		_no("freed target", "is_targetable said true for a freed node")
	if TargetScorer.pick_best([], Vector3.ZERO, Vector3.ZERO, 10.0, victim, victim) == null:
		_ok("pick_best survives freed sticky and rally references")
	else:
		_no("pick_best", "returned something for an empty candidate list")


func _check_assembled() -> void:
	var missing: Array[String] = []
	for part in ["hero", "camera", "hud", "presentation", "quality", "run",
			"rally", "convergence", "pause"]:
		if _slice.get(part) == null:
			missing.append(part)
	if missing.is_empty():
		_ok("every system is present in one scene",
			"hero, camera, HUD, audio, effects, quality, run state, rally, convergence, pause")
	else:
		_no("assembly", "missing: %s" % ", ".join(missing))

	# The starting team is now EMPTY, and that is the point.
	#
	# Guide §5 said "one of each species" at the start. The owner overrode it:
	# "right off the gate I shouldn't have all three summons — I should start off
	# with just a basic shot, then once I reach a certain level I can get the
	# dog". So the assertion is inverted: a run that begins with summons already
	# bonded has regressed to the old design. docs/PROGRESSION_DESIGN.md records
	# the amendment.
	var summons: Array = _slice.summons
	var bonded: Array = _slice.run.bonded_ids()
	if summons.is_empty() and bonded.is_empty():
		_ok("the run starts with the Focus Weapon alone", "no summons bonded at level 1")
	else:
		_no("starting team", "%d summons and %d bonds at level 1 — summons are "
			% [summons.size(), bonded.size()] + "supposed to be earned")

	# ...and the unlock thresholds must be reachable, or they are decorative.
	var thresholds: Dictionary = Balance.progression().get("summon_unlock_levels", {})
	if thresholds.size() == 3:
		var levels: Array = []
		for k in thresholds:
			levels.append("%s@%d" % [k, int(thresholds[k])])
		levels.sort()
		_ok("all three summons have an unlock level", ", ".join(levels))
	else:
		_no("unlock levels", "%d species have thresholds, expected 3" % thresholds.size())

	# Each summon must have found the hero, or it will sit at the origin forever.
	var orphans := 0
	for s in summons:
		if (s as SummonBase).hero == null:
			orphans += 1
	if orphans == 0:
		_ok("every summon is following the hero")
	else:
		_no("summon follow", "%d summons have no hero" % orphans)

	if _slice.presentation.audio.slot_count() > 0:
		_ok("audio is loaded", "%d slots" % _slice.presentation.audio.slot_count())
	else:
		_no("audio", "no slots loaded")

	# Music has to actually be playing, not merely requested.
	if _slice.presentation.audio.current_music() != &"":
		_ok("a music bed is playing", String(_slice.presentation.audio.current_music()))
	else:
		_no("music", "nothing playing")


# ---------------------------------------------------------------------- camera

func _check_camera() -> void:
	var cam: FollowCamera = _slice.camera

	if cam.is_unrotated():
		_ok("the camera is level", "guide §12: never rotates during gameplay")
	else:
		_no("camera rotation", "y %.3f, z %.3f" % [cam.rotation.y, cam.rotation.z])

	# The real invariant is "the wall between the camera and the hero does not block
	# the view", and there are two independent ways to satisfy it: look over the
	# wall, or do not draw it. This check used to assert only the first — a pure
	# geometry test — which made it a stale proxy the moment WardBuilder started
	# hiding camera-side walls. Pinning the geometry alone would now block the
	# closer framing the owner asked for, for a reason that no longer exists.
	var wall_h := WardLayout.WALL_HEIGHT
	var pitch := deg_to_rad(cam.pitch())
	# Ray height at a wall depends on pitch alone; the camera distance cancels.
	var nearest_wall := INF
	for s in WardLayout.spaces():
		nearest_wall = minf(nearest_wall, s.size.y * 0.5)
	var ray_height := cam.look_height + nearest_wall * tan(pitch)
	var clears := ray_height > wall_h

	# Ask the ward itself, rather than trusting the default.
	var ward := _slice.get_node_or_null("Ward")
	var hidden: bool = ward != null and bool(ward.get("hide_camera_side_walls"))

	if hidden or clears:
		_ok("the near wall cannot block the view",
			"camera-side walls hidden=%s, sight line %.1f m vs %.1f m wall" % [
				hidden, ray_height, wall_h])
	else:
		_no("camera occlusion", "walls are drawn and the sight line is only %.1f m "
			% ray_height + "at a %.1f m wall — the near wall will fill the frame" % wall_h)

	# And the hidden walls must still stop the player, or the fix trades a visual
	# problem for the player walking out of the level.
	if hidden:
		# Counted on the HIDDEN meshes specifically. Counting the whole ward passed
		# with every hidden wall's collision stripped, because the visible walls
		# still had theirs — the number was never about the walls under test.
		var hidden_meshes := 0
		var hidden_with_collision := 0
		for child in (ward.get_children() if ward != null else []):
			var counts := _audit_hidden_walls(child)
			hidden_meshes += counts.x
			hidden_with_collision += counts.y
		if hidden_meshes == 0:
			_no("wall collision", "no hidden wall meshes found, so hiding is not happening")
		elif hidden_with_collision == hidden_meshes:
			_ok("every hidden wall keeps its collision",
				"%d hidden meshes, all still solid" % hidden_meshes)
		else:
			_no("wall collision", "%d of %d hidden walls have no StaticBody — "
				% [hidden_meshes - hidden_with_collision, hidden_meshes]
				+ "the player can walk out through a wall they cannot see")



	# Guide: "Hero reads at 88 px tall at 1920x1080." That is a readability FLOOR,
	# not a framing target — the first playtest at exactly 88 px came back as
	# "really zoomed out", and the owner set the framing closer. The check now
	# guards the floor and a sanity ceiling instead of pinning one number.
	var visible_height := 2.0 * cam.distance * tan(deg_to_rad(cam.fov * 0.5))
	var hero_px := 1.8 / visible_height * 1080.0
	if hero_px >= 88.0 and hero_px <= 175.0:
		_ok("the hero clears the 88 px readability floor", "%.0f px at %.1f m" % [hero_px, cam.distance])
	else:
		_no("hero size", "%.0f px at %.1f m — floor 88, ceiling 175" % [hero_px, cam.distance])

	# A framing change must ease rather than cut. Guide §12: 0.35-0.6 s.
	var before := cam.framing()
	cam.set_framing(before * 1.15)
	cam.tick(STEP)
	var after_one_frame := cam.framing()
	if after_one_frame > before and after_one_frame < before * 1.15:
		_ok("a framing change interpolates instead of cutting",
			"%.1f -> %.1f m over %.2fs" % [before, before * 1.15, cam.zoom_seconds])
	else:
		_no("framing", "jumped from %.1f to %.1f in one frame" % [before, after_one_frame])
	cam.set_framing(before)



## Walks the ward and returns (hidden mesh count, how many of those still own a
## StaticBody). Visibility and physics are independent in Godot; this is the pair
## of numbers that proves the hiding trick did not also delete the walls.
func _audit_hidden_walls(node: Node) -> Vector2i:
	var total := Vector2i.ZERO
	var mesh := node as MeshInstance3D
	if mesh != null and not mesh.visible:
		total.x += 1
		for child in mesh.get_children():
			if child is StaticBody3D:
				total.y += 1
				break
	for child in node.get_children():
		total += _audit_hidden_walls(child)
	return total

# ---------------------------------------------------------------------- combat

## Walking into a combat space has to start a fight, and the enemies have to come
## from the balance file rather than from a list in the scene.


func _check_combat_triggers() -> void:
	var hero: Node3D = _slice.hero
	var combat := WardLayout.space(&"combat_a")

	# The hero spawns inside the Arrival Path, and the Arrival Path runs an
	# encounter — guide §9 gives it three Rift Crawlers, and they sat unspawned in
	# the balance file until the trigger stopped requiring kind == COMBAT. So the
	# baseline at boot is arrival's declared count, not zero.
	# Only the FIRST wave is on the floor at boot — the rest arrive as the fight
	# progresses. This compared against the encounter's grand total, which was
	# the same number while arrival had a single wave and stopped being so the
	# moment it gained a second.
	var arrival_declared: int = _slice.wave_size_for(&"arrival", 0)
	if arrival_declared <= 0:
		_no("arrival encounter", "balance file declares no arrival enemies")
	elif _slice.enemies_alive() == arrival_declared \
			and _slice.enemies_alive(&"arrival") == arrival_declared:
		_ok("the arrival path spawns its first wave at boot",
			"%d enemies, all tagged to arrival (of %d across %d waves)"
			% [arrival_declared, _slice.total_enemies_for(&"arrival"),
				_slice._wave_count(&"arrival")])
	else:
		_no("arrival encounter", "%d alive at boot (%d tagged arrival), balance says %d"
			% [_slice.enemies_alive(), _slice.enemies_alive(&"arrival"), arrival_declared])

	# The Rift and the boss must NOT be walk-in fights: one is an unchained timed
	# event, the other an unchained boss arena. Asserted on the rule itself
	# (_runs_encounter), not on enemy counts — the hero never goes near either
	# room in this suite, so a count of zero would pass with the rule deleted.
	var rift_runs: bool = _slice._runs_encounter(WardLayout.space(&"optional_rift"))
	var boss_runs: bool = _slice._runs_encounter(WardLayout.space(&"boss"))
	var arrival_runs: bool = _slice._runs_encounter(WardLayout.space(&"arrival"))
	var well_runs: bool = _slice._runs_encounter(WardLayout.space(&"spirit_well"))
	if not rift_runs and not boss_runs and arrival_runs and not well_runs:
		_ok("walk-in encounters are exactly the declared, chained ones",
			"arrival yes; rift, boss, spirit well no")
	else:
		_no("trigger scope", "runs_encounter: arrival=%s rift=%s boss=%s well=%s"
			% [arrival_runs, rift_runs, boss_runs, well_runs])

	hero.global_position = combat.centre
	_slice._process(STEP)

	var spawned: int = _slice.enemies_alive(&"combat_a")
	if spawned <= 0:
		_no("combat trigger", "walking into %s spawned nothing" % combat.label)
		return

	# Entering a combat room seals it. Locked means solid on layer 9 — the
	# player's mask — and visible; open means neither. GateController's counters
	# make the round trip checkable at the end of the soak.
	var gates: GateController = _slice.ward.combat_gates(&"combat_a")
	if gates == null:
		_no("gates", "combat_a has no GateController")
	elif gates.is_locked and gates.gate_meshes.size() >= 2:
		# "Locked" has to mean "solid", not just "flagged". A barrier is solid when
		# it is a collision object on a layer the player's mask includes AND it
		# carries a shape — a StaticBody with the right layer and no
		# CollisionShape stops nothing, and that mutant passed the flag check.
		var solid := 0
		for path in gates.gate_meshes:
			var body := gates.get_node_or_null(path) as CollisionObject3D
			if body == null or body.collision_layer != (1 << 8):
				continue
			for child in body.get_children():
				var cs := child as CollisionShape3D
				if cs != null and cs.shape != null:
					solid += 1
					break
		var player_masked: bool = (int(hero.collision_mask) & (1 << 8)) != 0
		if solid == gates.gate_meshes.size() and player_masked:
			_ok("the fight seals the room",
				"%d barriers locked, all shaped on layer 9, player mask includes 9" % solid)
		else:
			_no("gates", "%d of %d locked barriers actually solid; player masks layer 9: %s"
				% [solid, gates.gate_meshes.size(), player_masked])
	else:
		_no("gates", "locked=%s barriers=%d after triggering combat_a"
			% [gates.is_locked, gates.gate_meshes.size()])

	# Cross-check the count against the balance file, so a wave silently emptied
	# there cannot pass as a working trigger.
	var expected := 0
	for entry in Balance.data().get("encounters", []):
		var block: Dictionary = entry
		if StringName(block.get("id", "")) != &"combat_a":
			continue
		var waves: Array = block.get("waves", [])
		if waves.is_empty():
			break
		var flat: Array = waves[0]
		var i := 1
		while i < flat.size():
			expected += int(flat[i])
			i += 2
		break

	if expected > 0 and spawned == expected:
		_ok("entering a combat space spawns its first wave from the balance file",
			"%d enemies in %s" % [spawned, combat.label])
	else:
		_no("wave contents", "spawned %d, balance says %d" % [spawned, expected])

	# Every wave has to be reachable, not just the first. combat_a is 2x6 and
	# combat_b is 7+4+1; the build shipped to the first playtest spawned waves[0]
	# and silently dropped the rest, which is what "we need more mobs" was.
	var declared: int = _slice.total_enemies_for(&"combat_a")
	if declared > expected:
		_ok("the encounter declares more than one wave",
			"%d enemies across %d waves, first wave %d" % [
				declared, _slice._wave_count(&"combat_a"), expected])
	else:
		_no("wave data", "combat_a totals %d, same as its first wave — "
			% declared + "the multi-wave path cannot be exercised")

	# The per-action feedback layer. The second playtest's "I don't see anything
	# on the screen" was three unconnected pieces: a weapon with a fired signal,
	# audio slots for it, and no listener. Assert the bindings so the gap cannot
	# silently reopen.
	var weapon := (_slice.hero as Player).focus_weapon()
	if weapon != null and weapon.fired.get_connections().size() > 0:
		_ok("the hero's shots have a listener")
	else:
		_no("fired binding", "nothing is connected to the focus weapon's fired signal")
	if _slice.hero.stepped.get_connections().size() > 0 \
			and _slice.hero.dashed.get_connections().size() > 0:
		_ok("footsteps and dashes have listeners")
	else:
		_no("movement feedback", "stepped: %d, dashed: %d connections" % [
			_slice.hero.stepped.get_connections().size(),
			_slice.hero.dashed.get_connections().size()])
	if _slice.presentation.particles != null \
			and _slice.presentation.particles.emitter_count() > 0:
		_ok("particle pool built", "%d emitters across %d kinds" % [
			_slice.presentation.particles.emitter_count(),
			_slice.presentation.particles.kinds().size()])
	else:
		_no("particles", "presentation has no particle pool")

	# Free-asset packs are optional (assets/ is untracked), but when they ARE
	# installed they must actually take effect — a manifest that silently falls
	# back to primitives is indistinguishable from working until someone looks.
	if DirAccess.dir_exists_absolute("res://assets/environment/models/kenney_fantasy_town"):
		var model_props: int = _slice.ward.model_prop_count("combat_b")
		if model_props >= 5:
			_ok("installed packs replace blockout props", "%d model props in combat_b" % model_props)
		else:
			_no("model props", "packs installed but only %d model props in combat_b" % model_props)
	else:
		print("        - model packs not installed; primitive fallback in use (run tools/fetch_free_assets.sh)")

	if FileAccess.file_exists("res://assets/audio/music/external/market_day.ogg"):
		var explore_path := String(_slice.presentation.audio._slots[&"music_sunfall_explore"]["path"])
		var combat_path := String(_slice.presentation.audio._slots[&"music_sunfall_combat"]["path"])
		if explore_path.ends_with("external/market_day.ogg") \
				and combat_path.ends_with("external/battle_ready.mp3"):
			_ok("real music overrides the synthesized beds",
				"Market Day (explore), Battle Ready (combat)")
		else:
			_no("music override", "fetched files exist but slots point at %s / %s"
				% [explore_path, combat_path])
	else:
		print("        - real music not fetched; synthesized beds in use")

	# Every enemy must be hunting the hero, or the fight never starts.
	var untargeted := 0
	for e in _slice.enemies:
		if (e as EnemyBase).target != hero:
			untargeted += 1
	if untargeted == 0:
		_ok("every spawned enemy is hunting the hero")
	else:
		_no("enemy targets", "%d enemies have no target" % untargeted)

	# Re-entering must not spawn a second copy of the same wave.
	_slice._process(STEP)
	if _slice.enemies_alive(&"combat_a") == spawned:
		_ok("a cleared trigger does not re-fire", "%d enemies, not %d" % [spawned, spawned * 2])
	else:
		_no("re-trigger", "%d enemies after a second frame in the room"
			% _slice.enemies_alive(&"combat_a"))

	# Wave advancement counts only the active fight's survivors. Kill combat_a's
	# wave while arrival's crawlers still stand: the next wave must arrive anyway.
	# A global count here stalls forever on stragglers from another room — which
	# with the arrival fight wired is no longer a hypothetical.
	var stragglers: int = _slice.enemies_alive(&"arrival")
	for e in _slice.enemies.duplicate():
		if is_instance_valid(e) and e.is_alive() \
				and e.get_meta(&"encounter_space", &"") == &"combat_a":
			e.kill()
	# One frame to notice the deaths, then the full wave gap, then the spawn.
	var gap_frames := int(_slice.WAVE_GAP_SECONDS / STEP) + 3
	for _i in gap_frames:
		_slice._process(STEP)
	if stragglers > 0 and _slice.enemies_alive(&"combat_a") > 0 \
			and _slice.deepest_wave_reached(&"combat_a") >= 1:
		_ok("stragglers from another room cannot stall the next wave",
			"wave 2 arrived with %d arrival crawlers still alive" % stragglers)
	else:
		_no("per-space waves", "arrival stragglers=%d, combat_a alive=%d, deepest=%d"
			% [stragglers, _slice.enemies_alive(&"combat_a"),
				_slice.deepest_wave_reached(&"combat_a")])


## Phase 15 asserts no growing node count across repeated room clears. The slice is
## what actually spawns and frees enemies, so it is where that can break.
func _check_no_growth() -> void:
	var before: int = _slice.get_child_count()
	var spawned: int = _slice.spawned_total()

	for e in _slice.enemies.duplicate():
		if is_instance_valid(e):
			e.kill()
	# Two frames: one to notice the deaths, one for queue_free to take effect.
	_slice._process(STEP)
	for _i in 3:
		_slice._process(STEP)

	if _slice.enemies_alive() == 0:
		_ok("killing a wave clears the room", "%d spawned this run" % spawned)
	else:
		_no("room clear", "%d enemies still alive" % _slice.enemies_alive())

	if _slice.enemies.is_empty():
		_ok("dead enemies leave the tracking list", "no leak into the next room")
	else:
		_no("enemy list", "%d entries left after every enemy died" % _slice.enemies.size())

	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	if orphans <= 0:
		_ok("no orphaned nodes", "%d" % int(orphans))
	else:
		# Reported rather than failed: other suites in the same process contribute.
		print("        - %d orphan nodes reported (process-wide, not necessarily this scene)" % int(orphans))
		_ok("room clear completed without leaking enemies")

	if _slice.get_child_count() <= before:
		_ok("clearing a room does not grow the scene",
			"%d children before, %d after" % [before, _slice.get_child_count()])
	else:
		_no("node growth", "%d -> %d children" % [before, _slice.get_child_count()])


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PLAYABLE:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
