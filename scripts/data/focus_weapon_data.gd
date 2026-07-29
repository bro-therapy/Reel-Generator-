class_name FocusWeaponData
extends Resource

## Master guide §15: damage, interval, range, projectile, aim assist, tags.
##
## Numbers are seeded from docs/LEVEL1_BALANCE.json via `apply_balance()`.

@export var id: StringName = &"conjurer_staff"
@export var display_name: String = "Conjurer Staff"

@export_group("Damage")
@export var base_damage: int = 12
@export var critical_chance: float = 0.05
@export var critical_multiplier: float = 1.75

@export_group("Cadence")
@export var attack_interval_seconds: float = 0.72

@export_group("Projectile")
@export var projectile_speed_units_per_second: float = 16.0
@export var projectile_lifetime_seconds: float = 1.1
@export var projectile_radius_units: float = 0.22
@export var pierce_count: int = 0

@export_group("Targeting")
@export var range_units: float = 14.0
@export var aim_assist_degrees: float = 22.0
## Master guide §16: rescore every 0.20 seconds.
@export var target_refresh_seconds: float = 0.20

@export_group("Tags")
@export var tags: Array[StringName] = [&"focus", &"staff", &"violet"]


func apply_balance() -> void:
	var staff := Balance.conjurer_staff()
	if not staff.is_empty():
		base_damage = int(staff.get("base_damage", base_damage))
		attack_interval_seconds = float(staff.get("attack_interval_seconds", attack_interval_seconds))
		projectile_speed_units_per_second = float(staff.get("projectile_speed_units_per_second", projectile_speed_units_per_second))
		projectile_lifetime_seconds = float(staff.get("projectile_lifetime_seconds", projectile_lifetime_seconds))
		critical_chance = float(staff.get("critical_chance", critical_chance))
		critical_multiplier = float(staff.get("critical_multiplier", critical_multiplier))

	var p := Balance.player()
	if not p.is_empty():
		range_units = float(p.get("auto_target_range_units", range_units))
		aim_assist_degrees = float(p.get("focus_aim_assist_degrees", aim_assist_degrees))

	var refresh: Variant = Balance.get_value("summons/global/target_refresh_seconds", null)
	if refresh != null:
		target_refresh_seconds = float(refresh)


## Rolls a single shot's damage. Returns [damage, was_critical].
func roll_damage(rng: RandomNumberGenerator) -> Array:
	var crit := rng.randf() < critical_chance
	var dmg := int(round(float(base_damage) * (critical_multiplier if crit else 1.0)))
	return [dmg, crit]
