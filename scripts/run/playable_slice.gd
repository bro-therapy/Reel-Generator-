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
## Progression (owner-requested; docs/PROGRESSION_DESIGN.md).
signal summon_unlocked(spirit_id: StringName, level: int)
signal level_up_opened(level: int, offer: Array)
## The spirit-bonding page. Separate from level_up_opened because the two carry
## different id namespaces — spirit ids here, upgrade ids there.
signal summon_choice_opened(level: int, offer: Array)
signal room_entered(space_id: StringName)
signal boss_door_refused(reason: String)
signal boss_engaged(max_hp: int)
signal rooms_cleared(count: int, seconds: float)
signal room_refought(space_id: StringName, times: int)

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

## Progression. Summons are NOT bonded at the start any more — the owner asked
## to begin with the Focus Weapon alone and earn the team, so STARTING_SPIRITS
## is now an unlock ORDER rather than a starting roster.
var upgrades: UpgradeEffects
var catalog: UpgradeCatalog
var level_up_screen: LevelUpScreen
var _orbs: Array[ExperienceOrb] = []
var _pending_levels := 0
## Spirit slots the player has earned and not yet filled.
var _pending_summon_picks := 0
var _unlocked: Array[StringName] = []
var _boss_warned := false
var boss: FirstBellBoss
var _rooms_announced := false
var _reentry_armed: Dictionary = {}
var _reclears: Dictionary = {}


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

	_build_progression()
	presentation.audio.play_music(&"music_sunfall_explore")
	_report()


## Experience orbs, upgrade rolling, and the level-up screen.
const ORB_POOL_SIZE := 48

func _build_progression() -> void:
	upgrades = UpgradeEffects.new()
	catalog = UpgradeCatalog.new()

	var orbs := Node3D.new()
	orbs.name = "Orbs"
	add_child(orbs)
	for i in ORB_POOL_SIZE:
		var orb := ExperienceOrb.new()
		orb.name = "Orb%d" % i
		orbs.add_child(orb)
		orb.collected.connect(_on_orb_collected)
		_orbs.append(orb)

	level_up_screen = LevelUpScreen.new()
	level_up_screen.name = "LevelUp"
	level_up_screen.visible = false
	level_up_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(level_up_screen)
	level_up_screen.chosen.connect(_on_upgrade_chosen)

	run.levelled_up.connect(_on_levelled_up)


func _drop_orb(at: Vector3, xp: int) -> bool:
	for orb in _orbs:
		if not orb.is_active():
			orb.drop(at, xp)
			return true
	# Pool exhausted. Award the experience anyway rather than silently losing a
	# kill's worth of progress — a missing pickup is cosmetic, missing XP is not.
	run.gain_experience(xp)
	return false


func _on_orb_collected(_orb: ExperienceOrb, amount: int) -> void:
	run.gain_experience(amount)
	presentation.audio.play_at(&"pickup", hero.global_position)


## One screen per level gained, queued: a kill worth three levels owes three
## choices, and showing them at once would collapse into one.
func _on_levelled_up(level: int) -> void:
	_pending_levels += 1
	_apply_summon_unlocks()
	if not level_up_screen.visible:
		_show_next_choice(level)


func _show_level_up(level: int) -> void:
	var offer := catalog.roll_offer(_unlocked, upgrades.taken())
	level_up_screen.visible = true
	level_up_screen.open(level, offer)
	get_tree().paused = true
	level_up_opened.emit(level, offer)


## Bonding comes before upgrading.
##
## A level that opens a spirit slot usually also owes an upgrade choice, and
## offering the upgrades first means picking from a list that does not yet
## include the spirit the same level just granted.
func _show_next_choice(level: int) -> void:
	if _pending_summon_picks > 0:
		var offer := bondable_spirits()
		if offer.is_empty():
			# Every species already bonded. Drop the debt rather than opening a
			# screen with nothing on it.
			_pending_summon_picks = 0
		else:
			level_up_screen.visible = true
			level_up_screen.open_summon_choice(level, offer)
			get_tree().paused = true
			summon_choice_opened.emit(level, offer)
			return
	if _pending_levels > 0:
		_show_level_up(level)
		return
	level_up_screen.visible = false
	get_tree().paused = false


