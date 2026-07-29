extends SceneTree

## Probe: trace one summon's state timeline and why it stalls between attacks.

const FIELD := "res://scenes/tests/summon_field.tscn"

var _field: Node3D
var _player: Player
var _hound: SummonBase
var _ticks := 0
var _bound := false


func _initialize() -> void:
	var packed := load(FIELD) as PackedScene
	_field = packed.instantiate() as Node3D
	root.add_child(_field)
	_player = _field.get_node_or_null("Player") as Player


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if not _bound:
		_hound = _field.get_node_or_null("rune_hound") as SummonBase
		if _hound == null:
			return false
		_bound = true
		_hound.state_changed.connect(func(to, from):
			var tc := _hound.get_node("TargetController") as SummonTargetController
			print("t=%6.3f  %-8s -> %-8s  cd=%.3f  tgt=%s  inRange=%s  d=%.2f" % [
				float(_ticks) / 60.0,
				SummonStateMachine.name_of(from), SummonStateMachine.name_of(to),
				_hound._attack_cooldown,
				tc.current_target.name if tc.current_target != null else "none",
				str(_hound._in_attack_range()),
				_hound.global_position.distance_to(_player.global_position),
			]))
		print("hound lane=%s target Close at %s" % [_hound.data.lane_offset, (_field.get_node("Close") as Node3D).global_position])
		return false

	if _ticks > 60 * 10:
		print("attacks=%d in %.1fs" % [_hound.attacks_landed, float(_ticks) / 60.0])
		quit(0)
		return true
	return false
