extends Node

## Autoload. Accessibility, audio, graphics, and input-display preferences.
##
## Master guide §17 lists the accessibility surface. Phase 0 establishes the
## storage and signals; the settings menu that drives them lands in Phase 13.

signal settings_changed(key: String, value: Variant)

const DEFAULTS := {
	# Accessibility (guide §17)
	"reduced_screen_shake": false,
	"reduced_flashes": false,
	"effect_opacity": 1.0,
	"aim_assist_strength": 1.0,
	"high_contrast_telegraphs": false,
	"alternate_friendly_hostile_colors": false,
	"damage_numbers": true,
	"manual_focus_fire_is_toggle": false,
	# Audio buses (guide §14) — placeholder levels, no audio ships with the package
	"volume_master": 1.0,
	"volume_music": 0.8,
	"volume_sfx": 1.0,
	# Graphics quality toggles (guide §17)
	"quality_shadows": true,
	"quality_particles": true,
	"quality_volumetrics": true,
	# Input display
	"input_display": "auto",  # auto | keyboard | controller
	# Debug
	"debug_overlay_visible": false,
}

var _values: Dictionary = DEFAULTS.duplicate(true)


func get_setting(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_setting(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("GameSettings: unknown key '%s'" % key)
		return
	if _values.get(key) == value:
		return
	_values[key] = value
	settings_changed.emit(key, value)


func all_settings() -> Dictionary:
	return _values.duplicate(true)


func apply_settings(values: Dictionary) -> void:
	for key in values:
		if DEFAULTS.has(key):
			set_setting(key, values[key])


func reset_to_defaults() -> void:
	apply_settings(DEFAULTS.duplicate(true))
