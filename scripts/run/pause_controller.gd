class_name PauseController
extends Node

## Pause that freezes the fight but not the menu. Brief Phase 13.
##
## Godot's `SceneTree.paused` stops every node whose `process_mode` is
## PROCESS_MODE_PAUSABLE (the default) and keeps running anything marked
## PROCESS_MODE_WHEN_PAUSED or ALWAYS. So the rule is entirely about which nodes
## opt out — a menu that forgets to is a menu the player cannot navigate once
## they have opened it.
##
## This wraps that so the opting-out is done in one place and can be asserted.

signal paused_changed(is_paused: bool)

var _tree: SceneTree


func _init(tree: SceneTree = null) -> void:
	_tree = tree
	# Set here rather than in _ready(): the controller has to keep running while
	# the tree is paused or it could never unpause, and _ready() is too late if
	# it is added to an already-paused tree.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _tree == null:
		_tree = get_tree()


func is_paused() -> bool:
	return _tree != null and _tree.paused


func set_paused(value: bool) -> void:
	if _tree == null or _tree.paused == value:
		return
	_tree.paused = value
	paused_changed.emit(value)


func toggle() -> bool:
	set_paused(not is_paused())
	return is_paused()


## Marks a menu so it keeps taking input while the game is frozen. Applied to
## the subtree, because a Control whose children are still pausable renders but
## does not respond.
static func make_menu_interactive(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	for child in node.get_children():
		make_menu_interactive(child)


## Marks combat content so it freezes. The default already does this; naming it
## makes the intent explicit at the call site.
static func make_pausable(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE


## True when every node in the subtree keeps running while paused.
static func subtree_runs_while_paused(node: Node) -> bool:
	if node.process_mode not in [Node.PROCESS_MODE_WHEN_PAUSED, Node.PROCESS_MODE_ALWAYS]:
		return false
	for child in node.get_children():
		if not subtree_runs_while_paused(child):
			return false
	return true
