class_name PlayableSlice
extends Node3D

## The playable build — one run of Sunfall Ward. The game shell instantiates it.
##
## Every phase built and tested its systems in isolation, and until this file
## existed nothing put them in the same scene — pressing play showed a Phase 0
## diagnostic screen. This assembles them:
##
##   Sunfall Ward geometry, the hero, a follow camera, the HUD, the audio mixer,
##   the realistic effects, three bonded summons, Rally, Convergence, Stability,
##   the pause menu, and enemies that spawn from the balance file when you walk
##   into a combat space.
##
## What is deliberately NOT here yet, so nobody mistakes this for the finished
## slice: room-to-room progression through EncounterController's gates, the
## reward screen between rooms, the merchant, the Rift, and the boss fight are all
## built and tested but not yet chained into one run. This is a playable ward you
## can fight in, not the full 8–12 minute loop.
##
## Nothing here owns balance. Wave contents come from LEVEL1_BALANCE.json through
## Balance.encounters(), so tuning a fight never means editing this file.

const HERO := preload("res://scenes/actors/player.tscn")
const SUMMON := preload("res://scenes/actors/summon_base.tscn")
const ENEMY := preload("res://scenes/enemies/enemy_base.tscn")

## Guide §5: the starting team is one of each species.
const STARTING_SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]

## How close the hero has to get before a combat space wakes up. Comfortably
## inside the room so the fight starts after you are through the door, not as the
## door comes into view.
const TRIGGER_RADIUS := 13.0

## Emitted when the last combat encounter on the critical path is cleared.
signal level_cleared(seconds: float)
signal encounter_cleared(space_id: StringName)
signal encounter_started(space_id: StringName, waves: int)

var hero: Node3D
var ward: Node3D
var camera: FollowCamera
var hud: CombatHUD
var presentation: CombatPresentation
var quality: QualityController
var run: RunState
var rally: RallyController
var convergence: ConvergenceController
var pause: PauseController

var summons: Array[SummonBase] = []
var enemies: Array[EnemyBase] = []

var _triggered: Dictionary = {}
var _spawned_total := 0
## Which space is fighting, and how far through its wave list it is.
var _active_space: StringName = &""
var _wave_index := 0
var _wave_gap := 0.0
## Deepest wave index reached per space. Exists because "total enemies spawned"
## cannot distinguish real wave progression from several rooms each firing only
## their first wave — the mutant that reverted progression passed against a
## cumulative count.
var _deepest_wave: Dictionary = {}
## Spaces whose encounter has been fully cleared, and the run clock.
var _cleared: Dictionary = {}
var _elapsed := 0.0
var _level_done := false


func _ready() -> void:
	AutoloadRef.set_flow_state("RUN")

	_build_world()
	_build_hero()
	_build_camera()
	_build_run_state()
	_build_summons()
	_build_presentation()
	_build_hud()
	_build_pause()

	# Quality settings last: it walks the finished tree, so anything built after it
	# would keep its shadows and particles whatever the settings say.
	quality = QualityController.new()
	quality.name = "Quality"
	quality.settings_source = AutoloadRef.settings()
	add_child(quality)
	quality.apply_to(self)

	presentation.audio.play_music(&"music_sunfall_explore")
	_report()


# ----------------------------------------------------------------------- world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.38, 0.46)
	e.ambient_light_energy = 0.75
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.shadow_enabled = true
	add_child(sun)

	ward = Node3D.new()
	ward.name = "Ward"
	ward.set_script(load("res://scripts/world/ward_builder.gd"))
	add_child(ward)
	ward.build()


func _build_hero() -> void:
	hero = HERO.instantiate()
	hero.name = "Player"
	add_child(hero)
	var start := WardLayout.space(&"arrival")
	# Slightly back from the centre of Arrival, facing the ward, so the first thing
	# on screen is the corridor rather than a wall.
	hero.position = start.centre + Vector3(-6.0, 0.0, 0.0)
	var dbg := OS.get_environment("PZC_START_ROOM")
	if dbg != "":
		var sp := WardLayout.space(StringName(dbg))
		if sp != null:
			hero.position = sp.centre


func _build_camera() -> void:
	camera = FollowCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.follow(hero)
	camera.make_current()


# ------------------------------------------------------------------- run state

