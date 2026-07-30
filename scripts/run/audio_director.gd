class_name AudioDirector
extends Node

## Buses, voices and mix priority. Guide §14.
##
##   var audio := AudioDirector.new()
##   audio.settings_source = GameSettings
##   add_child(audio)
##   audio.play(&"hero_hurt")
##   audio.play_at(&"enemy_crawler_attack", enemy.global_position)
##   audio.play_music(&"music_sunfall_combat")
##
## The part of this worth reading is voice allocation.
##
## Guide §14 gives a mix priority with "player damage warning" at the top and
## "environment" at the bottom. In a room with 250 enemies that is not a mixing
## preference, it is a correctness requirement: the sound telling the player they
## are being hurt has to be audible through everything else, and a naive
## fire-and-forget player per sound either runs out of voices or turns into mud
## exactly when it matters most.
##
## So voices are pooled and finite, and a new sound may steal a voice only from a
## strictly lower priority. A priority-1 damage warning can always take a voice
## from an attack or a footstep; a footstep can never take one from anything. When
## nothing is stealable the new sound is dropped, which is the correct outcome —
## the alternative is queueing it and playing it after the moment it described.
##
## Slot names and priorities come from docs/generated/audio_slots.json, which is
## generated alongside the files themselves, so a slot cannot exist in one and not
## the other.

signal sound_played(slot: StringName, priority: int)
signal sound_dropped(slot: StringName, reason: StringName)
signal music_changed(slot: StringName)

const MANIFEST := "res://docs/generated/audio_slots.json"

## Guide §14's mix order. 1 must always be audible; 6 is the first thing dropped.
const PRIORITY_PLAYER_DAMAGE := 1
const PRIORITY_TELEGRAPH := 2
const PRIORITY_RALLY := 3
const PRIORITY_SIGNATURE := 4
const PRIORITY_ATTACK := 5
const PRIORITY_ENVIRONMENT := 6
const WORST_PRIORITY := 99

## Comfortably more than a 250-enemy room needs. The ceiling exists so the mix
## stays legible, not because the hardware cannot open more streams.
@export var max_voices := 24

## A crawler pack can land forty identical attacks on one frame. Past this many
## copies of the same slot inside `flood_window_seconds`, the extras are dropped:
## the 5th simultaneous copy of a sound is not audible as a 5th, it is audible as
## distortion.
@export var max_same_slot := 4
@export var flood_window_seconds := 0.12

## Per-playback pitch variation, in semitones either side of centre.
##
## The single cheapest thing that stops a placeholder set sounding like a
## placeholder set. Forty crawler hits in one fight were forty byte-identical
## playbacks of the same file, which the ear reads as a machine gun rather than as
## forty separate impacts — no amount of better synthesis fixes that, because the
## problem is repetition, not timbre.
##
## Music is exempt: a bed that changes key every time it loops is a bug.
@export var pitch_variation_semitones := 1.6

var settings_source: Object

var _slots: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _active: Array[Dictionary] = []
var _recent: Dictionary = {}
var _music: AudioStreamPlayer
var _music_slot: StringName = &""
var _clock := 0.0

var _played := 0
var _dropped := 0
var _stolen := 0


var _initialized := false


func _ready() -> void:
	initialize()


## Idempotent, and public, so a caller does not have to know whether `_ready` has
## run yet. It has not, immediately after `add_child` from a `--script` harness —
## `_ready` is deferred until the tree is processing, and a director built that way
## reported zero slots while its manifest sat on disk perfectly readable. This is
## the fourth bug in this project traced to assuming `_ready` ordering; making
## setup callable is cheaper than remembering the rule.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_ensure_buses()
	load_manifest()
	_build_voices()
	if settings_source == null:
		settings_source = AutoloadRef.settings()
	if settings_source != null and settings_source.has_signal("settings_changed"):
		if not settings_source.settings_changed.is_connected(_on_setting_changed):
			settings_source.settings_changed.connect(_on_setting_changed)
	apply_volumes()


# ---------------------------------------------------------------------- buses

## Buses are created in code rather than shipped as a bus layout resource. A
## layout file is a binary the editor rewrites, and this way the names the guide
## documents are the names in source, where they can be read and asserted.
func _ensure_buses() -> void:
	for name in ["music", "sfx", "ui"]:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


func bus_names() -> Array:
	var out: Array = []
	for i in AudioServer.bus_count:
		out.append(AudioServer.get_bus_name(i))
	return out


# -------------------------------------------------------------------- manifest