func _on_upgrade_chosen(chosen_id: StringName) -> void:
	# One handler for both pages: the screen knows which one it was showing, and
	# a second signal would be a second thing to keep in step.
	if level_up_screen.mode() == LevelUpScreen.Mode.SUMMON:
		if chosen_id != &"":
			unlock_summon(chosen_id)
		_pending_summon_picks = maxi(0, _pending_summon_picks - 1)
	else:
		if chosen_id != &"":
			upgrades.take(chosen_id)
		_pending_levels = maxi(0, _pending_levels - 1)
	_show_next_choice(run.level)


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


## No summons at the start. The owner's call: "right off the gate I shouldn't
## have all three summons — I should start off with just a basic shot, then once
## I reach a certain level I can get the dog". This conflicts with guide §5
## ("the starting team is one of each species"); the owner overrides the guide,
## and the amendment is recorded in docs/PROGRESSION_DESIGN.md.
func _build_summons() -> void:
	pass


## Bonds a spirit mid-run and puts it in the world. Idempotent: a second unlock
## of the same species is ignored rather than spawning a duplicate.
func unlock_summon(spirit_id: StringName) -> bool:
	if _unlocked.has(spirit_id):
		return false
	var path := "res://data/spirits/%s.tres" % spirit_id
	var spirit := load(path) as SpiritData
	if spirit == null:
		push_warning("playable: cannot load %s" % path)
		return false

	_unlocked.append(spirit_id)
	run.bond(spirit)

	var s := SUMMON.instantiate() as SummonBase
	s.name = String(spirit.id)
	s.data = spirit
	s.hero = hero
	add_child(s)
	s.snap_to_lane()
	summons.append(s)
	# Without this the spirit fights silently and invisibly: damage is applied
	# straight through CombatDamage, so a Gun Construct "burst" was pure
	# bookkeeping. Binding here rather than in _build_presentation because
	# summons arrive mid-run, one level-up at a time.
	presentation.bind_summon(s)

	presentation.play_signature(spirit_id)
	summon_unlocked.emit(spirit_id, run.level)
	print("[play] unlocked %s at level %d" % [spirit_id, run.level])
	return true


## The levels at which a spirit slot opens, ascending.
##
## The balance file lists a level per species. It is read here as "the Nth slot
## opens at the Nth level", NOT as "this species arrives at this level" — the
## owner asked to choose: "There should be a page where you can pick which
## upgrade you want. If you want the wolf or the robot or the sword." The pacing
## is untouched; only who fills each slot moved from the data to the player.
func summon_unlock_levels() -> Array:
	var thresholds: Dictionary = Balance.progression().get("summon_unlock_levels", {})
	var levels: Array = []
	for spirit_id in thresholds:
		levels.append(int(thresholds[spirit_id]))
	levels.sort()
	return levels


## How many spirits the current level entitles the player to hold.
func entitled_summon_count() -> int:
	var n := 0
	for level in summon_unlock_levels():
		if run.level >= int(level):
			n += 1
	return n


## Species that exist and are not bonded yet.
func bondable_spirits() -> Array:
	var out: Array = []
	for spirit_id in Balance.progression().get("summon_unlock_levels", {}).keys():
		var id := StringName(spirit_id)
		if not _unlocked.has(id) and ResourceLoader.exists("res://data/spirits/%s.tres" % id):
			out.append(id)
	out.sort()
	return out


## Queues a bonding choice for every slot the level has opened and not filled.
## Queued rather than granted — the screen is what actually bonds the spirit.
func _apply_summon_unlocks() -> void:
	var owed := entitled_summon_count() - _unlocked.size()
	if owed > 0:
		_pending_summon_picks += owed


