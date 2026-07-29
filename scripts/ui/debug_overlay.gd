extends CanvasLayer

## Debug overlay required by Phase 0: FPS, active enemies, projectiles,
## current target, and room state. Toggled with F3 / controller Back.
##
## Every reading is defensive — the systems it reports on arrive in later
## phases, so it must render correctly when none of them exist yet.

const GROUP_ENEMIES := "enemies"
const GROUP_PROJECTILES := "projectiles"
const GROUP_PLAYER := "player"
const GROUP_COMBAT_ROOM := "combat_room"

const REFRESH_INTERVAL := 0.25

@onready var _label: Label = $Panel/Margin/Readout

var _elapsed := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	if _label == null:
		return
	_label.text = "\n".join([
		"FPS            %d" % Engine.get_frames_per_second(),
		"Enemies        %d" % _count_in_group(GROUP_ENEMIES),
		"Projectiles    %d" % _count_in_group(GROUP_PROJECTILES),
		"Target         %s" % _current_target_name(),
		"Room           %s" % _room_state(),
		"Nodes          %d" % _node_count(),
	])


func _count_in_group(group: StringName) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group(group).size()


func _first_in_group(group: StringName) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null


## Reads the player's current Focus Weapon target once Phase 2 lands.
func _current_target_name() -> String:
	var player := _first_in_group(GROUP_PLAYER)
	if player == null:
		return "-"
	if not player.has_method("get_current_target"):
		return "-"
	var target: Variant = player.call("get_current_target")
	if target == null or not is_instance_valid(target):
		return "none"
	return String((target as Node).name)


## Reads the active room's state machine once Phase 6 lands.
func _room_state() -> String:
	var room := _first_in_group(GROUP_COMBAT_ROOM)
	if room == null:
		return "-"
	if not room.has_method("get_state_name"):
		return "-"
	return String(room.call("get_state_name"))


func _node_count() -> int:
	var tree := get_tree()
	return tree.get_node_count() if tree != null else 0
