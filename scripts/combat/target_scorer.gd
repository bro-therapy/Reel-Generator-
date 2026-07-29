class_name TargetScorer
extends RefCounted

## The shared target-selection contract (master guide §16).
##
##     score = distance_weight
##           + threat_weight
##           + facing_weight
##           + damaged_target_weight
##           + rally_bonus
##           - blocked_penalty
##
## The Focus Weapon and every summon species score through this class. Species
## may add their own distance/facing terms, but the weights below are shared so
## that Rally always wins and priority reads consistently across the team.

const RALLY_BONUS := 1000.0
const BOSS_BONUS := 80.0
const SPAWNER_OR_HEXER_BONUS := 50.0
const ELITE_BONUS := 40.0
const STICKINESS_BONUS := 20.0
const DISTANCE_PENALTY_PER_UNIT := -2.0
const BEHIND_AIM_PENALTY := -25.0
const BEHIND_AIM_DEGREES := 60.0
const BLOCKED_PENALTY := 60.0

## Threat classes a target may report from `threat_class()`.
const THREAT_NORMAL := &"normal"
const THREAT_SPAWNER := &"spawner"
const THREAT_HEXER := &"hexer"
const THREAT_ELITE := &"elite"
const THREAT_BOSS := &"boss"

## A node is targetable when it is in the "enemies" group, still inside the
## tree, visible, and reports itself alive. Anything that fails is skipped —
## this is what keeps dead, despawned, and hidden enemies from being selected.
static func is_targetable(node: Object) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node3D):
		return false
	var n := node as Node3D
	if not n.is_inside_tree():
		return false
	if n.is_queued_for_deletion():
		return false
	if not n.is_visible_in_tree():
		return false
	if not n.is_in_group("enemies"):
		return false
	if n.has_method("is_targetable"):
		return bool(n.call("is_targetable"))
	if n.has_method("is_alive"):
		return bool(n.call("is_alive"))
	return true


static func target_point(node: Node3D) -> Vector3:
	if node.has_method("target_point"):
		return node.call("target_point") as Vector3
	return node.global_position


static func threat_class(node: Node3D) -> StringName:
	if node.has_method("threat_class"):
		return node.call("threat_class") as StringName
	return THREAT_NORMAL


static func threat_weight(node: Node3D) -> float:
	match threat_class(node):
		THREAT_BOSS:
			return BOSS_BONUS
		THREAT_SPAWNER, THREAT_HEXER:
			return SPAWNER_OR_HEXER_BONUS
		THREAT_ELITE:
			return ELITE_BONUS
		_:
			return 0.0


## Scores one candidate. `preferred_aim` may be zero, which simply drops the
## facing term — that is the no-aim promise: not aiming costs priority nuance,
## never the ability to fire.
static func score(
	candidate: Node3D,
	origin: Vector3,
	preferred_aim: Vector3,
	current_target: Node3D = null,
	rally_target: Node3D = null,
	blocked: bool = false
) -> float:
	var point := target_point(candidate)
	var to_target := point - origin
	var distance := to_target.length()

	var total := distance * DISTANCE_PENALTY_PER_UNIT
	total += threat_weight(candidate)

	if rally_target != null and candidate == rally_target:
		total += RALLY_BONUS

	if current_target != null and candidate == current_target:
		total += STICKINESS_BONUS

	if preferred_aim.length_squared() > 0.0001 and distance > 0.0001:
		var flat_aim := Vector3(preferred_aim.x, 0.0, preferred_aim.z).normalized()
		var flat_to := Vector3(to_target.x, 0.0, to_target.z).normalized()
		if flat_aim.length_squared() > 0.0001 and flat_to.length_squared() > 0.0001:
			var degrees := rad_to_deg(flat_aim.angle_to(flat_to))
			if degrees > BEHIND_AIM_DEGREES:
				total += BEHIND_AIM_PENALTY

	if blocked:
		total -= BLOCKED_PENALTY

	return total


## Picks the highest-scoring valid target within `range_units`, or null.
static func pick_best(
	candidates: Array,
	origin: Vector3,
	preferred_aim: Vector3,
	range_units: float,
	current_target: Node3D = null,
	rally_target: Node3D = null
) -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	var range_squared := range_units * range_units

	for candidate in candidates:
		if not is_targetable(candidate):
			continue
		var node := candidate as Node3D
		if origin.distance_squared_to(target_point(node)) > range_squared:
			continue
		var s := score(node, origin, preferred_aim, current_target, rally_target)
		if s > best_score:
			best_score = s
			best = node

	return best
