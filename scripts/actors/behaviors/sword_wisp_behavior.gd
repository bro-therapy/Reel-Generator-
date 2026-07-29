class_name SwordWispBehavior
extends SummonBehavior

## Sword Wisp — orbit, lunge, slice, return (brief Phase 4, guide §5).
##
## Signature read: the wisp never sits still. It circles the hero continuously,
## so even in a crowded fight the constant angular motion identifies it. The
## orbit is what the acceptance check measures.

## Radians per second around the hero while following.
const ORBIT_SPEED := 1.9
## Fraction of reach the lunge closes to.
const LUNGE_CLOSE := 0.4

var _angle := 0.0
var _orbit_radius := 1.4
var _orbit_height := 1.6
var _lunge_to := Vector3.ZERO
var _return_to := Vector3.ZERO


func setup(owner_summon: SummonBase) -> void:
	super.setup(owner_summon)
	# Derive the orbit from the authored lane so the species stays data-driven.
	var lane: Vector3 = owner_summon.data.lane_offset
	_orbit_radius = maxf(0.8, Vector2(lane.x, lane.z).length())
	_orbit_height = lane.y
	_angle = atan2(lane.z, lane.x)


func signature() -> String:
	return "orbit lunge return"


## Circles the hero rather than holding a fixed lane point.
func follow_target(_lane: Vector3, delta: float) -> Vector3:
	_angle = wrapf(_angle + ORBIT_SPEED * delta, -PI, PI)
	var hero_pos: Vector3 = summon.hero.global_position if summon.hero != null else Vector3.ZERO
	return hero_pos + Vector3(cos(_angle) * _orbit_radius, _orbit_height, sin(_angle) * _orbit_radius)


func on_state_entered(state: int) -> void:
	match state:
		SummonStateMachine.State.WINDUP:
			_return_to = summon.global_position
		SummonStateMachine.State.ATTACK:
			var dir := flat_direction_to_target()
			var contact := target_point() - dir * (summon.form.range_units * LUNGE_CLOSE)
			_lunge_to = Vector3(contact.x, summon.global_position.y, contact.z)


func on_windup(delta: float, _lane: Vector3) -> bool:
	# Tilt toward the target without breaking the orbit.
	_angle = wrapf(_angle + ORBIT_SPEED * 0.35 * delta, -PI, PI)
	return false


func on_attack_tick(delta: float, _lane: Vector3) -> bool:
	var speed: float = summon.data.follow_speed_units_per_second * 2.6
	summon.global_position = summon.global_position.move_toward(_lunge_to, speed * delta)
	return true


func on_recover(delta: float, _lane: Vector3) -> bool:
	# Return along the blade's path back to the orbit.
	var speed: float = summon.data.follow_speed_units_per_second * 2.0
	summon.global_position = summon.global_position.move_toward(_return_to, speed * delta)
	return true


func deliver_attack(target: Node3D, damage: int) -> bool:
	if target != null and target.has_method("take_damage"):
		target.call("take_damage", damage)
	spawn_effect(target_point(), &"friendly_b", 1.1)
	return true
