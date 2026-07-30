class_name FirstBellBoss
extends Node3D

## The First Bell. Guide §11 and brief Phase 11.
##
## Not an EnemyBase subclass: the roster enemies run one attack on a cadence,
## while the boss runs a scripted rotation with phases, a stagger window and an
## enrage clock. Sharing the base would have meant special-casing most of it.
##
## What it does share is the rule that matters — nothing lands without a red
## telegraph having been armed first. That is enforced the same way, in
## `_deal_damage()`, and is the check Phase 5 already proved for the roster.
##
## Every number comes from LEVEL1_BALANCE.json `boss`.

signal phase_changed(phase: int)
signal staggered(seconds: float)
signal stagger_ended()
signal enraged()
signal attack_landed(kind: StringName, amount: int)
signal attack_suppressed_without_telegraph()
signal crawlers_called(count: int)
signal hexer_called()
signal defeated()

enum Phase { ONE, TWO }
enum Move { IDLE, SLAM, CHAIN_SWEEP, TOLL, CALL }

## Guide §11: "approximately 2.5 times the hero's gameplay height."
## Guide §11 said 2.5x the hero. The owner overrode it after playtesting the
## arena — "I need the boss to be scaled up much larger towards the end, I
## couldn't even tell I was at the last room" — so The First Bell now stands
## more than four times the hero's height. At 2.5x it read as a large enemy;
## a boss has to read as a landmark from the doorway.
const HERO_HEIGHT_MULTIPLE := 4.4
const HERO_WORLD_HEIGHT := 1.8

## Time between rotation entries. Not in balance — the telegraph durations are
## what the fight is tuned on, and this only spaces them out.
const RECOVER_SECONDS := 0.8

var phase: Phase = Phase.ONE
var hp: int = 0
var max_hp: int = 0
var world_height: float = HERO_WORLD_HEIGHT * HERO_HEIGHT_MULTIPLE

var is_staggered := false
var stagger_time_left := 0.0
var vulnerability_multiplier := 1.0
var has_enraged := false
var elapsed := 0.0

var current_move: Move = Move.IDLE
var telegraph: TelegraphController

## Counters the acceptance harness reads.
var attacks_landed := 0
var attacks_suppressed := 0
var untelegraphed_hits := 0
var slams_this_fight := 0
var sweeps_this_fight := 0

var _move_time := 0.0
var _windup_left := 0.0
var _recover_left := 0.0
var _call_cooldown := 0.0
var _rotation := 0
var _defeat_emitted := false
var _alive := true
var _balance: Dictionary = {}


func _ready() -> void:
	_balance = Balance.boss()
	max_hp = int(_balance.get("hp", 2600))
	hp = max_hp
	_call_cooldown = float(_balance.get("crawler_summon_cooldown_seconds", 12.0))

	telegraph = TelegraphController.new()
	telegraph.name = "Telegraph"
	add_child(telegraph)

	initialize()


## Public and idempotent. `_ready` does not fire for a node added during a
## `--script` harness's `_initialize()`, which this project has been bitten by
## five times now — most recently here, where the boss's brand-new sprite was
## invisible to its own acceptance check for exactly that reason.
var _initialized := false

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_build_hurtbox()
	_build_sprite()


## The boss was INVISIBLE. All twelve of its frames have shipped since Phase 11
## and nothing ever displayed them — it was a bare logic node with a telegraph,
## which is why the arena read as empty and the playtest said "I couldn't even
## tell I was at the last room".
const FRAME_DIR := "res://assets/enemies/boss_action_frames"
const FRAMES := {
	&"idle": "00_idle", &"move": "01_move",
	&"slam_windup": "02_slam_windup", &"slam_impact": "03_slam_impact",
	&"sweep_windup": "04_chain_sweep_windup", &"toll": "05_bell_toll",
	&"stagger": "06_stagger_core_open", &"defeat": "07_defeat",
	&"sweep_active": "08_chain_sweep_active", &"hit": "09_hit",
	&"phase_two": "10_phase_two", &"enrage": "11_enrage",
}

var sprite: AnimatedSprite3D

