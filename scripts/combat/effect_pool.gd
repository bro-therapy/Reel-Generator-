class_name EffectPool
extends Node3D

## Fixed-capacity pool of VfxEffect instances, shared by the hero and summons.
##
## Same discipline as ProjectilePool: nothing is freed during a run, so node
## count stays flat however long combat lasts.

const DEFAULT_CAPACITY := 24

@export var effect_scene: PackedScene
@export var capacity: int = DEFAULT_CAPACITY

var _free: Array[VfxEffect] = []
var _busy: Array[VfxEffect] = []
var _starved := 0


func _ready() -> void:
	if effect_scene == null:
		push_error("EffectPool: effect_scene not set")
		return
	for i in capacity:
		var e := effect_scene.instantiate() as VfxEffect
		if e == null:
			push_error("EffectPool: scene is not a VfxEffect")
			return
		e.finished.connect(_on_finished)
		add_child(e)
		_free.append(e)


## Spawns one effect. Returns null when exhausted rather than allocating.
func spawn(position: Vector3, row: StringName, scale_units: float = 1.0) -> VfxEffect:
	if _free.is_empty():
		_starved += 1
		return null
	var e: VfxEffect = _free.pop_back()
	_busy.append(e)
	e.play_at(position, row, scale_units)
	return e


func _on_finished(e: VfxEffect) -> void:
	_busy.erase(e)
	if not _free.has(e):
		_free.append(e)


func release_all() -> void:
	for e in _busy.duplicate():
		e.stop()


func active_count() -> int:
	return _busy.size()


func free_count() -> int:
	return _free.size()


func total_count() -> int:
	return _busy.size() + _free.size()


func starved_count() -> int:
	return _starved
