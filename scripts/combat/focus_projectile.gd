class_name FocusProjectile
extends Area3D

## Conjurer Staff projectile. Pooled — never freed during a run.
##
## Friendly attack (collision layer 6) that monitors enemy hurtboxes (layer 5).
## Colour ownership (master guide §2): violet body with a bright core. Never red.

signal expired(projectile: FocusProjectile)
## A real hit, at the point of contact. The presentation layer turns this into
## an impact burst and the staff_impact sound; expiring by lifetime stays
## silent on purpose (a shot fading over empty ground is not an event).
signal impacted(at: Vector3)
signal hit_target(target: Node3D, damage: int, was_critical: bool)

const FRIENDLY_ATTACK_LAYER := 1 << 5  # layer 6
const ENEMY_HURTBOX_MASK := 1 << 4     # layer 5
const HOSTILE_ATTACK_LAYER := 1 << 6   # layer 7
const PLAYER_HURTBOX_MASK := 1 << 3    # layer 4

## Which group this projectile damages. Set by the pool: friendly pools hit
## "enemies", hostile pools hit "player". Everything else about the projectile
## is identical, so both share one scene and one pool implementation.
var hits_group: StringName = &"enemies"

var speed := 16.0
var lifetime := 1.1
var damage := 12
var was_critical := false
var pierce_remaining := 0

var _direction := Vector3.FORWARD
var _life_left := 0.0
var _active := false
var _trail: GPUParticles3D
var _hit_this_flight: Array[Node3D] = []


## Switches this projectile to the hostile side. Called by the pool at build
## time, never mid-flight.
func make_hostile() -> void:
	collision_layer = HOSTILE_ATTACK_LAYER
	collision_mask = PLAYER_HURTBOX_MASK
	hits_group = &"player"
	_hostile_visual = true
	_apply_side_visual()


## Colour ownership on the shared scene: the friendly staff bolt is violet, and
## the SAME scene fired from a hostile pool must be warm — a violet enemy shot
## is exactly the confusion guide §4 forbids. Called from make_hostile (pool
## build time) and again from _ready, whichever runs first.
var _hostile_visual := false

func _apply_side_visual() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and _hostile_visual:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.82, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.15)
		mat.emission_energy_multiplier = 2.4
		mesh.set_surface_override_material(0, mat)
	if _trail != null and _hostile_visual:
		var ppm := _trail.process_material as ParticleProcessMaterial
		if ppm != null:
			var ramp := Gradient.new()
			ramp.set_color(0, Color(1.0, 0.9, 0.7, 1.0))
			ramp.set_color(1, Color(0.95, 0.4, 0.1, 0.0))
			var tex := GradientTexture1D.new()
			tex.gradient = ramp
			ppm = ppm.duplicate()
			ppm.color_ramp = tex
			_trail.process_material = ppm


func _ready() -> void:
	add_to_group("projectiles")
	if collision_layer == 0:
		collision_layer = FRIENDLY_ATTACK_LAYER
		collision_mask = ENEMY_HURTBOX_MASK
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	_trail = get_node_or_null("Trail") as GPUParticles3D
	if _trail != null and _trail.draw_pass_1 == null:
		# The spark quad is built here rather than saved in the scene: a
		# QuadMesh with an additive unshaded material, same recipe as
		# ParticleFx. Kept in code so the scene diff stays readable.
		var quad := QuadMesh.new()
		quad.size = Vector2(0.08, 0.08)
		var qmat := StandardMaterial3D.new()
		qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qmat.vertex_color_use_as_albedo = true
		quad.material = qmat
		_trail.draw_pass_1 = quad
	_apply_side_visual()
	_deactivate()


## Convenience launch for the Focus Weapon, which carries its values on a
## FocusWeaponData resource.
func launch(from: Vector3, direction: Vector3, weapon: FocusWeaponData, rolled_damage: int, critical: bool) -> void:
	launch_raw(
		from,
		direction,
		weapon.projectile_speed_units_per_second,
		weapon.projectile_lifetime_seconds,
		rolled_damage,
		critical,
		weapon.pierce_count
	)


## Explicit-parameter launch. Summon species carry their projectile values on
## their own behaviour rather than a FocusWeaponData, so they use this directly
## and share the same pool.
func launch_raw(from: Vector3, direction: Vector3, projectile_speed: float, projectile_lifetime: float, projectile_damage: int, critical: bool, pierce: int) -> void:
	global_position = from
	_direction = direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD
	speed = projectile_speed
	lifetime = projectile_lifetime
	damage = projectile_damage
	was_critical = critical
	pierce_remaining = pierce

	_life_left = lifetime
	_hit_this_flight.clear()
	_activate()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	global_position += _direction * speed * delta
	_life_left -= delta
	if _life_left <= 0.0:
		expire()


## Returns the projectile to the pool. Safe to call more than once.
func expire() -> void:
	if not _active:
		return
	_deactivate()
	expired.emit(self)


func is_active() -> bool:
	return _active


## `monitoring` cannot be assigned directly while an area_entered/body_entered
## signal is being emitted — Godot blocks it and the write is silently dropped,
## leaving an expired projectile still monitoring. Always defer it.
func _activate() -> void:
	_active = true
	if _trail != null:
		_trail.emitting = true
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _deactivate() -> void:
	_active = false
	visible = false
	if _trail != null:
		_trail.emitting = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	global_position = Vector3(0.0, -1000.0, 0.0)


func _on_area_entered(area: Area3D) -> void:
	_try_hit(area.get_parent() as Node3D)


func _on_body_entered(body: Node3D) -> void:
	_try_hit(body)


func _try_hit(target: Node3D) -> void:
	if not _active or target == null or not is_instance_valid(target):
		return
	if _hit_this_flight.has(target):
		return
	if not target.is_in_group(hits_group):
		return

	_hit_this_flight.append(target)
	# Pass the impact point so directional defences (the Bellguard shield) can
	# tell a frontal hit from one landing in its back.
	CombatDamage.apply(target, damage, global_position)
	hit_target.emit(target, damage, was_critical)
	impacted.emit(global_position)

	if pierce_remaining > 0:
		pierce_remaining -= 1
	else:
		expire()
