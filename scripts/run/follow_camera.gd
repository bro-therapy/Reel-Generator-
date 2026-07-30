class_name FollowCamera
extends Camera3D

## Follows the hero at a fixed angle. Guide §12.
##
##   var cam := FollowCamera.new()
##   add_child(cam)
##   cam.follow(hero)
##
## Two rules from the guide, and they are the reason this is a script rather than
## a camera parented to the player:
##
##   "Camera never rotates during gameplay." So the angle is set once and never
##   derived from anything the hero does. Parenting a camera to the player is the
##   usual way this rule gets broken by accident — the player's own facing leaks
##   into the camera basis and the room appears to swing.
##
##   "No sudden zoom steps — interpolate 0.35–0.6s." Distance changes are eased
##   over `zoom_seconds`, so the boss pull-back is a move rather than a cut.
##
## Position is smoothed and the angle is not, which is what makes it feel attached
## to the hero rather than dragged behind them.

## Degrees below horizontal, and metres back along the view axis. Both are
## derived, not chosen by eye.
##
## Pitch is set by the walls. Ward walls are 7 m (guide §12 keeps them tall enough
## to fill frame at the boss framing), and a wall standing between the camera and
## the hero occludes unless the sight line clears it. That height is a function of
## pitch alone — distance cancels — and at the 32 degrees the static test scenes
## used, the line clears a 7 m wall by 0.2 m, so the near wall filled the bottom
## half of the screen. 44 degrees clears it by 3.3 m.
##
## Distance is then set by the hero. Guide: "Hero reads at 88 px tall at
## 1920x1080." With a 45 degree vertical FOV, a 1.8 m hero subtends 88 px at
## 26.5 m — so that is the distance, rather than whatever looked right.
@export var pitch_degrees := 44.0
@export var distance := 26.5
## How high above the hero's feet the camera aims. Roughly chest height, so the
## hero sits slightly below frame centre and there is room to see what is ahead.
@export var look_height := 1.6
## Seconds for the position to catch up. Small enough to feel attached, large
## enough to absorb a dash.
@export var follow_seconds := 0.18
## Guide §12's interpolation window for a framing change.
@export_range(0.35, 0.6) var zoom_seconds := 0.45

var _target: Node3D
var _distance_goal := 0.0
var _distance_velocity := 0.0
var _position_velocity := Vector3.ZERO
var _snapped := false


func _ready() -> void:
	fov = 45.0
	_distance_goal = distance
	# Rotation is assigned once, here, and nothing else in this file writes to it.
	rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)


func follow(target: Node3D) -> void:
	_target = target
	_snapped = false


## Requests a new framing distance, eased in over `zoom_seconds`. Guide §12 pulls
## back 10–15% for the boss; this is how.
func set_framing(new_distance: float) -> void:
	_distance_goal = maxf(new_distance, 1.0)


func framing() -> float:
	return distance


func _physics_process(delta: float) -> void:
	tick(delta)


## Explicit so a check can drive the camera without a running tree.
func tick(delta: float) -> void:
	if _target == null:
		return

	distance = _ease(distance, _distance_goal, zoom_seconds, delta)

	var look_at := _target_position() + Vector3(0.0, look_height, 0.0)
	# Straight up the pitch angle from the look-at point. Derived from the fixed
	# angle rather than from the hero's transform, so the hero cannot rotate it.
	var back := Vector3(
		0.0,
		sin(deg_to_rad(pitch_degrees)),
		cos(deg_to_rad(pitch_degrees))).normalized()
	var goal := look_at + back * distance

	if not _snapped:
		# First frame lands on the mark. Easing in from wherever the camera was
		# built reads as a swoop nobody asked for.
		global_position = goal
		_snapped = true
		return

	global_position = Vector3(
		_ease(global_position.x, goal.x, follow_seconds, delta),
		_ease(global_position.y, goal.y, follow_seconds, delta),
		_ease(global_position.z, goal.z, follow_seconds, delta))


func _target_position() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	# Nodes added this frame are not in the tree yet, so global_position throws.
	return _target.global_position if _target.is_inside_tree() else _target.position


## Exponential approach, framerate independent. `seconds` is roughly the time to
## close most of the gap; using a fixed per-frame lerp factor instead would make
## the camera faster at high framerates, which is the classic version of this bug.
static func _ease(from: float, to: float, seconds: float, delta: float) -> float:
	if seconds <= 0.0:
		return to
	return lerpf(from, to, 1.0 - exp(-delta / seconds))


## True while the camera is level about Y and Z — the guide's "never rotates"
## rule, in a form a check can assert.
func is_unrotated() -> bool:
	return is_zero_approx(rotation.y) and is_zero_approx(rotation.z)


func pitch() -> float:
	return -rad_to_deg(rotation.x)
