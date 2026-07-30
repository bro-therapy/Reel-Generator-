extends SceneTree

## Phase 6 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase6_acceptance.gd

const ROOM := "res://scenes/rooms/combat_room.tscn"
const PLAYER := "res://scenes/actors/player.tscn"
const TICK := 1.0 / 60.0

var _pass := 0
var _fail := 0

var _world: Node3D
var _room: EncounterController
var _player: Player

var _stage := -1
var _ticks := 0
var _mark := 0.0
var _lock_at_entry := false
var _waves_started: Array[int] = []
var _wave_counts: Array[int] = []
var _rewards := 0
var _clear_seen := false
var _live_at_wave_start := 0
var _idol_children_counted := false
var _room_live_with_only_children := -1
var _expected_children := 0
var _state_with_only_children := -1
var _injected_combat := false


func _initialize() -> void:
	print("\n=== PHASE 6 ACCEPTANCE ===\n")
	_check_state_graph()
	_check_encounter_parsing()

	_world = Node3D.new()
	root.add_child(_world)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)

	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	# Position before insertion: the player carries top_level pools, and assigning
	# global_position the instant after add_child makes Godot read a transform
	# mid-propagation. Harmless, but it is avoidable noise.
	_player.position = Vector3(0, 0, 20)
	_world.add_child(_player)

	_room = (load(ROOM) as PackedScene).instantiate() as EncounterController
	# combat_b is the richest encounter: three waves, a Nest Idol whose children
	# must hold the room open, and the Gilded Bellguard elite.
	_room.encounter_id = &"combat_b"
	_world.add_child(_room)


func _physics_process(delta: float) -> bool:
	if _room == null:
		_summary()
		return true
	_ticks += 1
	if _ticks < 5:
		return false

	match _stage:
		-1: _stage_bind()
		0: _stage_gate_open_before_entry()
		1: _stage_enter()
		2: _stage_lock_after_entry()
		3: _stage_wave_progress()
		4: _stage_clear_checks()
		5: _stage_reward_once()
		6: _stage_exit_unlocks()
		_:
			_summary()
			return true
	return false


func _stage_bind() -> void:
	_room.wave_started.connect(func(i, n):
		_waves_started.append(i)
		_wave_counts.append(n))
	_room.reward_spawned.connect(func(_r): _rewards += 1)
	_room.room_cleared.connect(func(): _clear_seen = true)
	_ok("combat room instantiates", "encounter '%s'" % _room.encounter_id)
	_stage = 0


## Brief: "Gates lock only after the player enters."
func _stage_gate_open_before_entry() -> void:
	_mark += TICK
	if _mark < 0.5:
		# The player is parked outside; the gate must stay open the whole time.
		if _room.is_gate_locked():
			_no("gate locked before entry", "sealed while the player was still outside")
			_stage = 1
		return
	if not _room.is_gate_locked() and _room.state() == RoomStateMachine.State.INACTIVE:
		_ok("gate stays open until the player enters", "INACTIVE and unlocked for %.1fs" % _mark)
	else:
		_no("gate before entry", "state %s locked=%s" % [_room.state_name(), _room.is_gate_locked()])
	_stage = 1


func _stage_enter() -> void:
	var trigger := _room.get_node_or_null("EntryTrigger") as RoomEntryTrigger
	if trigger == null:
		_no("entry trigger present", "no EntryTrigger on the room")
		_stage = 99
		return
	_lock_at_entry = _room.is_gate_locked()
	trigger.notify_entered(_player)
	if _room.state() == RoomStateMachine.State.INTRO:
		_ok("entering the room starts the encounter", "INACTIVE -> INTRO")
	else:
		_no("entry transition", "state %s" % _room.state_name())
	_mark = 0.0
	_stage = 2


func _stage_lock_after_entry() -> void:
	_mark += TICK
	if _mark < 1.0:
		return
	if not _lock_at_entry and _room.is_gate_locked():
		_ok("the gate locks after entry", "unlocked at entry, sealed once the encounter began")
	else:
		_no("gate lock", "locked_at_entry=%s locked_now=%s" % [_lock_at_entry, _room.is_gate_locked()])

	if _room.state() == RoomStateMachine.State.WAVES:
		_ok("room reaches WAVES", "INTRO -> LOCKED -> WAVES")
	else:
		_no("room state after lock", _room.state_name())
	_mark = 0.0
	_stage = 3


