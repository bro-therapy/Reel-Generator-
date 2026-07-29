class_name WardLayout
extends RefCounted

## The spatial structure of Sunfall Ward.
##
## `PZC_Sunfall_Ward_Route_Map_v1.svg` is a flow diagram, not a floorplan — it
## fixes the topology (which space leads where, what is optional) and leaves the
## geometry open. This holds the geometry; the topology below matches the map
## arrow for arrow.
##
## Encounter content is NOT here. Waves and rewards come from
## LEVEL1_BALANCE.json via EncounterData, keyed by the same ids, so balance stays
## in one place and this file only says where the rooms are.
##
##     arrival -> combat_a -> spirit_well -> combat_b -> boss
##                    \                        /
##                     -> optional_rift ------
##
## Units are metres, matching the rest of the project: the hero is 1.8 u tall and
## runs at 6.2 u/s, so a 30 u combat floor is about five seconds corner to corner.

enum Kind { TRAVEL, COMBAT, RIFT, SERVICE, BOSS }

## Wall height. Guide §12 pulls the camera back 10–15% for the boss, so walls
## have to stay tall enough to fill frame at the widest framing.
const WALL_HEIGHT := 7.0
const WALL_THICKNESS := 1.0
## Corridors are wide enough that three summons in lane can follow the hero
## through without shoving each other into a wall.
const CORRIDOR_WIDTH := 10.0

## Radius around a combat centre that stays clear of props. Guide §9 calls for
## "broad clean combat floors" and pushes props to the edges.
const CLEAR_RADIUS := 9.0


## One room. `size` is the floor extent on X and Z; boss rooms are circular and
## use size.x as the diameter.
class Space:
	var id: StringName
	var kind: Kind
	var centre: Vector3
	var size: Vector2
	var label: String

	func _init(p_id: StringName, p_kind: Kind, p_centre: Vector3, p_size: Vector2, p_label: String) -> void:
		id = p_id
		kind = p_kind
		centre = p_centre
		size = p_size
		label = p_label

	func is_round() -> bool:
		return kind == Kind.BOSS

	func radius() -> float:
		return size.x * 0.5


## A walkable link between two spaces. `optional` marks the Rift detour, which
## the route map draws in violet and off the main line.
class Link:
	var from: StringName
	var to: StringName
	var optional: bool
	var gated: bool

	func _init(p_from: StringName, p_to: StringName, p_optional := false, p_gated := false) -> void:
		from = p_from
		to = p_to
		optional = p_optional
		gated = p_gated


static func spaces() -> Array:
	return [
		Space.new(&"arrival", Kind.TRAVEL, Vector3(0, 0, 0), Vector2(26, 18), "Arrival Path"),
		Space.new(&"combat_a", Kind.COMBAT, Vector3(46, 0, 0), Vector2(32, 32), "Combat Zone A"),
		# The Rift sits off the spine on +Z so it is visibly a detour rather than
		# a room the main path passes through.
		Space.new(&"optional_rift", Kind.RIFT, Vector3(46, 0, -46), Vector2(28, 28), "Rift"),
		Space.new(&"spirit_well", Kind.SERVICE, Vector3(94, 0, 0), Vector2(24, 24), "Spirit Well"),
		Space.new(&"combat_b", Kind.COMBAT, Vector3(142, 0, 0), Vector2(36, 36), "Combat Zone B"),
		Space.new(&"boss", Kind.BOSS, Vector3(196, 0, 0), Vector2(44, 44), "The First Bell"),
	]


static func links() -> Array:
	return [
		Link.new(&"arrival", &"combat_a"),
		Link.new(&"combat_a", &"spirit_well"),
		# Route map: Combat A -> Optional Rift -> Rift Return -> Spirit Well.
		# The return leg is the shortcut gate, so it is one-way in the fiction
		# and modelled here as a second, optional way into the Spirit Well.
		Link.new(&"combat_a", &"optional_rift", true, true),
		Link.new(&"optional_rift", &"spirit_well", true, true),
		Link.new(&"spirit_well", &"combat_b"),
		# Guide §9: Combat B's reward is the boss gate key.
		Link.new(&"combat_b", &"boss", false, true),
	]


## Spaces the player must pass through, in order. The Rift is deliberately absent.
static func critical_path() -> Array[StringName]:
	return [&"arrival", &"combat_a", &"spirit_well", &"combat_b", &"boss"]


static func space(id: StringName) -> Space:
	for s in spaces():
		if s.id == id:
			return s
	return null


## Encounter ids this layout expects to find in LEVEL1_BALANCE.json. Every space
## except the Spirit Well runs an encounter; the well is a service room.
static func encounter_ids() -> Array[StringName]:
	return [&"arrival", &"combat_a", &"optional_rift", &"combat_b", &"boss"]
