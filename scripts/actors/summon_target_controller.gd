class_name SummonTargetController
extends Node

## Target selection for one summon.
##
## Scores through the shared TargetScorer contract (master guide §16), the same
## one the Focus Weapon uses, so Rally priority reads identically across the
## whole team. Species may tune range; they never get their own weights.

signal target_changed(to: Node3D, from: Node3D)

@export var refresh_seconds := 0.20

var current_target: Node3D = null
var rally_target: Node3D = null
var range_units := 3.0
## Zero unless the owning summon is given an aim preference. Summons inherit the
## hero's preferred aim in later phases; Phase 3 leaves it neutral.
var preferred_aim := Vector3.ZERO

var _cooldown := 0.0
var _refreshes := 0


func _ready() -> void:
	# Stagger the first refresh so three summons do not rescore on the same tick.
	_cooldown = randf() * refresh_seconds


## Returns true when a refresh actually ran this tick.
func tick(delta: float, origin: Vector3) -> bool:
	_cooldown -= delta
	if _cooldown > 0.0:
		return false
	_cooldown = refresh_seconds
	refresh(origin)
	return true


func refresh(origin: Vector3) -> void:
	_refreshes += 1
	var previous := current_target

	# Drop an invalid target before scoring so stickiness cannot resurrect it.
	if not TargetScorer.is_targetable(current_target):
		current_target = null

	var tree := get_tree()
	var candidates: Array = tree.get_nodes_in_group("enemies") if tree != null else []

	current_target = TargetScorer.pick_best(
		candidates,
		origin,
		preferred_aim,
		range_units,
		current_target,
		rally_target
	)

	if current_target != previous:
		target_changed.emit(current_target, previous)


func has_valid_target() -> bool:
	return TargetScorer.is_targetable(current_target)


func clear() -> void:
	var previous := current_target
	current_target = null
	if previous != null:
		target_changed.emit(null, previous)


func refresh_count() -> int:
	return _refreshes