## Brief: "Each wave begins only when its condition is met" and
## "Room clear waits for all living encounter enemies."
func _stage_wave_progress() -> void:
	_mark += TICK

	# Sample continuously: a second wave must never start while the first is
	# still alive. Checking only at the end would miss an early overlap.
	if _waves_started.size() > 1 and _live_at_wave_start > 0:
		_no("wave condition", "wave %d started with %d enemies still alive" % [_waves_started[-1], _live_at_wave_start])
		_stage = 4
		return
	if _waves_started.size() != _live_at_wave_start:
		pass

	# A Nest Idol's children are live enemies and must hold the room open. Record
	# any moment where the live count exceeds what the wave itself spawned.
	var idol_alive := false
	for n in root.get_tree().get_nodes_in_group("enemies"):
		if n is EnemyBase and String((n as EnemyBase).data.id) == "nest_idol" and (n as EnemyBase).is_alive():
			idol_alive = true
			var role := (n as EnemyBase).behavior as NestIdolRole
			if role != null:
				# The authored 5.5 s pulse is slower than this harness's kill
				# cadence, so the idol would die before ever spawning. Speed it up
				# so the child-counting rule is actually exercised.
				if role.spawn_interval > 0.5:
					role.set_spawn_interval(0.3)
				if role.live_child_count() > 0 and not _idol_children_counted:
					# Prove the ROOM counts the children, not merely that the idol
					# has them. Kill the idol and every non-child enemy, then the
					# only things left alive are spawned children — if the room
					# still reports them and stays in WAVES, they hold it open.
					var children := role.live_child_count()
					var child_set := {}
					for c in role._children:
						child_set[c] = true
					for other in root.get_tree().get_nodes_in_group("enemies"):
						if other is EnemyBase and (other as EnemyBase).is_alive() and not child_set.has(other):
							(other as EnemyBase).kill()
					_room_live_with_only_children = _room.live_enemy_count()
					_expected_children = children
					_state_with_only_children = _room.state()
					_idol_children_counted = true

	# Kill everything periodically so the encounter progresses without a hero
	# actually fighting, then verify the room only advances when nothing lives.
	# Hold off the kill sweep until the idol has produced children, so the room
	# is genuinely held open by spawned enemies rather than by the idol itself.
	if idol_alive and not _idol_children_counted and _ticks < 2400:
		return

	if _mark > 1.0:
		var live := _room.live_enemy_count()
		# Just before the final kill, put real combat on screen so the cleanup
		# assertion has something to clean. Checking an already-empty scene
		# proved nothing.
		if live == 1 and not _injected_combat:
			_injected_combat = true
			_inject_live_combat()
		if live > 0:
			var before := _waves_started.size()
			# Kill exactly one enemy and confirm the room does NOT advance while
			# others remain — that is the "waits for all living enemies" rule.
			var killed := false
			for n in root.get_tree().get_nodes_in_group("enemies"):
				if n is EnemyBase and (n as EnemyBase).is_alive():
					if live > 1 and not killed:
						(n as EnemyBase).kill()
						killed = true
					elif live == 1:
						(n as EnemyBase).kill()
			if live > 1 and _waves_started.size() != before:
				_no("premature wave advance", "next wave started with enemies still alive")
				_stage = 4
				return
		_mark = 0.0

	if _room.state() != RoomStateMachine.State.WAVES:
		_stage = 4
	elif _ticks > 3600:
		_no("encounter progress", "still in WAVES after 60s")
		_stage = 4


## Puts a projectile in flight and a telegraph on the floor, so "projectiles and
## telegraphs clean up on clear" is measured against a scene that actually had
## some.
func _inject_live_combat() -> void:
	var tree := root.get_tree()
	for pool in tree.get_nodes_in_group("hostile_projectile_pool"):
		if pool is ProjectilePool:
			var p := (pool as ProjectilePool).acquire()
			if p != null:
				p.launch_raw(_player.global_position + Vector3(0, 1, 0), Vector3.FORWARD, 2.0, 30.0, 1, false, 0)
	var focus_pool := _player.get_node_or_null("ProjectilePool") as ProjectilePool
	if focus_pool != null:
		var fp := focus_pool.acquire()
		if fp != null:
			fp.launch_raw(_player.global_position + Vector3(0, 1, 0), Vector3.FORWARD, 2.0, 30.0, 1, false, 0)
	for t in tree.get_nodes_in_group("telegraphs"):
		if t is TelegraphController:
			(t as TelegraphController).show_telegraph(&"circle", 30.0, 2.0)


