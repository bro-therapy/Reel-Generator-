extends Node

## Autoload. Settings and lightweight meta save.
##
## Phase 14 owns the full acceptance surface. Phase 0 provides the safe
## load/save path so a corrupt or missing file yields defaults instead of
## crashing — that behaviour is required and is cheap to establish now.

const SAVE_PATH := "user://pzc_save.json"
const SAVE_VERSION := 1

var _data: Dictionary = _default_data()


static func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {},
		"input_bindings": {},
		"best_clear_time_seconds": 0.0,
		"discovered_starters": [],
	}


func _ready() -> void:
	load_game()


## Returns true when an existing save was read cleanly. A missing or corrupt
## file is not an error — it resets to defaults and returns false.
func load_game() -> bool:
	_data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveService: cannot open %s (err %d); using defaults" % [SAVE_PATH, FileAccess.get_open_error()])
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveService: %s is corrupt; using defaults" % SAVE_PATH)
		return false

	var loaded := parsed as Dictionary
	if int(loaded.get("version", -1)) != SAVE_VERSION:
		push_warning("SaveService: save version mismatch; using defaults")
		return false

	# Merge over defaults so a save missing newer keys still loads.
	for key in _data:
		if loaded.has(key):
			_data[key] = loaded[key]

	if _data["settings"] is Dictionary:
		GameSettings.apply_settings(_data["settings"])
	return true


func save_game() -> bool:
	_data["version"] = SAVE_VERSION
	_data["settings"] = GameSettings.all_settings()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(_data, "  "))
	file.close()
	return true


func get_value(key: String, fallback: Variant = null) -> Variant:
	return _data.get(key, fallback)


func set_value(key: String, value: Variant) -> void:
	_data[key] = value


func record_clear_time(seconds: float) -> void:
	var best := float(_data.get("best_clear_time_seconds", 0.0))
	if best <= 0.0 or seconds < best:
		_data["best_clear_time_seconds"] = seconds


func discover_starter(species_id: String) -> void:
	var found: Array = _data.get("discovered_starters", [])
	if not found.has(species_id):
		found.append(species_id)
		_data["discovered_starters"] = found
