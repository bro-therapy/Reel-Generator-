class_name EnemyBase
extends CharacterBody3D

## One reusable enemy driving all six Level 1 roles (build brief Phase 5).
##
## Implements the targeting contract the Focus Weapon and every summon score
## against — group "enemies", is_targetable, target_point, threat_class,
## take_damage — so Phase 2-4 systems bind to real enemies unchanged.
##
## The rule that every damaging attack is telegraphed is enforced here rather
## than trusted to each role: `_deal_damage()` refuses to fire unless the
## TelegraphController confirms a warning was shown for this attack. A role that
## forgets to telegraph simply deals no damage, which fails loudly in testing
## instead of shipping an unfair hit.

signal died(enemy: EnemyBase)
signal damaged(amount: int, remaining: int)
signal attack_landed(target: Node3D, amount: int)
signal attack_suppressed_without_telegraph()

const DEATH_LINGER_SECONDS := 0.35

@export var data: EnemyData
## Assigned at spawn.
var target: Node3D

@onready var _sprite: AnimatedSprite3D = $VisualPivot/AnimatedSprite3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hurtbox: Area3D = $Hurtbox
@onready var _attack_origin: Node3D = $AttackOrigin
@onready var _fsm: EnemyStateMachine = $StateMachine
@onready var _telegraph: TelegraphController = $TelegraphController

var behavior: EnemyBehavior
var hp := 1
## Multiplier applied to starting health at spawn, for the run's difficulty
## escalation. Set by whoever spawns this enemy, BEFORE it enters the tree.
## Health only — scaling damage is how escalation becomes unfair.
var health_scale := 1.0
## This instance's actual starting health after escalation, so the HUD and the
## checks read the real number rather than the resource's base value.
var max_hp_scaled := 1

## Set by a role while it is open to extra damage — the Bellguard's exposed back
## after a failed slam, for instance.
var vulnerability_multiplier := 1.0

var attacks_landed := 0
var attacks_suppressed := 0
var damage_taken_total := 0

var _attack_cooldown := 0.0
var _death_linger := 0.0
var _alive := true
var _pivot_offsets: Dictionary = {}
var _base_sprite_offset_px := 0.0
var _last_anim := ""


func _ready() -> void:
	add_to_group("enemies")
	if data == null:
		push_error("EnemyBase: no EnemyData assigned")
		return
	data.apply_balance()
	# Scaled per instance. `data` is a shared resource: writing the scaled value
	# back into it would compound on every later spawn and leak into the next run.
	max_hp_scaled = maxi(1, int(round(float(data.max_hp) * health_scale)))
	hp = max_hp_scaled

	_telegraph.shape = data.telegraph_shape
	_telegraph.radius = data.telegraph_radius_units

	_configure_bodies()
	_load_pivot_offsets()
	_configure_sprite()
	_install_behavior()
	_fsm.transition_to(EnemyStateMachine.State.SEEK)


func _install_behavior() -> void:
	if data.behavior_script == null:
		return
	var instance: Variant = data.behavior_script.new()
	if instance is EnemyBehavior:
		behavior = instance as EnemyBehavior
		behavior.name = "Behavior"
		add_child(behavior)
		behavior.setup(self)
	else:
		push_error("EnemyBase: behavior_script on '%s' is not an EnemyBehavior" % data.id)


