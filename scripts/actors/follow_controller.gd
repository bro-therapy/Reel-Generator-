class_name FollowController
extends Node

## Keeps a summon in its lane around the hero (master guide §4).
##
## Simple steering, never pathfinding: the brief is explicit that a separated
## summon reforms rather than routing across the room, so this only ever moves
## toward a lane point and reports when it has fallen too far behind.

@export var lane_offset := Vector3(-1.3, 0.0, 1.5)
@export var speed_units_per_second := 9.5
@export var lane_tolerance_units := 0.25
## Smoothing on the hero's facing basis so summons swing rather than snap when
## the hero spins.
@export var basis_smoothing := 8.0

var _smoothed_forward := Vector3.FORWARD


func reset_basis(forward: Vector3) -> void:
	_smoothed_forward = _flatten(forward)


## Lane point in world space for the given hero transform.
func lane_position(hero_position: Vector3, hero_forward: Vector3) -> Vector3:
	var forward := _flatten(hero_forward)
	var right := Vector3(forward.z, 0.0, -forward.x)
	return hero_position \
		+ right * lane_offset.x \
		+ Vector3.UP * lane_offset.y \
		+ forward * lane_offset.z


## Advances the smoothed facing basis. Call once per physics tick before
## lane_position() so the lane trails the hero instead of snapping.
func update_basis(hero_forward: Vector3, delta: float) -> Vector3:
	var target := _flatten(hero_forward)
	if target.length_squared() > 0.0001:
		var t := clampf(basis_smoothing * delta, 0.0, 1.0)
		_smoothed_forward = _flatten(_smoothed_forward.lerp(target, t))
	return _smoothed_forward


func smoothed_forward() -> Vector3:
	return _smoothed_forward


## Steers `current` toward `lane` and returns the new position. Never overshoots.
##
## Exponential approach, not move_toward-with-a-deadzone. The old version was
## bang-bang: outside a 0.25 u tolerance it ran at the full 9.5 u/s, inside it
## returned `current` unchanged — a dead stop. Since the hero's top speed
## (6.2 u/s) is below the follow speed, a moving hero put the summon into a
## per-frame cycle of overshoot-into-the-deadzone, stop, fall behind, sprint —
## which is exactly the hard shaking that was reported.
##
## Here the step is proportional to the distance remaining, so it eases in and
## has no discontinuity to oscillate across. `1 - exp(-rate * delta)` rather
## than `rate * delta` keeps it identical at any framerate. The speed clamp
## still applies, so a summon far out of position closes at a bounded rate
## instead of teleporting.
@export var approach_rate := 12.0

func steer(current: Vector3, lane: Vector3, delta: float) -> Vector3:
	var to_lane := lane - current
	var distance := to_lane.length()
	if distance <= 0.0005:
		return current
	var step := to_lane * clampf(1.0 - exp(-approach_rate * delta), 0.0, 1.0)
	var max_step := speed_units_per_second * delta
	if step.length() > max_step:
		step = to_lane / distance * max_step
	return current + step


func is_in_lane(current: Vector3, lane: Vector3) -> bool:
	return current.distance_to(lane) <= lane_tolerance_units


static func _flatten(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
