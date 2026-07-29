class_name GateController
extends Node3D

## Room gates. Open by default — the brief is explicit that gates lock only
## after the player enters, so a room the player has not reached must never be
## sealed.

signal locked()
signal unlocked()

@export var gate_meshes: Array[NodePath] = []

var is_locked := false
var lock_count := 0
var unlock_count := 0


func _ready() -> void:
	add_to_group("gates")
	set_locked(false)


func set_locked(value: bool) -> void:
	if is_locked == value:
		return
	is_locked = value
	if value:
		lock_count += 1
		locked.emit()
	else:
		unlock_count += 1
		unlocked.emit()
	_apply()


func _apply() -> void:
	for path in gate_meshes:
		var n := get_node_or_null(path)
		if n is Node3D:
			(n as Node3D).visible = is_locked
		if n is CollisionObject3D:
			# Layer 9 NavigationBlocker while sealed.
			(n as CollisionObject3D).collision_layer = (1 << 8) if is_locked else 0
