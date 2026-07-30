class_name ExperienceOrb
extends Area3D

## What a dead enemy leaves behind.
##
## Built entirely in code, like ParticleFx, so an assetless checkout still drops
## visible pickups and there is no scene file to keep in sync with the pool.
##
## Colour ownership: rewards are gold / teal / soft-green (guide §4). An orb is
## never violet — violet is the player's own colour, and a violet pickup on the
## floor reads as a summon, which is exactly the confusion the rule exists to
## prevent.
##
## Pooled, never freed mid-run: an encounter can drop a dozen at once and node
## churn during a fight is the thing the project already pools projectiles to
## avoid.

signal collected(orb: ExperienceOrb, amount: int)

## Layer 11 — outside the fixed 1-10 combat layers in guide §15, so a pickup can
## never be mistaken for a hurtbox by anything that already exists.
const PICKUP_LAYER := 1 << 10
const PLAYER_BODY_MASK := 1 << 1

var amount := 4
var _active := false
var _life := 0.0
var _magnet_radius := 4.5
var _magnet_speed := 11.0
var _lifetime := 30.0
var _mesh: MeshInstance3D
var _spin := 0.0


func _ready() -> void:
	collision_layer = PICKUP_LAYER
	collision_mask = PLAYER_BODY_MASK
	monitoring = true
	monitorable = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Generous relative to the visual: this is a pickup, and a player who walks
	# over the middle of one and does not collect it reads it as broken.
	sphere.radius = 0.6
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.18
	gem.height = 0.36
	gem.radial_segments = 6
	gem.rings = 3
	_mesh.mesh = gem
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.95, 0.7)
	mat.emission_energy_multiplier = 2.2
	_mesh.set_surface_override_material(0, mat)
	# Actor visual layer, so the floor decals cannot paint it.
	_mesh.layers = 2
	add_child(_mesh)

	body_entered.connect(_on_body_entered)
	_read_balance()
	_deactivate()


func _read_balance() -> void:
	var p := Balance.progression()
	_magnet_radius = float(p.get("orb_magnet_radius_units", 4.5))
	_magnet_speed = float(p.get("orb_magnet_speed_units_per_second", 11.0))
	_lifetime = float(p.get("orb_lifetime_seconds", 30.0))


func drop(at: Vector3, xp: int) -> void:
	amount = maxi(1, xp)
	global_position = at + Vector3(0.0, 0.45, 0.0)
	_life = 0.0
	_spin = 0.0
	_active = true
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


## Drifts toward the hero once inside the magnet radius, and accelerates as it
## closes so collection feels decisive rather than like a slow tractor beam.
func _physics_process(delta: float) -> void:
	if not _active:
		return
	_life += delta
	_spin += delta * 3.0
	if _mesh != null:
		_mesh.rotation.y = _spin
		_mesh.position.y = sin(_spin * 1.6) * 0.06

	if _life >= _lifetime:
		expire()
		return

	var hero := _hero()
	if hero == null:
		return
	var to_hero := hero.global_position + Vector3(0.0, 0.6, 0.0) - global_position
	var distance := to_hero.length()
	if distance > _magnet_radius:
		return
	# Closer means faster: 1x at the edge of the radius, 3x at the hero.
	var urgency: float = 1.0 + 2.0 * (1.0 - distance / maxf(_magnet_radius, 0.001))
	global_position += to_hero.normalized() * _magnet_speed * urgency * delta
	if distance < 0.5:
		_collect()


func _hero() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


func _on_body_entered(body: Node3D) -> void:
	if _active and body != null and body.is_in_group("player"):
		_collect()


func _collect() -> void:
	if not _active:
		return
	_deactivate()
	collected.emit(self, amount)


## Times out rather than lingering forever. Emits nothing — an orb the player
## never reached is not a collection.
func expire() -> void:
	_deactivate()


func _deactivate() -> void:
	_active = false
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	global_position = Vector3(0.0, -1000.0, 0.0)


func is_active() -> bool:
	return _active