func _configure_bodies() -> void:
	# Layer 3 EnemyBody; collides with World (1) and NavigationBlocker (9).
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 8)

	if _collision != null and _collision.shape is CapsuleShape3D:
		var capsule := _collision.shape as CapsuleShape3D
		capsule.radius = data.collision_radius_units
		capsule.height = data.collision_height_units
		_collision.position.y = data.collision_height_units * 0.5

	if _hurtbox != null:
		# Layer 5 EnemyHurtbox, monitorable so friendly attacks (layer 6) find it.
		_hurtbox.collision_layer = 1 << 4
		_hurtbox.collision_mask = 1 << 5
		_hurtbox.monitorable = true


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_fsm.tick(delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	if _fsm.state == EnemyStateMachine.State.DEATH:
		_process_death(delta)
		return

	match _fsm.state:
		EnemyStateMachine.State.WINDUP:
			_process_windup(delta)
		EnemyStateMachine.State.ATTACK:
			_process_attack(delta)
		EnemyStateMachine.State.RECOVER:
			_process_recover(delta)
		EnemyStateMachine.State.STAGGER:
			_process_stagger(delta)
		_:
			_process_seek(delta)

	move_and_slide()
	_update_animation()


# ---------------------------------------------------------------- states

func _process_seek(delta: float) -> void:
	if behavior != null and behavior.on_seek(delta):
		return
	_default_seek(delta)


## Steer toward the target and commit to an attack once in reach.
func _default_seek(delta: float) -> void:
	if not _has_valid_target():
		velocity = Vector3.ZERO
		return
	var to := _flat_to_target()
	var distance := to.length()
	if distance > data.attack_range_units:
		velocity = to.normalized() * data.speed_units_per_second
	else:
		velocity = velocity.move_toward(Vector3.ZERO, data.speed_units_per_second * 6.0 * delta)
		if _attack_cooldown <= 0.0:
			begin_attack()


## Starts the telegraphed windup. Every damaging role goes through here.
func begin_attack() -> void:
	if not _fsm.transition_to(EnemyStateMachine.State.WINDUP):
		return
	var seconds: float = data.windup_seconds
	if behavior != null:
		seconds = behavior.windup_seconds(seconds)
	_telegraph.show_telegraph(data.telegraph_shape, seconds, data.telegraph_radius_units)
	if behavior != null:
		behavior.on_windup_started()


func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, data.speed_units_per_second * 8.0 * delta)
	if behavior != null and behavior.on_windup(delta):
		return
	if not _has_valid_target():
		_cancel_attack()
		return
	if _fsm.time_in_state >= _telegraph.last_duration:
		_fsm.transition_to(EnemyStateMachine.State.ATTACK)


func _process_attack(delta: float) -> void:
	if _fsm.time_in_state <= delta:
		_deal_damage()
	if behavior != null and behavior.on_attack(delta):
		return
	if _fsm.time_in_state >= data.active_seconds:
		_fsm.transition_to(EnemyStateMachine.State.RECOVER)


func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, data.speed_units_per_second * 4.0 * delta)
	if behavior != null and behavior.on_recover(delta):
		return
	if _fsm.time_in_state >= data.recover_seconds:
		vulnerability_multiplier = 1.0
		_fsm.transition_to(EnemyStateMachine.State.SEEK)


func _process_stagger(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, data.speed_units_per_second * 8.0 * delta)
	if _fsm.time_in_state >= 0.6:
		vulnerability_multiplier = 1.0
		_fsm.transition_to(EnemyStateMachine.State.SEEK)


## A corpse must never hold a room open. The body leaves the enemies group the
## instant it dies, so room-completion checks stop counting it immediately, and
## the node frees itself after a short linger for the death frame.
func _process_death(delta: float) -> void:
	velocity = Vector3.ZERO
	_death_linger -= delta
	if _death_linger <= 0.0:
		queue_free()


func _cancel_attack() -> void:
	_telegraph.cancel()
	_fsm.transition_to(EnemyStateMachine.State.SEEK)


# ---------------------------------------------------------------- combat

## Damage is gated on the telegraph. A role that attacks without announcing it
## lands nothing and increments a counter the acceptance harness reads.
func _deal_damage() -> void:
	if not _telegraph.is_armed():
		attacks_suppressed += 1
		attack_suppressed_without_telegraph.emit()
		return
	_telegraph.disarm()
	_attack_cooldown = data.attack_interval_seconds

	if behavior != null and behavior.deliver_attack():
		attacks_landed += 1
		return

	if not _has_valid_target():
		return
	if _flat_to_target().length() > data.attack_range_units * 1.35:
		return  # the player left the telegraph in time

	CombatDamage.apply(target, data.damage, attack_origin_position())
	attacks_landed += 1
	attack_landed.emit(target, data.damage)


