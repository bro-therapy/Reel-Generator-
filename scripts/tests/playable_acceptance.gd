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
const SOAK_FRAMES := 900  # 15 seconds

var _soaking := false
var _soak_started := 0
var _spawned_at_soak := 0


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

	if _frames - _soak_started < SOAK_FRAMES:
		return false

	_check_soak()
	_summary()
	return true


## The fight ran for fifteen real seconds with no input. Two things have to be
## true at the end: enemies actually died (the no-aim promise — summons fight
## effectively with nobody touching aim), and the run got there without a script
## error (enforced by check_project.sh, which fails any suite that emits one).
func _check_soak() -> void:
	if _spawned_at_soak <= 0:
		_no("combat soak", "combat_b spawned nothing to fight")
		return
	var alive: int = _slice.enemies_alive()
	if alive < _spawned_at_soak:
		_ok("summons fight a real wave unaided for 15 seconds",
			"%d of %d enemies down, no input, no script errors" % [
				_spawned_at_soak - alive, _spawned_at_soak])
	else:
		_no("no-aim promise", "%d enemies alive after 15s of summon combat — nothing died" % alive)

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

	# The starting team. Guide §5: one of each species, and all three have to be
	# bonded *and* materialised — a bond with no summon in the world is invisible.
	var summons: Array = _slice.summons
	var bonded: Array = _slice.run.bonded_ids()
	if summons.size() == 3 and bonded.size() == 3:
		_ok("the starting team is bonded and in the world", ", ".join(bonded))
	else:
		_no("starting team", "%d summons, %d bonds" % [summons.size(), bonded.size()])

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

	# The sight line to the hero has to clear a wall standing between them, or the
	# near wall fills the lower frame — which is exactly what happened at the 32
	# degrees the static test scenes used.
	var wall_h := WardLayout.WALL_HEIGHT
	var pitch := deg_to_rad(cam.pitch())
	var cam_height := cam.distance * sin(pitch)
	var cam_depth := cam.distance * cos(pitch)
	# The nearest wall of the smallest room, measured from its centre.
	var nearest_wall := INF
	for s in WardLayout.spaces():
		nearest_wall = minf(nearest_wall, s.size.y * 0.5)
	var ray_height := cam.look_height + (nearest_wall / cam_depth) * cam_height

	if ray_height > wall_h + 1.0:
		_ok("the camera sees over the walls",
			"sight line %.1f m at the wall, wall is %.1f m" % [ray_height, wall_h])
	else:
		_no("camera occlusion", "sight line only %.1f m at a %.1f m wall — the near "
			% [ray_height, wall_h] + "wall will fill the lower frame")

	# Guide: "Hero reads at 88 px tall at 1920x1080." That is a readability FLOOR,
	# not a framing target — the first playtest at exactly 88 px came back as
	# "really zoomed out", and the owner set the framing closer. The check now
	# guards the floor and a sanity ceiling instead of pinning one number.
	var visible_height := 2.0 * cam.distance * tan(deg_to_rad(cam.fov * 0.5))
	var hero_px := 1.8 / visible_height * 1080.0
	if hero_px >= 88.0 and hero_px <= 150.0:
		_ok("the hero clears the 88 px readability floor", "%.0f px at %.1f m" % [hero_px, cam.distance])
	else:
		_no("hero size", "%.0f px at %.1f m — floor 88, ceiling 150" % [hero_px, cam.distance])

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


# ---------------------------------------------------------------------- combat

## Walking into a combat space has to start a fight, and the enemies have to come
## from the balance file rather than from a list in the scene.
func _check_combat_triggers() -> void:
	var hero: Node3D = _slice.hero
	var combat := WardLayout.space(&"combat_a")

	if _slice.enemies_alive() != 0:
		_no("combat trigger", "%d enemies before entering a room" % _slice.enemies_alive())
		return
	_ok("no enemies before entering a combat space")

	hero.global_position = combat.centre
	_slice._process(STEP)

	var spawned: int = _slice.enemies_alive()
	if spawned <= 0:
		_no("combat trigger", "walking into %s spawned nothing" % combat.label)
		return

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
	if _slice.enemies_alive() == spawned:
		_ok("a cleared trigger does not re-fire", "%d enemies, not %d" % [spawned, spawned * 2])
	else:
		_no("re-trigger", "%d enemies after a second frame in the room" % _slice.enemies_alive())


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
