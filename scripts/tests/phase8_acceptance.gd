extends SceneTree

## Phase 8 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase8_acceptance.gd
##
## The five criteria:
##   - Main path is readable without a minimap.
##   - Optional Rift branch is visible and clearly optional.
##   - Camera cannot see missing world geometry.
##   - Combat centres are uncluttered.
##   - Navigation works across all required rooms.
##
## Topology comes from WardLayout, encounter ids from LEVEL1_BALANCE.json. The
## checks that matter are physical: they raycast the built geometry rather than
## re-reading the layout table, so a builder that silently stops emitting walls
## fails here instead of passing on the strength of its own data.

const WARD_SCENE := "res://scenes/world/sunfall_ward.tscn"
## Guide §15: layer 1 is world geometry.
const WORLD_MASK := 1
## Eye height for the enclosure sweep — above the hero, below the wall top.
const EYE_HEIGHT := 3.0

var _pass := 0
var _fail := 0
var _world: Node3D
var _space_state: PhysicsDirectSpaceState3D
var _stage := -1
var _mark := 0.0


func _initialize() -> void:
	print("\n=== PHASE 8 ACCEPTANCE ===\n")
	_check_topology()
	_check_rift_is_optional()
	_check_encounters_exist()

	var packed := load(WARD_SCENE) as PackedScene
	if packed == null:
		_no("ward scene", "could not load %s" % WARD_SCENE)
		_summary()
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_stage = 0


# ------------------------------------------------------------- static checks

func _check_topology() -> void:
	# Route map: arrival -> combat_a -> spirit_well -> combat_b -> boss, with the
	# Rift hanging off Combat A. Every critical step must be a real link.
	var path := WardLayout.critical_path()
	var missing: Array[String] = []
	for i in path.size() - 1:
		var found := false
		for link in WardLayout.links():
			if link.from == path[i] and link.to == path[i + 1] and not link.optional:
				found = true
		if not found:
			missing.append("%s -> %s" % [path[i], path[i + 1]])
	if missing.is_empty():
		_ok("critical path is connected end to end", " -> ".join(path))
	else:
		_no("critical path", "missing links: " + "; ".join(missing))

	# "Readable without a minimap" starts with there being one way forward.
	# A space with two unmarked exits is a space a player can get lost in.
	var ambiguous: Array[String] = []
	for i in path.size() - 1:
		var forward := 0
		for link in WardLayout.links():
			if link.from == path[i] and not link.optional:
				forward += 1
		if forward > 1:
			ambiguous.append("%s has %d unmarked exits" % [path[i], forward])
	if ambiguous.is_empty():
		_ok("no critical room has an ambiguous exit", "one way on, detours marked")
	else:
		_no("route readability", "; ".join(ambiguous))


func _check_rift_is_optional() -> void:
	var rift_links: Array = []
	for link in WardLayout.links():
		if link.from == &"optional_rift" or link.to == &"optional_rift":
			rift_links.append(link)

	if rift_links.is_empty():
		_no("rift branch", "no links touch optional_rift")
		return

	var unmarked := 0
	for link in rift_links:
		if not link.optional or not link.gated:
			unmarked += 1
	if unmarked == 0:
		_ok("every Rift link is optional and gated", "%d links, all marked" % rift_links.size())
	else:
		_no("rift marking", "%d Rift links are not marked optional+gated" % unmarked)

	# The decisive test of "optional": deleting it must not break the route.
	if not WardLayout.critical_path().has(&"optional_rift"):
		_ok("Rift is off the critical path", "the run completes without entering it")
	else:
		_no("rift optionality", "optional_rift is on the critical path")

	# ...and it must still be reachable, or it is not a branch at all.
	var entrances := 0
	for link in rift_links:
		if link.to == &"optional_rift":
			entrances += 1
	if entrances >= 1:
		_ok("Rift is reachable from the main route", "%d entrance(s)" % entrances)
	else:
		_no("rift reachability", "no link leads into the Rift")


