class_name RuneHoundBehavior
extends SummonBehavior

## Rune Hound — melee lunge (brief Phase 4, guide §5).
##
## Signature read: the hound physically throws itself at the target and snaps
## back. Its identity in heavy combat is translation, not a hit flash — you can
## tell which summon it is purely from the burst of movement.

## Multiplier on follow speed during the lunge itself.
const LUNGE_SPEED_SCALE := 3.4
## How far past the contact point the lunge carries, in units.
const OVERSHOOT := 0.35
## Backward gather during the windup, as a fraction of a unit.
const GATHER := 0.55

var _lunge_to := Vector3.ZERO
var _gather_from := Vector3.ZERO


func signature() -> String:
	return "melee lunge"


func on_state_entered(state: int) -> void:
	match state:
		SummonStateMachine.State.WINDUP:
			# Coil backwards so the lunge reads as a pounce — but the attack
			# commits from wherever the coil ends, and ACQUIRE hands over at the
			# very edge of reach. Coiling freely would push the target out of
			# range and the hit would be silently refused, so clamp it.
			_gather_from = summon.global_position
			_lunge_to = _clamped_gather()
		SummonStateMachine.State.ATTACK:
			var dir := flat_direction_to_target()
			var contact := target_point() - dir * (summon.form.range_units * 0.35)
			_lunge_to = Vector3(contact.x, summon.global_position.y, contact.z) + dir * OVERSHOOT


## The furthest back the hound can coil while still holding the target inside
## 90% of its reach.
func _clamped_gather() -> Vector3:
	var away := -flat_direction_to_target()
	var limit: float = summon.form.range_units * 0.9
	var tp := target_point()
	var candidate := summon.global_position + away * GATHER
	if summon.attack_origin_offset_from(candidate).distance_to(tp) <= limit:
		return candidate
	# Fall back to the largest coil that still fits, down to none at all.
	for fraction in [0.66, 0.33]:
		candidate = summon.global_position + away * (GATHER * fraction)
		if summon.attack_origin_offset_from(candidate).distance_to(tp) <= limit:
			return candidate
	return summon.global_position


func on_windup(delta: float, _lane: Vector3) -> bool:
	summon.global_position = summon.global_position.move_toward(_lunge_to, summon.data.follow_speed_units_per_second * delta)
	return true


func on_attack_tick(delta: float, _lane: Vector3) -> bool:
	var speed: float = summon.data.follow_speed_units_per_second * LUNGE_SPEED_SCALE
	summon.global_position = summon.global_position.move_toward(_lunge_to, speed * delta)
	return true


func deliver_attack(target: Node3D, damage: int) -> bool:
	# Direct melee damage, plus a violet impact on the target.
	CombatDamage.apply(target, damage, summon.attack_origin_position())
	spawn_effect(target_point(), &"friendly_a", 1.0)
	return true
