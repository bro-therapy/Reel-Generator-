class_name AdditiveVfx
extends MeshInstance3D

## Plays one realistic effect sheet as an additive quad.
##
## Deliberately not an AnimatedSprite3D. SpriteBase3D has no blend mode, and its
## material_override replaces the material that carries the per-frame texture, so
## there is no way to get an additive sprite out of it. A quad with a shader that
## indexes the sheet costs the same one draw call and actually glows.
##
## The node is built to be pooled: `play()` and `stop()` are the whole interface,
## and a stopped effect keeps its mesh and material rather than freeing them.

signal finished(effect: AdditiveVfx)

const SHADER := preload("res://shaders/additive_vfx.gdshader")

var data: AdditiveVfxData

## Multiplies the effect's own energy. Owned by QualityController, which drives it
## from `effect_opacity` and `reduced_flashes` — an additive effect that blows out
## to white is exactly what a player who asked for reduced flashes is asking not
## to see. It scales the light rather than hiding the effect: the effect still has
## to read, or the setting would be changing what the player can know.
var energy_scale: float = 1.0:
	set(value):
		energy_scale = maxf(value, 0.0)
		if _material != null and data != null:
			_material.set_shader_parameter("energy", data.energy * energy_scale)

var _material: ShaderMaterial
var _quad: QuadMesh
var _elapsed := 0.0
var _playing := false
var _frame := -1


func _ready() -> void:
	add_to_group("vfx")
	if data != null:
		configure(data)
	set_process(_playing)


## Rebuilds the quad and material for `d`. Safe to call again with different data
## — that is how a pool reuses one node for different effects.
func configure(d: AdditiveVfxData) -> void:
	data = d
	if data == null:
		return

	_quad = QuadMesh.new()
	_quad.size = Vector2(data.world_height * data.aspect, data.world_height)
	# `play(p)` means the same thing for every effect: the effect sits on the
	# ground at p. Both standing kinds therefore lift the quad by half its height
	# so the node's origin is at the base. Leaving VIEW unlifted put half of the
	# lightning burst under the floor, where the depth test cut it off along a
	# hard horizontal line.
	if data.facing != AdditiveVfxData.Facing.GROUND:
		_quad.center_offset = Vector3(0.0, _quad.size.y * 0.5, 0.0)
	mesh = _quad

	# The quad is authored facing +Z. A ground effect has to lie in XZ, which is a
	# rotation of the node, not of the shader — the shader leaves facing 2 alone
	# for exactly this reason, so the rotation survives.
	rotation = Vector3.ZERO
	if data.facing == AdditiveVfxData.Facing.GROUND:
		rotation = Vector3(-PI * 0.5, 0.0, 0.0)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("sheet", data.texture)
	_material.set_shader_parameter("cols", data.cols)
	_material.set_shader_parameter("rows", data.rows)
	_material.set_shader_parameter("frame", 0)
	_material.set_shader_parameter("energy", data.energy * energy_scale)
	_material.set_shader_parameter("fade", 1.0)
	_material.set_shader_parameter("facing", int(data.facing))
	_material.set_shader_parameter("tint", data.tint)
	# Not a per-effect choice: it comes from the palette, so a friendly effect
	# cannot be authored on top of a hostile telegraph by mistake.
	_material.render_priority = data.render_priority()
	material_override = _material

	# These never cast or receive light — they are light.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func play(at: Vector3 = global_position, scale_multiplier: float = 1.0) -> void:
	if data == null:
		return
	if is_inside_tree():
		global_position = at
	else:
		position = at
	scale = Vector3.ONE * scale_multiplier
	_elapsed = 0.0
	_frame = -1
	_playing = true
	visible = true
	set_process(true)
	_apply(0)


func stop() -> void:
	if not _playing:
		return
	_playing = false
	visible = false
	set_process(false)
	finished.emit(self)


func is_playing() -> bool:
	return _playing


func current_frame() -> int:
	return maxi(_frame, 0)


func _process(delta: float) -> void:
	tick(delta)


## Explicit so acceptance checks can drive the animation without a running tree.
func tick(delta: float) -> void:
	if not _playing or data == null:
		return
	_elapsed += delta
	var total := data.duration()

	if data.loop:
		_apply(int(_elapsed * data.fps) % data.frame_count)
		return

	if _elapsed >= total:
		_apply(data.frame_count - 1)
		stop()
		return
	_apply(mini(int(_elapsed * data.fps), data.frame_count - 1))


func _apply(frame: int) -> void:
	if _material == null:
		return
	if frame != _frame:
		_frame = frame
		_material.set_shader_parameter("frame", data.cell_for(frame))
	_material.set_shader_parameter("fade", _fade_at(_elapsed))


## A one-shot ramps its light down over the tail of its run so it does not cut to
## nothing on the last frame. Loops stay at full until something stops them.
func _fade_at(elapsed: float) -> float:
	if data == null or data.loop:
		return 1.0
	var total := data.duration()
	var tail := total * data.fade_out_fraction
	if tail <= 0.0:
		return 1.0
	var into_tail := elapsed - (total - tail)
	if into_tail <= 0.0:
		return 1.0
	return clampf(1.0 - into_tail / tail, 0.0, 1.0)


func fade_value() -> float:
	return _fade_at(_elapsed)


func render_priority_value() -> int:
	return _material.render_priority if _material != null else -999


func shader_material() -> ShaderMaterial:
	return _material
