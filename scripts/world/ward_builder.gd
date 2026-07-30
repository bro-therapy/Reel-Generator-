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
## Ground cover: band -> weighted model list, and path -> the Mesh pulled out of
## it once. Empty on a checkout without the nature pack, which simply means no
## scatter — the ward is still a complete blockout without it.
var _scatter_models: Dictionary = {}
var _scatter_meshes: Dictionary = {}
var _scatter_tints: Dictionary = {}
var _moss_index := 0


func _ready() -> void:
	build()


func build() -> void:
	_moss_index = 0
	_load_prop_models()
	_load_scatter_models()
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
	_build_scatter(room, s, _doorway_points(s))
	if s.kind == WardLayout.Kind.COMBAT:
		_build_combat_barriers(room, s)


## Damp growing up the wall feet. Requested alongside the grass: "or like moss
## on the walls".
##
## The texture is generated, not downloaded. It is two things multiplied — a
## vertical fade so the moss thins as it climbs, and value noise so it grows in
## patches rather than as a painted skirting board — and a StandardMaterial3D
## cannot multiply two textures without a shader. Writing the RGBA directly is
## fewer moving parts than a shader and needs no art file, which matters for a
## repo whose assets are fetched rather than committed.
const MOSS_HEIGHT := 1.9
const MOSS_TEX_SIZE := 64

var _moss_mat: StandardMaterial3D


