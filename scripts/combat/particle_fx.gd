class_name ParticleFx
extends Node3D

## Code-built one-shot particle bursts: muzzle flashes, impacts, dust, dashes.
##
## The playtest line this answers: "I still don't see any particle effects...
## walking or dashing or even using my attacks." The additive VFX pool covers
## the big authored effects (fire, beams); what was missing is the small
## per-action feedback layer every action game has. These are GPUParticles3D
## configured entirely in code — no textures, no art dependency, works on an
## assetless checkout.
##
## Colour ownership is enforced by construction: each kind carries its side.
## Violet/blue-white kinds are the player's; warm kinds are the enemies'.
## Nothing here may ever paint a hostile action violet.

## How many emitters per kind. A kind that bursts while all its emitters are
## mid-flight steals the oldest — at these lifetimes (<= 0.45 s) that is
## invisible, and it caps the scene's particle nodes at kinds x POOL_PER_KIND.
const POOL_PER_KIND := 4

## kind -> config. amount/lifetime/velocity/scale are ParticleProcessMaterial
## fields; colour is a ramp from bright core to fade-out.
const KINDS := {
	&"muzzle_violet": {
		"amount": 10, "lifetime": 0.16, "velocity": 5.0, "spread": 28.0,
		"scale": 0.10, "gravity": 0.0, "up": false,
		"from": Color(0.92, 0.88, 1.0), "to": Color(0.55, 0.38, 1.0),
	},
	&"impact_violet": {
		"amount": 18, "lifetime": 0.28, "velocity": 6.5, "spread": 180.0,
		"scale": 0.09, "gravity": -3.0, "up": false,
		"from": Color(0.9, 0.85, 1.0), "to": Color(0.5, 0.32, 0.95),
	},
	&"dash_burst": {
		"amount": 22, "lifetime": 0.34, "velocity": 4.5, "spread": 70.0,
		"scale": 0.12, "gravity": 1.5, "up": false,
		"from": Color(0.85, 0.8, 1.0), "to": Color(0.42, 0.3, 0.8),
	},
	# Footstep dust is terrain, not allegiance: warm sandstone grey, low and
	# slow, drifting up. Deliberately dim so it reads as ground contact, not
	# as an effect.
	&"dust_puff": {
		"amount": 5, "lifetime": 0.45, "velocity": 1.1, "spread": 55.0,
		"scale": 0.16, "gravity": 0.35, "up": true,
		"from": Color(0.68, 0.6, 0.5, 0.55), "to": Color(0.55, 0.5, 0.42, 0.0),
	},
	# Hostile side: warm sparks when something hostile lands a hit, and a
	# heavier ember burst when an enemy dies. Never violet.
	&"hit_warm": {
		"amount": 14, "lifetime": 0.24, "velocity": 5.5, "spread": 160.0,
		"scale": 0.09, "gravity": -2.0, "up": false,
		"from": Color(1.0, 0.85, 0.6), "to": Color(0.95, 0.4, 0.15),
	},
	&"death_warm": {
		"amount": 26, "lifetime": 0.42, "velocity": 5.0, "spread": 180.0,
		"scale": 0.12, "gravity": -1.0, "up": false,
		"from": Color(1.0, 0.8, 0.5), "to": Color(0.8, 0.25, 0.1),
	},
}

## Visible shots. The summons apply damage instantly, so nothing ever travelled
## between a shooter and its target — the Gun Construct's "bullets" were pure
## bookkeeping. These are cosmetic: the hit has already landed, and the tracer
## exists so the player can see WHY.
const TRACER_COUNT := 24
const TRACER_SECONDS := 0.09

## Visible sword arcs. Same problem as the tracers, different weapon: the Sword
## Wisp's damage landed with nothing on screen. Built as geometry rather than
## from a flipbook because the CC0 slash sheet's license is still unverified,
## and an arc is cheap to describe exactly.
const SLASH_COUNT := 8
const SLASH_SECONDS := 0.16
## How far the arc travels during its life, in degrees. The blade is already
## through the target when this plays; the sweep is what sells the follow-through.
const SLASH_SWEEP_DEGREES := 38.0

var _tracers: Array[MeshInstance3D] = []
var _tracer_live: Array[Dictionary] = []
var _tracer_cursor := 0
var _tracer_shown := 0

var _slashes: Array[MeshInstance3D] = []
var _slash_live: Array[Dictionary] = []
var _slash_cursor := 0
var _slash_shown := 0
## Alternates every call, so consecutive hits cut down-left then down-right —
## the "back and forth" read, rather than the same stroke stamped repeatedly.
var _slash_flip := false

var _pools: Dictionary = {}
var _cursor: Dictionary = {}
var _bursts_fired := 0


func _ready() -> void:
	initialize()


var _initialized := false