## Incoming damage. `from_position` lets a role apply directional reduction —
## the Bellguard's shield halves frontal hits.
func take_damage(amount: int, from_position: Variant = null) -> bool:
	if not _alive:
		return false

	var incoming := float(amount)
	if behavior != null:
		incoming = behavior.modify_incoming_damage(incoming, from_position)
	incoming *= vulnerability_multiplier

	var applied := maxi(0, int(round(incoming)))
	hp -= applied
	damage_taken_total += applied
	damaged.emit(applied, hp)

	if hp <= 0:
		kill()
	return true


## Death cancels everything in flight, including a windup mid-telegraph.
func kill() -> void:
	if not _alive:
		return
	_alive = false
	hp = 0
	_telegraph.cancel()
	_fsm.kill()
	_death_linger = DEATH_LINGER_SECONDS
	# Leave the group immediately so nothing counts a corpse as a live enemy.
	if is_in_group("enemies"):
		remove_from_group("enemies")
	velocity = Vector3.ZERO
	died.emit(self)


func stagger() -> void:
	if _alive:
		_fsm.transition_to(EnemyStateMachine.State.STAGGER)


# ---------------------------------------------------------------- targeting contract

func is_targetable() -> bool:
	return _alive


func is_alive() -> bool:
	return _alive


func target_point() -> Vector3:
	return global_position + Vector3(0.0, data.collision_height_units * 0.6, 0.0)


func threat_class() -> StringName:
	return data.threat_class


func state() -> int:
	return _fsm.state


func state_name() -> String:
	return _fsm.state_name()


func telegraph() -> TelegraphController:
	return _telegraph


func illegal_transition_count() -> int:
	return _fsm.illegal_attempts


# ---------------------------------------------------------------- helpers

func _has_valid_target() -> bool:
	return target != null and is_instance_valid(target)


func _flat_to_target() -> Vector3:
	if not _has_valid_target():
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	return to


func attack_origin_position() -> Vector3:
	return _attack_origin.global_position if _attack_origin != null else global_position


func facing_target() -> Vector3:
	var to := _flat_to_target()
	return to.normalized() if to.length_squared() > 0.0001 else Vector3.FORWARD


# ---------------------------------------------------------------- visuals

func _configure_sprite() -> void:
	if _sprite == null or data == null:
		return
	if data.sprite_frames != null:
		_sprite.sprite_frames = data.sprite_frames
	_sprite.pixel_size = data.pixel_size()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = false
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.centered = true
	_base_sprite_offset_px = float(data.source_cell_height_px) * 0.5
	_apply_sprite_offset(0)
	_play("idle")


func _update_animation() -> void:
	match _fsm.state:
		EnemyStateMachine.State.DEATH:
			_play("death")
		EnemyStateMachine.State.WINDUP:
			_play("attack_windup")
		EnemyStateMachine.State.ATTACK:
			_play("attack_active")
		EnemyStateMachine.State.STAGGER:
			_play("hit")
		_:
			_play("move" if velocity.length_squared() > 0.05 else "idle")


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
	if _sprite != null:
		_sprite.offset = Vector2(0.0, _base_sprite_offset_px - float(correction_px))


func _load_pivot_offsets() -> void:
	const METRICS := "res://docs/generated/enemy_metrics.json"
	if data == null or not FileAccess.file_exists(METRICS):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METRICS))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var roles: Dictionary = (parsed as Dictionary).get("roles", {})
	var entry: Dictionary = roles.get(String(data.id), {})
	_pivot_offsets = entry.get("pivot_offsets", {})