func load_manifest() -> int:
	_slots.clear()
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		push_warning("no audio manifest at %s — run tools/make_placeholder_audio.py" % MANIFEST)
		return 0
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("%s is not valid JSON" % MANIFEST)
		return 0

	var doc: Dictionary = parsed
	for group in ["sfx", "music"]:
		for entry_v in doc.get(group, []):
			var e: Dictionary = entry_v
			var slot := StringName(e.get("slot", ""))
			if slot == &"":
				continue
			# The stream is loaded lazily. A missing file is a warning at play
			# time rather than a hard failure at boot: a checkout without assets
			# should still run, silently.
			_slots[slot] = {
				"path": String(e.get("path", "")),
				"bus": String(e.get("bus", "sfx")),
				"priority": int(e.get("priority", PRIORITY_ATTACK)),
				"loop": bool(e.get("loop", false)),
				"stream": null,
			}
	return _slots.size()


func has_slot(slot: StringName) -> bool:
	return _slots.has(slot)


func slot_count() -> int:
	return _slots.size()


func slot_names() -> Array:
	var out: Array = _slots.keys()
	out.sort()
	return out


func priority_of(slot: StringName) -> int:
	return int((_slots.get(slot, {}) as Dictionary).get("priority", WORST_PRIORITY))


func bus_of(slot: StringName) -> String:
	return String((_slots.get(slot, {}) as Dictionary).get("bus", "sfx"))


func _stream_for(slot: StringName) -> AudioStream:
	var entry: Dictionary = _slots.get(slot, {})
	if entry.is_empty():
		return null
	if entry["stream"] != null:
		return entry["stream"]
	var path: String = entry["path"]
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	entry["stream"] = stream
	return stream


# --------------------------------------------------------------------- voices

func _build_voices() -> void:
	# `_active` is index-parallel to the pools and must be sized with them. Left
	# empty, every loop over `_active.size()` is a no-op and nothing ever plays.
	_active.clear()
	for i in max_voices:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_voices.append(p)

		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Voice3D%d" % i
		add_child(p3)
		_voices_3d.append(p3)

		_active.append({})

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "music"
	add_child(_music)


## Non-positional. UI, and anything that belongs to the player rather than a place.
func play(slot: StringName, volume_db: float = 0.0) -> bool:
	return _play(slot, false, Vector3.ZERO, volume_db)


## Positional. Everything that happens somewhere in the world.
func play_at(slot: StringName, at: Vector3, volume_db: float = 0.0) -> bool:
	return _play(slot, true, at, volume_db)


func _play(slot: StringName, positional: bool, at: Vector3, volume_db: float) -> bool:
	if not _slots.has(slot):
		_dropped += 1
		sound_dropped.emit(slot, &"unknown_slot")
		push_warning("no audio slot named '%s'" % slot)
		return false

	var priority := priority_of(slot)

	# Flood control comes before voice allocation on purpose: forty copies of one
	# attack should not be allowed to evict forty other sounds on their way to
	# being inaudible anyway.
	if _same_slot_recently(slot) >= max_same_slot:
		_dropped += 1
		sound_dropped.emit(slot, &"flood")
		return false

	var index := _claim_voice(priority)
	if index < 0:
		_dropped += 1
		sound_dropped.emit(slot, &"no_voice")
		return false

	var stream := _stream_for(slot)
	if stream == null:
		# No file in this checkout. The voice is released and the call reports
		# false, but it is not an error — an assetless clone plays silently.
		_release(index)
		_dropped += 1
		sound_dropped.emit(slot, &"missing_stream")
		return false

	# Semitones to a ratio: 2^(n/12). Applied per playback, so the same file is a
	# slightly different sound every time it fires.
	var cents := randf_range(-pitch_variation_semitones, pitch_variation_semitones)
	var pitch := pow(2.0, cents / 12.0)

	var player: Node
	if positional:
		var p3 := _voices_3d[index]
		p3.stream = stream
		p3.bus = bus_of(slot)
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.global_position = at if p3.is_inside_tree() else p3.global_position
		p3.play()
		player = p3
	else:
		var p := _voices[index]
		p.stream = stream
		p.bus = bus_of(slot)
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()
		player = p

	_active[index] = {
		"slot": slot,
		"priority": priority,
		"started": _clock,
		# A voice is released when its sound is over, tracked from the stream's own
		# length, *or* when the player reports it stopped — whichever comes first.
		#
		# Both are needed. `playing` alone is not enough: it is whatever the audio
		# driver says, and the headless dummy driver never reports a sound as
		# finished, so the pool filled to exactly max_voices and then silently
		# dropped everything for the rest of the run. A duration the director owns
		# means voice accounting behaves the same on every driver.
		# Divided by pitch: playing at 0.9x takes 11% longer, and reclaiming the
		# voice on the unpitched duration would cut the tail off.
		"ends_at": _clock + maxf(stream.get_length() / maxf(pitch, 0.01), 0.01),
		"positional": positional,
		"player": player,
	}
	_recent[slot] = (_recent.get(slot, []) as Array) + [_clock]
	_played += 1
	sound_played.emit(slot, priority)
	return true


