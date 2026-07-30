class_name Player
extends CharacterBody3D

## Tower Exile. Phase 1 hero sandbox.
##
## Movement, dash, eight-direction facing, hurtbox with contact grace, and a
## camera target. All tuning comes from CharacterData, which is seeded from
## docs/LEVEL1_BALANCE.json — no gameplay constants live in this file.
##
## State machine (master guide §15): MOVE -> DASH -> MOVE, plus HURT, CAST, DEFEAT.

signal health_changed(current: int, maximum: int)
signal died
signal dashed
## A foot hits the ground: walk's contact frame, run's extension and recovery
## frames. The presentation layer turns these into dust puffs and step sounds.
signal stepped
signal damage_taken(amount: int)
signal damage_ignored_during_grace(amount: int)

enum State { MOVE, DASH, HURT, CAST, DEFEAT }

## ASSET_MANIFEST row_order for the locomotion atlas. Index maps to the
## compass octant starting at south and rotating clockwise-on-screen.
const DIRECTION_NAMES := ["south", "southwest", "west", "northwest", "north", "northeast", "east", "southeast"]

const PIVOT_OFFSETS_PATH := "res://data/characters/tower_exile_pivot_offsets.json"

## Below this planar speed the hero is treated as idle for animation purposes.
const IDLE_SPEED_EPSILON := 0.05

@export var data: CharacterData

@onready var _sprite: AnimatedSprite3D = $VisualPivot/AnimatedSprite3D
@onready var _visual_pivot: Node3D = $VisualPivot
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hurtbox: Area3D = $Hurtbox
@onready var _camera_target: Node3D = $CameraTarget
@onready var _focus: FocusWeaponController = $FocusWeaponController

var state: State = State.MOVE
var hp: int = 100

var facing_index: int = 0  ## Index into DIRECTION_NAMES.
var preferred_aim: Vector3 = Vector3.FORWARD

var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_iframes_left := 0.0
var _grace_left := 0.0
var _dash_direction := Vector3.ZERO
var _dash_distance_travelled := 0.0
var _dash_finishing := false

var _pivot_offsets: Dictionary = {}
var _base_sprite_offset_px := 0.0
var _last_anim := ""
var _last_frame := -1


func _ready() -> void:
	add_to_group("player")
	if data == null:
		data = CharacterData.new()
	data.apply_balance()
	hp = data.max_hp

	_load_pivot_offsets()
	_configure_sprite()
	_configure_bodies()
	health_changed.emit(hp, data.max_hp)


# ---------------------------------------------------------------- setup

func _configure_sprite() -> void:
	if _sprite == null:
		return
	if data.sprite_frames != null:
		_sprite.sprite_frames = data.sprite_frames

	# 2D pixel actor inside a 3D world (master guide §15).
	_sprite.pixel_size = data.pixel_size()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = false
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.centered = true

	# Place the bottom of the source cell on the node origin so the actor is
	# grounded. Per-frame corrections ride on top of this.
	_base_sprite_offset_px = float(data.source_cell_height_px) * 0.5
	_apply_sprite_offset(0)

	_play_animation("idle_%s" % DIRECTION_NAMES[facing_index])
	if not _sprite.frame_changed.is_connected(_on_frame_changed):
		_sprite.frame_changed.connect(_on_frame_changed)


func _configure_bodies() -> void:
	# Layer 2 PlayerBody; collides with World (1) and NavigationBlocker (9).
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 8)

	if _collision != null and _collision.shape is CapsuleShape3D:
		var capsule := _collision.shape as CapsuleShape3D
		capsule.radius = data.collision_radius_units
		capsule.height = data.collision_height_units
		_collision.position.y = data.collision_height_units * 0.5

	if _hurtbox != null:
		# Layer 4 PlayerHurtbox; monitors HostileAttack (7).
		_hurtbox.collision_layer = 1 << 3
		_hurtbox.collision_mask = 1 << 6