func _moss_material() -> StandardMaterial3D:
	if _moss_mat != null:
		return _moss_mat
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.055
	noise.seed = 20250730

	var img := Image.create(MOSS_TEX_SIZE, MOSS_TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in MOSS_TEX_SIZE:
		# v = 0 at the top of the quad, 1 at the floor.
		var v := 1.0 - float(y) / float(MOSS_TEX_SIZE - 1)
		# Squared, so the fade is thick at the foot and gone well before the top
		# rather than a linear ramp that reads as a gradient someone applied.
		var climb := pow(1.0 - v, 2.2)
		for x in MOSS_TEX_SIZE:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var a: float = clampf((n - 0.46) * 3.2, 0.0, 1.0) * climb
			# Two greens mixed by the same noise, so the patch has depth instead
			# of being one flat colour cut into a shape.
			var shade := 0.75 + n * 0.5
			img.set_pixel(x, y, Color(0.26 * shade, 0.34 * shade, 0.18 * shade, a))

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	# Nothing may light this: it is grime on a wall, and an emissive or
	# specular-lit moss patch reads as a glowing panel.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_moss_mat = mat
	return _moss_mat


## One moss quad hugging a wall segment, pulled a hair off the face so it does
## not z-fight with it.
func _moss_strip(room: Node3D, at: Vector3, width: float, facing: Vector3) -> void:
	if width < 1.0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(width, MOSS_HEIGHT)
	var mi := MeshInstance3D.new()
	# Numbered explicitly. add_child() defaults to force_readable_name = false,
	# so a duplicate "Moss" becomes "@Moss@2" — which does not begin with "Moss",
	# and the acceptance check counting strips by name saw one per room and
	# passed while the rest were invisible to it.
	_moss_index += 1
	mi.name = "Moss_%d" % _moss_index
	mi.mesh = quad
	# Tiled along the wall, not stretched across it. One 64 px texture spread
	# over a 26 m wall turns patchy noise into a smooth band, which reads as a
	# painted skirting board rather than as growth. Roughly one tile every three
	# metres puts the patches back at a size the eye reads as moss.
	var mat := _moss_material().duplicate() as StandardMaterial3D
	mat.uv1_scale = Vector3(maxf(width / 3.0, 1.0), 1.0, 1.0)
	mi.material_override = mat
	mi.layers = WORLD_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Basis.looking_at, NOT Node3D.look_at. look_at reads global_transform, which
	# needs the node in the tree — and rooms are built before they are added, so
	# every strip but the last silently failed to orient and every one of them
	# printed "Node not inside tree" into a log nobody was reading. The basis
	# form needs no tree at all.
	#
	# Negated because looking_at aims local -Z, and a QuadMesh's face is +Z: the
	# unnegated version pointed the lit side into the wall and only survived on
	# CULL_DISABLED flipping the normal back.
	mi.transform = Transform3D(
		Basis.looking_at(-facing, Vector3.UP),
		at + facing * 0.06 + Vector3(0.0, MOSS_HEIGHT * 0.5, 0.0))
	room.add_child(mi)


func _build_box_walls(room: Node3D, s: WardLayout.Space, openings: Dictionary) -> void:
	var half := s.size * 0.5
	var h := WardLayout.WALL_HEIGHT
	var t := WardLayout.WALL_THICKNESS
	var y := h * 0.5

	# East and west run along Z; north and south run along X.
	for side in ["east", "west"]:
		var x: float = s.centre.x + (half.x if side == "east" else -half.x)
		var inward_x := -1.0 if side == "east" else 1.0
		for seg in _segments(s.centre.z - half.y, s.centre.z + half.y, openings.get(side, [])):
			var v: Vector2 = seg
			var length := v.y - v.x
			if length <= 0.01:
				continue
			_box(room, Vector3(x, y, (v.x + v.y) * 0.5), Vector3(t, h, length), _wall_mat)
			# Segments already exclude the doorways, so moss never grows across
			# an opening — the same cut that shapes the wall shapes the moss.
			_moss_strip(room, Vector3(x + inward_x * t * 0.5, 0.0, (v.x + v.y) * 0.5),
				length, Vector3(inward_x, 0.0, 0.0))

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
			else:
				# No moss on a wall nobody can see. The south wall is hidden for
				# the camera, and its moss would hang in mid-air in front of the
				# room without it.
				var inward_z := 1.0 if side == "north" else -1.0
				_moss_strip(room, Vector3((v.x + v.y) * 0.5, 0.0, z + inward_z * t * 0.5),
					length, Vector3(0.0, 0.0, inward_z))


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


# --------------------------------------------------------------- ground cover

## How many scatter slots a room gets, before the clear radius and the doorways
## take their share back. Scaled by floor area so a 32 m combat room and a 20 m
## service room end up equally dressed rather than equally populated.
const SCATTER_PER_SQUARE_METRE := 0.45
## Band along the wall where the taller growth goes — the "moss on the walls"
## line. Measured inward from the wall face.
const WALL_BAND := 2.6
## Kept off the fighting floor for the same reason the props are: guide §9 wants
## broad clean combat floors, and a tuft the player's eye has to filter out
## during a wave is clutter however pretty it is.
const SCATTER_CLEAR_MARGIN := 1.0


## Grass, low plants and pebbles, drawn as MultiMesh instances.
##
## Answers "the assets that are sitting around seem very bland and are just kind
## of sitting there... definitely need some growth of like grass and different
## things around or like moss on the walls."
##
## One MultiMeshInstance3D per model, not one node per tuft: a few hundred tufts
## as scene instances is a few hundred draw calls on a scene that has a frame
## budget to keep (Phase 15). As instances they cost one each.
##
## Nothing here collides. Grass a player bumps into is worse than no grass, and
## a collider per tuft would also put hundreds of bodies in the physics world
## for decoration.
func _build_scatter(room: Node3D, s: WardLayout.Space, doors: Array) -> void:
	# Travel spaces DO get ground cover, unlike props. The rule that keeps crates
	# out of them is about obstruction, and grass obstructs nothing — while the
	# arrival path is the first room anyone sees, so it is the last place that
	# should be bare.
	if _scatter_models.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	# A different seed from _build_props, or the scatter would land in exactly
	# the same sequence of angles as the crates and grow out of them.
	rng.seed = hash(String(s.id) + "|scatter")

	var half_x: float = s.radius() if s.is_round() else s.size.x * 0.5
	var half_z: float = s.radius() if s.is_round() else s.size.y * 0.5
	var area := 4.0 * half_x * half_z
	var slots := int(round(area * SCATTER_PER_SQUARE_METRE))

	# model path -> the transforms chosen for it. Collected first, then built,
	# because a MultiMesh's instance_count has to be known before any transform
	# can be written to it.
	var placements: Dictionary = {}

	for i in slots:
		var pos: Vector3
		if s.is_round():
			# sqrt so the points spread evenly over the disc instead of piling
			# up in the middle, which is where they are least wanted.
			var a := rng.randf_range(0.0, TAU)
			var r: float = half_x * sqrt(rng.randf())
			pos = s.centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		else:
			pos = s.centre + Vector3(
				rng.randf_range(-half_x, half_x), 0.0,
				rng.randf_range(-half_z, half_z))

		var edge_gap: float = minf(half_x - absf(pos.x - s.centre.x),
			half_z - absf(pos.z - s.centre.z))
		if s.is_round():
			edge_gap = half_x - pos.distance_to(s.centre)
		# Right against the wall face the model would clip through it.
		if edge_gap < 0.35:
			continue

		if s.kind == WardLayout.Kind.COMBAT \
				and pos.distance_to(s.centre) < WardLayout.CLEAR_RADIUS + SCATTER_CLEAR_MARGIN:
			continue

		var blocked := false
		for door in doors:
			if pos.distance_to(door) < DOOR_WIDTH * 0.85:
				blocked = true
		if blocked:
			continue

		var band: String = "wall" if edge_gap <= WALL_BAND else "floor"
		var pick: Dictionary = _pick_scatter(band, rng)
		if pick.is_empty():
			continue

		var scale_range: Array = pick["scale"]
		var sc := rng.randf_range(float(scale_range[0]), float(scale_range[1]))
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
			Vector3(sc, sc, sc))
		var path: String = pick["file"]
		if not placements.has(path):
			placements[path] = []
			_scatter_tints[path] = pick["tint"]
		(placements[path] as Array).append(Transform3D(basis, pos))

	for path in placements:
		_build_scatter_batch(room, path, placements[path], rng)


