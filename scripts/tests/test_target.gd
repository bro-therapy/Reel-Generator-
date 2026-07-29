extends Node3D

## TEST SCAFFOLDING ONLY — not an enemy.
##
## Implements the minimum targeting contract so Phase 2 can be verified before
## EnemyBase exists in Phase 5. Delete once real enemies land; the contract it
## implements (group "enemies" + is_targetable/target_point/threat_class/
## take_damage) is what EnemyBase must provide.

@export var threat: StringName = &"normal"
@export var hp: int = 1000
@export var target_height: float = 0.9

var damage_taken_total := 0
var hit_count := 0

var _alive := true


func _ready() -> void:
	add_to_group("enemies")


func is_targetable() -> bool:
	return _alive


func is_alive() -> bool:
	return _alive


func target_point() -> Vector3:
	return global_position + Vector3(0.0, target_height, 0.0)


func threat_class() -> StringName:
	return threat


func take_damage(amount: int) -> void:
	if not _alive:
		return
	damage_taken_total += amount
	hit_count += 1
	hp -= amount
	if hp <= 0:
		kill()


func kill() -> void:
	_alive = false
