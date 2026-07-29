class_name FocusWeaponController
extends Node3D

## The one Focus Weapon. Phase 2.
##
## Auto-targets and auto-fires on its own. Optional aim input rotates the
## preferred direction, which reweights priority through TargetScorer — it never
## gates firing. That is the no-aim promise (master guide §3), and it is why
## `_fire_if_ready()` does not consult aim state at all.

signal fired(target: Node3D, damage: int, was_critical: bool)
signal target_changed(new_target: Node3D, previous: Node3D)

@export var weapon: FocusWeaponData
@export var muzzle_path: NodePath
@export var pool_path: NodePath

## Optional. When unset the controller scans the "enemies" group directly.
@export var use_group_scan := true

var current_target: Node3D = null
var rally_target: Node3D = null
var preferred_aim := Vector3.ZERO

var shots_fired := 0

var _cooldown := 0.0
var _refresh := 0.0
var _muzzle: Node3D
var _pool: ProjectilePool
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if weapon == null:
		weapon = FocusWeaponData.new()
	weapon.apply_balance()
	_rng.randomize()

	_muzzle = get_node_or_null(muzzle_path) as Node3D
	_pool = get_node_or_null(pool_path) as ProjectilePool

	# Fire on the first frame a target exists rather than after a full interval.
	_cooldown = 0.0
	_refresh = 0.0


func _physics_process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = weapon.target_refresh_seconds
		refresh_target()

	_cooldown -= delta
	_fire_if_ready()


# ---------------------------------------------------------------- targeting

func refresh_target() -> void:
	var previous := current_target

	# Drop an invalid target before scoring so stickiness cannot resurrect it.
	if not TargetScorer.is_targetable(current_target):
		current_target = null

	var candidates := _candidates()
	var best := TargetScorer.pick_best(
		candidates,
		_origin(),
		preferred_aim,
		weapon.range_units,
		current_target,
		rally_target
	)
	current_target = best

	if current_target != previous:
		target_changed.emit(current_target, previous)


func _candidates() -> Array:
	if not use_group_scan:
		return []
	var tree := get_tree()
	if tree == null:
		return []
	return tree.get_nodes_in_group("enemies")


func _origin() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position


## Sets the preferred aim direction. Zero clears it, restoring pure proximity
## and threat ordering.
func set_preferred_aim(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	preferred_aim = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO


func has_aim_input() -> bool:
	return preferred_aim.length_squared() > 0.0001


# ---------------------------------------------------------------- firing

## Auto-fire. Deliberately independent of aim state and of the manual fire
## action — holding manual fire adds nothing because auto-fire is always on.
func _fire_if_ready() -> void:
	if _cooldown > 0.0:
		return
	if not TargetScorer.is_targetable(current_target):
		return
	fire_at(current_target)
	_cooldown = weapon.attack_interval_seconds


func fire_at(target: Node3D) -> bool:
	if _pool == null or target == null:
		return false

	var projectile := _pool.acquire()
	if projectile == null:
		return false

	var origin := _origin()
	var aim_point := TargetScorer.target_point(target)
	var direction := aim_point - origin
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD

	var roll := weapon.roll_damage(_rng)
	var dmg := int(roll[0])
	var crit := bool(roll[1])

	projectile.launch(origin, direction, weapon, dmg, crit)
	shots_fired += 1
	fired.emit(target, dmg, crit)
	return true


func cooldown_remaining() -> float:
	return maxf(0.0, _cooldown)


## Test seam so acceptance runs are not at the mercy of a critical roll.
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value
