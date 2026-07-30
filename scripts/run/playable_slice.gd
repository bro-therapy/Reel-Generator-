extends Node3D

## The playable build. This is what F5 runs.
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

var hero: Node3D
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


func _ready() -> void:
	if Engine.has_singleton("SceneFlow"):
		SceneFlow.set_state(SceneFlow.State.RUN)

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
	if Engine.has_singleton("GameSettings"):
		quality.settings_source = GameSettings
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

	var ward := Node3D.new()
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
	_check_combat_triggers()
	_prune_enemies()
	_handle_input()
	if camera != null:
		camera.tick(delta)


## Walking into a combat space starts its fight. A stand-in for
## EncounterController's gate-and-wave flow, which is built and tested but not yet
## chained room to room — the difference is that this does not lock you in or hand
## out a reward when the room clears.
func _check_combat_triggers() -> void:
	if hero == null or not hero.is_inside_tree():
		return
	for space in WardLayout.spaces():
		if space.kind != WardLayout.Kind.COMBAT:
			continue
		if _triggered.has(space.id):
			continue
		if hero.global_position.distance_to(space.centre) > TRIGGER_RADIUS:
			continue
		_triggered[space.id] = true
		_spawn_wave(space)


## Wave contents come from the balance file, never from here.
func _spawn_wave(space: WardLayout.Space) -> void:
	var wave := _first_wave_for(space.id)
	if wave.is_empty():
		push_warning("playable: no wave data for '%s'" % space.id)
		return

	var index := 0
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
			var angle := TAU * float(index) / 8.0
			var radius := space.size.x * 0.28
			enemy.global_position = space.centre + Vector3(
				cos(angle) * radius, 0.0, sin(angle) * radius)
			enemy.target = hero
			presentation.bind_enemy(enemy)
			enemies.append(enemy)
			index += 1
			count += 1

	_spawned_total += count
	presentation.audio.play_music(&"music_sunfall_combat")
	print("[play] %s: %d enemies" % [space.label, count])


## First wave of the encounter with this id, as [[enemy_id, count], ...].
##
## LEVEL1_BALANCE.json stores a wave as a flat alternating list — id, count, id,
## count — so it is unpacked here rather than assumed to be pairs.
func _first_wave_for(id: StringName) -> Array:
	for entry in Balance.data().get("encounters", []):
		var block: Dictionary = entry
		if StringName(block.get("id", "")) != id:
			continue
		var waves: Array = block.get("waves", [])
		if waves.is_empty():
			return []
		var flat: Array = waves[0]
		var out: Array = []
		var i := 0
		while i + 1 < flat.size():
			out.append([StringName(flat[i]), int(flat[i + 1])])
			i += 2
		return out
	return []


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
		presentation.audio.play_music(&"music_sunfall_explore")
		print("[play] room clear")


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


func enemies_alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			n += 1
	return n


func spawned_total() -> int:
	return _spawned_total