func _check_encounters_exist() -> void:
	# The layout names rooms; the balance file owns what happens in them. If the
	# two drift apart a room becomes empty at runtime, so pin them together.
	var missing: Array[String] = []
	for id in WardLayout.encounter_ids():
		if EncounterData.from_balance(String(id)) == null:
			missing.append(String(id))
	if missing.is_empty():
		_ok("every room's encounter exists in balance", "%d encounters" % WardLayout.encounter_ids().size())
	else:
		_no("encounter wiring", "not in LEVEL1_BALANCE.json: " + ", ".join(missing))


# ------------------------------------------------------------ runtime checks

func _process(delta: float) -> bool:
	match _stage:
		0:
			# One frame for the builder's _ready() and the physics server to settle.
			_mark += delta
			if _mark >= 0.2:
				var vp := root.get_viewport() as Viewport
				_space_state = vp.world_3d.direct_space_state
				_stage = 1
		1:
			_check_enclosure()
			_check_decals_are_flat()
			_check_corridor_corners()
			_stage = 2
		2:
			_check_combat_centres_clear()
			_stage = 3
		3:
			_check_walkable_route()
			_stage = 99
		99:
			_summary()
			return true
	return false


## "Camera cannot see missing world geometry."
##
## Swept as a full circle of rays at eye height from each room centre: if every
## ray lands on world geometry, the room is closed and there is nothing to see
## past. A missing wall segment shows up as a ray that runs to its limit.
func _check_enclosure() -> void:
	var leaks: Array[String] = []
	var rays := 72

	for s in WardLayout.spaces():
		var origin: Vector3 = s.centre + Vector3(0, EYE_HEIGHT, 0)
		# Far enough to cross the widest room and its doorway, short enough that
		# a genuine hole does not accidentally hit the next room along.
		var reach: float = maxf(s.size.x, s.size.y) * 1.5
		var escaped := 0

		for i in rays:
			var a := TAU * float(i) / float(rays)
			var target: Vector3 = origin + Vector3(cos(a), 0.0, sin(a)) * reach
			var query := PhysicsRayQueryParameters3D.create(origin, target)
			query.collision_mask = WORLD_MASK
			query.collide_with_areas = false
			if _space_state.intersect_ray(query).is_empty():
				escaped += 1

		# Doorways are real openings, so a handful of escaping rays is correct.
		# Four doors at 10 u across a 32 u room is well under a fifth of the
		# sweep; a fifth or more means a wall is missing, not a door.
		var budget := int(rays * 0.2)
		if escaped > budget:
			leaks.append("%s: %d/%d rays escaped" % [s.id, escaped, rays])

	if leaks.is_empty():
		_ok("every room is visually enclosed", "%d-ray sweep per room, only doorways open" % rays)
	else:
		_no("enclosure", "; ".join(leaks))


## "Combat centres are uncluttered." Guide §9 wants broad clean combat floors
## with props pushed to the edges.
func _check_combat_centres_clear() -> void:
	var cluttered: Array[String] = []
	for s in WardLayout.spaces():
		if s.kind != WardLayout.Kind.COMBAT:
			continue
		# A cylinder: CLEAR_RADIUS is a radius, and the two shapes this check was
		# first written with both got that wrong. A sphere reached down through
		# the floor; a box tested a square, so it flagged props sitting 12 u out
		# at the corners of a 9 u "radius". A cylinder is a circle in plan and
		# spans only the height a player occupies.
		var shape := CylinderShape3D.new()
		shape.radius = WardLayout.CLEAR_RADIUS
		shape.height = 2.0
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis.IDENTITY, s.centre + Vector3(0, 1.2, 0))
		params.collision_mask = WORLD_MASK
		var hits := _space_state.intersect_shape(params, 8)
		if not hits.is_empty():
			var names: Array[String] = []
			for h in hits:
				var col: Object = h.get("collider")
				var owner_node: Node = (col as Node).get_parent() if col is Node else null
				names.append(owner_node.name if owner_node != null else "?")
			cluttered.append("%s: %s" % [s.id, ", ".join(names)])

	if cluttered.is_empty():
		_ok("combat centres are clear", "%.0f u radius around each, props at the edges" % WardLayout.CLEAR_RADIUS)
	else:
		_no("combat clutter", "; ".join(cluttered))