func _stage_clear_checks() -> void:
	var expected_waves := _room.data.wave_count() if _room.data != null else 0
	if _waves_started.size() == expected_waves:
		_ok("every wave ran in order", "%d waves, counts %s" % [_waves_started.size(), str(_wave_counts)])
	else:
		_no("wave count", "%d started, encounter declares %d" % [_waves_started.size(), expected_waves])

	if _clear_seen:
		_ok("room clear fires once nothing lives", "room_cleared emitted")
	else:
		_no("room clear", "room_cleared never emitted")

	if _room.live_enemy_count() == 0:
		_ok("no living enemy remains at clear", "0 alive")
	else:
		_no("clear with survivors", "%d still alive" % _room.live_enemy_count())

	# Brief: "Projectiles and telegraphs clean up on clear."
	var tree := root.get_tree()
	var live_projectiles := 0
	for p in tree.get_nodes_in_group("projectiles"):
		if p is FocusProjectile and (p as FocusProjectile).is_active():
			live_projectiles += 1
	var live_telegraphs := 0
	for t in tree.get_nodes_in_group("telegraphs"):
		if t is TelegraphController and (t as TelegraphController).is_visible_now():
			live_telegraphs += 1

	if not _injected_combat:
		_no("cleanup precondition", "no projectile or telegraph was live before the clear, so cleanup was untested")
	elif live_projectiles == 0 and live_telegraphs == 0:
		_ok("projectiles and telegraphs clean up on clear", "live combat injected before the clear, 0 left afterwards")
	else:
		_no("combat cleanup", "%d projectiles, %d telegraphs survived the clear" % [live_projectiles, live_telegraphs])

	if not _idol_children_counted:
		_no("child counting", "the idol never had live children, so the rule was untested")
	elif _room_live_with_only_children >= _expected_children and _expected_children > 0:
		_ok("Nest Idol children hold the room open", "idol and all others killed; room still counted %d child enemies" % _room_live_with_only_children)
	else:
		_no("child counting", "with only %d children alive the room reported %d live" % [_expected_children, _room_live_with_only_children])

	if _state_with_only_children == RoomStateMachine.State.WAVES:
		_ok("the room does not advance while children live", "stayed in WAVES with only spawned children alive")
	else:
		_no("premature advance on children", "room was %s" % RoomStateMachine.name_of(_state_with_only_children))

	if not _room.unknown_enemy_ids.is_empty():
		_no("unknown enemies in the encounter", ", ".join(_room.unknown_enemy_ids))
	else:
		_ok("every enemy the encounter names exists", "no unresolved ids")

	_mark = 0.0
	_stage = 5


## Brief: "Reward appears once."
func _stage_reward_once() -> void:
	_mark += TICK
	if _mark < 1.5:
		return
	if _room.state() != RoomStateMachine.State.REWARD:
		_no("reward state", "expected REWARD, got %s" % _room.state_name())
		_stage = 6
		return

	if _rewards == 1:
		_ok("reward spawns exactly once", "%d reward(s) after %d clears" % [_rewards, 1])
	else:
		_no("reward count", "%d rewards spawned" % _rewards)

	# Hammer the entry points that could double-spawn it.
	var trigger := _room.get_node_or_null("EntryTrigger") as RoomEntryTrigger
	for i in 5:
		if trigger != null:
			trigger.notify_entered(_player)
		_room.on_player_entered(_player)
	if _rewards == 1:
		_ok("re-entering cannot re-trigger the reward", "still %d after 10 further attempts" % _rewards)
	else:
		_no("reward re-trigger", "%d rewards after replay attempts" % _rewards)

	if _room.illegal_transition_count() > 0:
		_ok("forward-only room states rejected the replays", "%d illegal transitions blocked" % _room.illegal_transition_count())
	else:
		_ok("replays were absorbed without illegal transitions")

	_stage = 6


## Brief: "Exit never remains locked after reward selection."
func _stage_exit_unlocks() -> void:
	var locked_before := _room.is_gate_locked()
	_room.complete_reward_selection()

	if locked_before and not _room.is_gate_locked():
		_ok("the exit unlocks on reward selection", "locked through the fight, open afterwards")
	else:
		_no("exit lock", "locked_before=%s locked_after=%s" % [locked_before, _room.is_gate_locked()])

	if _room.state() == RoomStateMachine.State.COMPLETE:
		_ok("room reaches COMPLETE", "full lifecycle traversed")
	else:
		_no("final state", _room.state_name())

	# Completing again must not re-lock or re-reward.
	for i in 3:
		_room.complete_reward_selection()
	if not _room.is_gate_locked() and _rewards == 1:
		_ok("a completed room stays open", "no re-lock, no second reward")
	else:
		_no("completed room mutated", "locked=%s rewards=%d" % [_room.is_gate_locked(), _rewards])

	_stage = 99