## Public and idempotent — the project's standing answer to `_ready` never
## firing for nodes added during a `--script` harness's `_initialize`.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	for kind in KINDS:
		var list: Array = []
		for i in POOL_PER_KIND:
			var p := _build_emitter(kind, KINDS[kind])
			add_child(p)
			list.append(p)
		_pools[kind] = list
		_cursor[kind] = 0

	for i in TRACER_COUNT:
		var t := MeshInstance3D.new()
		t.name = "Tracer%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.10, 0.10, 1.0)
		t.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(0.85, 0.9, 1.0)
		t.set_surface_override_material(0, mat)
		t.visible = false
		t.layers = 2
		add_child(t)
		_tracers.append(t)

	var arc := _build_arc_mesh()
	for i in SLASH_COUNT:
		var s := MeshInstance3D.new()
		s.name = "Slash%d" % i
		s.mesh = arc
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		# Two-sided: the arc is a flat ribbon and the flip that gives the
		# back-stroke turns it away from the camera half the time.
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Deliberately NOT billboard_mode. Godot's billboard replaces the whole
		# model basis in the vertex shader, which throws away the roll — and the
		# roll IS the slash. `_face_camera` does the same job per frame and keeps
		# the stroke angle.
		smat.albedo_color = SLASH_COLOUR
		s.set_surface_override_material(0, smat)
		s.visible = false
		s.layers = 2
		add_child(s)
		_slashes.append(s)


## Blue-white: the Sword Wisp is the player's, and guide §4 gives the cool end
## of the spectrum to the friendly side without exception.
const SLASH_COLOUR := Color(0.82, 0.90, 1.0)

## The crescent, in the mesh's own XY plane, radius 1. Callers scale it.
##
## Tapered to a point at both ends — a constant-width band reads as a rainbow,
## not a blade. Width peaks in the middle where the edge would be moving fastest.
const ARC_DEGREES := 108.0
const ARC_SEGMENTS := 24
const ARC_HALF_WIDTH := 0.15

