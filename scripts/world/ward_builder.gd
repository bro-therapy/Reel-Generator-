@tool
class_name WardBuilder
extends Node3D

## Builds the Sunfall Ward blockout from WardLayout.
##
## Blockout, per CLAUDE.md: box and cylinder primitives with the package's tiling
## textures, not modelled meshes. The modular kit sheet is a visual target, not a
## mesh source.
##
## Geometry is generated rather than hand-placed so the layout stays a single
## source of truth — moving a room in WardLayout moves its walls, its corridors,
## its doorways and its navigation mesh together.

const TEX_DIR := "res://assets/environment/textures"
const DECAL_DIR := "res://assets/environment/decals"

## Doorway width. Wider than a corridor would strictly need so three summons in
## lane do not clip the frame while following the hero through.
const DOOR_WIDTH := 10.0

## Collision layer 1 is world geometry (guide §15).
const WORLD_LAYER := 1

@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			build()

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _rift_mat: StandardMaterial3D
var _gate_mat: StandardMaterial3D
var _prop_mat: StandardMaterial3D
var _foliage_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _lantern_mat: StandardMaterial3D
var _crystal_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _barrier_mat: StandardMaterial3D

## GateController per COMBAT space, keyed by space id. Filled during build.
var _combat_gates: Dictionary = {}

## Model-backed props, kind -> Array of {scene, scale, collider}. Loaded from the
## manifest at build time; a kind with no installed model falls back to its
## primitive construction, so an assetless checkout builds exactly the old ward.
## docs/FREE_ASSETS.json is the source of truth for what belongs here and where
## it came from — assets stay untracked (LFS uploads are blocked from the build
## environment), the manifest carries URLs and licenses instead.
const FREE_ASSETS_MANIFEST := "res://docs/FREE_ASSETS.json"
const MODEL_DIR := "res://assets/environment/models"
var _prop_models: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	_load_prop_models()
	for child in get_children():
		child.free()

	_make_materials()

	var openings := _collect_openings()
	for s in WardLayout.spaces():
		_build_space(s, openings.get(s.id, {}))
	for link in WardLayout.links():
		_build_corridor(link)

	_build_navigation()


# ---------------------------------------------------------------- materials

func _texture(file: String) -> Texture2D:
	var path := "%s/%s" % [TEX_DIR, file]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _surface(tex_file: String, tint: Color, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := _texture(tex_file)
	if tex != null:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
		m.uv1_triplanar = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = tint
	m.roughness = 0.95
	m.metallic = 0.0
	return m


func _make_materials() -> void:
	# Guide §2: the ward is warm and sunlit but less saturated than the actors,
	# so it sits behind them rather than competing.
	_floor_mat = _surface("cobblestone_01.png", Color(1, 1, 1), 0.14)
	_wall_mat = _surface("sandstone_wall.png", Color(0.94, 0.92, 0.88), 0.12)
	_prop_mat = _surface("weathered_wood.png", Color(1, 1, 1), 0.5)
	_foliage_mat = _surface("planter_foliage.png", Color(1, 1, 1), 0.7)
	_roof_mat = _surface("terracotta_roof.png", Color(1, 1, 1), 0.4)
	# Lantern glass and crystal are emissive: they are light sources in the fiction
	# and have to read as lit even where their OmniLight does not reach.
	_lantern_mat = _surface("cream_plaster.png", Color(1.0, 0.9, 0.65), 0.3)
	_lantern_mat.emission_enabled = true
	_lantern_mat.emission = Color(1.0, 0.82, 0.5)
	_lantern_mat.emission_energy_multiplier = 0.9
	# Emission belongs on small shapes. At 1.4 on a shard it reads as a glowing
	# crystal; the same material on the fountain's 5 m basin saturated the whole
	# disc to white and took the surrounding floor with it. 0.55 keeps the shards
	# violet instead of blowing them out, and the basin gets its own material.
	_crystal_mat = _surface("cream_plaster.png", Color(0.42, 0.32, 0.82), 0.15)
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.45, 0.34, 0.92)
	_crystal_mat.emission_energy_multiplier = 0.55
	# Standing water: violet by reflection, not by emission.
	_water_mat = _surface("cobblestone_03.png", Color(0.34, 0.30, 0.52), 0.25)
	_water_mat.roughness = 0.15
	_water_mat.metallic = 0.35

	# Rift floors read violet — friendly-side corruption, never hostile red.
	_rift_mat = _surface("cobblestone_02.png", Color(0.68, 0.56, 0.92), 0.14)

	_gate_mat = StandardMaterial3D.new()
	_gate_mat.albedo_color = Color("9c6bff")
	_gate_mat.emission_enabled = true
	_gate_mat.emission = Color("9c6bff")
	_gate_mat.emission_energy_multiplier = 1.6

	# Combat barriers are an obstruction the player must respect, so they read
	# hostile — warm orange, never violet (colour ownership, guide §2). Alpha so
	# the room beyond stays visible; a fight should never black out the exit.
	_barrier_mat = StandardMaterial3D.new()
	_barrier_mat.albedo_color = Color(1.0, 0.55, 0.25, 0.4)
	_barrier_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_barrier_mat.emission_enabled = true
	_barrier_mat.emission = Color(1.0, 0.45, 0.15)
	_barrier_mat.emission_energy_multiplier = 1.1
	_barrier_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


