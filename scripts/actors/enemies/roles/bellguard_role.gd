class_name BellguardRole
extends EnemyBehavior

## Tank and space-maker (guide §10). Its shield halves damage taken from the
## front, and a slam that misses leaves its back exposed.

const FRONTAL_REDUCTION := 0.5
## Beyond this angle from the Bellguard's facing, a hit counts as coming from
## behind and the shield does not apply.
const SHIELD_ARC_DEGREES := 90.0
const EXPOSED_MULTIPLIER := 2.0
const EXPOSED_SECONDS := 1.6

var _slam_connected := false
var _exposed_left := 0.0


func role_name() -> String:
	return "tank"


func _process(delta: float) -> void:
	if _exposed_left > 0.0:
		_exposed_left -= delta
		if _exposed_left <= 0.0:
			enemy.vulnerability_multiplier = 1.0


func on_windup_started() -> void:
	_slam_connected = false


## A slam that lands nothing leaves the guard over-committed and open.
func on_recover(_delta: float) -> bool:
	if not _slam_connected and _exposed_left <= 0.0:
		expose()
	return false


func deliver_attack() -> bool:
	# Let EnemyBase resolve the hit, but record whether it connected so recovery
	# knows if the slam whiffed.
	_slam_connected = _target_in_wedge()
	return false


func _target_in_wedge() -> bool:
	if enemy.target == null or not is_instance_valid(enemy.target):
		return false
	var to := enemy.target.global_position - enemy.global_position
	to.y = 0.0
	return to.length() <= enemy.data.attack_range_units * 1.35


func expose() -> void:
	_exposed_left = EXPOSED_SECONDS
	enemy.vulnerability_multiplier = EXPOSED_MULTIPLIER


func is_exposed() -> bool:
	return _exposed_left > 0.0


## Halves damage arriving inside the shield arc. A hit from behind, or one with
## no known origin, takes full damage.
func modify_incoming_damage(amount: float, from_position: Variant) -> float:
	if _exposed_left > 0.0:
		return amount
	if from_position == null or typeof(from_position) != TYPE_VECTOR3:
		return amount
	var origin: Vector3 = from_position
	var to_attacker := origin - enemy.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() <= 0.0001:
		return amount
	var facing := enemy.facing_target()
	var degrees := rad_to_deg(facing.angle_to(to_attacker.normalized()))
	if degrees <= SHIELD_ARC_DEGREES:
		return amount * FRONTAL_REDUCTION
	return amount