func _build_run_state() -> void:
	# RunState is a RefCounted, not a Node — it is run bookkeeping, not something
	# in the world, so it is held rather than parented.
	run = RunState.new()

	rally = RallyController.new()
	rally.name = "Rally"
	add_child(rally)

	convergence = ConvergenceController.new()
	convergence.name = "Convergence"
	add_child(convergence)

	hero.damage_taken.connect(_on_hero_damaged)
	hero.dashed.connect(func() -> void: convergence.on_dash_dodge())


func _build_summons() -> void:
	for path in STARTING_SPIRITS:
		var spirit := load(path) as SpiritData
		if spirit == null:
			push_warning("playable: cannot load %s" % path)
			continue
		run.bond(spirit)

		var s := SUMMON.instantiate() as SummonBase
		s.name = String(spirit.id)
		s.data = spirit
		s.hero = hero
		add_child(s)
		s.snap_to_lane()
		summons.append(s)


func _build_presentation() -> void:
	presentation = CombatPresentation.new()
	presentation.name = "Presentation"
	add_child(presentation)
	presentation.bind_convergence(convergence)


func _build_hud() -> void:
	hud = CombatHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(run, convergence, rally)
	hud.set_health(hero.hp, hero.data.max_hp if hero.data != null else hero.hp)
	hero.health_changed.connect(hud.set_health)
	# Stability is not connected here: hud.bind() already subscribes to it, and
	# connecting again makes Godot log a duplicate-connection error every boot.


func _build_pause() -> void:
	pause = PauseController.new()
	pause.name = "Pause"
	add_child(pause)


# -------------------------------------------------------------------- combat

func _process(delta: float) -> void:
	_elapsed += delta
	_check_combat_triggers()
	_prune_enemies()
	_advance_waves(delta)
	_handle_input()
	if camera != null:
		camera.tick(delta)


## Clearing a wave brings the next one, after a beat.
##
## The pause is the point: guide §6 gives an encounter a rhythm, and a wave that
## lands the instant the last enemy dies reads as an endless stream rather than a
## fight with structure. It also gives the player a moment to see the room is
## briefly clear, which is what makes the next wave feel like a wave.
const WAVE_GAP_SECONDS := 1.6

func _advance_waves(delta: float) -> void:
	if _active_space == &"":
		return
	if enemies_alive(_active_space) > 0:
		_wave_gap = 0.0
		return

	var remaining := _wave_count(_active_space) - (_wave_index + 1)
	if remaining <= 0:
		# Encounter finished. Music is already back to explore via _prune_enemies.
		var done := _active_space
		_cleared[done] = true
		_active_space = &""
		_wave_gap = 0.0
		_set_gates_locked(done, false)
		encounter_cleared.emit(done)
		presentation.audio.play(&"gate")
		print("[play] %s cleared" % String(done))
		_check_level_cleared()
		return

	_wave_gap += delta
	if _wave_gap < WAVE_GAP_SECONDS:
		return
	_wave_gap = 0.0
	_wave_index += 1
	var space := WardLayout.space(_active_space)
	if space != null:
		_spawn_wave(space, _wave_index)


## Walking into a combat space starts its fight. A stand-in for
## EncounterController's gate-and-wave flow, which is built and tested but not yet
## chained room to room — the difference is that this does not lock you in or hand
## out a reward when the room clears.
func _check_combat_triggers() -> void:
	if hero == null or not hero.is_inside_tree():
		return
	for space in WardLayout.spaces():
		if not _runs_encounter(space):
			continue
		if _triggered.has(space.id):
			continue
		if hero.global_position.distance_to(space.centre) > TRIGGER_RADIUS:
			continue
		_triggered[space.id] = true
		_active_space = space.id
		_wave_index = 0
		encounter_started.emit(space.id, _wave_count(space.id))
		_set_gates_locked(space.id, true)
		_spawn_wave(space, 0)


## Whether walking into this space starts a fight.
##
## Driven by the data, not the kind: the guide gives the Arrival Path three Rift
## Crawlers (§9, "movement, camera, Focus Weapon, and first summon") and they were
## in the balance file all along — but the old kind == COMBAT test meant a TRAVEL
## space could never spawn them. Two kinds stay excluded on purpose:
##   BOSS — the First Bell is built and tested but not yet chained into this run,
##          and spawning it as a plain wave would skip its arena, gate and phases.
##   RIFT — guide §10 makes the Rift a timed protect-the-core event with an entry
##          cost (RiftEvent), not a walk-in fight; wiring its waves here would
##          ship a redesign of a locked decision.
func _runs_encounter(space: WardLayout.Space) -> bool:
	if space.kind == WardLayout.Kind.BOSS or space.kind == WardLayout.Kind.RIFT:
		return false
	return _wave_count(space.id) > 0


