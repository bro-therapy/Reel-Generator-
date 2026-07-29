class_name SiphonEyeRole
extends EnemyBehavior

## Leech and debuffer (guide §10). Attaches a red tether that drains over time.
## The tether breaks when the target moves eight units away, when it is dashed
## through, or when the Eye dies.

var tether_break_distance := 8.0
var damage_per_second := 4.0

var tethered_to: Node3D = null
var tether_breaks := 0
var drain_applied := 0.0

var _drain_carry := 0.0


func role_name() -> String:
	return "leech"


func setup(owner_enemy: EnemyBase) -> void:
	super.setup(owner_enemy)
	tether_break_distance = float(Balance.get_value("enemies/siphon_eye/tether_break_distance", 8.0))
	damage_per_second = float(Balance.get_value("enemies/siphon_eye/damage_per_second", 4.0))


func on_seek(delta: float) -> bool:
	if enemy.target == null or not is_instance_valid(enemy.target):
		enemy.velocity = Vector3.ZERO
		break_tether()
		return true

	var to := enemy.target.global_position - enemy.global_position
	to.y = 0.0
	var distance := to.length()

	if tethered_to != null:
		_tick_tether(delta, distance)
	elif distance <= tether_break_distance * 0.75:
		attach_tether(enemy.target)
	else:
		enemy.velocity = to.normalized() * enemy.data.speed_units_per_second
		return true

	# Holds station while draining rather than closing.
	enemy.velocity = enemy.velocity.move_toward(Vector3.ZERO, enemy.data.speed_units_per_second * 4.0 * delta)
	return true


func attach_tether(to: Node3D) -> void:
	tethered_to = to
	_drain_carry = 0.0
	# The tether is the damaging effect, so it is what gets telegraphed.
	enemy.telegraph().show_telegraph(&"line", 0.4, tether_break_distance * 0.5)


## Drains while attached, and snaps the moment the target passes the break
## distance. The check uses the balance value directly, never a local copy.
func _tick_tether(delta: float, distance: float) -> void:
	if distance > tether_break_distance:
		break_tether()
		return
	_drain_carry += damage_per_second * delta
	while _drain_carry >= 1.0:
		_drain_carry -= 1.0
		drain_applied += 1.0
		CombatDamage.apply(tethered_to, 1, enemy.global_position)


func break_tether() -> void:
	if tethered_to == null:
		return
	tethered_to = null
	_drain_carry = 0.0
	tether_breaks += 1
	enemy.telegraph().cancel()


func is_tethered() -> bool:
	return tethered_to != null and is_instance_valid(tethered_to)


## The Eye's damage is the drain, delivered per tick rather than as a strike.
func deliver_attack() -> bool:
	return true
