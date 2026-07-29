class_name TelegraphController
extends Node3D

## Hostile attack telegraphs (master guide §10, §11, §12).
##
## Every damaging enemy attack must announce itself in red or orange before it
## lands. EnemyBase enforces that structurally — it refuses to deal damage
## unless this controller confirms a telegraph was shown for the current attack
## — so the rule cannot be broken by forgetting a call.
##
## Colours come from ASSET_MANIFEST.json `color_rules.hostile`, and the material
## is pinned to RenderPriority.HOSTILE_TELEGRAPH so friendly violet can never
## draw over it.

signal telegraph_shown(shape: StringName, seconds: float)

## ASSET_MANIFEST color_rules.hostile.
const HOSTILE_RED := Color("#FF5B67")
const HOSTILE_ORANGE := Color("#FF8A3D")
const HOSTILE_WARM_WHITE := Color("#FFF0D4")

const SHAPE_CIRCLE := &"circle"
const SHAPE_WEDGE := &"wedge"
const SHAPE_LINE := &"line"

var shape: StringName = SHAPE_CIRCLE
var radius := 1.8

## Diagnostics for the acceptance harness.
var telegraphs_shown := 0
var last_shape: StringName = &""
var last_duration := 0.0

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _time_left := 0.0
## True from the moment a telegraph starts until the attack it announced resolves.
var _armed := false


func _ready() -> void:
	add_to_group("telegraphs")
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(HOSTILE_RED.r, HOSTILE_RED.g, HOSTILE_RED.b, 0.55)
	# Guide §11: red telegraphs remain visible beneath all friendly effects.
	_material.render_priority = RenderPriority.HOSTILE_TELEGRAPH
	_material.no_depth_test = true

	_mesh = MeshInstance3D.new()
	_mesh.name = "TelegraphMesh"
	_mesh.mesh = PlaneMesh.new()
	_mesh.material_override = _material
	_mesh.visible = false
	add_child(_mesh)


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_mesh.visible = false


## Starts a telegraph. `seconds` should match the windup so the warning is on
## screen for exactly as long as the player has to react.
func show_telegraph(telegraph_shape: StringName, seconds: float, telegraph_radius: float) -> void:
	shape = telegraph_shape
	radius = telegraph_radius
	_time_left = maxf(seconds, 0.0)
	_armed = true
	telegraphs_shown += 1
	last_shape = telegraph_shape
	last_duration = seconds

	var plane := _mesh.mesh as PlaneMesh
	match telegraph_shape:
		SHAPE_LINE:
			# A thin lane along the dash path.
			plane.size = Vector2(0.35, telegraph_radius * 2.0)
			_mesh.position = Vector3(0.0, 0.03, -telegraph_radius)
			_material.albedo_color = Color(HOSTILE_RED.r, HOSTILE_RED.g, HOSTILE_RED.b, 0.7)
		SHAPE_WEDGE:
			# Approximated as a forward rectangle for the blockout.
			plane.size = Vector2(telegraph_radius * 1.4, telegraph_radius)
			_mesh.position = Vector3(0.0, 0.03, -telegraph_radius * 0.5)
			_material.albedo_color = Color(HOSTILE_ORANGE.r, HOSTILE_ORANGE.g, HOSTILE_ORANGE.b, 0.6)
		_:
			plane.size = Vector2(telegraph_radius * 2.0, telegraph_radius * 2.0)
			_mesh.position = Vector3(0.0, 0.03, 0.0)
			_material.albedo_color = Color(HOSTILE_RED.r, HOSTILE_RED.g, HOSTILE_RED.b, 0.55)

	_mesh.visible = true
	telegraph_shown.emit(telegraph_shape, seconds)


## True when a telegraph has been shown for the attack currently resolving.
## EnemyBase gates damage on this.
func is_armed() -> bool:
	return _armed


## Called once the announced attack has resolved (or been cancelled), so the
## next attack must telegraph again rather than reusing this one.
func disarm() -> void:
	_armed = false


func cancel() -> void:
	_armed = false
	_time_left = 0.0
	if _mesh != null:
		_mesh.visible = false


func is_visible_now() -> bool:
	return _mesh != null and _mesh.visible


## The colour currently displayed, for the acceptance check that telegraphs stay
## inside the hostile palette.
func current_color() -> Color:
	return _material.albedo_color if _material != null else Color.BLACK


func render_priority() -> int:
	return _material.render_priority if _material != null else -999


## True when `c` is a red/orange warm hue — hostile by the guide's colour
## ownership rules, and specifically not violet.
static func is_hostile_color(c: Color) -> bool:
	if c.r < 0.55:
		return false
	if c.b > c.r * 0.85:
		return false  # too blue: drifting toward the friendly violet range
	return c.r >= c.g
