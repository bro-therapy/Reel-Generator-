class_name EnemyData
extends Resource

## Master guide §15: id, hp, speed, contact damage, threat, scene, drops.

@export var id: StringName = &"rift_crawler"
@export var display_name: String = "Rift Crawler"

@export_group("Stats")
@export var max_hp: int = 24
@export var damage: int = 8
@export var speed_units_per_second: float = 4.5
@export var attack_interval_seconds: float = 1.2
@export var attack_range_units: float = 1.6

@export_group("Threat")
## One of TargetScorer's threat classes: normal, spawner, hexer, elite, boss.
@export var threat_class: StringName = &"normal"
@export var threat_weight: int = 1

@export_group("Attack timing")
## Telegraph duration. Master guide §10 requires a visible windup on every
## damaging attack, so this is never zero for an attacker.
@export var windup_seconds: float = 0.55
@export var active_seconds: float = 0.12
@export var recover_seconds: float = 0.45

@export_group("Telegraph")
## Circle, wedge, or line — matched to the role in guide §10.
@export var telegraph_shape: StringName = &"circle"
@export var telegraph_radius_units: float = 1.8

@export_group("Visuals")
@export var sprite_frames: SpriteFrames
@export var world_height_units: float = 1.4
@export var source_cell_height_px: int = 209
@export var collision_radius_units: float = 0.4
@export var collision_height_units: float = 1.0

@export_group("Behaviour")
@export var behavior_script: Script

@export_group("Drops")
@export var currency_drop: int = 0
@export var stability_restore: int = 0


func pixel_size() -> float:
	if source_cell_height_px <= 0:
		return 0.01
	return world_height_units / float(source_cell_height_px)


## Pulls this role's numbers from docs/LEVEL1_BALANCE.json.
func apply_balance() -> void:
	var e := Balance.enemy(String(id))
	if e.is_empty():
		push_warning("EnemyData: no balance entry for '%s'" % id)
		return
	max_hp = int(e.get("hp", max_hp))
	speed_units_per_second = float(e.get("speed", speed_units_per_second))
	threat_weight = int(e.get("threat", threat_weight))
	if e.has("damage"):
		damage = int(e["damage"])
	if e.has("attack_interval"):
		attack_interval_seconds = float(e["attack_interval"])


## True when this role can actually hurt the player, and therefore must
## telegraph. The Nest Idol deals no damage and only spawns.
func is_damaging() -> bool:
	return damage > 0
