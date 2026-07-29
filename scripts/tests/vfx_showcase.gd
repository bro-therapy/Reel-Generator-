extends Node3D

## Puts every realistic effect next to the hero, on the real floor, at real scale.
##
##   ./tools/screenshot.sh scenes/tests/vfx_showcase.tscn build/shots/vfx.png 40 70
##
## The point of this scene is the one thing headless acceptance checks cannot do:
## show whether the effects read. A check can prove the shockwave is hostile-red
## and sorts under a telegraph; only a render shows whether a 7 m ring reads as an
## impact or as a smear, and whether filmed fire sits on pixel actors or fights
## them.
##
## Effects are stepped by a fixed slice rather than the real frame delta. Two
## captures of the same run at the same frame number then show the same animation
## frame, which is the only way to tell a rendering change from an animation
## change when comparing two renders. Under llvmpipe the real delta swings enough
## that an unrelated diff looked like a shader bug.

const HERO := preload("res://scenes/actors/player.tscn")
const EFFECT_DIR := "res://data/vfx/realtime"
const ORDER := ["fire", "beam", "lightning", "shockwave"]
const SPACING := 7.0
const FIXED_STEP := 1.0 / 60.0

var _effects: Array[AdditiveVfx] = []


func _ready() -> void:
	_build_floor()
	_build_light()

	var slots := ORDER.size() + 1  # the hero occupies the leftmost slot
	var span := SPACING * float(slots - 1)
	var left := -span * 0.5

	var hero := HERO.instantiate()
	add_child(hero)
	hero.position = Vector3(left, 0.0, 0.0)

	for i in ORDER.size():
		var id: String = ORDER[i]
		var path := "%s/%s.tres" % [EFFECT_DIR, id]
		if not ResourceLoader.exists(path):
			push_warning("missing effect resource: %s" % path)
			continue
		var data := load(path) as AdditiveVfxData
		_spawn(data, Vector3(left + SPACING * float(i + 1), 0.02, 0.0), id)

	_build_camera(span)


func _process(_delta: float) -> void:
	for fx in _effects:
		fx.tick(FIXED_STEP)


func _spawn(data: AdditiveVfxData, at: Vector3, label: String) -> void:
	var fx := AdditiveVfx.new()
	fx.name = "Vfx_%s" % label
	fx.data = data
	add_child(fx)
	fx.configure(data)
	fx.play(at)
	# The showcase drives every effect itself, on a fixed step, so captures are
	# reproducible. Leaving the node's own _process on as well would tick each
	# effect twice at two different rates.
	fx.set_process(false)
	# One-shots would play once and vanish before a late capture frame, so the
	# showcase restarts them. `finished` already carries the effect, so binding it
	# again would make a three-argument call — only the position is bound here.
	if not data.loop:
		fx.finished.connect(_replay.bind(at))
	_effects.append(fx)


func _replay(fx: AdditiveVfx, at: Vector3) -> void:
	if not is_inside_tree():
		return
	fx.play(at)
	# play() turns the effect's own _process back on. The showcase is the only
	# thing allowed to tick it.
	fx.set_process(false)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	# Darker than the hero sandbox floor on purpose: additive effects add light,
	# so a bright floor is the worst case for reading them and a misleading one
	# for judging how they will look in the Ward.
	mat.albedo_color = Color(0.16, 0.14, 0.13)
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Vector3(0.86, 0.0, -0.5),
		Vector3(-0.32, 0.77, -0.55),
		Vector3(0.39, 0.63, 0.66),
		Vector3(0, 12, 0))
	sun.light_energy = 1.1
	add_child(sun)


## Pulls back far enough that the whole row is inside the frustum. Framing this by
## eye is how the first render lost the hero off one edge and the shockwave off
## the other.
func _build_camera(span: float) -> void:
	var cam := Camera3D.new()
	var fov_deg := 45.0
	cam.fov = fov_deg
	# Godot keeps vertical FOV, so the horizontal half-angle has to come off the
	# viewport aspect rather than the fov value.
	var aspect := 16.0 / 9.0
	var half_h := tan(deg_to_rad(fov_deg * 0.5)) * aspect
	var distance := (span * 0.5 + SPACING * 0.9) / half_h
	var pitch := deg_to_rad(32.0)

	add_child(cam)
	# look_at_from_position rather than a hand-built basis. Writing the three
	# columns out by hand has now put a camera through the floor once and pointed
	# one at the sky once, both times reporting a perfectly clean run over an
	# empty frame.
	cam.look_at_from_position(
		Vector3(0.0, distance * sin(pitch) + 1.5, distance * cos(pitch)),
		Vector3(0.0, 1.5, 0.0),
		Vector3.UP)
	cam.make_current()
