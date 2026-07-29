extends Node3D

## Phase 5 test room. A dummy hero plus one of each enemy role, and a hostile
## projectile pool for the Lantern Hexer's orb.

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_base.tscn")
const ROLES := ["rift_crawler", "lantern_hexer", "bellguard", "nest_idol", "blade_mite", "siphon_eye"]

var enemies: Dictionary = {}


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.RUN)
	var hero := get_node_or_null("Player") as Node3D
	if hero == null:
		return
	var i := 0
	for role in ROLES:
		var d := load("res://data/enemies/%s.tres" % role) as EnemyData
		if d == null:
			continue
		var e := ENEMY_SCENE.instantiate() as EnemyBase
		e.name = role
		e.data = d
		e.target = hero
		add_child(e)
		# Spread them so they do not interfere with one another, but inside the
		# Siphon Eye's 6 u tether-attach range so every role engages on its own.
		var angle := TAU * float(i) / float(ROLES.size())
		e.global_position = Vector3(cos(angle), 0.0, sin(angle)) * 4.5
		enemies[role] = e
		i += 1


func enemy(role: String) -> EnemyBase:
	return enemies.get(role) as EnemyBase
