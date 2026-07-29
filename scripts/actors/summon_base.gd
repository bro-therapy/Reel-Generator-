class_name SummonBase
extends Node3D

## The one generic summon. All three starters are this scene plus a SpiritData.
##
## Deliberately a plain Node3D, not a physics body. The brief forbids physical
## collision with the player, other summons, and normal enemies — the cheapest
## way to guarantee that is to have no body at all, so it cannot be violated by
## a later layer-mask edit.
##
## Movement is steering toward a lane, never pathfinding. A summon that falls
## more than `teleport_back_distance_units` from the hero reforms in place
## instead of routing back (master guide §4).

signal attacked(target: Node3D, damage: int)
signal reformed()
signal state_changed(to: int, from: int)

const REFORM_ANIM := "reform"

@export var data: SpiritData
@export var form_index := 0
## Assigned at spawn. Kept as NodePath-free direct reference so a summon can be
## reparented between rooms without losing its hero.
var hero: Node3D

@onready var _visual_pivot: Node3D = $VisualPivot
@onready var _sprite: AnimatedSprite3D = $VisualPivot/AnimatedSprite3D
@onready var _attack_origin: Node3D = $AttackOrigin
@onready var _follow: FollowController = $FollowController
@onready var _targeting: SummonTargetController = $TargetController
@onready var _fsm: SummonStateMachine = $StateMachine

var form: SpiritFormData
## Species behaviour module (Phase 4). Null falls back to the generic cycle.
var behavior: SummonBehavior

var _reform_delay := 0.35
var _teleport_distance := 10.0
var _rally_bonus := 0.15
var _attack_cooldown := 0.0
var _pivot_offsets: Dictionary = {}
var _base_sprite_offset_px := 0.0
var _last_anim := ""
var _attack_delivered := false

## Diagnostics for the acceptance harness.
var attacks_landed := 0
var reform_count := 0


func _ready() -> void:
	add_to_group("summons")

	_teleport_distance = SpiritData.teleport_back_distance()
	_reform_delay = SpiritData.reform_delay()
	_rally_bonus = SpiritData.rally_damage_bonus()

	if data == null:
		push_error("SummonBase: no SpiritData assigned")
		return
	data.apply_balance()
	form = data.form(form_index)
	if form == null:
		push_error("SummonBase: SpiritData '%s' has no forms" % data.id)
		return

	_follow.lane_offset = data.lane_offset
	_follow.speed_units_per_second = data.follow_speed_units_per_second
	_follow.lane_tolerance_units = data.lane_tolerance_units
	_follow.reset_basis(_hero_forward())

	_targeting.refresh_seconds = SpiritData.target_refresh_seconds()
	# See far enough to engage: a melee species must notice targets it has to
	# walk to, a ranged one must see to the edge of its own reach.
	_targeting.range_units = maxf(form.range_units, data.engage_radius_units)

	_install_behavior()
	_fsm.state_changed.connect(_on_state_changed)
	_load_pivot_offsets()
	_configure_sprite()


## Instantiates the species behaviour named by the SpiritData, if any.
func _install_behavior() -> void:
	if data.behavior_script == null:
		return
	var instance: Variant = data.behavior_script.new()
	if instance is SummonBehavior:
		behavior = instance as SummonBehavior
		behavior.name = "Behavior"
		add_child(behavior)
		behavior.setup(self)
	else:
		push_error("SummonBase: behavior_script on '%s' is not a SummonBehavior" % data.id)