## "Navigation works across all required rooms."
##
## Walked physically rather than through a navmesh: baking one headless is
## unreliable, and what the criterion actually asks is whether a player can get
## from arrival to the boss. Each step checks there is floor underfoot and no
## wall in the way.
func _check_walkable_route() -> void:
	var path := WardLayout.critical_path()
	var blocked: Array[String] = []
	var steps_walked := 0

	for i in path.size() - 1:
		var a := WardLayout.space(path[i])
		var b := WardLayout.space(path[i + 1])
		if a == null or b == null:
			blocked.append("%s or %s missing" % [path[i], path[i + 1]])
			continue

		# Corridors run axis-aligned, X first where both axes differ, matching
		# how WardBuilder lays them out.
		var waypoints: Array[Vector3] = [a.centre]
		if absf(a.centre.x - b.centre.x) > 0.5 and absf(a.centre.z - b.centre.z) > 0.5:
			waypoints.append(Vector3(b.centre.x, 0.0, a.centre.z))
		waypoints.append(b.centre)

		for w in waypoints.size() - 1:
			var from: Vector3 = waypoints[w]
			var to: Vector3 = waypoints[w + 1]
			var span := from.distance_to(to)
			var steps := maxi(1, int(span / 2.0))
			for step in range(1, steps + 1):
				var p: Vector3 = from.lerp(to, float(step) / float(steps))
				steps_walked += 1

				# Floor underfoot.
				var down := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p + Vector3(0, -3.0, 0))
				down.collision_mask = WORLD_MASK
				if _space_state.intersect_ray(down).is_empty():
					blocked.append("no floor at %s between %s and %s" % [str(p.round()), path[i], path[i + 1]])
					break

				# Nothing standing in the way at hero height.
				var ahead := PhysicsRayQueryParameters3D.create(
					p + Vector3(0, 1.0, 0),
					p.lerp(to, minf(1.0, float(step + 1) / float(steps))) + Vector3(0, 1.0, 0),
				)
				ahead.collision_mask = WORLD_MASK
				var hit := _space_state.intersect_ray(ahead)
				if not hit.is_empty():
					var col: Object = hit.get("collider")
					var owner_node: Node = (col as Node).get_parent() if col is Node else null
					var where: String = owner_node.get_parent().name + "/" + owner_node.name if owner_node != null and owner_node.get_parent() != null else "?"
					var at: Vector3 = hit.get("position", Vector3.ZERO)
					blocked.append("%s at %s blocks near %s" % [where, str(at.round()), str(p.round())])
					break

	if blocked.is_empty():
		_ok("the whole critical route is walkable", "%d probe steps from arrival to boss" % steps_walked)
	else:
		_no("navigation", "; ".join(blocked.slice(0, 3)))


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


## Floor sigils must be FLOOR elements.
##
## A Decal paints everything inside its box. The Spirit Well marker shipped as a
## 4 m tall box centred 1 m above the floor, so it swept the volume the player
## stands in and projected the sigil onto the hero — "like a projector shooting
## over the top of it". Geometry, so it is checkable: the box must not reach the
## height an actor occupies, and must not be allowed to draw on the actor layer.
## A decal box must STRADDLE the floor plane — a box entirely below y=0 paints
## nothing at all — so "top must be at or under 0" is not a usable rule. What
## matters is that the box cannot reach a body: 0.25 m is ankle height on a
## 2 m actor, and the original offender reached 3.0 m.
const MAX_SIGIL_TOP := 0.25


## The ward scene wraps its rooms in a builder node; find whatever holds them.
func _rooms_root() -> Node:
	for child in _world.get_children():
		if child.get_child_count() > 0:
			return child
	return _world