func _build_scatter_batch(room: Node3D, path: String, transforms: Array,
		rng: RandomNumberGenerator) -> void:
	var mesh: Mesh = _scatter_meshes.get(path)
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Per-instance colour, so a hundred copies of one mesh are not a hundred
	# identical silhouettes in the same green. This is what the request for
	# shaders was actually after — the flatness is repetition, not lighting.
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var tint: Color = _scatter_tints.get(path, Color.WHITE)
	# The same origins, kept where a test can read them.
	#
	# MultiMesh instance data lives in the RenderingServer, and under --headless
	# that is the DUMMY server: get_instance_transform() hands back identity for
	# every instance. So an acceptance check asserting "no tufts on the combat
	# floor" measured every tuft as sitting at the world origin and passed with
	# the rule deleted from this function. Written from the same array in the
	# same loop as the transforms, so the two cannot disagree.
	var origins := PackedVector3Array()
	origins.resize(transforms.size())
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		origins[i] = (transforms[i] as Transform3D).origin
		var shade := rng.randf_range(0.80, 1.14)
		mm.set_instance_color(i, Color(
			tint.r * shade,
			tint.g * shade * rng.randf_range(0.95, 1.05),
			tint.b * shade * rng.randf_range(0.92, 1.04)))

	var node := MultiMeshInstance3D.new()
	node.name = "Scatter_%s" % path.get_file().get_basename()
	node.set_meta("scatter_origins", origins)
	node.multimesh = mm
	# The instance colour only reaches the pixel if SOMETHING reads it as albedo,
	# and the imported glTF material does not. Overriding also drops the pack's
	# palette texture, which is the point: its greens are the teal this tint
	# exists to replace, and a flat-shaded tuft matches a blockout ward anyway.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.layers = WORLD_LAYER
	# Ground cover does not need to cast shadows, and several hundred instances
	# that do is the cheapest frame-budget mistake available here.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(node)