func _physics_process(delta: float) -> void:
	if form == null or hero == null:
		return

	_fsm.tick(delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Master guide §16 scores every 0.20 s. Ticking this inside the state match
	# stalled the cadence during windup/attack/recover, so it runs unconditionally.
	_targeting.tick(delta, _origin())

	var forward := _follow.update_basis(_hero_forward(), delta)
	var lane := _follow.lane_position(hero.global_position, forward)
	if behavior != null:
		lane = behavior.follow_target(lane, delta)

	# Separation check runs before anything else: reform outranks every state.
	if _fsm.state != SummonStateMachine.State.REFORM:
		if global_position.distance_to(hero.global_position) > _teleport_distance:
			_begin_reform()

	match _fsm.state:
		SummonStateMachine.State.REFORM:
			_process_reform(lane)
		SummonStateMachine.State.WINDUP:
			_process_windup(delta, lane)
		SummonStateMachine.State.ATTACK:
			_process_attack(delta, lane)
		SummonStateMachine.State.RECOVER:
			_process_recover(delta, lane)
		SummonStateMachine.State.ACQUIRE:
			_process_acquire(delta, lane)
		_:
			_process_follow(delta, lane)

	_update_animation()


# ---------------------------------------------------------------- states

func _process_follow(delta: float, lane: Vector3) -> void:
	global_position = _follow.steer(global_position, lane, delta)
	if _attack_cooldown <= 0.0 and _targeting.has_valid_target() and _within_leash():
		_fsm.transition_to(SummonStateMachine.State.ACQUIRE)


## Closes on the target until it is in reach, then commits to the windup.
## Bounded by the leash so this stays steering, never room-wide pursuit.
func _process_acquire(delta: float, lane: Vector3) -> void:
	if not _targeting.has_valid_target() or not _within_leash():
		_fsm.transition_to(SummonStateMachine.State.FOLLOW)
		return

	if _in_attack_range():
		_fsm.transition_to(SummonStateMachine.State.WINDUP)
		return

	# A planted species shoots from where it stands and never closes distance.
	if behavior != null and behavior.plants_to_attack():
		_fsm.transition_to(SummonStateMachine.State.FOLLOW)
		return

	global_position = _follow.steer(global_position, _approach_point(lane), delta)


## A standoff point just inside reach, holding the species' lane height so the
## overhead Sword Wisp does not dive to the floor to engage.
func _approach_point(lane: Vector3) -> Vector3:
	var target := _targeting.current_target
	if target == null:
		return lane
	var point := TargetScorer.target_point(target)
	var from := global_position
	var to_target := point - from
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return Vector3(from.x, lane.y, from.z)
	var standoff: float = form.range_units * 0.75
	var desired := point - to_target.normalized() * standoff
	return Vector3(desired.x, lane.y, desired.z)


## True while the current target is close enough to the hero to be worth
## leaving the lane for.
func _within_leash() -> bool:
	var target := _targeting.current_target
	if target == null or hero == null:
		return false
	return hero.global_position.distance_to(TargetScorer.target_point(target)) <= data.engage_radius_units


func _process_windup(delta: float, lane: Vector3) -> void:
	if not _targeting.has_valid_target():
		_fsm.transition_to(SummonStateMachine.State.FOLLOW)
		return
	if behavior != null:
		behavior.on_windup(delta, lane)
	if _fsm.time_in_state >= form.windup_seconds:
		_fsm.transition_to(SummonStateMachine.State.ATTACK)


## The attack lands once on entry; the remaining ticks let a species carry its
## movement through (the hound's lunge, the wisp's slice) before recovering.
func _process_attack(delta: float, lane: Vector3) -> void:
	if not _attack_delivered:
		_deal_damage()
		_attack_delivered = true
	if behavior != null:
		behavior.on_attack_tick(delta, lane)
	if _fsm.time_in_state >= _attack_tick_seconds():
		_fsm.transition_to(SummonStateMachine.State.RECOVER)


## How long the ATTACK state holds. Species that move through their attack need
## a few frames; instant ones fall through on the next tick.
func _attack_tick_seconds() -> float:
	return 0.0 if behavior == null else 0.12


func _process_recover(delta: float, lane: Vector3) -> void:
	# Return to the lane rather than parking on the corpse.
	var handled := behavior != null and behavior.on_recover(delta, lane)
	if not handled:
		global_position = _follow.steer(global_position, lane, delta)
	if _fsm.time_in_state >= form.recover_seconds:
		_fsm.transition_to(SummonStateMachine.State.FOLLOW)


func _process_reform(lane: Vector3) -> void:
	if _fsm.time_in_state < _reform_delay:
		return
	# Teleport rather than travel — explicitly what the brief asks for.
	global_position = lane
	_follow.reset_basis(_hero_forward())
	_targeting.clear()
	_fsm.transition_to(SummonStateMachine.State.FOLLOW)
	reform_count += 1
	reformed.emit()


func _begin_reform() -> void:
	if _fsm.force_reform():
		_targeting.clear()


# ---------------------------------------------------------------- combat

func _deal_damage() -> void:
	var target := _targeting.current_target
	if not TargetScorer.is_targetable(target):
		return
	if not _in_attack_range():
		return

	var dmg := form.damage
	if _targeting.rally_target != null and target == _targeting.rally_target:
		dmg = int(round(float(dmg) * (1.0 + _rally_bonus)))

	var handled := behavior != null and behavior.deliver_attack(target, dmg)
	if not handled and target.has_method("take_damage"):
		target.call("take_damage", dmg)

	attacks_landed += 1
	_attack_cooldown = form.attack_interval_seconds
	attacked.emit(target, dmg)


func _in_attack_range() -> bool:
	var target := _targeting.current_target
	if target == null:
		return false
	return _origin().distance_to(TargetScorer.target_point(target)) <= form.range_units


func _origin() -> Vector3:
	return _attack_origin.global_position if _attack_origin != null else global_position


func set_rally_target(target: Node3D) -> void:
	_targeting.rally_target = target


func current_target() -> Node3D:
	return _targeting.current_target


func state() -> int:
	return _fsm.state


func state_name() -> String:
	return _fsm.state_name()


func illegal_transition_count() -> int:
	return _fsm.illegal_attempts


## Summons are invulnerable for the prototype (master guide §4). The method
## exists so hostile code can call it uniformly; it simply refuses.
func take_damage(_amount: int) -> bool:
	return false


func is_invulnerable() -> bool:
	return SpiritData.invulnerable_in_prototype()


# ---------------------------------------------------------------- visuals

func _configure_sprite() -> void:
	if _sprite == null or form == null:
		return
	if form.sprite_frames != null:
		_sprite.sprite_frames = form.sprite_frames
	_sprite.pixel_size = form.pixel_size()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = false
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.centered = true

	_base_sprite_offset_px = float(form.source_cell_height_px) * 0.5
	_apply_sprite_offset(0)
	_play("idle")


func _update_animation() -> void:
	match _fsm.state:
		SummonStateMachine.State.REFORM:
			_play(REFORM_ANIM)
		SummonStateMachine.State.WINDUP:
			_play("aim_or_windup")
		SummonStateMachine.State.ATTACK:
			_play("attack")
		SummonStateMachine.State.RECOVER:
			_play("attack_recover")
		_:
			_play("move" if _is_moving() else "idle")


func _is_moving() -> bool:
	if hero == null:
		return false
	var lane := _follow.lane_position(hero.global_position, _follow.smoothed_forward())
	return not _follow.is_in_lane(global_position, lane)


func _play(anim: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if not _sprite.sprite_frames.has_animation(anim):
		return
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)
	if anim != _last_anim:
		_last_anim = anim
		_apply_sprite_offset(int(_pivot_offsets.get("%s/0" % anim, 0)))


func _apply_sprite_offset(correction_px: int) -> void:
	if _sprite == null:
		return
	_sprite.offset = Vector2(0.0, _base_sprite_offset_px - float(correction_px))


func _load_pivot_offsets() -> void:
	const METRICS := "res://docs/generated/summon_metrics.json"
	if data == null or not FileAccess.file_exists(METRICS):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METRICS))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var species: Dictionary = (parsed as Dictionary).get("species", {})
	var entry: Dictionary = species.get(String(data.id), {})
	_pivot_offsets = entry.get("pivot_offsets", {})


