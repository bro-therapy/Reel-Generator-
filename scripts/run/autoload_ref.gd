class_name AutoloadRef
extends RefCounted

## How to reach an autoload from code that must also run without one.
##
## `Engine.has_singleton("GameSettings")` looks like the right question and is
## always false. Autoloads are children of the scene tree root, not engine
## singletons. Measured, with all three autoloads bound and a real window open:
##
##   has_singleton(SceneFlow)   = false      /root/SceneFlow    = true
##   has_singleton(GameSettings)= false      /root/GameSettings = true
##
## So every guard written the has_singleton way was dead code that read as
## working. Three of them mattered: the audio director never picked up the volume
## sliders, the quality controller never read the graphics preference, and
## SceneFlow's state stayed BOOT for an entire run. All three failed silently,
## which is why sixteen green phases never caught them.
##
## GDScript will happily let you write `GameSettings.foo` directly — the compiler
## knows the autoload names — but that aborts a `--script` harness, where no
## autoloads are bound. So the lookup stays dynamic and returns null instead of
## exploding, and every caller already has a null path because it needed one for
## the harnesses anyway.

## Never instantiated; the class is a namespace for the four lookups below.
static func node_named(autoload_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null:
			return root.get_node_or_null(NodePath(autoload_name))
	return null


static func settings() -> Node:
	return node_named("GameSettings")


static func save_service() -> Node:
	return node_named("SaveService")


static func scene_flow() -> Node:
	return node_named("SceneFlow")


## SceneFlow's own State enum, readable without the autoload being bound. Taken
## from the script resource rather than retyped here, so a new state added there
## is a new state here and the two cannot drift.
const SCENE_FLOW_SCRIPT := preload("res://scripts/run/scene_flow.gd")

static func flow_states() -> Dictionary:
	return SCENE_FLOW_SCRIPT.State


## Moves SceneFlow to a named state. Returns false when there is no autoload to
## move — a `--script` harness, or the boot scene run on its own — which is a
## normal outcome, not an error.
##
## Dispatched through call() rather than `flow.set_state(...)` because scene_flow.gd
## carries no class_name, so to the type checker `flow` is a plain Node with no
## such method.
static func set_flow_state(state_name: String) -> bool:
	var states: Dictionary = SCENE_FLOW_SCRIPT.State
	if not states.has(state_name):
		push_warning("AutoloadRef: no SceneFlow state named '%s'" % state_name)
		return false
	var flow := scene_flow()
	if flow == null:
		return false
	flow.call("set_state", int(states[state_name]))
	return true


## The live SceneFlow state as a name, or "" with no autoload bound. Exists so a
## check can assert the transition actually happened rather than assert that the
## call was made.
static func flow_state_name() -> String:
	var flow := scene_flow()
	if flow == null:
		return ""
	var value := int(flow.get("state"))
	for key in SCENE_FLOW_SCRIPT.State:
		if int(SCENE_FLOW_SCRIPT.State[key]) == value:
			return String(key)
	return ""


## True when the autoloads are bound — i.e. this is a real run, not a `--script`
## harness. Used to decide whether to bother looking rather than to gate anything
## important; individual lookups are null-checked on their own.
static func bound() -> bool:
	return settings() != null