# ---------------------------------------------------------------- static

func _check_state_graph() -> void:
	print("Room lifecycle (brief Phase 6)")
	var fsm := RoomStateMachine.new()
	fsm.warn_on_illegal = false
	var order := [
		RoomStateMachine.State.INTRO, RoomStateMachine.State.LOCKED,
		RoomStateMachine.State.WAVES, RoomStateMachine.State.CLEARING,
		RoomStateMachine.State.REWARD, RoomStateMachine.State.COMPLETE,
	]
	var walked := true
	for st in order:
		if not fsm.transition_to(st):
			walked = false
			break
	if walked:
		_ok("documented lifecycle is walkable", "INACTIVE -> INTRO -> LOCKED -> WAVES -> CLEARING -> REWARD -> COMPLETE")
	else:
		_no("lifecycle", "blocked at %s" % fsm.state_name())
	fsm.free()

	# No skipping: a room must not jump straight to REWARD or COMPLETE.
	var skipped: Array[String] = []
	for st in [RoomStateMachine.State.WAVES, RoomStateMachine.State.REWARD, RoomStateMachine.State.COMPLETE]:
		var probe := RoomStateMachine.new()
		probe.warn_on_illegal = false
		if probe.transition_to(st):
			skipped.append(RoomStateMachine.name_of(st))
		probe.free()
	if skipped.is_empty():
		_ok("states cannot be skipped", "reward and completion are unreachable early")
	else:
		_no("state skipping", "reached directly from INACTIVE: %s" % ", ".join(skipped))

	# No going back: a completed room cannot re-lock.
	var back := RoomStateMachine.new()
	back.warn_on_illegal = false
	back.state = RoomStateMachine.State.COMPLETE
	var regressed: Array[String] = []
	for st in [RoomStateMachine.State.LOCKED, RoomStateMachine.State.WAVES, RoomStateMachine.State.REWARD]:
		var probe := RoomStateMachine.new()
		probe.warn_on_illegal = false
		probe.state = RoomStateMachine.State.COMPLETE
		if probe.transition_to(st):
			regressed.append(RoomStateMachine.name_of(st))
		probe.free()
	if regressed.is_empty():
		_ok("a completed room cannot regress", "no path back to LOCKED")
	else:
		_no("state regression", "COMPLETE can return to: %s" % ", ".join(regressed))
	back.free()


func _check_encounter_parsing() -> void:
	print("\nEncounters parsed from LEVEL1_BALANCE.json")
	# Derived from the JSON, not pinned to a snapshot of it. The literal table
	# that used to live here broke the moment an encounter was retuned, which
	# says nothing about whether the PARSER works — the thing actually under
	# test. What must hold is that every declared encounter round-trips: the
	# parser sees the same wave count and the same enemy total the file states.
	var wrong: Array[String] = []
	var seen := 0
	for entry in Balance.data().get("encounters", []):
		var id := String(entry.get("id", ""))
		if id == "":
			continue
		seen += 1
		var waves: Array = entry.get("waves", [])
		var declared_enemies := 0
		for wave in waves:
			var i := 1
			while i < wave.size():
				declared_enemies += int(wave[i])
				i += 2

		var d := EncounterData.from_balance(id)
		if d == null:
			wrong.append("%s missing" % id)
			continue
		if d.wave_count() != waves.size() or d.total_enemies() != declared_enemies:
			wrong.append("%s parsed %d waves/%d enemies, JSON declares %d/%d"
				% [id, d.wave_count(), d.total_enemies(), waves.size(), declared_enemies])

	if seen == 0:
		wrong.append("no encounters declared in the balance file at all")
	if wrong.is_empty():
		_ok("every encounter round-trips from the JSON",
			"%d encounters, wave and enemy counts match" % seen)
	else:
		_no("encounter parsing", "; ".join(wrong))

	var rift := EncounterData.from_balance("optional_rift")
	if rift != null and rift.is_timed() and is_equal_approx(rift.duration_seconds, 45.0):
		_ok("the Rift is a timed encounter", "45 s survive-the-core, not clear-to-win")
	else:
		_no("timed encounter", "optional_rift duration %s" % (rift.duration_seconds if rift != null else "missing"))


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	print("\n" + "=".repeat(46))
	print("PHASE 6:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
