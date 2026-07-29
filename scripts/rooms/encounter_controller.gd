class_name EncounterController
extends Node3D

## Runs one room's encounter (build brief Phase 6).
##
## Owns the room lifecycle, spawns waves at spawn-point groups, decides when the
## room is clear, and spawns the reward exactly once.
##
## Two rules are structural rather than procedural:
##   - the gate never locks until the player has actually entered, and
##   - the room can only move forward through its states,
## so "gates lock only after the player enters", "reward appears once", and
## "exit never remains locked" cannot be broken by a mis-ordered call.

signal player_entered()
signal wave_started(index: int, enemy_count: int)
signal wave_cleared(index: int)
signal room_cleared()
signal reward_spawned(reward_id: StringName)
signal room_completed()

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const ENEMY_DATA_DIR := "res://data/enemies"

@export var encounter_id: StringName = &"combat_a"
@export var gate_path: NodePath
@export var spawn_root_path: NodePath
@export var reward_marker_path: NodePath
## Seconds of INTRO before the gate seals, so the player sees the room first.
@export var intro_seconds := 0.4
## Grace after the last enemy dies, letting projectiles and effects settle.
@export var clearing_seconds := 0.5

var data: EncounterData
var target: Node3D

var current_wave := -1
var rewards_spawned := 0
var unknown_enemy_ids: Array[String] = []

var _fsm: RoomStateMachine
var _gate: GateController
var _spawn_root: Node3D
var _reward_marker: Node3D
## Everything this encounter spawned, plus anything they spawned in turn.
var _spawned: Array[EnemyBase] = []
var _timer := 0.0


func _ready() -> void:
	add_to_group("combat_room")
	_fsm = RoomStateMachine.new()
	_fsm.name = "RoomStateMachine"
	add_child(_fsm)

	_gate = get_node_or_null(gate_path) as GateController
	_spawn_root = get_node_or_null(spawn_root_path) as Node3D
	_reward_marker = get_node_or_null(reward_marker_path) as Node3D

	data = EncounterData.from_balance(String(encounter_id))
	if data == null:
		push_error("EncounterController: no encounter '%s' in LEVEL1_BALANCE.json" % encounter_id)


func _physics_process(delta: float) -> void:
	_fsm.tick(delta)
	match _fsm.state:
		RoomStateMachine.State.INTRO:
			if _fsm.time_in_state >= intro_seconds:
				_begin_lock()
		RoomStateMachine.State.WAVES:
			_process_waves(delta)
		RoomStateMachine.State.CLEARING:
			if _fsm.time_in_state >= clearing_seconds:
				_begin_reward()
		_:
			pass


# ---------------------------------------------------------------- entry

## Called by the room's entry trigger. Until this fires the gate stays open —
## a room the player has not reached is never sealed.
func on_player_entered(player: Node3D) -> void:
	if _fsm.state != RoomStateMachine.State.INACTIVE:
		return
	target = player
	_fsm.transition_to(RoomStateMachine.State.INTRO)
	player_entered.emit()


func _begin_lock() -> void:
	_fsm.transition_to(RoomStateMachine.State.LOCKED)
	if _gate != null:
		_gate.set_locked(true)
	_fsm.transition_to(RoomStateMachine.State.WAVES)
	current_wave = -1
	_start_next_wave()


# ---------------------------------------------------------------- waves

func _process_waves(delta: float) -> void:
	if data == null:
		_begin_clearing()
		return

	# Timed encounters (the Rift) end on the clock, not on the last kill.
	if data.is_timed():
		_timer += delta
		if _timer >= data.duration_seconds:
			_begin_clearing()
			return

	# A wave's condition is simply that the previous wave is gone. Checking live
	# enemies rather than a spawn count is what makes Nest Idol children count.
	if live_enemy_count() > 0:
		return

	if current_wave >= 0:
		wave_cleared.emit(current_wave)
	if current_wave + 1 < data.wave_count():
		_start_next_wave()
	else:
		_begin_clearing()