## Wave contents come from the balance file, never from here.
func _spawn_wave(space: WardLayout.Space, index: int) -> void:
	var wave := _wave_for(space.id, index)
	if wave.is_empty():
		return

	# Placement counter, distinct from the wave `index` parameter.
	var slot := 0
	var count := 0
	for entry in wave:
		var enemy_id: StringName = entry[0]
		var how_many: int = entry[1]
		var data := load("res://data/enemies/%s.tres" % enemy_id) as EnemyData
		if data == null:
			push_warning("playable: no enemy data for '%s'" % enemy_id)
			continue
		for _i in how_many:
			var enemy := ENEMY.instantiate() as EnemyBase
			enemy.data = data
			add_child(enemy)
			# A ring inside the room, away from the doorway the hero came through.
			var angle := TAU * float(slot) / 8.0
			var radius := space.size.x * 0.28
			enemy.global_position = space.centre + Vector3(
				cos(angle) * radius, 0.0, sin(angle) * radius)
			enemy.target = hero
			# Which fight this enemy belongs to. Wave advancement counts only its
			# own space's survivors, so an arrival straggler wandering in can
			# never stall Combat A's next wave.
			enemy.set_meta(&"encounter_space", space.id)
			presentation.bind_enemy(enemy)
			enemies.append(enemy)
			slot += 1
			count += 1

	_spawned_total += count
	_deepest_wave[space.id] = maxi(int(_deepest_wave.get(space.id, 0)), index)
	presentation.audio.play_music(&"music_sunfall_combat")
	print("[play] %s wave %d/%d: %d enemies" % [
		space.label, index + 1, _wave_count(space.id), count])


## Wave `index` of the encounter with this id, as [[enemy_id, count], ...].
##
## LEVEL1_BALANCE.json stores a wave as a flat alternating list — id, count, id,
## count — so it is unpacked here rather than assumed to be pairs.
##
## This used to read waves[0] and nothing else, which quietly discarded most of
## every fight: combat_a has two waves of six, combat_b has three totalling
## twelve. The owner asked for "more mobs" and the mobs were already in the
## balance file, unspawned.
func _wave_for(id: StringName, index: int) -> Array:
	var waves := _waves_for(id)
	if index < 0 or index >= waves.size():
		return []
	var flat: Array = waves[index]
	var out: Array = []
	var i := 0
	while i + 1 < flat.size():
		out.append([StringName(flat[i]), int(flat[i + 1])])
		i += 2
	return out


func _waves_for(id: StringName) -> Array:
	for entry in Balance.data().get("encounters", []):
		var block: Dictionary = entry
		if StringName(block.get("id", "")) == id:
			return block.get("waves", [])
	return []


func _wave_count(id: StringName) -> int:
	return _waves_for(id).size()


## Total enemies an encounter will spawn across every wave. Used by the checks so
## they assert against the balance file rather than against one wave of it.
## Deepest wave index this space has spawned, or -1 if it never started.
func deepest_wave_reached(id: StringName) -> int:
	return int(_deepest_wave.get(id, -1))


func total_enemies_for(id: StringName) -> int:
	var total := 0
	for flat in _waves_for(id):
		var i := 1
		while i < (flat as Array).size():
			total += int((flat as Array)[i])
			i += 2
	return total


## Dead enemies leave the list, and clearing a room puts the music back. Phase 15
## asserts no growing node count across room clears, and this is the room-clear
## half of keeping that true.
func _prune_enemies() -> void:
	var before := enemies.size()
	var alive: Array[EnemyBase] = []
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			alive.append(e)
		elif is_instance_valid(e):
			convergence.on_kill()
			e.queue_free()
	enemies = alive
	if before > 0 and enemies.is_empty():
		# Only call it a clear when there is no next wave queued, or every gap
		# between waves announces a room clear that has not happened.
		var more := _active_space != &"" \
			and _wave_count(_active_space) - (_wave_index + 1) > 0
		if not more:
			presentation.audio.play_music(&"music_sunfall_explore")
			print("[play] room clear")