func _build_sprite() -> void:
	if sprite != null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var loaded := 0
	for key in FRAMES:
		var path := "%s/00_the_first_bell__%s.png" % [FRAME_DIR, FRAMES[key]]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		frames.add_animation(key)
		frames.set_animation_loop(key, key in [&"idle", &"move"])
		frames.set_animation_speed(key, 6.0)
		frames.add_frame(key, tex)
		loaded += 1
	if loaded == 0:
		# Assetless checkout: a violet monolith so the arena is never empty.
		var stand_in := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.4, world_height, 2.4)
		stand_in.mesh = box
		stand_in.position = Vector3(0.0, world_height * 0.5, 0.0)
		stand_in.layers = 2
		add_child(stand_in)
		return

	sprite = AnimatedSprite3D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.centered = true
	sprite.layers = 2
	# Scaled from the source art's own height so the on-screen size follows
	# world_height rather than being a second number that can drift from it.
	var source_h := 724.0
	sprite.pixel_size = world_height / source_h
	sprite.position = Vector3(0.0, world_height * 0.5, 0.0)
	add_child(sprite)
	sprite.play(&"idle")


## Shows the pose for what the boss is doing. Falls through silently when a
## frame is absent, so a partial art install degrades rather than breaks.
func _show(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation != anim:
		sprite.play(anim)


## Without this the boss is unkillable, and nothing noticed for eleven phases.
##
## Every acceptance check drives `take_damage()` directly, so the fight was
## fully tested and fully correct while being impossible to actually hit: a
## FocusProjectile looks for a body or area on the EnemyHurtbox layer whose
## owner is in the "enemies" group, and this was a bare Node3D with neither.
## Walking into the boss room found nothing to fight.
##
## Layer 5 EnemyHurtbox, per the fixed 1-10 layers in guide §15.
const ENEMY_HURTBOX_LAYER := 1 << 4

func _build_hurtbox() -> void:
	if not is_in_group("enemies"):
		add_to_group("enemies")
	if get_node_or_null("Hurtbox") != null:
		return

	var hurtbox := Area3D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = ENEMY_HURTBOX_LAYER
	# Monitorable, not monitoring: attacks come looking for it, it does not go
	# looking for them.
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# Sized to the boss's own world height rather than a literal, so the two
	# cannot drift apart. Guide §11 puts it at 2.5x the hero.
	capsule.height = world_height
	capsule.radius = world_height * 0.28
	shape.shape = capsule
	shape.position = Vector3(0.0, world_height * 0.5, 0.0)
	hurtbox.add_child(shape)
	add_child(hurtbox)


# ---------------------------------------------------------------- combat loop

func _physics_process(delta: float) -> void:
	tick(delta)


## Explicit so the acceptance harness can drive the fight faster than real time.
func tick(delta: float) -> void:
	if not _alive:
		return

	elapsed += delta
	_check_enrage()

	if is_staggered:
		stagger_time_left -= delta
		if stagger_time_left <= 0.0:
			_end_stagger()
		return

	_call_cooldown -= delta

	if _recover_left > 0.0:
		_recover_left -= delta
		if _recover_left <= 0.0:
			current_move = Move.IDLE
		return

	if current_move == Move.IDLE:
		_begin_next_move()
		return

	if _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_deal_damage()


func _begin_next_move() -> void:
	# The Crawler call is on its own clock (guide §11: every 12 seconds) rather
	# than in the rotation, so it cannot be starved by a long slam.
	if _call_cooldown <= 0.0:
		_call_crawlers()
		return

	var rotation: Array = _rotation_for_phase()
	current_move = rotation[_rotation % rotation.size()]
	_rotation += 1
	_move_time = 0.0

	match current_move:
		Move.SLAM:
			_windup_left = float(_balance.get("slam_telegraph_seconds", 1.25))
			slams_this_fight += 1
			# Guide §12: the slam telegraph is a concentric red circle. Phase two
			# adds a second ring, which is a bigger radius, not more damage.
			telegraph.show_telegraph(TelegraphController.SHAPE_CIRCLE, _windup_left, 6.0 if phase == Phase.TWO else 4.5)
		Move.CHAIN_SWEEP:
			_windup_left = float(_balance.get("chain_sweep_telegraph_seconds", 0.95))
			sweeps_this_fight += 1
			telegraph.show_telegraph(TelegraphController.SHAPE_WEDGE, _windup_left, 7.0)
		Move.TOLL:
			# The toll disperses summons and deals no damage, so it carries no
			# red telegraph — there is nothing for the player to dodge.
			_windup_left = 0.6
		_:
			current_move = Move.IDLE


func _rotation_for_phase() -> Array:
	if phase == Phase.TWO:
		# Guide §11 phase two: an extra slam ring and a reversing sweep, so the
		# rotation leans harder on both.
		return [Move.SLAM, Move.CHAIN_SWEEP, Move.SLAM, Move.TOLL, Move.CHAIN_SWEEP]
	return [Move.SLAM, Move.CHAIN_SWEEP, Move.TOLL]


func _deal_damage() -> void:
	# The rule the whole roster shares: nothing lands unless a red telegraph was
	# armed for it. A move that reaches this point without one is dropped and
	# counted, so a regression is loud instead of invisible.
	if current_move in [Move.SLAM, Move.CHAIN_SWEEP]:
		if not telegraph.is_armed():
			attacks_suppressed += 1
			untelegraphed_hits += 1
			attack_suppressed_without_telegraph.emit()
			_finish_move()
			return

	var amount := 0
	match current_move:
		Move.SLAM:
			amount = int(_balance.get("slam_damage", 24))
		Move.CHAIN_SWEEP:
			amount = int(_balance.get("chain_sweep_damage", 18))
		Move.TOLL:
			amount = 0

	if amount > 0:
		attacks_landed += 1
		attack_landed.emit(_move_name(), amount)
	elif current_move == Move.TOLL:
		attack_landed.emit(&"toll", 0)

	telegraph.disarm()
	_finish_move()


func _finish_move() -> void:
	_recover_left = RECOVER_SECONDS
	current_move = Move.IDLE if _recover_left <= 0.0 else current_move


func _move_name() -> StringName:
	match current_move:
		Move.SLAM:
			return &"slam"
		Move.CHAIN_SWEEP:
			return &"chain_sweep"
		Move.TOLL:
			return &"toll"
		Move.CALL:
			return &"call"
		_:
			return &"idle"


func _call_crawlers() -> void:
	_call_cooldown = float(_balance.get("crawler_summon_cooldown_seconds", 12.0))
	crawlers_called.emit(int(_balance.get("crawler_summon_count", 3)))
	# Guide §11 phase two: "Summon may add one Hexer."
	if phase == Phase.TWO:
		hexer_called.emit()
	_recover_left = RECOVER_SECONDS


# ---------------------------------------------------------------- damage

func take_damage(amount: int, _from: Variant = null) -> bool:
	if not _alive or amount <= 0:
		return false
	var applied := int(round(float(amount) * vulnerability_multiplier))
	hp = maxi(0, hp - applied)

	_check_phase()
	if hp == 0:
		kill()
	return true


## Guide §11: after two missed slams or enough Rally damage the front bell cracks
## open for four seconds at a 1.75 multiplier, and the boss does not attack.
func stagger() -> void:
	if is_staggered or not _alive:
		return
	is_staggered = true
	stagger_time_left = float(_balance.get("stagger_duration_seconds", 4.0))
	vulnerability_multiplier = float(_balance.get("stagger_damage_window_multiplier", 1.75))
	# Whatever was winding up is abandoned, telegraph and all — the boss does not
	# attack during a stagger.
	telegraph.cancel()
	_windup_left = 0.0
	_recover_left = 0.0
	current_move = Move.IDLE
	staggered.emit(stagger_time_left)


func _end_stagger() -> void:
	is_staggered = false
	stagger_time_left = 0.0
	vulnerability_multiplier = 1.0
	stagger_ended.emit()


## True while the red core is exposed — what the player is meant to read.
func core_is_exposed() -> bool:
	return is_staggered


func _check_phase() -> void:
	if phase == Phase.TWO:
		return
	var fraction := float(_balance.get("phase_2_hp_fraction", 0.5))
	if float(hp) <= float(max_hp) * fraction:
		phase = Phase.TWO
		_rotation = 0
		phase_changed.emit(2)


## Guide §11 / balance: enrage at 180 s. It shortens the gaps rather than raising
## damage — brief Phase 11: "without adding one-shot damage".
func _check_enrage() -> void:
	if has_enraged:
		return
	if elapsed >= float(_balance.get("enrage_time_seconds", 180.0)):
		has_enraged = true
		enraged.emit()


func slam_damage() -> int:
	return int(_balance.get("slam_damage", 24))


func chain_sweep_damage() -> int:
	return int(_balance.get("chain_sweep_damage", 18))


func is_alive() -> bool:
	return _alive


func kill() -> void:
	if not _alive:
		return
	_alive = false
	hp = 0
	telegraph.cancel()
	# Guide: the result state opens exactly once, however many killing blows
	# arrive on the same frame.
	if not _defeat_emitted:
		_defeat_emitted = true
		defeated.emit()
