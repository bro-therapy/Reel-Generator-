class_name SummonBehavior
extends Node

## Base class for the three starter species behaviours (build brief Phase 4).
##
## Phase 3 established one generic SummonBase driving the shared state cycle.
## A behaviour customises *how* each state looks and feels without touching the
## state graph, so all three species stay on one base scene.
##
## Hooks return `true` when they have handled movement for the frame, which tells
## SummonBase to skip its default lane steering.

## Set by SummonBase before any hook fires.
var summon: SummonBase


func setup(owner_summon: SummonBase) -> void:
	summon = owner_summon


## Human-readable signature, used in debug output and the acceptance report.
func signature() -> String:
	return "generic"


## Where the summon wants to sit while idling near the hero. Default is the lane.
func follow_target(lane: Vector3, _delta: float) -> Vector3:
	return lane


## True when this species holds still to attack rather than closing distance.
## A planted species skips the approach step entirely.
func plants_to_attack() -> bool:
	return false


## Called every physics tick while in WINDUP. Return true if movement handled.
func on_windup(_delta: float, _lane: Vector3) -> bool:
	return false


## Called every physics tick while in ATTACK. Return true if movement handled.
func on_attack_tick(_delta: float, _lane: Vector3) -> bool:
	return false


## Called every physics tick while in RECOVER. Return true if movement handled.
func on_recover(_delta: float, _lane: Vector3) -> bool:
	return false


## The damage delivery itself. Return true when the behaviour has dealt with
## the hit (e.g. spawned a projectile); false to let SummonBase apply direct
## damage. Runs once per attack, on entering ATTACK.
func deliver_attack(_target: Node3D, _damage: int) -> bool:
	return false


## Called once when a state is entered, for one-shot setup.
func on_state_entered(_state: int) -> void:
	pass


# ---------------------------------------------------------------- helpers

func target_point() -> Vector3:
	var t := summon.current_target()
	if t == null:
		return summon.global_position
	return TargetScorer.target_point(t)


func flat_direction_to_target() -> Vector3:
	var to := target_point() - summon.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else Vector3.FORWARD


func spawn_effect(position: Vector3, row: StringName = &"friendly_a", scale_units: float = 1.0) -> void:
	summon.spawn_effect(position, row, scale_units)