## Camera distance is adjustable at runtime, and prints what it lands on.
##
## The framing has now been guessed at three times — 26.5 m, 20.5 m, 16.0 m — each
## time from a description ("zoomed out", "he's a little small") rather than a
## number, because a number is not a thing anyone can be expected to supply by
## eye. So the dial is in the build: mouse wheel, or - and =. It prints the value,
## which makes the next conversation about a number instead of an adjective.
const CAMERA_MIN := 10.0
const CAMERA_MAX := 32.0
const CAMERA_STEP := 1.0


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	var delta := 0.0
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			delta = -CAMERA_STEP
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			delta = CAMERA_STEP
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_MINUS:
			delta = CAMERA_STEP
		elif key.keycode == KEY_EQUAL:
			delta = -CAMERA_STEP

	if is_zero_approx(delta):
		return
	var want := clampf(camera.framing() + delta, CAMERA_MIN, CAMERA_MAX)
	camera.set_framing(want)
	# The px figure is the one that matters — the guide's floor is 88 px.
	var visible_height := 2.0 * want * tan(deg_to_rad(camera.fov * 0.5))
	print("[camera] distance %.1f m   hero reads at %.0f px   (tell Claude this number)"
		% [want, 1.8 / visible_height * 1080.0])


func _handle_input() -> void:
	# Convergence is the one thing with no automatic trigger — guide §8 makes it a
	# spend, so it needs a button. Everything else the hero and summons do already.
	if InputMap.has_action("convergence") and Input.is_action_just_pressed("convergence"):
		if convergence.is_full():
			convergence.trigger(run.bonded_ids())

	if InputMap.has_action("rally") and Input.is_action_just_pressed("rally"):
		var nearest := _nearest_enemy()
		if nearest != null:
			rally.mark(nearest)
			for s in summons:
				s.set_rally_target(nearest)


## The stage is clear when every COMBAT space on the critical path is clear.
##
## The Rift is deliberately excluded — WardLayout.critical_path() leaves it out,
## and guide §10 makes it an optional detour. Requiring it would turn an optional
## room into a mandatory one, which is a design change, not a completion rule.
func _check_level_cleared() -> void:
	if _level_done:
		return
	var required := required_encounters()
	for id in required:
		if not _cleared.has(id):
			return
	_level_done = true
	presentation.audio.play_music(&"music_sunfall_explore")
	presentation.audio.play(&"evolve")
	print("[play] STAGE CLEAR — %d encounters in %.1fs" % [required.size(), _elapsed])
	level_cleared.emit(_elapsed)


## Combat spaces on the critical path, in route order. Read from WardLayout rather
## than listed, so moving a room in the layout moves the win condition with it.
func required_encounters() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WardLayout.critical_path():
		var space := WardLayout.space(id)
		if space != null and space.kind == WardLayout.Kind.COMBAT:
			out.append(id)
	return out


func cleared_encounters() -> Array:
	var out: Array = _cleared.keys()
	out.sort()
	return out


func is_level_cleared() -> bool:
	return _level_done


func elapsed_seconds() -> float:
	return _elapsed


## Seals or opens a combat room's doorways. Rooms without gates (the arrival
## path) are a no-op, which is the point of asking the ward instead of assuming.
func _set_gates_locked(space_id: StringName, value: bool) -> void:
	if ward == null:
		return
	var gates: GateController = ward.combat_gates(space_id)
	if gates != null:
		gates.set_locked(value)


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive():
			continue
		var d := hero.global_position.distance_to(e.global_position)
		if d < best_distance:
			best_distance = d
			best = e
	return best


func _on_hero_damaged(amount: int) -> void:
	presentation.audio.play(&"hero_hurt")
	# Guide §12: Stability is the run-level resource the hero's health feeds.
	run.adjust_stability(-maxi(1, amount / 10))


# -------------------------------------------------------------------- reporting

func _report() -> void:
	print("\n[play] Sunfall Ward — playable build")
	print("[play] hero at %s, %d summons bonded" % [hero.position, summons.size()])
	print("[play] %d audio slots, %d effects" % [
		presentation.audio.slot_count(), presentation.vfx.effect_ids().size()])
	var missing := AssetCheck.report()
	if missing != "":
		print(missing)
	print("[play] WASD move  ·  Space dash  ·  hold to fire  ·  F3 debug  ·  Esc pause")
	print("[play] walk east into Combat Zone A to start a fight\n")


## Living enemies, optionally only those belonging to one encounter space.
func enemies_alive(space_id: StringName = &"") -> int:
	var n := 0
	for e in enemies:
		if not is_instance_valid(e) or not e.is_alive():
			continue
		if space_id != &"" and e.get_meta(&"encounter_space", &"") != space_id:
			continue
		n += 1
	return n


func spawned_total() -> int:
	return _spawned_total