func _same_slot_recently(slot: StringName) -> int:
	var stamps: Array = _recent.get(slot, [])
	var count := 0
	for s in stamps:
		if _clock - float(s) <= flood_window_seconds:
			count += 1
	return count


## Finds a voice for `priority`. Prefers a free one; otherwise steals from the
## worst active voice, but only if that voice is strictly lower priority. Equal
## priority does not steal — two attacks should not fight over one slot, and
## letting them would make the mix depend on call order.
func _claim_voice(priority: int) -> int:
	for i in _active.size():
		if _active[i].is_empty():
			return i

	var worst := -1
	var worst_priority := priority
	for i in _active.size():
		var p := int(_active[i].get("priority", WORST_PRIORITY))
		if p > worst_priority:
			worst = i
			worst_priority = p
	if worst < 0:
		return -1

	_stop_voice(worst)
	_stolen += 1
	return worst


func _stop_voice(index: int) -> void:
	var entry: Dictionary = _active[index]
	if entry.is_empty():
		return
	var player: Variant = entry.get("player")
	if player != null and is_instance_valid(player):
		player.stop()
	_release(index)


func _release(index: int) -> void:
	_active[index] = {}


func _process(delta: float) -> void:
	tick(delta)


## Explicit so acceptance checks can advance the mixer without a running tree.
func tick(delta: float) -> void:
	_clock += delta
	for i in _active.size():
		var entry: Dictionary = _active[i]
		if entry.is_empty():
			continue
		if _clock >= float(entry.get("ends_at", 0.0)):
			_stop_voice(i)
			continue
		var player: Variant = entry.get("player")
		if player == null or not is_instance_valid(player) or not player.playing:
			_release(i)

	# Old flood stamps would otherwise grow without bound over a long run.
	for slot in _recent.keys():
		var kept: Array = []
		for s in (_recent[slot] as Array):
			if _clock - float(s) <= flood_window_seconds:
				kept.append(s)
		if kept.is_empty():
			_recent.erase(slot)
		else:
			_recent[slot] = kept


func stop_all() -> void:
	for i in _active.size():
		_stop_voice(i)


func active_voices() -> int:
	var n := 0
	for entry in _active:
		if not entry.is_empty():
			n += 1
	return n


func active_slots() -> Array:
	var out: Array = []
	for entry in _active:
		if not entry.is_empty():
			out.append(entry["slot"])
	return out


func is_slot_active(slot: StringName) -> bool:
	return slot in active_slots()


func played_count() -> int:
	return _played


func dropped_count() -> int:
	return _dropped


func stolen_count() -> int:
	return _stolen


# ---------------------------------------------------------------------- music

## Guide §14 names three beds. Re-requesting the one already playing is a no-op,
## so a room that re-announces its own music on every entry does not restart it.
func play_music(slot: StringName) -> bool:
	if slot == _music_slot and _music != null and _music.playing:
		return true
	if not _slots.has(slot):
		sound_dropped.emit(slot, &"unknown_slot")
		return false
	var stream := _stream_for(slot)
	if stream == null:
		sound_dropped.emit(slot, &"missing_stream")
		return false
	# Placeholder beds are written as an exact number of bars so the seam lands on
	# a beat; the loop flag has to be set for that to be worth anything.
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music.stream = stream
	_music.pitch_scale = 1.0
	_music.play()
	_music_slot = slot
	music_changed.emit(slot)
	return true


func stop_music() -> void:
	if _music != null:
		_music.stop()
	_music_slot = &""


func current_music() -> StringName:
	return _music_slot


# -------------------------------------------------------------------- volumes

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("volume_"):
		apply_volumes()


func apply_volumes() -> void:
	_set_bus_volume("Master", _setting("volume_master", 1.0))
	_set_bus_volume("music", _setting("volume_music", 0.8))
	_set_bus_volume("sfx", _setting("volume_sfx", 1.0))
	# The guide gives no separate UI slider, so UI rides the SFX one.
	_set_bus_volume("ui", _setting("volume_sfx", 1.0))


func _setting(key: String, fallback: float) -> float:
	if settings_source == null or not settings_source.has_method("get_setting"):
		return fallback
	var v: Variant = settings_source.get_setting(key)
	return fallback if v == null else float(v)


## Linear 0..1 to decibels. Zero is muted rather than -inf: linear_to_db(0)
## returns -inf, which Godot accepts but which makes a bus volume unprintable and
## awkward to assert on.
func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(clamped, 0.0001)))


func bus_volume_linear(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return -1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))