# ---------------------------------------------------------------- primitives

## Hides the mesh of walls on the camera side of a room while keeping their
## collision. Guide §12 fixes the camera — it never rotates — so the +Z wall of
## every space is always the one between the viewer and the floor, and drawing it
## means its lit outer face fills the bottom third of the screen while the room you
## are standing in occupies a band in the middle.
##
## Only `visible` is touched. The StaticBody is a child of the mesh and physics
## does not care about visibility, so the player still cannot walk out through a
## wall they cannot see. Turn it off to inspect the blockout as solid geometry.
@export var hide_camera_side_walls := true

## Anything whose near face sits at or beyond this much +Z from its room centre is
## a camera-side wall. Half a wall thickness of slack, so a wall exactly on the
## boundary counts.
const CAMERA_SIDE_EPSILON := 0.51


func _box(parent: Node3D, centre: Vector3, size: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)

	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mi.add_child(body)
	return mi


func _cylinder(parent: Node3D, centre: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	body.add_child(shape)
	mi.add_child(body)
	return mi


# ---------------------------------------------------------------- doorways

## Which wall side of a space each corridor punches through, and where.
##
## Returned as {space_id: {side: [interval, ...]}} where side is one of
## "north"/"south"/"east"/"west" and an interval is a Vector2 of start/end along
## that wall's axis. Walls are then emitted as the complement of these, which is
## what keeps a doorway and its corridor from drifting apart.
func _collect_openings() -> Dictionary:
	var out: Dictionary = {}
	for link in WardLayout.links():
		var a := WardLayout.space(link.from)
		var b := WardLayout.space(link.to)
		if a == null or b == null:
			continue

		# Openings are derived from the same path the corridor is built along,
		# so a door can never end up on a different wall than its corridor.
		var path := _corridor_path(a, b)
		for entry in [[a, path[0], path[1]], [b, path[path.size() - 1], path[path.size() - 2]]]:
			var here: WardLayout.Space = entry[0]
			var at: Vector3 = entry[1]
			var inward: Vector3 = entry[2]
			var side := _side_of_point(here, at, inward)
			var axis_centre: float = at.z if side in ["east", "west"] else at.x
			if not out.has(here.id):
				out[here.id] = {}
			if not out[here.id].has(side):
				out[here.id][side] = []
			out[here.id][side].append(Vector2(axis_centre - DOOR_WIDTH * 0.5, axis_centre + DOOR_WIDTH * 0.5))
	return out


## Which wall a boundary point sits on, disambiguated by the direction the
## corridor runs away from it.
func _side_of_point(s: WardLayout.Space, at: Vector3, towards: Vector3) -> String:
	var d := towards - at
	if absf(d.x) >= absf(d.z):
		return "east" if d.x > 0.0 else "west"
	return "north" if d.z < 0.0 else "south"


## The point on a room's boundary where a corridor leaves it, heading for `dir`.
func _boundary_point(s: WardLayout.Space, dir: Vector3) -> Vector3:
	var half := s.size * 0.5
	if absf(dir.x) >= absf(dir.z):
		return Vector3(s.centre.x + (half.x if dir.x > 0.0 else -half.x), 0.0, s.centre.z)
	return Vector3(s.centre.x, 0.0, s.centre.z + (half.y if dir.z > 0.0 else -half.y))


## Corridor centreline, boundary to boundary.
##
## Runs edge to edge rather than centre to centre: a centre-to-centre corridor
## drags its own side walls back through the rooms it connects, which walls off
## the doorway it was supposed to open.
##
## Where both axes differ the run is an L — along X first, then Z — so the
## corridor leaves on an east/west wall and arrives on a north/south one.
func _corridor_path(a: WardLayout.Space, b: WardLayout.Space) -> Array:
	var dx := b.centre.x - a.centre.x
	var dz := b.centre.z - a.centre.z

	if absf(dx) > 0.5 and absf(dz) > 0.5:
		var exit_p := _boundary_point(a, Vector3(dx, 0, 0))
		var corner := Vector3(b.centre.x, 0.0, a.centre.z)
		var entry_p := _boundary_point(b, Vector3(0, 0, -dz))
		return [exit_p, corner, entry_p]

	var out_dir := Vector3(dx, 0, dz)
	return [_boundary_point(a, out_dir), _boundary_point(b, -out_dir)]


## The dominant direction from one space to another, as a wall side.
func _side_towards(here: WardLayout.Space, there: WardLayout.Space) -> String:
	var d := there.centre - here.centre
	if absf(d.x) >= absf(d.z):
		return "east" if d.x > 0.0 else "west"
	return "north" if d.z < 0.0 else "south"


## Where along that wall the doorway sits. Corridors run axis-aligned, so the
## door lines up with the corridor's own centreline, clamped inside the wall.
func _door_centre_on_side(here: WardLayout.Space, there: WardLayout.Space, side: String) -> float:
	var half := here.size * 0.5
	if side in ["east", "west"]:
		var limit := half.y - DOOR_WIDTH * 0.5 - 1.0
		return clampf(here.centre.z, here.centre.z - limit, here.centre.z + limit)
	var limit_x := half.x - DOOR_WIDTH * 0.5 - 1.0
	return clampf(here.centre.x, here.centre.x - limit_x, here.centre.x + limit_x)


## Wall segments for one side, as the complement of its openings.
func _segments(from: float, to: float, openings: Array) -> Array:
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(p, q): return p.x < q.x)
	var out: Array = []
	var cursor := from
	for cut in cuts:
		var c: Vector2 = cut
		if c.y <= cursor:
			continue
		if c.x > cursor:
			out.append(Vector2(cursor, minf(c.x, to)))
		cursor = maxf(cursor, c.y)
		if cursor >= to:
			break
	if cursor < to:
		out.append(Vector2(cursor, to))
	return out