func _start_next_wave() -> void:
	current_wave += 1
	if data == null or current_wave >= data.wave_count():
		return
	var groups: Array = data.waves[current_wave]
	var spawned := 0
	for group in groups:
		var g: Dictionary = group
		var enemy_id := String(g.get("enemy", ""))
		for i in int(g.get("count", 0)):
			if _spawn_enemy(enemy_id, spawned):
				spawned += 1
	wave_started.emit(current_wave, spawned)


func _spawn_enemy(enemy_id: String, index: int) -> bool:
	var path := "%s/%s.tres" % [ENEMY_DATA_DIR, enemy_id]
	if not ResourceLoader.exists(path):
		# The boss and any not-yet-built role are recorded rather than silently
		# skipped, so an encounter referencing them fails visibly.
		if not unknown_enemy_ids.has(enemy_id):
			unknown_enemy_ids.append(enemy_id)
		return false
	var enemy_data := load(path) as EnemyData
	var scene := load(ENEMY_SCENE) as PackedScene
	if enemy_data == null or scene == null:
		return false

	var enemy := scene.instantiate() as EnemyBase
	enemy.data = enemy_data
	enemy.target = target
	add_child(enemy)
	enemy.global_position = _spawn_position(index)
	_spawned.append(enemy)
	return true


func _spawn_position(index: int) -> Vector3:
	var points: Array[Node3D] = []
	if _spawn_root != null:
		for c in _spawn_root.get_children():
			if c is Node3D:
				points.append(c as Node3D)
	if points.is_empty():
		var angle := TAU * float(index) / 8.0
		return global_position + Vector3(cos(angle), 0.0, sin(angle)) * 6.0
	var point := points[index % points.size()]
	# Fan multiple enemies around a shared point so they do not stack exactly.
	var ring := float(index / points.size())
	var spread := TAU * float(index) / 5.0
	return point.global_position + Vector3(cos(spread), 0.0, sin(spread)) * (0.6 * ring)


## Live enemies belonging to this encounter, including anything they spawned.
## Counts group membership rather than the spawn list, so a Nest Idol's children
## hold the room open exactly as its parent does.
func live_enemy_count() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var n := 0
	for node in tree.get_nodes_in_group("enemies"):
		if node is EnemyBase and (node as EnemyBase).is_alive():
			n += 1
	return n


# ---------------------------------------------------------------- clear

func _begin_clearing() -> void:
	if not _fsm.transition_to(RoomStateMachine.State.CLEARING):
		return
	_cleanup_combat()
	room_cleared.emit()


## Projectiles and telegraphs must not survive a room clear (brief acceptance).
func _cleanup_combat() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for pool in tree.get_nodes_in_group("hostile_projectile_pool"):
		if pool is ProjectilePool:
			(pool as ProjectilePool).release_all()
	for p in tree.get_nodes_in_group("projectiles"):
		if p is FocusProjectile and (p as FocusProjectile).is_active():
			(p as FocusProjectile).expire()
	for t in tree.get_nodes_in_group("telegraphs"):
		if t is TelegraphController:
			(t as TelegraphController).cancel()


func _begin_reward() -> void:
	if not _fsm.transition_to(RoomStateMachine.State.REWARD):
		return
	# Forward-only states make this idempotent: REWARD is entered exactly once,
	# so the reward cannot double-spawn however often this is reached.
	rewards_spawned += 1
	reward_spawned.emit(data.reward if data != null else &"")


## Called by the reward UI once the player has chosen. Phase 7 owns the cards;
## Phase 6 only guarantees the room opens afterwards.
func complete_reward_selection() -> void:
	if _fsm.state != RoomStateMachine.State.REWARD:
		return
	_fsm.transition_to(RoomStateMachine.State.COMPLETE)
	if _gate != null:
		_gate.set_locked(false)
	room_completed.emit()


# ---------------------------------------------------------------- queries

func state() -> int:
	return _fsm.state


func state_name() -> String:
	return _fsm.state_name()


func get_state_name() -> String:
	return _fsm.state_name()


func is_gate_locked() -> bool:
	return _gate != null and _gate.is_locked


func illegal_transition_count() -> int:
	return _fsm.illegal_attempts


func spawned_count() -> int:
	return _spawned.size()
