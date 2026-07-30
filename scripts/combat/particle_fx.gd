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
