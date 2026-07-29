class_name NestIdolRole
extends EnemyBehavior

## Spawner (guide §10). Plants itself and creates Rift Crawlers, capped at four
## live children. Deals no damage itself, so it telegraphs the nest pulse rather
## than an attack. Threat class "spawner" — the shared scorer gives it +50.

const CRAWLER_DATA := "res://data/enemies/rift_crawler.tres"

var spawn_interval := 5.5
var spawn_cap := 4

var _timer := 0.0
var _children: Array[EnemyBase] = []
var spawned_total := 0
var spawns_refused_at_cap := 0


func role_name() -> String:
	return "spawner"


func setup(owner_enemy: EnemyBase) -> void:
	super.setup(owner_enemy)
	spawn_interval = float(Balance.get_value("enemies/nest_idol/spawn_interval", 5.5))
	spawn_cap = int(Balance.get_value("enemies/nest_idol/spawn_cap", 4))
	_timer = spawn_interval


## The pulse timer runs every frame, not only while seeking. Decrementing it
## inside on_seek tied the spawn cadence to the length of the idol's own
## windup/attack/recover cycle, so spawn_interval was silently ignored.
func _process(delta: float) -> void:
	if enemy == null or not enemy.is_alive():
		return
	_timer -= delta


## Planted: never moves, just waits for the next pulse.
func on_seek(_delta: float) -> bool:
	enemy.velocity = Vector3.ZERO
	if _timer > 0.0:
		return true
	_timer = spawn_interval
	# The cap is enforced before the telegraph, so a capped idol does not pulse
	# and then do nothing.
	if live_child_count() < spawn_cap:
		enemy.begin_attack()
	else:
		spawns_refused_at_cap += 1
	return true


## The "attack" is a spawn. Returning true keeps EnemyBase from also applying
## melee damage — the idol deals none.
func deliver_attack() -> bool:
	_prune()
	if live_child_count() >= spawn_cap:
		spawns_refused_at_cap += 1
		return true
	_spawn_child()
	return true


func _spawn_child() -> void:
	var child_data := load(CRAWLER_DATA) as EnemyData
	var scene := load("res://scenes/enemies/enemy_base.tscn") as PackedScene
	if child_data == null or scene == null:
		return
	var child := scene.instantiate() as EnemyBase
	child.data = child_data
	child.target = enemy.target
	enemy.get_parent().add_child(child)
	var angle := randf() * TAU
	child.global_position = enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.4
	_children.append(child)
	spawned_total += 1


## Drops freed or dead children so the cap counts only what is actually alive.
func _prune() -> void:
	var live: Array[EnemyBase] = []
	for c in _children:
		if c != null and is_instance_valid(c) and c.is_alive():
			live.append(c)
	_children = live


## Retunes the pulse cadence and applies it immediately. Setting spawn_interval
## alone leaves the countdown already in flight at the old value.
func set_spawn_interval(seconds: float) -> void:
	spawn_interval = maxf(seconds, 0.01)
	_timer = minf(_timer, spawn_interval)


func live_child_count() -> int:
	_prune()
	return _children.size()