# ---------------------------------------------------------------- spaces

func _build_space(s: WardLayout.Space, openings: Dictionary) -> void:
	var room := Node3D.new()
	room.name = String(s.id)
	add_child(room)

	var mat := _rift_mat if s.kind == WardLayout.Kind.RIFT else _floor_mat

	if s.is_round():
		_cylinder(room, s.centre + Vector3(0, -0.5, 0), s.radius(), 1.0, mat)
		_build_round_wall(room, s, openings)
	else:
		_box(room, s.centre + Vector3(0, -0.5, 0), Vector3(s.size.x, 1.0, s.size.y), mat)
		_build_box_walls(room, s, openings)

	_build_decal(room, s)
	_build_props(room, s, _doorway_points(s))
	if s.kind == WardLayout.Kind.COMBAT:
		_build_combat_barriers(room, s)


func _build_box_walls(room: Node3D, s: WardLayout.Space, openings: Dictionary) -> void:
	var half := s.size * 0.5
	var h := WardLayout.WALL_HEIGHT
	var t := WardLayout.WALL_THICKNESS
	var y := h * 0.5

	# East and west run along Z; north and south run along X.
	for side in ["east", "west"]:
		var x: float = s.centre.x + (half.x if side == "east" else -half.x)
		for seg in _segments(s.centre.z - half.y, s.centre.z + half.y, openings.get(side, [])):
			var v: Vector2 = seg
			var length := v.y - v.x
			if length <= 0.01:
				continue
			_box(room, Vector3(x, y, (v.x + v.y) * 0.5), Vector3(t, h, length), _wall_mat)

	for side in ["north", "south"]:
		var z: float = s.centre.z + (-half.y if side == "north" else half.y)
		for seg in _segments(s.centre.x - half.x, s.centre.x + half.x, openings.get(side, [])):
			var v: Vector2 = seg
			var length := v.y - v.x
			if length <= 0.01:
				continue
			var wall := _box(room, Vector3((v.x + v.y) * 0.5, y, z), Vector3(length, h, t), _wall_mat)
			# South is +Z, which is the side the fixed camera looks from.
			if hide_camera_side_walls and side == "south":
				wall.visible = false