## Fills every open slot without asking, in the species order the balance file
## happens to list. For headless runs and for tests that need a coherent team at
## a given level without driving the UI — never called during play.
func grant_entitled_summons() -> void:
	for id in bondable_spirits():
		if _unlocked.size() >= entitled_summon_count():
			break
		unlock_summon(id)
	_pending_summon_picks = 0


func _build_presentation() -> void:
	presentation = CombatPresentation.new()
	presentation.name = "Presentation"
	add_child(presentation)
	presentation.bind_convergence(convergence)
	presentation.bind_hero(hero as Player)


func _build_hud() -> void:
	hud = CombatHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(run, convergence, rally)
	hud.set_health(hero.hp, hero.data.max_hp if hero.data != null else hero.hp)
	hero.health_changed.connect(hud.set_health)
	# Experience is event-driven like everything else on the HUD — nothing polls.
	hud.set_experience(run.level, run.experience, run.experience_to_next)
	run.experience_gained.connect(
		func(_amount: int, _total: int) -> void:
			hud.set_experience(run.level, run.experience, run.experience_to_next))
	run.levelled_up.connect(
		func(_level: int) -> void:
			hud.set_experience(run.level, run.experience, run.experience_to_next))
	# Stability is not connected here: hud.bind() already subscribes to it, and
	# connecting again makes Godot log a duplicate-connection error every boot.


func _build_pause() -> void:
	pause = PauseController.new()
	pause.name = "Pause"
	add_child(pause)


# -------------------------------------------------------------------- combat

func _process(delta: float) -> void:
	_elapsed += delta
	_check_room_reentry()
	_check_combat_triggers()
	_check_boss_trigger()
	_prune_enemies()
	_advance_waves(delta)
	_handle_input()
	if camera != null:
		camera.tick(delta)


## Puts The First Bell in its room. Built and acceptance-tested since Phase 11
## and never actually placed in the world — walking to the far room found an
## empty arena, which is exactly what the playtest reported.
func _spawn_boss(space: WardLayout.Space) -> void:
	if boss != null and is_instance_valid(boss):
		return
	boss = FirstBellBoss.new()
	boss.name = "FirstBell"
	add_child(boss)
	boss.global_position = space.centre
	# Escalation reaches the boss too, but through its own health rather than
	# the per-instance path the mob spawner uses.
	var boss_mult := float(Balance.progression().get("boss_health_multiplier", 1.0))
	boss.max_hp = maxi(1, int(round(float(boss.max_hp) * difficulty_scale() * boss_mult)))
	boss.hp = boss.max_hp

	presentation.bind_boss(boss)
	boss.defeated.connect(_on_boss_defeated)
	presentation.audio.play_music(&"music_first_bell")
	boss_engaged.emit(boss.max_hp)
	print("[play] The First Bell awakens — %d hp" % boss.max_hp)


func _on_boss_defeated() -> void:
	print("[play] The First Bell falls")
	presentation.audio.play_music(&"music_sunfall_explore")
	_cleared[&"boss"] = true
	_level_done = true
	level_cleared.emit(_elapsed)


## How much tougher enemies are right now, from elapsed run time.
##
## The owner asked that "it should increase in difficulty the longer it takes
## you to clear out all the mobs, but don't make it way too difficult" — so this
## is a slow drift with a hard ceiling, both from the balance file. At the
## shipped 8%/minute and 1.5x cap, a brisk 8-minute run ends around 1.5x while a
## player who dawdles for twenty minutes still faces 1.5x, never 2.6x.
##
## Applied to health only, never to damage. Tougher enemies lengthen a fight;
## harder-hitting ones kill a player who was doing fine a minute ago, which is
## the "way too difficult" the owner explicitly ruled out.
func difficulty_scale() -> float:
	var prog := Balance.progression()
	var per_minute := float(prog.get("escalation_per_minute", 0.08))
	var cap := float(prog.get("escalation_cap", 1.5))
	return minf(1.0 + (_elapsed / 60.0) * per_minute, cap)