## Corridor corners must be sealed and single-surfaced.
##
## The one L-shaped corridor in this ward produced three separate playtest
## reports from a single cause — overlapping floor boxes flickering, a leg's
## side wall blocking the other leg, and an unwalled outer corner you could walk
## out of. Both halves are geometric, so both are checkable.
func _check_corridor_corners() -> void:
	print("Corridor corners")
	var floors: Array[Vector3] = []
	var overlaps: Array[String] = []
	var corners: Array[Vector3] = []

	for child in _rooms_root().get_children():
		if not String(child.name).begins_with("corridor_"):
			continue
		var boxes: Array[MeshInstance3D] = []
		for node in child.get_children():
			if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
				var m := node as MeshInstance3D
				# Floor slabs sit centred half a unit below y=0.
				if absf(m.position.y + 0.5) < 0.01:
					boxes.append(m)
		# Coplanar floor slabs whose footprints overlap will z-fight.
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a := boxes[i]
				var b := boxes[j]
				var sa: Vector3 = (a.mesh as BoxMesh).size
				var sb: Vector3 = (b.mesh as BoxMesh).size
				var overlap_x: float = minf(a.position.x + sa.x * 0.5, b.position.x + sb.x * 0.5) \
					- maxf(a.position.x - sa.x * 0.5, b.position.x - sb.x * 0.5)
				var overlap_z: float = minf(a.position.z + sa.z * 0.5, b.position.z + sb.z * 0.5) \
					- maxf(a.position.z - sa.z * 0.5, b.position.z - sb.z * 0.5)
				if overlap_x > 0.05 and overlap_z > 0.05:
					overlaps.append("%s: two floors overlap %.1f x %.1f u"
						% [child.name, overlap_x, overlap_z])
		if boxes.size() >= 3:
			corners.append(Vector3.ZERO)

	if overlaps.is_empty():
		_ok("no corridor floor z-fights", "%d corridors, no coplanar overlaps" % _corridor_count())
	else:
		_no("floor overlap", "; ".join(overlaps.slice(0, 3)))

	# And the L corner must be walled on its outer sides. Probe just beyond the
	# outer corner: if a ray from inside escapes to the void, the map is open.
	var rift := WardLayout.space(&"optional_rift")
	var well := WardLayout.space(&"spirit_well")
	if rift == null or well == null:
		return
	var corner := Vector3(well.centre.x, 0.0, rift.centre.z)
	var half := WardLayout.CORRIDOR_WIDTH * 0.5
	var sealed_sides := 0
	var open_sides: Array[String] = []
	for side in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var from: Vector3 = corner + Vector3(0.0, 1.0, 0.0)
		var to: Vector3 = from + side * (half + 2.0)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = WORLD_MASK
		if not _space_state.intersect_ray(query).is_empty():
			sealed_sides += 1
		else:
			open_sides.append("%.0f,%.0f" % [side.x, side.z])

	# Two sides are corridor openings; the other two must be solid.
	if sealed_sides >= 2:
		_ok("the corridor corner is sealed on its outer sides",
			"%d of 4 sides walled, 2 are the openings" % sealed_sides)
	else:
		_no("open corner", "only %d of 4 corner sides are walled (open toward %s) — "
			% [sealed_sides, ", ".join(open_sides)] + "the player can walk off the map")


func _corridor_count() -> int:
	var n := 0
	for child in _rooms_root().get_children():
		if String(child.name).begins_with("corridor_"):
			n += 1
	return n


func _check_decals_are_flat() -> void:
	print("Floor sigils")
	var offenders: Array[String] = []
	var found := 0
	var highest := -INF
	for room in _rooms_root().get_children():
		for node in room.get_children():
			if not (node is Decal):
				continue
			found += 1
			var d := node as Decal
			var top: float = d.position.y + d.size.y * 0.5
			var bottom: float = d.position.y - d.size.y * 0.5
			highest = maxf(highest, top)
			if top > MAX_SIGIL_TOP:
				offenders.append("%s reaches %.2f m — high enough to paint an actor"
					% [room.name, top])
			if bottom > 0.0 or top < 0.0:
				offenders.append("%s spans %.2f..%.2f m and misses the floor plane"
					% [room.name, bottom, top])
			if (d.cull_mask & 2) != 0:
				offenders.append("%s can draw on the actor visual layer" % room.name)
			if d.normal_fade < 0.5:
				offenders.append("%s has normal_fade %.2f — it will paint vertical "
					% [room.name, d.normal_fade] + "surfaces like a billboarded sprite")
	if found == 0:
		print("        - no decals installed (art not present)")
		return
	if offenders.is_empty():
		_ok("floor sigils stay on the floor",
			"%d decal(s), highest reaches %.2f m, none on the actor layer" % [found, highest])
	else:
		_no("sigil projection", "; ".join(offenders))


func _summary() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	print("\n" + "=".repeat(46))
	print("PHASE 8:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
