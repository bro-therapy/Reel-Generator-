class_name EncounterData
extends Resource

## Master guide §15: waves, spawn points, completion, reward.
##
## Waves are authored in docs/LEVEL1_BALANCE.json as flat pairs, e.g.
## ["rift_crawler", 6, "lantern_hexer", 2]. They are parsed here so the JSON
## stays the single source of encounter composition.

@export var id: StringName = &"combat_a"
## Each entry: Array of { "enemy": StringName, "count": int }.
@export var waves: Array = []
@export var reward: StringName = &"three_card_choice"
## Optional survive-the-timer encounters (the Rift). Zero means clear-to-win.
@export var duration_seconds := 0.0


static func from_balance(encounter_id: String) -> EncounterData:
	var all: Variant = Balance.get_value("encounters", [])
	if typeof(all) != TYPE_ARRAY:
		return null
	for entry in all:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		if String(d.get("id", "")) != encounter_id:
			continue
		var data := EncounterData.new()
		data.id = StringName(encounter_id)
		data.reward = StringName(str(d.get("reward", "")))
		data.duration_seconds = float(d.get("duration_seconds", 0.0))
		data.waves = _parse_waves(d.get("waves", []))
		return data
	return null


## Turns ["rift_crawler", 6, "lantern_hexer", 2] into
## [{enemy: rift_crawler, count: 6}, {enemy: lantern_hexer, count: 2}].
static func _parse_waves(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for wave in raw:
		if typeof(wave) != TYPE_ARRAY:
			continue
		var groups: Array = []
		var flat: Array = wave
		var i := 0
		while i + 1 < flat.size():
			groups.append({"enemy": StringName(str(flat[i])), "count": int(flat[i + 1])})
			i += 2
		out.append(groups)
	return out


func wave_count() -> int:
	return waves.size()


func enemies_in_wave(index: int) -> int:
	if index < 0 or index >= waves.size():
		return 0
	var total := 0
	for group in waves[index]:
		total += int((group as Dictionary).get("count", 0))
	return total


func total_enemies() -> int:
	var total := 0
	for i in waves.size():
		total += enemies_in_wave(i)
	return total


func is_timed() -> bool:
	return duration_seconds > 0.0
