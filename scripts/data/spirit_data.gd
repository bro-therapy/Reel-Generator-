class_name SpiritData
extends Resource

## Master guide §15: id, role, origin, element, temperament, icon, scene, forms.
##
## One resource per species. The forms array carries the evolution chain; Phase 3
## only needs Bound, and Phase 7 wires Echo evolution to advance the index.

@export var id: StringName = &"rune_hound"
@export var display_name: String = "Rune Hound"

@export_group("Identity")
## Balance role string, e.g. melee_burst / mobile_cleave / ranged_sustain.
@export var role: StringName = &"melee_burst"
@export var origin: String = "spirit"
@export var element: StringName = &"violet"
@export var temperament: String = ""

@export_group("Presentation")
@export var icon: Texture2D
## Overrides SummonBase.tscn when a species needs its own scene. Phase 3 proves
## one generic base drives all three, so this stays null.
@export var scene: PackedScene

@export_group("Follow lane")
## Master guide §4: each summon holds a lane around the hero. Offset is in
## hero-local space — x = right of the hero, y = up, z = the hero's facing.
@export var lane_offset: Vector3 = Vector3(-1.3, 0.0, 1.5)
## How fast the summon closes on its lane point.
@export var follow_speed_units_per_second: float = 9.5
## Lane arrival tolerance, so summons settle instead of jittering.
@export var lane_tolerance_units: float = 0.25
## How far from the HERO a summon will roam to engage. This is the leash that
## keeps "simple steering" from becoming room-wide pursuit (master guide §4).
## Must stay below the 10 u teleport threshold or a summon would strand itself
## chasing and then reform on its own.
@export var engage_radius_units: float = 8.0

@export_group("Behaviour")
## Species behaviour module (Phase 4). A SummonBehavior subclass; SummonBase
## instantiates it so all three species keep sharing one base scene.
@export var behavior_script: Script

@export_group("Forms")
@export var forms: Array[SpiritFormData] = []


func form(index: int) -> SpiritFormData:
	if forms.is_empty():
		return null
	return forms[clampi(index, 0, forms.size() - 1)]


func bound_form() -> SpiritFormData:
	return form(0)


func max_form_index() -> int:
	return maxi(0, forms.size() - 1)


## Pushes LEVEL1_BALANCE.json numbers into every authored form. Evolution
## bonuses scale off the Bound values so a single JSON edit moves the chain.
func apply_balance() -> void:
	var s := Balance.summon(String(id))
	if s.is_empty():
		push_warning("SpiritData: no balance entry for '%s'" % id)
		return
	if s.has("role"):
		role = StringName(str(s["role"]))
	for f in forms:
		if f == null:
			continue
		f.damage = int(s.get("damage", f.damage))
		f.attack_interval_seconds = float(s.get("attack_interval_seconds", f.attack_interval_seconds))
		f.range_units = float(s.get("range_units", f.range_units))


## Global summon rules from LEVEL1_BALANCE.json summons/global.
static func global_rules() -> Dictionary:
	return Balance.get_value("summons/global", {}) as Dictionary


static func teleport_back_distance() -> float:
	return float(global_rules().get("teleport_back_distance_units", 10.0))


static func reform_delay() -> float:
	return float(global_rules().get("reform_delay_seconds", 0.35))


static func target_refresh_seconds() -> float:
	return float(global_rules().get("target_refresh_seconds", 0.20))


static func rally_damage_bonus() -> float:
	return float(global_rules().get("rally_damage_bonus", 0.15))


static func invulnerable_in_prototype() -> bool:
	return bool(global_rules().get("invulnerable_in_prototype", true))
