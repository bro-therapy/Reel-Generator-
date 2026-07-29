extends SceneTree

## Probe: reproduce the phase3 stage-1 sample instant and report, for each summon,
## its state and its distance from its OWN lane point — the quantity the harness
## check at phase3_acceptance.gd:134 never measures.

const FIELD := "res://scenes/tests/summon_field.tscn"
const TICK := 1.0 / 60.0

var _field: Node3D
var _player: Node3D
var _summons: Array = []
var _ticks := 0
var _mark := 0.0
var _armed := false


func _initialize() -> void:
	var packed := load(FIELD) as PackedScene
	_field = packed.instantiate() as Node3D
	root.add_child(_field)
	_player = _field.get_node_or_null("Player") as Node3D


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks < 5:
		return false
	if not _armed:
		for n in ["rune_hound", "sword_wisp", "gun_construct"]:
			_summons.append(_field.get_node_or_null(n))
		_armed = true
		return false

	_mark += TICK
	if _mark < 1.5:
		return false

	print("\n--- stage-1 sample instant (mark %.2fs) ---" % _mark)
	var positions := []
	for s in _summons:
		var fc: FollowController = s.get_node("FollowController")
		var lane: Vector3 = fc.lane_position(_player.global_position, fc.smoothed_forward())
		var d: float = s.global_position.distance_to(lane)
		positions.append(s.global_position)
		print("  %-14s state=%-8s lane_offset=%s  dist_from_own_lane=%.3f u (tolerance %.2f)  IN_LANE=%s" % [
			s.name, s.state_name(), str(fc.lane_offset), d, fc.lane_tolerance_units, str(d <= fc.lane_tolerance_units)])

	var min_sep := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			min_sep = minf(min_sep, (positions[i] as Vector3).distance_to(positions[j] as Vector3))
	print("  harness metric: min pairwise separation = %.3f u, gate is > 0.6 -> %s" % [min_sep, "PASS" if min_sep > 0.6 else "FAIL"])

	# What the authored lane points are actually separated by.
	var lanes := []
	for s in _summons:
		var fc: FollowController = s.get_node("FollowController")
		lanes.append(fc.lane_position(_player.global_position, fc.smoothed_forward()))
	var lane_min := INF
	for i in lanes.size():
		for j in range(i + 1, lanes.size()):
			lane_min = minf(lane_min, (lanes[i] as Vector3).distance_to(lanes[j] as Vector3))
	print("  authored lane points: min pairwise separation = %.3f u" % lane_min)

	quit(0)
	return true
