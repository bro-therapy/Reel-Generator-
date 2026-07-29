class_name CharacterData
extends Resource

## Master guide §15: id, max_hp, move speed, dash values, visuals, Focus Weapon.
##
## Numeric defaults come from docs/LEVEL1_BALANCE.json via `from_balance()` so the
## JSON stays the single source of truth. Visual fields are authored here because
## they describe presentation, not balance.

@export var id: StringName = &"tower_exile"
@export var display_name: String = "Tower Exile"

@export_group("Vitals")
@export var max_hp: int = 100
@export var contact_grace_seconds: float = 0.40

@export_group("Movement")
@export var move_speed_units_per_second: float = 6.2
@export var acceleration: float = 35.0
@export var deceleration: float = 42.0

@export_group("Dash")
@export var dash_distance_units: float = 4.3
@export var dash_duration_seconds: float = 0.18
@export var dash_cooldown_seconds: float = 1.35
@export var dash_invulnerability_seconds: float = 0.20

@export_group("Focus Weapon")
@export var focus_weapon_id: StringName = &"conjurer_staff"
@export var auto_target_range_units: float = 14.0
@export var focus_aim_assist_degrees: float = 22.0

@export_group("Visuals")
## Sprite frames built from the locomotion split frames.
@export var sprite_frames: SpriteFrames
## World-space height of the actor, used with the test camera to hit the
## 88 px-at-1080p gameplay target (master guide §2).
@export var world_height_units: float = 1.8
## Source cell height in pixels (ASSET_MANIFEST grid cell = 162x242).
@export var source_cell_height_px: int = 242
@export var collision_radius_units: float = 0.35
@export var collision_height_units: float = 1.4


## Speed the dash must sustain to cover its distance in its duration.
func dash_speed() -> float:
	if dash_duration_seconds <= 0.0:
		return 0.0
	return dash_distance_units / dash_duration_seconds


## Pixels-to-world scale for AnimatedSprite3D.pixel_size.
func pixel_size() -> float:
	if source_cell_height_px <= 0:
		return 0.01
	return world_height_units / float(source_cell_height_px)


## Overwrite the numeric fields from LEVEL1_BALANCE.json.
func apply_balance() -> void:
	var p := Balance.player()
	if p.is_empty():
		push_warning("CharacterData: balance player block empty; keeping inspector values")
		return
	max_hp = int(p.get("max_hp", max_hp))
	move_speed_units_per_second = float(p.get("move_speed_units_per_second", move_speed_units_per_second))
	acceleration = float(p.get("acceleration", acceleration))
	deceleration = float(p.get("deceleration", deceleration))
	dash_distance_units = float(p.get("dash_distance_units", dash_distance_units))
	dash_duration_seconds = float(p.get("dash_duration_seconds", dash_duration_seconds))
	dash_cooldown_seconds = float(p.get("dash_cooldown_seconds", dash_cooldown_seconds))
	dash_invulnerability_seconds = float(p.get("dash_invulnerability_seconds", dash_invulnerability_seconds))
	contact_grace_seconds = float(p.get("contact_grace_seconds", contact_grace_seconds))
	auto_target_range_units = float(p.get("auto_target_range_units", auto_target_range_units))
	focus_aim_assist_degrees = float(p.get("focus_aim_assist_degrees", focus_aim_assist_degrees))
