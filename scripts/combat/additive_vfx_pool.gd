class_name AdditiveVfxPool
extends Node3D

## Pooled spawner for the realistic effect sheets.
##
##   var pool := AdditiveVfxPool.new()
##   add_child(pool)
##   pool.play(&"shockwave", impact_point)
##
## Effects are the one thing in this game that spawn in bursts — a boss slam and
## three summon signatures can land on the same frame — and they are also the one
## thing that is pure presentation. Allocating a node per hit is how a combat game
## ends up with a stutter that only shows up in the fight it matters in, so the
## nodes are made once and reused.
##
## Phase 15 asserts no growth in node count after repeated room clears. A pool
## with a hard ceiling is what makes that true by construction rather than by
## remembering to free things.

signal effect_started(id: StringName)
signal effect_dropped(id: StringName)

const EFFECT_DIR := "res://data/vfx/realtime"

## Per-effect ceiling. Past this, a request is dropped rather than queued: a
## fifth simultaneous shockwave adds nothing a player can see, and dropping is
## the only option that cannot cost frames.
@export var max_live_per_effect := 4

var _data: Dictionary = {}
var _free: Dictionary = {}
var _live: Dictionary = {}
var _started := 0
var _dropped := 0


func _ready() -> void:
	load_effects()


## Loads every .tres in the effect directory. Reads the directory rather than a
## hardcoded list so a new sheet is available as soon as it is built.
func load_effects() -> int:
	_data.clear()
	var dir := DirAccess.open(EFFECT_DIR)
	if dir == null:
		push_warning("no effect directory at %s — run build_additive_vfx.gd" % EFFECT_DIR)
		return 0

	for file in dir.get_files():
		# Exported builds rename .tres to .tres.remap, so match on the stem.
		if not file.ends_with(".tres") and not file.ends_with(".tres.remap"):
			continue
		var path := "%s/%s" % [EFFECT_DIR, file.trim_suffix(".remap")]
		var d := load(path) as AdditiveVfxData
		if d == null:
			push_warning("%s did not load as AdditiveVfxData" % path)
			continue
		var key := d.id if d.id != &"" else StringName(file.get_basename())
		_data[key] = d
		_free[key] = [] as Array[AdditiveVfx]
		_live[key] = [] as Array[AdditiveVfx]
	return _data.size()


func has_effect(id: StringName) -> bool:
	return _data.has(id)


func effect_ids() -> Array:
	var ids: Array = _data.keys()
	ids.sort()
	return ids


func data_for(id: StringName) -> AdditiveVfxData:
	return _data.get(id)


## Plays `id` at `at`. Returns the effect, or null if the request was dropped.
func play(id: StringName, at: Vector3, scale_multiplier: float = 1.0) -> AdditiveVfx:
	if not _data.has(id):
		push_warning("no effect named '%s'" % id)
		return null

	var live: Array = _live[id]
	if live.size() >= max_live_per_effect:
		_dropped += 1
		effect_dropped.emit(id)
		return null

	var free: Array = _free[id]
	var fx: AdditiveVfx
	if free.is_empty():
		fx = AdditiveVfx.new()
		fx.name = "Vfx_%s_%d" % [id, live.size()]
		add_child(fx)
		fx.configure(_data[id])
		fx.finished.connect(_on_finished.bind(id))
	else:
		fx = free.pop_back()

	live.append(fx)
	fx.play(at, scale_multiplier)
	_started += 1
	effect_started.emit(id)
	return fx


## Stops everything. Called on a room transition — a looping effect has no natural
## end, so without this a hazard fire would outlive the room that owns it.
func stop_all() -> void:
	for id in _live.keys():
		# stop() removes from _live via the finished signal, so iterate a copy.
		for fx in (_live[id] as Array).duplicate():
			fx.stop()


func live_count(id: StringName = &"") -> int:
	if id != &"":
		return (_live.get(id, []) as Array).size()
	var total := 0
	for key in _live:
		total += (_live[key] as Array).size()
	return total


func pooled_count() -> int:
	var total := 0
	for key in _free:
		total += (_free[key] as Array).size()
	return total


func started_count() -> int:
	return _started


func dropped_count() -> int:
	return _dropped


func _on_finished(fx: AdditiveVfx, id: StringName) -> void:
	var live: Array = _live[id]
	var at := live.find(fx)
	if at >= 0:
		live.remove_at(at)
	var free: Array = _free[id]
	if not free.has(fx):
		free.append(fx)