## The boss plaza is circular, so its wall is a ring of short segments with a gap
## where Combat B feeds in.
func _build_round_wall(room: Node3D, s: WardLayout.Space, openings: Dictionary) -> void:
	var segments := 48
	var r := s.radius()
	var h := WardLayout.WALL_HEIGHT
	# The entrance faces back down the spine, towards Combat B.
	var door_angle := PI
	var door_arc := DOOR_WIDTH / r

	for i in segments:
		var a := TAU * float(i) / float(segments)
		var delta := absf(wrapf(a - door_angle, -PI, PI))
		if delta < door_arc * 0.5:
			continue
		var mi := _box(
			room,
			s.centre + Vector3(cos(a) * r, h * 0.5, sin(a) * r),
			Vector3(WardLayout.WALL_THICKNESS, h, TAU * r / float(segments) + 0.4),
			_wall_mat,
		)
		mi.rotation.y = -a
		# The boss plaza's +Z arc sits between the fixed camera and the floor for
		# exactly the same reason a room's south wall does, so the same rule
		# applies. sin(a) > 0 is the camera-facing half; the 0.25 margin keeps the
		# segments at the east and west extremes, which frame the arena without
		# ever standing in front of the fight.
		if hide_camera_side_walls and sin(a) > 0.25:
			mi.visible = false


func _build_decal(room: Node3D, s: WardLayout.Space) -> void:
	var file := ""
	match s.kind:
		WardLayout.Kind.BOSS:
			file = "arena_bell_emblem.png"
		WardLayout.Kind.RIFT:
			file = "corruption_breach.png"
		WardLayout.Kind.SERVICE:
			file = "spirit_well_marker.png"
		_:
			return

	var path := "%s/%s" % [DECAL_DIR, file]
	if not ResourceLoader.exists(path):
		return
	var decal := Decal.new()
	decal.texture_albedo = load(path) as Texture2D
	var extent: float = minf(s.size.x, s.size.y) * 0.42
	# A Decal paints every surface inside its box, projecting down its local -Y.
	# This box used to be 4 m tall and centred 1 m ABOVE the floor, so it swept
	# the whole volume the player walks through and painted the sigil across the
	# hero's sprite — reported as "a projector shooting over the top of it".
	#
	# Three independent guards now, because one is easy to undo by accident:
	#   1. the box is 0.6 m tall and sits just under the floor plane, so there is
	#      no head-room for it to catch anything standing on the floor;
	#   2. normal_fade only paints surfaces whose normal points up, which a
	#      billboarded actor quad never does;
	#   3. cull_mask excludes visual layer 2, which is where actors live.
	decal.size = Vector3(extent, 0.6, extent)
	decal.position = s.centre + Vector3(0.0, -0.18, 0.0)
	decal.normal_fade = 0.85
	decal.cull_mask = 1
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	room.add_child(decal)


## Props hug the perimeter. Guide §9 wants "broad clean combat floors" with props
## pushed to the edges, and Phase 8 asks for combat centres to stay uncluttered —
## so nothing is placed inside WardLayout.CLEAR_RADIUS of a combat centre.
## Every point on this room's boundary where a corridor meets it.
func _doorway_points(s: WardLayout.Space) -> Array:
	var out: Array = []
	for link in WardLayout.links():
		var a := WardLayout.space(link.from)
		var b := WardLayout.space(link.to)
		if a == null or b == null:
			continue
		if a.id != s.id and b.id != s.id:
			continue
		var path := _corridor_path(a, b)
		out.append(path[0] if a.id == s.id else path[path.size() - 1])
	return out


