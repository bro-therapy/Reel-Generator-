class_name DamageNumbers
extends Node3D

## Floating combat text. Owner-requested: "some damage numbers over the enemy's
## head as to how much damage we're doing would be nice to have."
##
## Pooled Label3D, never allocated mid-fight — a Convergence burst can land a
## dozen hits in a frame, and node churn during combat is exactly what the
## projectile pool and the particle pool already exist to avoid.
##
## Colour ownership (guide §4) decides the colour, not the magnitude:
##   damage the PLAYER deals   -> blue-white, the friendly side
##   damage the player TAKES   -> warm red, the hostile side
##   a critical                -> gold, which is the reward colour and the one
##                                the eye should be pulled to
##
## Label3D rather than a Control: the number belongs in the world above a
## specific enemy, and a screen-space label would need per-frame unprojection
## and would sit wrongly the instant the camera eases.

const POOL_SIZE := 32
const RISE_UNITS := 1.3
const LIFETIME := 0.75
## Horizontal scatter so two hits on the same enemy in the same frame do not
## print exactly on top of each other and read as one number.
const SPREAD := 0.55

var _labels: Array[Label3D] = []
var _live: Array[Dictionary] = []
var _cursor := 0
var _rng := RandomNumberGenerator.new()
var _shown := 0
var _initialized := false


func _ready() -> void:
	initialize()


## Public and idempotent — `_ready` does not fire for nodes added during a
## `--script` harness's `_initialize`, which this project has been bitten by
## repeatedly.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_rng.randomize()
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.name = "Damage%d" % i
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		# Sized against the hero, who reads at 88 px on a 1080p screen. The first
		# pass rendered numbers nearly as tall as him, which pulled the eye off
		# the fight; and a 12 px outline at that scale swallowed the fill colour
		# so every number looked navy regardless of side.
		label.font_size = 40
		label.outline_size = 5
		label.outline_modulate = Color(0.05, 0.04, 0.09, 0.85)
		label.pixel_size = 0.0009
		label.visible = false
		# Actor visual layer, so floor decals cannot paint over it.
		label.layers = 2
		# Above actors but below the world UI, matching RenderPriority's order.
		label.render_priority = RenderPriority.WORLD_UI
		add_child(label)
		_labels.append(label)


## `to_player` flips the colour to the hostile side. `critical` overrides both.
func show_damage(amount: int, at: Vector3, critical: bool = false,
		to_player: bool = false) -> void:
	initialize()
	if amount <= 0 or _labels.is_empty():
		return
	var label := _labels[_cursor]
	_cursor = (_cursor + 1) % _labels.size()

	label.text = str(amount)
	if critical:
		label.modulate = Color(1.0, 0.86, 0.4)
		label.font_size = 54
	elif to_player:
		label.modulate = Color(1.0, 0.5, 0.4)
		label.font_size = 44
	else:
		label.modulate = Color(0.86, 0.93, 1.0)
		label.font_size = 40

	var start := at + Vector3(
		_rng.randf_range(-SPREAD, SPREAD), 0.2, _rng.randf_range(-SPREAD, SPREAD))
	label.global_position = start
	label.visible = true
	_live.append({"label": label, "from": start, "age": 0.0})
	_shown += 1


func _process(delta: float) -> void:
	if _live.is_empty():
		return
	var still_live: Array[Dictionary] = []
	for entry in _live:
		var label := entry["label"] as Label3D
		var age := float(entry["age"]) + delta
		if age >= LIFETIME or not is_instance_valid(label):
			if is_instance_valid(label):
				label.visible = false
			continue
		var t := age / LIFETIME
		# Rises fast then settles, and fades over the back half only, so the
		# number is fully readable for the first moment it exists.
		var eased := 1.0 - pow(1.0 - t, 2.0)
		label.global_position = (entry["from"] as Vector3) + Vector3(0.0, RISE_UNITS * eased, 0.0)
		label.modulate.a = 1.0 if t < 0.5 else clampf((1.0 - t) * 2.0, 0.0, 1.0)
		entry["age"] = age
		still_live.append(entry)
	_live = still_live


# ------------------------------------------------------------------ inspection

func shown_count() -> int:
	return _shown


func live_count() -> int:
	return _live.size()


func pool_size() -> int:
	return _labels.size()