static func _build_arc_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var span := deg_to_rad(ARC_DEGREES)
	for i in ARC_SEGMENTS:
		var t0 := float(i) / float(ARC_SEGMENTS)
		var t1 := float(i + 1) / float(ARC_SEGMENTS)
		var a0 := (t0 - 0.5) * span
		var a1 := (t1 - 0.5) * span
		# sin(pi*t) is 0 at both ends and 1 in the middle: the taper.
		var w0 := sin(PI * t0) * ARC_HALF_WIDTH
		var w1 := sin(PI * t1) * ARC_HALF_WIDTH
		var inner0 := Vector3(cos(a0) * (1.0 - w0), sin(a0) * (1.0 - w0), 0.0)
		var outer0 := Vector3(cos(a0) * (1.0 + w0), sin(a0) * (1.0 + w0), 0.0)
		var inner1 := Vector3(cos(a1) * (1.0 - w1), sin(a1) * (1.0 - w1), 0.0)
		var outer1 := Vector3(cos(a1) * (1.0 + w1), sin(a1) * (1.0 + w1), 0.0)
		verts.append_array([inner0, outer0, outer1, inner0, outer1, inner1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Cuts a visible arc at `at`. Consecutive calls alternate stroke direction, so
## a summon holding a target slices back and forth instead of stamping the same
## frame. `scale` is the arc's radius in world units.
func slash(at: Vector3, scale: float = 1.0, colour: Color = SLASH_COLOUR) -> bool:
	initialize()
	if _slashes.is_empty() or scale <= 0.0:
		return false
	var s := _slashes[_slash_cursor]
	_slash_cursor = (_slash_cursor + 1) % _slashes.size()

	_slash_flip = not _slash_flip
	var direction := 1.0 if _slash_flip else -1.0
	# Off-vertical so the stroke is a diagonal cut rather than a windscreen wipe.
	var start := deg_to_rad(52.0) * direction
	var mat := s.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		mat.albedo_color = colour
	s.global_position = at
	s.visible = true
	_slash_live.append({
		"node": s, "age": 0.0, "at": at, "scale": scale,
		"start": start, "direction": direction,
	})
	_slash_shown += 1
	return true


## Points a node's local XY plane at the active camera and rolls it by `angle`.
## Stands in for billboarding, which cannot carry the roll.
func _face_camera(node: Node3D, at: Vector3, angle: float, scale: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var to_camera := Vector3.BACK
	if camera != null:
		var delta := camera.global_position - at
		if delta.length_squared() > 0.0001:
			to_camera = delta.normalized()
	var up := Vector3.UP
	if absf(to_camera.dot(up)) > 0.999:
		up = Vector3.BACK
	var basis := Basis.looking_at(-to_camera, up) * Basis(Vector3(0, 0, 1), angle)
	node.global_transform = Transform3D(basis.scaled(Vector3(scale, scale, scale)), at)


## Fires a visible bolt from `from` to `to`. Stretched along its own path so it
## reads as a shot rather than a dot, and gone in under a tenth of a second —
## long enough to see the line, short enough not to clutter a firefight.
func tracer(from: Vector3, to: Vector3, colour: Color = Color(0.85, 0.9, 1.0)) -> bool:
	initialize()
	if _tracers.is_empty():
		return false
	var t := _tracers[_tracer_cursor]
	_tracer_cursor = (_tracer_cursor + 1) % _tracers.size()

	var delta := to - from
	var length := delta.length()
	if length < 0.05:
		return false
	t.global_position = (from + to) * 0.5
	t.look_at(to, Vector3.UP)
	t.scale = Vector3(1.0, 1.0, length)
	var mat := t.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		mat.albedo_color = colour
	t.visible = true
	_tracer_live.append({"node": t, "age": 0.0})
	_tracer_shown += 1
	return true


func _process(delta: float) -> void:
	_process_tracers(delta)
	_process_slashes(delta)


func _process_slashes(delta: float) -> void:
	if _slash_live.is_empty():
		return
	var still: Array[Dictionary] = []
	for entry in _slash_live:
		var node := entry["node"] as MeshInstance3D
		var age := float(entry["age"]) + delta
		if age >= SLASH_SECONDS or not is_instance_valid(node):
			if is_instance_valid(node):
				node.visible = false
			continue
		var t := age / SLASH_SECONDS
		# Decelerating sweep: fast out of the shoulder, settling at the end.
		var eased := 1.0 - pow(1.0 - t, 2.5)
		var angle := float(entry["start"]) \
			- deg_to_rad(SLASH_SWEEP_DEGREES) * float(entry["direction"]) * eased
		_face_camera(node, entry["at"] as Vector3, angle, float(entry["scale"]))
		var mat := node.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			# Holds full brightness through the first third, then falls away, so
			# the arc is legible before it starts leaving.
			mat.albedo_color.a = 1.0 if t < 0.35 else clampf((1.0 - t) / 0.65, 0.0, 1.0)
		entry["age"] = age
		still.append(entry)
	_slash_live = still


func _process_tracers(delta: float) -> void:
	if _tracer_live.is_empty():
		return
	var still: Array[Dictionary] = []
	for entry in _tracer_live:
		var node := entry["node"] as MeshInstance3D
		var age := float(entry["age"]) + delta
		if age >= TRACER_SECONDS or not is_instance_valid(node):
			if is_instance_valid(node):
				node.visible = false
			continue
		var mat := node.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = 1.0 - age / TRACER_SECONDS
		entry["age"] = age
		still.append(entry)
	_tracer_live = still


func tracers_fired() -> int:
	return _tracer_shown


func slashes_cut() -> int:
	return _slash_shown


func _build_emitter(kind: StringName, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "%s_%d" % [kind, _pools.get(kind, []).size()]
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(cfg["amount"])
	p.lifetime = float(cfg["lifetime"])
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0) if bool(cfg["up"]) else Vector3(0, 0.35, 1)
	mat.spread = float(cfg["spread"])
	mat.initial_velocity_min = float(cfg["velocity"]) * 0.6
	mat.initial_velocity_max = float(cfg["velocity"])
	mat.gravity = Vector3(0, float(cfg["gravity"]), 0)
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.7
	mat.scale_max = 1.15

	var ramp := Gradient.new()
	ramp.set_color(0, cfg["from"])
	ramp.set_color(1, Color(cfg["to"].r, cfg["to"].g, cfg["to"].b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(float(cfg["scale"]), float(cfg["scale"]))
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.vertex_color_use_as_albedo = true
	quad.material = qmat
	p.draw_pass_1 = quad
	return p


## Fires a burst. `aim` orients directional kinds (muzzle, dash); radial kinds
## ignore it. Unknown kinds are a warning, not a crash — a typo in a caller
## must not take the run down.
func burst(kind: StringName, at: Vector3, aim: Vector3 = Vector3.ZERO) -> bool:
	initialize()
	if not _pools.has(kind):
		push_warning("ParticleFx: unknown kind '%s'" % kind)
		return false
	var list: Array = _pools[kind]
	var index := int(_cursor[kind])
	_cursor[kind] = (index + 1) % list.size()
	var p := list[index] as GPUParticles3D

	p.global_position = at
	if aim.length_squared() > 0.001:
		var mat := p.process_material as ParticleProcessMaterial
		mat.direction = aim.normalized() + Vector3(0, 0.25, 0)
	p.restart()
	p.emitting = true
	_bursts_fired += 1
	return true


# ------------------------------------------------------------------ inspection

func kinds() -> Array:
	return KINDS.keys()


func emitter_count() -> int:
	var n := 0
	for kind in _pools:
		n += (_pools[kind] as Array).size()
	return n


func bursts_fired() -> int:
	return _bursts_fired
