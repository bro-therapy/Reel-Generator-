class_name Balance
extends RefCounted

## Data-driven access to docs/LEVEL1_BALANCE.json.
##
## The build brief requires gameplay values live in Resources or JSON-backed data,
## never scattered constants. Every system reads its numbers through here.
##
##     Balance.player().dash_distance_units
##     Balance.get_value("conjurer_staff/attack_interval_seconds", 0.72)

const BALANCE_PATH := "res://docs/LEVEL1_BALANCE.json"

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_load()
	return _data


static func _load() -> void:
	_loaded = true
	if not FileAccess.file_exists(BALANCE_PATH):
		push_error("Balance: missing %s" % BALANCE_PATH)
		return
	var text := FileAccess.get_file_as_string(BALANCE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Balance: %s is not a JSON object" % BALANCE_PATH)
		return
	_data = parsed


## Reload from disk. Used by tests that need a clean read.
static func reload() -> void:
	_loaded = false
	_data = {}
	_load()


## Fetch a nested value by slash-separated path, e.g. "player/dash_distance_units".
## Returns `fallback` when any segment is missing, so a partial balance file
## degrades instead of crashing.
static func get_value(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = data()
	for key in path.split("/", false):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(key):
			return fallback
		node = (node as Dictionary)[key]
	return node


static func player() -> Dictionary:
	return get_value("player", {}) as Dictionary


static func conjurer_staff() -> Dictionary:
	return get_value("conjurer_staff", {}) as Dictionary


static func summon(species_id: String) -> Dictionary:
	return get_value("summons/%s" % species_id, {}) as Dictionary


static func enemy(enemy_id: String) -> Dictionary:
	return get_value("enemies/%s" % enemy_id, {}) as Dictionary


static func boss() -> Dictionary:
	return get_value("boss", {}) as Dictionary


static func overdrive() -> Dictionary:
	return get_value("overdrive", {}) as Dictionary


static func stability() -> Dictionary:
	return get_value("stability", {}) as Dictionary
