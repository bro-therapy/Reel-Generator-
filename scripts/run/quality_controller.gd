class_name QualityController
extends Node

## Makes the graphics and accessibility settings actually do something.
##
##   var q := QualityController.new()
##   q.settings_source = GameSettings
##   add_child(q)
##   q.apply_to(get_tree().current_scene)
##
## Guide §17 and brief Phase 15 both ask for shadow, particle and volumetric
## toggles. The keys have existed in GameSettings since Phase 0 and nothing read
## them — a settings screen that changes a dictionary and no pixels is worse than
## no settings screen, because it looks like it worked.
##
## Everything here is a presentation change. Nothing in this file may alter what
## the player can see *happen*: a red telegraph is still a red telegraph with
## shadows off, and reduced_flashes dims an effect rather than removing it. That
## is the line between a quality setting and a cheat.

## Ceiling on additive light when `reduced_flashes` is on. Not zero, and not a
## removal: the effect still has to read, it just stops blowing out to white.
const REDUCED_FLASH_ENERGY := 0.55

## Set to the GameSettings autoload, or to any object with get_setting(). Left
## injectable because `--script` harnesses have no autoloads.
var settings_source: Object

var _applied := {}


func _ready() -> void:
	if settings_source == null:
		settings_source = AutoloadRef.settings()
	_connect_source()


func _connect_source() -> void:
	if settings_source == null:
		return
	if not settings_source.has_signal("settings_changed"):
		return
	if not settings_source.settings_changed.is_connected(_on_setting_changed):
		settings_source.settings_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if not _applied.has(key):
		return
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null:
		apply_to(scene)


func _setting(key: String, fallback: Variant) -> Variant:
	if settings_source == null or not settings_source.has_method("get_setting"):
		return fallback
	var v: Variant = settings_source.get_setting(key)
	return fallback if v == null else v


## Walks `root` and applies every quality setting to what it finds. Returns a
## count per category so a caller — or an acceptance check — can tell whether the
## walk actually reached anything, rather than assuming a silent pass means the
## settings took.
func apply_to(root: Node) -> Dictionary:
	var shadows := bool(_setting("quality_shadows", true))
	var particles := bool(_setting("quality_particles", true))
	var volumetrics := bool(_setting("quality_volumetrics", true))
	var opacity := float(_setting("effect_opacity", 1.0))
	var reduced_flashes := bool(_setting("reduced_flashes", false))

	_applied = {
		"quality_shadows": shadows,
		"quality_particles": particles,
		"quality_volumetrics": volumetrics,
		"effect_opacity": opacity,
		"reduced_flashes": reduced_flashes,
	}

	var counts := {"lights": 0, "casters": 0, "particles": 0, "environments": 0, "effects": 0}
	_walk(root, shadows, particles, volumetrics, opacity, reduced_flashes, counts)
	return counts


func _walk(node: Node, shadows: bool, particles: bool, volumetrics: bool,
		opacity: float, reduced_flashes: bool, counts: Dictionary) -> void:
	if node is Light3D:
		(node as Light3D).shadow_enabled = shadows
		counts["lights"] += 1
	elif node is GPUParticles3D:
		var p := node as GPUParticles3D
		# Stopped rather than hidden: a hidden emitter still simulates, which is
		# the cost the setting exists to remove.
		p.emitting = particles and p.emitting
		p.visible = particles
		counts["particles"] += 1
	elif node is CPUParticles3D:
		var c := node as CPUParticles3D
		c.emitting = particles and c.emitting
		c.visible = particles
		counts["particles"] += 1
	elif node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		if env != null:
			env.volumetric_fog_enabled = volumetrics and env.volumetric_fog_enabled
			counts["environments"] += 1
	elif node is AdditiveVfx:
		var fx := node as AdditiveVfx
		var scale_v := opacity
		if reduced_flashes:
			scale_v = minf(scale_v, REDUCED_FLASH_ENERGY)
		fx.energy_scale = scale_v
		counts["effects"] += 1

	# Meshes that are not lights still choose whether to cast, and a shadow the
	# player never sees is the cheapest thing to switch off.
	if node is GeometryInstance3D and not (node is AdditiveVfx):
		var g := node as GeometryInstance3D
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not shadows:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			counts["casters"] += 1

	for child in node.get_children():
		_walk(child, shadows, particles, volumetrics, opacity, reduced_flashes, counts)


func applied() -> Dictionary:
	return _applied.duplicate()
