class_name ProjectilePool
extends Node3D

## Fixed-capacity projectile pool.
##
## Master guide §17 asks for pooling of repeated projectiles so node churn stays
## flat. Phase 2 acceptance requires projectiles return to a pool or free without
## leaks — this pool never frees during a run, so the live node count is constant
## no matter how long the staff fires.

const DEFAULT_CAPACITY := 48

@export var projectile_scene: PackedScene
@export var capacity: int = DEFAULT_CAPACITY

var _free: Array[FocusProjectile] = []
var _busy: Array[FocusProjectile] = []
## Counts requests that arrived with the pool exhausted, for the debug overlay.
var _starved := 0


func _ready() -> void:
	if projectile_scene == null:
		push_error("ProjectilePool: projectile_scene not set")
		return
	for i in capacity:
		var p := projectile_scene.instantiate() as FocusProjectile
		if p == null:
			push_error("ProjectilePool: scene is not a FocusProjectile")
			return
		p.expired.connect(_on_expired)
		add_child(p)
		_free.append(p)


## Returns an inactive projectile, or null when the pool is exhausted.
## Exhaustion is deliberately not an error — dropping a shot beats unbounded
## allocation, and the counter surfaces it.
func acquire() -> FocusProjectile:
	if _free.is_empty():
		_starved += 1
		return null
	var p: FocusProjectile = _free.pop_back()
	_busy.append(p)
	return p


func _on_expired(p: FocusProjectile) -> void:
	_busy.erase(p)
	if not _free.has(p):
		_free.append(p)


## Returns every live projectile to the pool. Used on room clear so stray
## projectiles cannot survive into the next encounter.
func release_all() -> void:
	for p in _busy.duplicate():
		p.expire()


func active_count() -> int:
	return _busy.size()


func free_count() -> int:
	return _free.size()


func total_count() -> int:
	return _busy.size() + _free.size()


func starved_count() -> int:
	return _starved