func _build_props(room: Node3D, s: WardLayout.Space, doors: Array) -> void:
	if s.kind == WardLayout.Kind.TRAVEL:
		return

	var rng := RandomNumberGenerator.new()
	# Seeded from the room id so the blockout is identical every run and a
	# screenshot diff means a real change.
	rng.seed = hash(String(s.id))

	# 22, not 10 — ten identical grey boxes around a 32 m room reads as an empty
	# room with debris in it. Guide §9 still wants "broad clean combat floors", so
	# the density goes up at the perimeter and the CLEAR_RADIUS centre stays empty.
	var count := 22
	var inner: float = (s.radius() if s.is_round() else minf(s.size.x, s.size.y) * 0.5) - 3.0
	# What each room kind is dressed with. Informed by the modular kit sheet, built
	# as blockout primitives: CLAUDE.md keeps that sheet as reference, not a texture
	# source, so nothing here is cut out of it.
	var kinds := _prop_palette(s.kind)

	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var dist := inner - rng.randf_range(0.0, 3.0)
		var pos: Vector3 = s.centre + Vector3(cos(a) * dist, 0.0, sin(a) * dist)

		# By extent, not centre: a 2 m hedge placed with its CENTRE just past the
		# line still pokes its end into the clear circle, which is exactly what
		# Phase 8's cylinder probe measures. 1.5 covers the longest prop's half
		# extent with a little slack.
		if s.kind == WardLayout.Kind.COMBAT \
				and pos.distance_to(s.centre) < WardLayout.CLEAR_RADIUS + 1.5:
			continue

		# Never in a doorway. Props ring the perimeter, which is exactly where
		# the exits are — the first version of this dropped a crate squarely in
		# Combat A's east door and walled the route off.
		var in_a_doorway := false
		for door in doors:
			if pos.distance_to(door) < DOOR_WIDTH * 0.85:
				in_a_doorway = true
		if in_a_doorway:
			continue

		_build_prop(room, kinds[rng.randi() % kinds.size()], pos, rng)

	# One centrepiece per non-combat room. A combat floor stays clear.
	# Offset from the centre, not on it. The critical route runs straight through
	# every room's centre point, and a solid stone basin sitting there made the
	# Spirit Well impassable — Phase 8's clutter probe caught it immediately. A
	# centrepiece the player walks around also just reads better than one they
	# collide with head-on coming through the door.
	if s.kind == WardLayout.Kind.SERVICE:
		_build_fountain(room, s.centre + Vector3(0.0, 0.0, -6.5))
	elif s.kind == WardLayout.Kind.RIFT:
		_build_crystal_cluster(room, s.centre + Vector3(0.0, 0.0, -6.0), rng, 2.2)