## Both conditions for the boss door: every other combat room cleared, AND the
## level threshold met. The owner asked for both — "you can't go to the boss
## room until you defeat all the other rooms" and "make a leveling system to
## where the character has to be a certain level before you can reach the boss
## room, so you have to revisit some of the rooms to level up".
func boss_is_unlocked() -> bool:
	return combat_rooms_cleared() and run.level >= boss_required_level()


## How many times each combat room must be cleared. The owner asked that "you
## shouldn't be able to enter the boss room until all the other rooms are
## cleared at least maybe twice" — one pass through the ward is no longer enough.
func boss_required_clears() -> int:
	return maxi(1, int(Balance.progression().get("boss_required_clears", 1)))


## Times a given room has been cleared, first clear included.
func clears_of(space_id: StringName) -> int:
	if not _cleared.has(space_id):
		return 0
	return 1 + int(_reclears.get(space_id, 0))


func boss_required_level() -> int:
	return int(Balance.progression().get("boss_required_level", 7))


## Every COMBAT space on the critical path, cleared. The boss room is a BOSS
## space and is deliberately not counted among them.
func combat_rooms_cleared() -> bool:
	for id in required_encounters():
		if clears_of(id) < boss_required_clears():
			return false
	return true


## Why the door did not open, said once rather than every frame the player
## stands in it.
func _warn_boss_locked() -> void:
	if _boss_warned:
		return
	_boss_warned = true
	var reason := ""
	if not combat_rooms_cleared():
		var need := boss_required_clears()
		var parts: Array[String] = []
		for id in required_encounters():
			parts.append("%s %d/%d" % [id, clears_of(id), need])
		reason = "clear every combat room %d times (%s)" % [need, ", ".join(parts)]
	else:
		reason = "reach level %d (currently %d)" % [boss_required_level(), run.level]
	print("[play] the boss door is sealed — %s" % reason)
	boss_door_refused.emit(reason)
	presentation.audio.play_at(&"gate", hero.global_position)


## A pulse of light on entry, then the fight. Uses the room's own lantern colour
## so it reads as the ward waking up rather than as a UI overlay.
func _flash_room(space: WardLayout.Space) -> void:
	var flash := OmniLight3D.new()
	flash.position = space.centre + Vector3(0.0, 3.0, 0.0)
	flash.light_color = Color(1.0, 0.78, 0.45)
	flash.omni_range = maxf(space.size.x, space.size.y) * 0.9
	flash.shadow_enabled = false
	flash.light_energy = 0.0
	add_child(flash)

	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 4.5, 0.18)
	tween.tween_property(flash, "light_energy", 0.0, 0.85)
	tween.tween_callback(flash.queue_free)
	presentation.audio.play_at(&"gate", space.centre)
	room_entered.emit(space.id)


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
## The boss room's own trigger, deliberately separate from the wave trigger.
##
## `_runs_encounter()` excludes BOSS on purpose — walking in must never start a
## mob wave, and a check pins that. So the boss arrives through its own path
## rather than by loosening a rule that is doing its job.
func _check_boss_trigger() -> void:
	if hero == null or not hero.is_inside_tree():
		return
	if boss != null and is_instance_valid(boss):
		return
	var arena := WardLayout.space(&"boss")
	if arena == null or _triggered.has(arena.id):
		return
	if hero.global_position.distance_to(arena.centre) > TRIGGER_RADIUS:
		return
	if not boss_is_unlocked():
		_warn_boss_locked()
		return
	_triggered[arena.id] = true
	_flash_room(arena)
	_spawn_boss(arena)


