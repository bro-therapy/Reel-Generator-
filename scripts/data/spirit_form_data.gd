class_name SpiritFormData
extends Resource

## Master guide §15: tier, visuals, stats, attacks, passive, Convergence.
##
## One form per evolution tier. Bound -> Awakened -> Ascendant (guide §5).

enum Tier { BOUND, AWAKENED, ASCENDANT }

@export var tier: Tier = Tier.BOUND
@export var display_name: String = ""

@export_group("Visuals")
@export var sprite_frames: SpriteFrames
## World height of the whole source cell, sized so the drawn creature meets the
## guide §2 on-screen pixel target. Computed by build_summon_spriteframes.gd.
@export var world_height_units: float = 2.0
@export var source_cell_height_px: int = 342

@export_group("Stats")
@export var damage: int = 10
@export var attack_interval_seconds: float = 1.0
@export var range_units: float = 3.0

@export_group("Attack timing")
## Windup and recovery are not in LEVEL1_BALANCE.json, so they are authored
## here — still data, never constants in behaviour scripts. Their sum must stay
## below attack_interval_seconds or the cycle cannot keep cadence.
@export var windup_seconds: float = 0.18
@export var recover_seconds: float = 0.22

@export_group("Description")
@export_multiline var passive_description: String = ""
@export_multiline var convergence_description: String = ""


func pixel_size() -> float:
	if source_cell_height_px <= 0:
		return 0.01
	return world_height_units / float(source_cell_height_px)


## True when windup + recovery fit inside the attack interval.
func timing_is_coherent() -> bool:
	return windup_seconds + recover_seconds < attack_interval_seconds


func tier_name() -> String:
	match tier:
		Tier.AWAKENED:
			return "Awakened"
		Tier.ASCENDANT:
			return "Ascendant"
		_:
			return "Bound"
