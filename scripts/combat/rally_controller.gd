class_name RallyController
extends Node

## The Rally mark. Guide §4 and brief Phase 12.
##
##   - six-second mark
##   - four-second cooldown
##   - shared priority: every summon reads the same mark
##   - +15% summon damage against the marked target
##
## "Shared priority" is why this is one controller rather than a field on each
## summon: the whole point of the mark is that the team converges on it, and
## three private copies would drift apart the moment one summon reformed.

signal marked(target: Node3D, seconds: float)
signal cleared(reason: StringName)

var target: Node3D = null
var time_left := 0.0
var cooldown_left := 0.0

var _duration := 6.0
var _cooldown := 4.0
var _damage_bonus := 0.15


func _ready() -> void:
	var p := Balance.player()
	_duration = float(p.get("rally_mark_duration_seconds", 6.0))
	_cooldown = float(p.get("rally_cooldown_seconds", 4.0))
	_damage_bonus = float(Balance.get_value("summons/global/rally_damage_bonus", 0.15))


func duration() -> float:
	return _duration


func cooldown() -> float:
	return _cooldown


func damage_bonus() -> float:
	return _damage_bonus


func is_ready() -> bool:
	return cooldown_left <= 0.0


func has_target() -> bool:
	return target != null and is_instance_valid(target)


## Places the mark. Refused while on cooldown, which is what stops the player
## from re-marking every frame and pinning the team to a dead target.
func mark(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node) or not is_ready():
		return false
	target = node
	time_left = _duration
	cooldown_left = _cooldown
	marked.emit(target, time_left)
	return true


func clear(reason: StringName = &"manual") -> void:
	if target == null:
		return
	target = null
	time_left = 0.0
	cleared.emit(reason)


func _process(delta: float) -> void:
	tick(delta)


## Explicit so tests can run six seconds in one call.
func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)

	if target == null:
		return

	# A mark on something that has died, been freed, or stopped being a legal
	# target has to go, or every summon in the team keeps steering at a corpse.
	if not _target_is_valid():
		clear(&"invalid")
		return

	time_left -= delta
	if time_left <= 0.0:
		clear(&"expired")


func _target_is_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree():
		return false
	# Anything that can say whether it is still worth attacking gets asked.
	if target.has_method("is_alive") and not target.call("is_alive"):
		return false
	if target.has_method("is_targetable") and not target.call("is_targetable"):
		return false
	return true


## The multiplier a summon should apply to damage against `node`.
func damage_multiplier_for(node: Node3D) -> float:
	if has_target() and node == target:
		return 1.0 + _damage_bonus
	return 1.0
