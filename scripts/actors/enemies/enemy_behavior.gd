class_name EnemyBehavior
extends Node

## Base class for the six Level 1 enemy roles (build brief Phase 5).
##
## EnemyBase owns the state graph and the telegraph gate; a role customises what
## happens inside each state. Hooks return true when they have fully handled the
## state for the frame.

var enemy: EnemyBase


func setup(owner_enemy: EnemyBase) -> void:
	enemy = owner_enemy


func role_name() -> String:
	return "generic"


func on_seek(_delta: float) -> bool:
	return false


func windup_seconds(default_seconds: float) -> float:
	return default_seconds


func on_windup_started() -> void:
	pass


func on_windup(_delta: float) -> bool:
	return false


func on_attack(_delta: float) -> bool:
	return false


func on_recover(_delta: float) -> bool:
	return false


## Return true when the role delivered its own damage (a projectile, a spawn,
## a tether) so EnemyBase does not also apply a melee hit.
func deliver_attack() -> bool:
	return false


## Directional or state-based damage reduction. `from_position` may be null.
func modify_incoming_damage(amount: float, _from_position: Variant) -> float:
	return amount
