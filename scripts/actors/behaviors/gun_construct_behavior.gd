class_name GunConstructBehavior
extends SummonBehavior

## Gun Construct — plant, aim, burst (brief Phase 4, guide §5).
##
## Signature read: the construct stops dead to shoot. Where the hound closes and
## the wisp circles, this one plants and holds position through the whole firing
## cycle, then fires a violet projectile. Stillness plus range is its identity,
## and both are what the acceptance check measures.

const PROJECTILE_SPEED := 18.0
const PROJECTILE_LIFETIME := 1.2


func signature() -> String:
	return "plant aim burst"


## Never leaves its lane to engage — it shoots from where it stands.
func plants_to_attack() -> bool:
	return true


## Planted: hold position for the entire windup/attack/recover cycle.
func on_windup(_delta: float, _lane: Vector3) -> bool:
	return true


func on_attack_tick(_delta: float, _lane: Vector3) -> bool:
	return true


func on_recover(_delta: float, _lane: Vector3) -> bool:
	return true


func deliver_attack(target: Node3D, damage: int) -> bool:
	# Ranged: a pooled projectile carries the damage, so nothing lands instantly.
	var pool := summon.projectile_pool()
	if pool == null:
		return false
	var p := pool.acquire()
	if p == null:
		return true  # pool exhausted; drop the shot rather than allocate

	var origin := summon.attack_origin_position()
	var aim := TargetScorer.target_point(target) if target != null else origin + Vector3.FORWARD
	p.launch_raw(origin, aim - origin, PROJECTILE_SPEED, PROJECTILE_LIFETIME, damage, false, 0)
	spawn_effect(origin, &"friendly_a", 0.7)
	return true