func _pick_scatter(band: String, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = _scatter_models.get(band, [])
	if options.is_empty():
		return {}
	var total := 0
	for o in options:
		total += int(o.get("weight", 1))
	var roll := rng.randi() % maxi(total, 1)
	for o in options:
		roll -= int(o.get("weight", 1))
		if roll < 0:
			return o
	return options[options.size() - 1]


## Pulls the first mesh out of each scatter model once.
##
## A MultiMesh needs a Mesh, and a glTF import is a scene — so the model is
## instantiated, its mesh taken, and the instance thrown away. Doing this per
## room would re-instantiate every model five times for nothing.
func _load_scatter_models() -> void:
	_scatter_models = {}
	_scatter_meshes = {}
	if not FileAccess.file_exists(FREE_ASSETS_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FREE_ASSETS_MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var map: Dictionary = (parsed as Dictionary).get("scatter_models", {})
	for band in map:
		if String(band).begins_with("_"):
			continue
		var usable: Array = []
		for e in map[band]:
			var entry: Dictionary = e
			var file := String(entry.get("file", ""))
			var path := "%s/%s" % [MODEL_DIR, file]
			if not _scatter_meshes.has(path):
				var mesh := _first_mesh_of(path)
				if mesh == null:
					continue
				_scatter_meshes[path] = mesh
			var t: Array = entry.get("tint", [1.0, 1.0, 1.0])
			usable.append({
				"file": path,
				"weight": int(entry.get("weight", 1)),
				"scale": entry.get("scale", [1.0, 1.0]),
				"tint": Color(float(t[0]), float(t[1]), float(t[2])),
			})
		if not usable.is_empty():
			_scatter_models[band] = usable


static func _first_mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root_node := packed.instantiate()
	var found := _find_mesh(root_node)
	root_node.queue_free()
	return found


static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _find_mesh(child)
		if m != null:
			return m
	return null


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
	if path.size() == 3:
		# An L-shaped corridor. Both legs used to be built at full length, which
		# put THREE defects at the single corner in this ward (x=94, z=-46, the
		# far back right) and the playtest found all three:
		#   * two coplanar floor boxes overlapping -> z-fighting, "the floor
		#     glitching back and forth";
		#   * each leg's side wall running across the OTHER leg's opening -> "a
		#     tile you can't walk through";
		#   * the outer corner left unwalled -> "open to blackness, you can walk
		#     off the map".
		# Fixed by making the corner its own piece: both legs stop half a width
		# short of it, one floor patch fills it, and the two sides that are not
		# openings get walls.
		_corridor_corner(node, path[0], path[1], path[2], w, mat)
	else:
		for i in path.size() - 1:
			_corridor_leg(node, path[i], path[i + 1], w, mat)

	if link.gated:
		_build_gate(node, path[0], path[1])


## Builds an L: two shortened legs plus a filled, walled corner square.
func _corridor_corner(parent: Node3D, from: Vector3, corner: Vector3, to: Vector3,
		width: float, mat: Material) -> void:
	var half := width * 0.5
	var dir_in := _axis_unit(from - corner)
	var dir_out := _axis_unit(to - corner)

	# Legs stop at the corner square's edge rather than running through it.
	_corridor_leg(parent, from, corner + dir_in * half, width, mat)
	_corridor_leg(parent, corner + dir_out * half, to, width, mat)

	# One floor for the corner itself. Nothing else covers this square, so there
	# is no second surface to fight with.
	_box(parent, corner + Vector3(0, -0.5, 0), Vector3(width, 1.0, width), mat)

	# Wall every side that is not an opening. The two openings are exactly the
	# directions the legs leave in; the remaining two are the outer corner, which
	# is where the map used to end in blackness.
	var h := WardLayout.WALL_HEIGHT
	var t := WardLayout.WALL_THICKNESS
	for side in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		if side.is_equal_approx(dir_in) or side.is_equal_approx(dir_out):
			continue
		var along_x := absf(side.x) > 0.5
		var wall_size := Vector3(t, h, width + t) if along_x else Vector3(width + t, h, t)
		var wall := _box(parent, corner + side * half + Vector3(0, h * 0.5, 0),
			wall_size, _wall_mat)
		# Same camera rule as a room's south wall: a +Z wall stands between the
		# camera and the floor, so it keeps its collision and loses its mesh.
		if hide_camera_side_walls and side.is_equal_approx(Vector3.BACK):
			wall.visible = false


## Nearest axis direction, as a unit vector. Corridors are axis-aligned, so this
## is exact rather than an approximation.
static func _axis_unit(v: Vector3) -> Vector3:
	if absf(v.x) >= absf(v.z):
		return Vector3(signf(v.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


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
