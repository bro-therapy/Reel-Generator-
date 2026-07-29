class_name RoomEntryTrigger
extends Area3D

## Fires the room's encounter the first time the player crosses it.
##
## The gate stays open until this reports an entry, which is the whole reason
## the trigger exists rather than the room activating itself on _ready.

@export var encounter_path: NodePath

var _fired := false


func _ready() -> void:
	# Layer 10 CameraTrigger; watches the player body on layer 2.
	collision_layer = 1 << 9
	collision_mask = 1 << 1
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _fired or not body.is_in_group("player"):
		return
	notify_entered(body)


## Direct entry point, used by tests and by scripted room transitions.
func notify_entered(body: Node3D) -> void:
	if _fired:
		return
	_fired = true
	var controller := get_node_or_null(encounter_path) as EncounterController
	if controller != null:
		controller.on_player_entered(body)
