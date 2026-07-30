class_name ProjectilePool
extends Node3D

## Re-broadcast of every pooled projectile's impact, so the presentation layer
## makes ONE connection per pool instead of one per projectile.
signal projectile_impacted(at: Vector3)

## Fixed-capacity projectile pool.
##
## Master guide §17 asks for pooling of repeated projectiles so node churn stays
## flat. Phase 2 acceptance requires projectiles return to a pool or free without
## leaks — this pool never frees during a run, so the live node count is constant
## no matter how long the staff fires.

const DEFAULT_CAPACITY := 48

@export var projectile_scene: PackedScene
@export var capacity: int = DEFAULT_CAPACITY
## Hostile pools fire enemy attacks: layer 7, hitting the player hurtbox on
## layer 4. Friendly pools keep the default layer 6 / layer 5 pairing.
@export var hostile := false

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
		if hostile:
			p.make_hostile()
		p.expired.connect(_on_expired)
		p.impacted.connect(func(at: Vector3) -> void: projectile_impacted.emit(at))
		add_child(p)
		_free.append(p)
	if hostile:
		add_to_group("hostile_projectile_pool")


## Returns an inactive projectile, or null when the pool is exhausted.
## Exhaustion is deliberately not an error — dropping a shot beats unbounded
## allocation, and the counter surfaces it.
func acquire() -> FocusProjectile:
	_reclaim_idle()
	if _free.is_empty():
		_starved += 1
		return null
	var p: FocusProjectile = _free.pop_back()
	_busy.append(p)
	return p


## A projectile is marked busy the moment it is handed out, before it is
## launched. A caller that acquires and then bails — pool exhausted downstream,
## an early return, an exception — would otherwise strand that slot for the rest
## of the run. Reclaiming checked-out-but-inactive projectiles makes the pool
## self-healing rather than trusting every caller to launch what it takes.
func _reclaim_idle() -> void:
	for p in _busy.duplicate():
		if not p.is_active():
			_busy.erase(p)
			if not _free.has(p):
				_free.append(p)


## Projectiles genuinely in flight. Distinct from the checked-out count: only
## this reflects what a player would see on screen.
func in_flight_count() -> int:
	var n := 0
	for p in _busy:
		if p.is_active():
			n += 1
	return n


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