## Lets a cleared combat room be fought again.
##
## The owner asked for this directly: "you have to revisit some of the rooms a
## couple times and kill mobs to level up to get into the room". Without it a
## room clears exactly once and the only way to gain levels is to walk forward,
## so a player short of the boss threshold would have no way to earn the
## difference.
##
## A re-entered room runs its LAST wave — the hardest one it declares — rather
## than the whole sequence again. Repeating a four-wave encounter from the top
## to farm one level is tedious, and the last wave is where the interesting
## enemies are. Time escalation applies as usual, so a late re-clear is worth
## the same experience against tougher enemies.
##
## `_cleared` is deliberately NOT unset: the room stays cleared for the boss
## gate. Re-fighting is for experience, and un-clearing a room would let the
## player accidentally lock themselves back out of the boss door.
const REENTRY_RADIUS_MULTIPLE := 1.8

func _check_room_reentry() -> void:
	if hero == null or not hero.is_inside_tree():
		return
	if _active_space != &"":
		return
	for id in _cleared.keys():
		var space := WardLayout.space(id)
		if space == null or space.kind != WardLayout.Kind.COMBAT:
			continue
		var distance := hero.global_position.distance_to(space.centre)
		# Hysteresis: the exit radius is wider than the entry radius, so
		# standing on the boundary cannot flicker a room open and shut.
		if distance > TRIGGER_RADIUS * REENTRY_RADIUS_MULTIPLE:
			if _triggered.has(id):
				_triggered.erase(id)
				_reentry_armed[id] = true


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
		# A room being fought again starts at its LAST wave; a first visit runs
		# the whole sequence.
		var repeat: bool = _reentry_armed.get(space.id, false)
		_wave_index = (_wave_count(space.id) - 1) if repeat else 0
		if repeat:
			_reentry_armed.erase(space.id)
			_reclears[space.id] = int(_reclears.get(space.id, 0)) + 1
			room_refought.emit(space.id, int(_reclears[space.id]))
		encounter_started.emit(space.id, _wave_count(space.id))
		_set_gates_locked(space.id, true)
		_spawn_wave(space, _wave_index)


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
## Every room with a declared encounter fights when you walk into it.
##
## The owner asked that "every room that you go into should have mobs". Only the
## boss room is excluded, and only because it has its own trigger — walking in
## must summon The First Bell, not a mob wave.
##
## The Rift used to be excluded too, which made an OPTIONAL room an EMPTY one:
## its encounter was declared in the balance file and never spawned. Optional
## means you need not go, not that there is nothing there when you do. It is
## still off the critical path, so it is still skippable and still not required
## by the boss gate.
func _runs_encounter(space: WardLayout.Space) -> bool:
	if space.kind == WardLayout.Kind.BOSS:
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
			# Escalation is applied to the INSTANCE, never to `data` — that is a
			# shared .tres, and scaling it would compound across every later
			# spawn and leak into the next run.
			enemy.health_scale = difficulty_scale()
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
			enemy.died.connect(_on_enemy_died)
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


## How many enemies one specific wave of a space declares.
func wave_size_for(id: StringName, index: int) -> int:
	var total := 0
	for entry in _wave_for(id, index):
		total += int(entry[1])
	return total


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
## An enemy that died leaves its experience where it fell. Worth is derived
## from its own threat weight, so a new species is worth the right amount the
## moment it exists.
func _on_enemy_died(enemy: EnemyBase) -> void:
	if enemy == null:
		return
	var threat := 1
	if enemy.data != null:
		threat = enemy.data.threat_weight
	_drop_orb(enemy.global_position, RunState.experience_for_threat(threat))


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
	# Clearing every combat room opens the boss door; it does not end the run.
	# The run ends when The First Bell falls.
	if not _rooms_announced:
		_rooms_announced = true
		presentation.audio.play(&"evolve")
		print("[play] every combat room cleared — the boss door is open at level %d"
			% boss_required_level())
		rooms_cleared.emit(required.size(), _elapsed)


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