func _load_pivot_offsets() -> void:
	if not FileAccess.file_exists(PIVOT_OFFSETS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIVOT_OFFSETS_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_pivot_offsets = (parsed as Dictionary).get("offsets", {})


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	match state:
		State.DASH:
			_process_dash(delta)
		State.DEFEAT:
			velocity = Vector3.ZERO
		_:
			_process_move(delta)

	move_and_slide()

	if _dash_finishing:
		_dash_finishing = false
		_end_dash()

	_update_facing()
	_update_animation()
	_update_aim()


func _tick_timers(delta: float) -> void:
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_dash_iframes_left = maxf(0.0, _dash_iframes_left - delta)
	_grace_left = maxf(0.0, _grace_left - delta)


func _process_move(delta: float) -> void:
	var input := get_move_input()
	var desired := input * data.move_speed_units_per_second
	var planar := Vector3(velocity.x, 0.0, velocity.z)

	# Separate accel/decel so the hero reaches full speed smoothly but also
	# stops without sliding (Phase 1 acceptance).
	var rate := data.acceleration if input.length_squared() > 0.0 else data.deceleration
	planar = planar.move_toward(desired, rate * delta)

	velocity.x = planar.x
	velocity.z = planar.z

	if state == State.MOVE and Input.is_action_just_pressed("dash"):
		try_dash()


## Drives the dash by distance rather than by timer alone. The final tick is
## clamped to the exact remaining distance, and the state change is deferred
## until after move_and_slide() so that last tick still moves the body —
## otherwise the dash lands one physics tick short of its 4.3 units.
func _process_dash(delta: float) -> void:
	if delta <= 0.0:
		return
	var speed := data.dash_speed()
	var remaining: float = data.dash_distance_units - _dash_distance_travelled
	var step := speed * delta

	if step >= remaining:
		step = remaining
		velocity = _dash_direction * (step / delta)
		_dash_time_left = 0.0
		_dash_finishing = true
	else:
		velocity = _dash_direction * speed
		_dash_time_left -= delta

	_dash_distance_travelled += step


# ---------------------------------------------------------------- input

## Planar movement input in world space. Returns a normalized XZ vector.
func get_move_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Screen up (W) runs away from the camera, i.e. -Z.
	var dir := Vector3(v.x, 0.0, v.y)
	return dir.normalized() if dir.length_squared() > 1.0 else dir


## Optional aim. Zero when the player never touches the stick, which is what
## keeps the no-aim promise honest.
func get_aim_input() -> Vector3:
	var v := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	return Vector3(v.x, 0.0, v.y)


# ---------------------------------------------------------------- dash

func can_dash() -> bool:
	return state == State.MOVE and _dash_cooldown_left <= 0.0


func try_dash() -> bool:
	if not can_dash():
		return false

	var dir := get_move_input()
	if dir.length_squared() <= 0.0:
		dir = facing_vector()

	_dash_direction = dir.normalized()
	_dash_time_left = data.dash_duration_seconds
	_dash_cooldown_left = data.dash_cooldown_seconds
	_dash_iframes_left = data.dash_invulnerability_seconds
	_dash_distance_travelled = 0.0
	_dash_finishing = false
	state = State.DASH
	dashed.emit()
	return true


func _end_dash() -> void:
	_dash_time_left = 0.0
	velocity = Vector3.ZERO
	if state == State.DASH:
		state = State.MOVE


func dash_cooldown_remaining() -> float:
	return _dash_cooldown_left


func last_dash_distance() -> float:
	return _dash_distance_travelled


func is_dashing() -> bool:
	return state == State.DASH


# ---------------------------------------------------------------- damage

func is_invulnerable() -> bool:
	return _dash_iframes_left > 0.0 or _grace_left > 0.0


## Returns true when the hit landed. A hit inside the contact grace window or
## dash i-frames is ignored, so the hero cannot take two hits back to back.
func take_damage(amount: int) -> bool:
	if state == State.DEFEAT:
		return false
	if is_invulnerable():
		damage_ignored_during_grace.emit(amount)
		return false

	hp = maxi(0, hp - amount)
	_grace_left = data.contact_grace_seconds
	damage_taken.emit(amount)
	health_changed.emit(hp, data.max_hp)

	if hp <= 0:
		state = State.DEFEAT
		died.emit()
	return true


func heal(amount: int) -> void:
	if state == State.DEFEAT:
		return
	hp = mini(data.max_hp, hp + amount)
	health_changed.emit(hp, data.max_hp)


# ---------------------------------------------------------------- facing

## Eight-direction index from a planar vector. Screen-south (+Z) is index 0 and
## the octants advance through southwest, west, northwest, north, and so on.
static func direction_index_from_vector(v: Vector3) -> int:
	if absf(v.x) < 0.0001 and absf(v.z) < 0.0001:
		return 0
	# atan2(-x, z): +Z -> 0 rad (south), -X -> +90 deg (west), -Z -> 180 (north).
	var angle := atan2(-v.x, v.z)
	var octant := int(round(angle / (TAU / 8.0)))
	return posmod(octant, 8)


func facing_vector() -> Vector3:
	var angle := float(facing_index) * (TAU / 8.0)
	return Vector3(-sin(angle), 0.0, cos(angle))


func facing_name() -> String:
	return DIRECTION_NAMES[facing_index]


func _update_facing() -> void:
	var reference := _dash_direction if state == State.DASH else Vector3(velocity.x, 0.0, velocity.z)
	if reference.length_squared() <= IDLE_SPEED_EPSILON * IDLE_SPEED_EPSILON:
		return
	facing_index = direction_index_from_vector(reference)


# ---------------------------------------------------------------- animation

## Gait is chosen from actual speed, not from "is the stick held".
##
## The package ships two distinct gaits and the SpriteFrames builder now keeps
## them apart, so the hero has to pick. The run threshold sits at 70% of top
## speed: below it the subtle walk poses read correctly, above it the full stride
## does. A dash is always a run — it is the fastest the hero ever moves.
##
## `_play_animation` falls through when an animation is missing, so a SpriteFrames
## built before the split (walk_* absent) still plays run_* and nothing breaks.
const RUN_SPEED_FRACTION := 0.7

func _update_animation() -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var moving := planar_speed > IDLE_SPEED_EPSILON
	var top_speed := data.move_speed_units_per_second if data != null else 6.2
	var running := state == State.DASH or planar_speed >= top_speed * RUN_SPEED_FRACTION

	# The dash has its own animation — an east-facing lunge with the violet
	# streak, flipped for leftward dashes. Falls through to run_* on a checkout
	# whose SpriteFrames predate the action atlas.
	if state == State.DASH and _sprite != null and _sprite.sprite_frames != null \
			and _sprite.sprite_frames.has_animation("dash"):
		_sprite.flip_h = _dash_direction.x < -0.01
		_sprite.speed_scale = 1.0
		_play_animation("dash")
		_sync_pivot_offset()
		return
	if _sprite != null:
		_sprite.flip_h = false

	var prefix := "idle"
	if moving or state == State.DASH:
		prefix = "run" if running else "walk"
	_play_animation("%s_%s" % [prefix, DIRECTION_NAMES[facing_index]])
	_sprite.speed_scale = _gait_speed_scale(prefix, planar_speed, top_speed)
	_sync_pivot_offset()


## Cadence proportional to ground speed, so the feet stop sliding.
##
## The single loudest thing that makes a walk read as fake is a stride that runs
## at a fixed rate while the body moves at a variable one — the feet skate. Both
## gaits played at a constant fps (7 and 12) no matter whether the hero was
## easing off a wall at 0.8 u/s or at full tilt, and that is what "the walking
## animation could be better" looks like from the outside.
##
## Each gait has a reference speed at which its authored fps is correct; the
## scale is the ratio. Clamped because a 2-frame walk played at 4x reads as a
## vibration, and because a frozen stride at near-zero speed reads as a bug.
const WALK_REFERENCE_SPEED := 3.4
const RUN_REFERENCE_SPEED := 6.2

func _gait_speed_scale(prefix: String, planar_speed: float, top_speed: float) -> float:
	if prefix == "idle":
		return 1.0
	# The references are authored against the shipped 6.2 u/s top speed. Scaling
	# them with the live value keeps the ratio honest if balance retunes speed.
	var scale_basis := top_speed / 6.2 if top_speed > 0.0 else 1.0
	if prefix == "walk":
		return clampf(planar_speed / (WALK_REFERENCE_SPEED * scale_basis), 0.55, 1.5)
	return clampf(planar_speed / (RUN_REFERENCE_SPEED * scale_basis), 0.7, 1.35)


## The gait the hero would play right now. Exposed so a check can assert the
## walk/run split actually engages at speed rather than trusting the animation
## name it happens to be showing.
func current_gait() -> String:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed <= IDLE_SPEED_EPSILON and state != State.DASH:
		return "idle"
	var top_speed := data.move_speed_units_per_second if data != null else 6.2
	if state == State.DASH or planar_speed >= top_speed * RUN_SPEED_FRACTION:
		return "run"
	return "walk"


func _play_animation(anim: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if not _sprite.sprite_frames.has_animation(anim):
		return
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)


## Applies the generated per-frame correction so the feet stay on the origin
## across every frame, including the ones whose source art floats.
## Contact frames per gait: walk frame 0 is walk_contact; run frames 0 and 2
## are extension and recovery, the two ground strikes of the stride.
func _on_frame_changed() -> void:
	if _sprite == null:
		return
	var anim := String(_sprite.animation)
	var f := _sprite.frame
	if (anim.begins_with("walk_") and f == 0) \
			or (anim.begins_with("run_") and (f == 0 or f == 2)):
		stepped.emit()


func _sync_pivot_offset() -> void:
	if _sprite == null:
		return
	var anim := String(_sprite.animation)
	var frame := _sprite.frame
	if anim == _last_anim and frame == _last_frame:
		return
	_last_anim = anim
	_last_frame = frame
	_apply_sprite_offset(int(_pivot_offsets.get("%s/%d" % [anim, frame], 0)))


func _apply_sprite_offset(correction_px: int) -> void:
	if _sprite == null:
		return
	_sprite.offset = Vector2(0.0, _base_sprite_offset_px - float(correction_px))


## The sprite's frame library, or null before _ready. For the acceptance tests.
func sprite_frames_or_null() -> SpriteFrames:
	return _sprite.sprite_frames if _sprite != null else null


## The animation the sprite is showing right now, for the acceptance tests.
func current_animation() -> String:
	return String(_sprite.animation) if _sprite != null else ""


## The playing animation's rate multiplier, for the acceptance tests.
func current_speed_scale() -> float:
	return _sprite.speed_scale if _sprite != null else 1.0


## Current pivot correction in pixels, for the acceptance tests.
func current_pivot_correction() -> int:
	if _sprite == null:
		return 0
	return int(_pivot_offsets.get("%s/%d" % [String(_sprite.animation), _sprite.frame], 0))


# ---------------------------------------------------------------- misc

func camera_target() -> Node3D:
	return _camera_target


## Read by the debug overlay and by the HUD in Phase 13.
func get_current_target() -> Node:
	return _focus.current_target if _focus != null else null


func focus_weapon() -> FocusWeaponController:
	return _focus


## Feeds optional aim into the Focus Weapon. Zero input leaves `preferred_aim`
## cleared, so the staff falls back to threat-and-proximity ordering and keeps
## firing — the no-aim promise.
func _update_aim() -> void:
	if _focus == null:
		return
	var aim := get_aim_input()
	if aim.length_squared() > 0.0001:
		preferred_aim = aim.normalized()
		_focus.set_preferred_aim(preferred_aim)


func world_height() -> float:
	return data.world_height_units
