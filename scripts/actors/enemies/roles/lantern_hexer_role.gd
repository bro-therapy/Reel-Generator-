class_name LanternHexerRole
extends EnemyBehavior

## Ranged shooter (guide §10). Holds a preferred standoff instead of closing,
## and fires a slow red orb. Threat class "hexer" so the shared scorer gives it
## +50 — the Gun Construct and Rally both prioritise it.

const PREFERRED_RANGE := 8.0
const RANGE_TOLERANCE := 1.2
const ORB_SPEED := 7.0
const ORB_LIFETIME := 2.2


func role_name() -> String:
	return "ranged shooter"


## Keeps station: closes if too far, backs off if the player crowds it.
func on_seek(delta: float) -> bool:
	if enemy.target == null or not is_instance_valid(enemy.target):
		enemy.velocity = Vector3.ZERO
		return true
	var to := enemy.target.global_position - enemy.global_position
	to.y = 0.0
	var distance := to.length()
	var speed: float = enemy.data.speed_units_per_second

	if distance > PREFERRED_RANGE + RANGE_TOLERANCE:
		enemy.velocity = to.normalized() * speed
	elif distance < PREFERRED_RANGE - RANGE_TOLERANCE:
		enemy.velocity = -to.normalized() * speed
	else:
		enemy.velocity = enemy.velocity.move_toward(Vector3.ZERO, speed * 6.0 * delta)
		enemy.begin_attack()
	return true


## Fires an orb rather than striking, so the damage travels and can be dodged
## after the telegraph ends.
func deliver_attack() -> bool:
	var pool := _pool()
	if pool == null or enemy.target == null:
		return false
	var p := pool.acquire()
	if p == null:
		return true
	var origin := enemy.attack_origin_position()
	var aim := enemy.target.global_position + Vector3(0.0, 0.8, 0.0)
	p.launch_raw(origin, aim - origin, ORB_SPEED, ORB_LIFETIME, enemy.data.damage, false, 0)
	return true


func _pool() -> ProjectilePool:
	var tree := enemy.get_tree()
	if tree == null:
		return null
	var pools := tree.get_nodes_in_group("hostile_projectile_pool")
	return pools[0] as ProjectilePool if not pools.is_empty() else null