## Shared pools, resolved from the hero so summons never own their own.
func projectile_pool() -> ProjectilePool:
	if hero == null:
		return null
	return hero.get_node_or_null("ProjectilePool") as ProjectilePool


func effect_pool() -> EffectPool:
	if hero == null:
		return null
	return hero.get_node_or_null("EffectPool") as EffectPool


func spawn_effect(position: Vector3, row: StringName, scale_units: float) -> void:
	var pool := effect_pool()
	if pool != null:
		pool.spawn(position, row, scale_units)


func attack_origin_position() -> Vector3:
	return _origin()


## The attack origin the summon would have if its body were at `position`.
## Behaviours use this to test a candidate move without committing to it.
func attack_origin_offset_from(position: Vector3) -> Vector3:
	return position + (_origin() - global_position)


func behavior_signature() -> String:
	return behavior.signature() if behavior != null else "generic"


func _hero_forward() -> Vector3:
	if hero == null:
		return Vector3.FORWARD
	if hero.has_method("facing_vector"):
		return hero.call("facing_vector") as Vector3
	return -hero.global_transform.basis.z


func _on_state_changed(to: int, from: int) -> void:
	if to == SummonStateMachine.State.ATTACK:
		_attack_delivered = false
	if behavior != null:
		behavior.on_state_entered(to)
	state_changed.emit(to, from)
