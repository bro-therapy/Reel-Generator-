class_name VfxEffect
extends Node3D

## A pooled, billboarded combat effect built from the VFX atlas.
##
## Friendly effects are pinned to RenderPriority.FRIENDLY_EFFECT so they cannot
## draw over hostile telegraphs (master guide §2). The priority is not a per-scene
## choice — it is assigned here from the shared contract.

signal finished(effect: VfxEffect)

@onready var _sprite: AnimatedSprite3D = $Sprite

var _active := false


func _ready() -> void:
	add_to_group("vfx")
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = false
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.animation_finished.connect(_on_animation_finished)
	_deactivate()


## `row` is a VFX atlas row: friendly_a, friendly_b, hostile, pickup_status.
func play_at(position: Vector3, row: StringName, scale_units: float) -> void:
	global_position = position
	_sprite.scale = Vector3.ONE * scale_units
	_sprite.render_priority = _priority_for(row)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(String(row)):
		_sprite.frame = 0
		_sprite.play(String(row))
	_activate()


## Friendly rows sit under hostile ones. Anything unrecognised is treated as
## friendly, which is the safe default — it can only ever be occluded, never occlude.
static func _priority_for(row: StringName) -> int:
	match row:
		&"hostile":
			return RenderPriority.HOSTILE_TELEGRAPH
		&"pickup_status":
			return RenderPriority.PICKUP
		_:
			return RenderPriority.FRIENDLY_EFFECT


func is_active() -> bool:
	return _active


func stop() -> void:
	if not _active:
		return
	_deactivate()
	finished.emit(self)


func _on_animation_finished() -> void:
	stop()


func _activate() -> void:
	_active = true
	visible = true
	set_process(true)


func _deactivate() -> void:
	_active = false
	visible = false
	set_process(false)
	global_position = Vector3(0.0, -1000.0, 0.0)
