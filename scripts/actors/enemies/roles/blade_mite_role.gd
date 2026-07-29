class_name BladeMiteRole
extends EnemyBehavior

## Dasher (guide §10). Draws a thin red line, lunges along it, and is vulnerable
## through the recovery that follows.

const DASH_SPEED_SCALE := 4.5
const RECOVERY_VULNERABILITY := 1.75

var _dash_direction := Vector3.ZERO


func role_name() -> String:
	return "dasher"


## A longer telegraph than a crawler: the line must be readable before the lunge.
func windup_seconds(default_seconds: float) -> float:
	return maxf(default_seconds, 0.7)


func on_windup_started() -> void:
	_dash_direction = enemy.facing_target()


## Commits along the telegraphed line, so sidestepping the line dodges the dash.
func on_attack(_delta: float) -> bool:
	enemy.velocity = _dash_direction * enemy.data.speed_units_per_second * DASH_SPEED_SCALE
	return true


func on_recover(_delta: float) -> bool:
	enemy.vulnerability_multiplier = RECOVERY_VULNERABILITY
	return false