func _load_prop_models() -> void:
	_prop_models = {}
	if not FileAccess.file_exists(FREE_ASSETS_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FREE_ASSETS_MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ward: %s is not valid JSON" % FREE_ASSETS_MANIFEST)
		return
	var map: Dictionary = (parsed as Dictionary).get("prop_models", {})
	for kind in map:
		var entries: Array = []
		for e in map[kind]:
			var entry: Dictionary = e
			var path := "%s/%s" % [MODEL_DIR, String(entry.get("file", ""))]
			if not ResourceLoader.exists(path):
				continue
			var packed := load(path) as PackedScene
			if packed == null:
				push_warning("ward: %s exists but is not a scene" % path)
				continue
			var collider: Variant = null
			if entry.has("collider"):
				var c: Array = entry["collider"]
				collider = Vector3(float(c[0]), float(c[1]), float(c[2]))
			entries.append({
				"scene": packed,
				"scale": float(entry.get("scale", 1.0)),
				"collider": collider,
			})
		if not entries.is_empty():
			_prop_models[kind] = entries


## True when an installed model stood in for this prop. Chooses deterministically
## from the room's own rng, so prop variety is stable per room across runs.
func _try_model_prop(room: Node3D, kind: String, pos: Vector3, rng: RandomNumberGenerator) -> bool:
	if not _prop_models.has(kind):
		return false
	var options: Array = _prop_models[kind]
	var pick: Dictionary = options[rng.randi() % options.size()]
	var inst := (pick["scene"] as PackedScene).instantiate() as Node3D
	if inst == null:
		return false
	room.add_child(inst)
	inst.position = pos
	var yaw := rng.randf_range(0.0, TAU)
	inst.rotation.y = yaw
	var sc: float = pick["scale"]
	inst.scale = Vector3(sc, sc, sc)
	if pick.has("y_offset"):
		inst.position.y += float(pick["y_offset"])

	# Imported glTF carries no physics. Where the primitive version was solid the
	# model version must be too, or swapping art would silently change gameplay.
	# The collider takes the model's yaw: an axis-aligned box under a rotated
	# hedge is an invisible wall at the wrong angle, and it was also how a prop
	# that respected the clear radius still poked its corner into it.
	var collider: Variant = pick["collider"]
	if collider != null:
		var size: Vector3 = collider
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.position = pos + Vector3(0, size.y * 0.5, 0)
		body.rotation.y = yaw
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		room.add_child(body)
	return true


## How many props in this room are model-backed. For the acceptance suite.
func model_prop_count(room_name: String) -> int:
	var room := get_node_or_null(NodePath(room_name))
	if room == null:
		return 0
	var n := 0
	for child in room.get_children():
		if child is Node3D and (child as Node3D).scene_file_path != "":
			n += 1
	return n


## Prop vocabulary per room kind. Lanterns are in every list on purpose: they
## carry an OmniLight3D, and a few warm pools of light around a perimeter is the
## cheapest thing that makes a blockout stop reading as a test level.
func _prop_palette(kind: WardLayout.Kind) -> Array:
	match kind:
		WardLayout.Kind.SERVICE:
			return ["planter", "planter", "bench", "barrel", "lantern", "stall", "crate"]
		WardLayout.Kind.RIFT:
			return ["crystal", "crystal", "barrel", "crate", "lantern", "rubble"]
		WardLayout.Kind.BOSS:
			return ["rubble", "rubble", "barrel", "lantern", "crate"]
		_:
			return ["crate", "barrel", "crate", "planter", "lantern", "bench", "rubble"]


func _build_prop(room: Node3D, kind: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
	# A lantern is a light source first and a shape second — the pool of warm
	# light arrives whether the visual is a model or a primitive.
	if kind == "lantern":
		_lantern_light(room, pos)
	if _try_model_prop(room, kind, pos, rng):
		return
	match kind:
		"barrel":
			var h := rng.randf_range(1.0, 1.4)
			var b := _cylinder(room, pos + Vector3(0, h * 0.5, 0), 0.55, h, _prop_mat)
			b.rotation.y = rng.randf_range(0.0, TAU)
		"planter":
			# Box of soil with a foliage slab on top, so it reads as planted rather
			# than as another crate.
			var box := _box(room, pos + Vector3(0, 0.35, 0), Vector3(2.0, 0.7, 1.1), _prop_mat)
			box.rotation.y = rng.randf_range(0.0, TAU)
			var leaves := _box(room, pos + Vector3(0, 0.95, 0), Vector3(1.8, 0.6, 0.95),
				_foliage_mat, false)
			leaves.rotation.y = box.rotation.y
		"bench":
			var seat := _box(room, pos + Vector3(0, 0.55, 0), Vector3(2.4, 0.18, 0.7), _prop_mat)
			seat.rotation.y = rng.randf_range(0.0, TAU)
			for side in [-0.9, 0.9]:
				var leg := _box(room, pos + Vector3(0, 0.25, 0), Vector3(0.18, 0.5, 0.6),
					_prop_mat, false)
				leg.position = pos + (seat.basis * Vector3(side, 0.25, 0.0))
		"stall":
			# Four posts and a pitched awning. The silhouette is what sells a market.
			var rot := rng.randf_range(0.0, TAU)
			for cx in [-1.3, 1.3]:
				for cz in [-1.0, 1.0]:
					var post := _box(room, pos, Vector3(0.16, 2.2, 0.16), _prop_mat, false)
					post.position = pos + Vector3(cos(rot) * cx - sin(rot) * cz, 1.1,
						sin(rot) * cx + cos(rot) * cz)
			var awning := _box(room, pos + Vector3(0, 2.35, 0), Vector3(3.2, 0.16, 2.4),
				_roof_mat, false)
			awning.rotation.y = rot
			awning.rotation.x = 0.12
		"lantern":
			var postm := _box(room, pos + Vector3(0, 1.1, 0), Vector3(0.14, 2.2, 0.14), _prop_mat)
			postm.rotation.y = rng.randf_range(0.0, TAU)
			var head := _box(room, pos + Vector3(0, 2.3, 0), Vector3(0.38, 0.42, 0.38),
				_lantern_mat, false)
			head.rotation.y = postm.rotation.y
		"crystal":
			_build_crystal_cluster(room, pos, rng, 1.0)
		_:
			# Rubble: a couple of low slabs, the cheapest way to break a clean floor
			# line without adding anything the player can hide behind.
			for _n in 2:
				var r := _box(room, pos, Vector3(rng.randf_range(0.7, 1.5), 0.35,
					rng.randf_range(0.7, 1.4)), _prop_mat, false)
				r.position = pos + Vector3(rng.randf_range(-0.8, 0.8), 0.17,
					rng.randf_range(-0.8, 0.8))
				r.rotation.y = rng.randf_range(0.0, TAU)


func _lantern_light(room: Node3D, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 2.3, 0)
	light.light_color = Color(1.0, 0.82, 0.55)
	light.light_energy = 2.6
	light.omni_range = 9.0
	# Lanterns are set dressing, not gameplay light. Casting shadows from twenty
	# of them is the single most expensive thing this scene could do for the
	# least readable gain.
	light.shadow_enabled = false
	room.add_child(light)


## Violet crystal. Rift rooms and the Spirit Well share the palette's friendly
## side, so these glow rather than reflect.
func _build_crystal_cluster(room: Node3D, at: Vector3, rng: RandomNumberGenerator,
		scale_v: float) -> void:
	var shards := 5
	for i in shards:
		var h := rng.randf_range(0.9, 2.1) * scale_v
		var shard := _box(room, at, Vector3(0.32 * scale_v, h, 0.32 * scale_v),
			_crystal_mat, false)
		var a := TAU * float(i) / float(shards) + rng.randf_range(-0.3, 0.3)
		var off := rng.randf_range(0.15, 0.8) * scale_v
		shard.position = at + Vector3(cos(a) * off, h * 0.45, sin(a) * off)
		shard.rotation = Vector3(rng.randf_range(-0.25, 0.25), a, rng.randf_range(-0.25, 0.25))
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 1.0 * scale_v, 0)
	glow.light_color = Color(0.62, 0.45, 1.0)
	glow.light_energy = 2.2 * scale_v
	glow.omni_range = 8.0 * scale_v
	glow.shadow_enabled = false
	room.add_child(glow)


## The Spirit Well's centrepiece. Guide §9 gives the well its own read, and a
## service room with nothing in the middle looks unfinished next to a combat floor
## that is empty on purpose.
func _build_fountain(room: Node3D, at: Vector3) -> void:
	_cylinder(room, at + Vector3(0, 0.3, 0), 3.2, 0.6, _prop_mat)
	# Water, not light. The emissive version of this washed the room out.
	_cylinder(room, at + Vector3(0, 0.66, 0), 2.7, 0.12, _water_mat)
	_cylinder(room, at + Vector3(0, 1.4, 0), 0.45, 2.0, _prop_mat)
	# One small shard cluster at the top carries the glow, and a single light
	# does the rest — the well should be the brightest thing in its room without
	# being the only thing you can see.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("spirit_well_fountain")
	_build_crystal_cluster(room, at + Vector3(0, 2.5, 0), rng, 0.45)


# ---------------------------------------------------------------- corridors

func _build_corridor(link: WardLayout.Link) -> void:
	var a := WardLayout.space(link.from)
	var b := WardLayout.space(link.to)
	if a == null or b == null:
		return

	var node := Node3D.new()
	node.name = "corridor_%s_%s" % [link.from, link.to]
	add_child(node)

	var w := WardLayout.CORRIDOR_WIDTH
	var mat := _rift_mat if link.optional else _floor_mat

	var path := _corridor_path(a, b)
	for i in path.size() - 1:
		_corridor_leg(node, path[i], path[i + 1], w, mat)

	if link.gated:
		_build_gate(node, path[0], path[1])


func _corridor_leg(parent: Node3D, from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var delta := to - from
	var along_x := absf(delta.x) >= absf(delta.z)
	var length := absf(delta.x) if along_x else absf(delta.z)
	if length <= 0.01:
		return

	var centre := (from + to) * 0.5
	var size := Vector3(length, 1.0, width) if along_x else Vector3(width, 1.0, length)
	_box(parent, centre + Vector3(0, -0.5, 0), size, mat)

	# Side walls, so the camera never looks off the edge of a corridor.
	var h := WardLayout.WALL_HEIGHT
	var t := WardLayout.WALL_THICKNESS
	for sign_value in [-1.0, 1.0]:
		var offset := Vector3(0, h * 0.5, sign_value * width * 0.5) if along_x else Vector3(sign_value * width * 0.5, h * 0.5, 0)
		var wall_size := Vector3(length, h, t) if along_x else Vector3(t, h, length)
		var wall := _box(parent, centre + offset, wall_size, _wall_mat)
		# A corridor running along X has a +Z side wall, and it is in the way for
		# the same reason a room's south wall is. One running along Z does not.
		if hide_camera_side_walls and along_x and sign_value > 0.0:
			wall.visible = false


## A violet frame across the opening. Route map draws the Rift branch and the
## boss gate in colour; this is that, in world space.
func _build_gate(parent: Node3D, at: Vector3, towards: Vector3) -> void:
	var d := towards - at
	var horizontal := absf(d.x) >= absf(d.z)
	var pos := at

	var span := DOOR_WIDTH
	var post := Vector3(0.6, WardLayout.WALL_HEIGHT * 0.8, 0.6)
	for sign_value in [-1.0, 1.0]:
		var offset := Vector3(0, post.y * 0.5, sign_value * span * 0.5) if horizontal else Vector3(sign_value * span * 0.5, post.y * 0.5, 0)
		_box(parent, pos + offset, post, _gate_mat, false)

	var lintel_size := Vector3(0.6, 0.6, span) if horizontal else Vector3(span, 0.6, 0.6)
	_box(parent, pos + Vector3(0, post.y, 0), lintel_size, _gate_mat, false)


## Lockable barriers across every doorway of a combat room.
##
## Guide §6: an encounter seals its room while waves are live. GateController was
## built and tested for exactly this in Phase 8 and then never given geometry —
## the playable build let you walk out of a fight mid-wave. These are its meshes:
## one energy panel per doorway, open (invisible, no collision) by default, made
## solid on layer 9 while locked. The player's mask already includes layer 9;
## enemies and summons never mask it, so a sealed door cannot strand an enemy
## outside its own fight.
func _build_combat_barriers(room: Node3D, s: WardLayout.Space) -> void:
	var controller := GateController.new()
	controller.name = "Gates"
	room.add_child(controller)

	var half := s.size * 0.5
	var n := 0
	for door in _doorway_points(s):
		var at: Vector3 = door
		# Which wall the doorway sits in decides the panel's orientation: a door
		# in an east/west wall spans z, one in a north/south wall spans x.
		var on_ew := absf(absf(at.x - s.centre.x) - half.x) < absf(absf(at.z - s.centre.z) - half.y)
		var span := DOOR_WIDTH + 1.0
		var size := Vector3(0.5, WardLayout.WALL_HEIGHT * 0.7, span) if on_ew \
			else Vector3(span, WardLayout.WALL_HEIGHT * 0.7, 0.5)

		var body := StaticBody3D.new()
		body.name = "Barrier%d" % n
		# Open by default; GateController flips this to layer 9 while locked.
		body.collision_layer = 0
		body.position = at + Vector3(0, size.y * 0.5, 0)
		controller.add_child(body)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)

		var mesh := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = size
		mesh.mesh = quad
		mesh.material_override = _barrier_mat
		body.add_child(mesh)

		controller.gate_meshes.append(controller.get_path_to(body))
		n += 1

	# _ready has already run if the ward was built after entering the tree, but
	# building happens from build() before that — apply the open state explicitly
	# rather than relying on ready order (the project's recurring lesson).
	controller.set_locked(false)
	controller._apply()
	_combat_gates[s.id] = controller


## The gate controller for a combat space, or null for spaces that have none.
func combat_gates(id: StringName) -> GateController:
	return _combat_gates.get(id)


# ---------------------------------------------------------------- navigation

func _build_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	add_child(region)

	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.6
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.4
	mesh.cell_size = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	region.navigation_mesh = mesh
