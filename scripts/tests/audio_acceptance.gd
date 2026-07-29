extends SceneTree

## Acceptance checks for the audio layer. Guide §14.
##
##   godot --headless --path . --script scripts/tests/audio_acceptance.gd
##
## Headless Godot uses a dummy audio driver, so nothing here can prove a sound is
## audible. What it can prove is the part that is a contract rather than a taste
## judgement, and the part most likely to break silently:
##
##   - every SFX family the guide lists has a slot
##   - the mix priority actually holds under voice starvation, which is the only
##     time it matters
##   - a priority-1 damage warning is never the sound that gets dropped
##   - flood control survives a 250-enemy room
##   - the placeholder files are real audio and not silence
##
## The last one is worth stating: "synthesised placeholder" is a licence to ship
## something rough, not a licence to ship an empty file. A silent placeholder is
## indistinguishable from an unwired hook.

const MANIFEST := "res://docs/generated/audio_slots.json"

## Guide §14's SFX families. Every one of these has to resolve to at least one
## slot, or a real audio pass has no idea it is missing.
const REQUIRED_FAMILIES := {
	"hero": ["hero_step", "hero_dash", "hero_hurt", "staff_shot", "staff_impact",
		"rally_mark", "convergence_start", "convergence_end"],
	"rune_hound": ["rune_hound_growl", "rune_hound_lunge", "rune_hound_bite",
		"rune_hound_crescent"],
	"sword_wisp": ["sword_wisp_hover", "sword_wisp_lunge", "sword_wisp_slash",
		"sword_wisp_return"],
	"gun_construct": ["gun_construct_servo", "gun_construct_aim",
		"gun_construct_shot", "gun_construct_burst"],
	"boss": ["boss_slam", "boss_chain_sweep", "boss_toll", "boss_stagger",
		"boss_core_break", "boss_defeat"],
	"rewards": ["pickup", "reward_card", "purchase", "reroll", "evolve", "gate",
		"rift_entry"],
}
## Guide §14: "Six enemy windups, attacks, hits, deaths." The roster is read from
## data/enemies/ rather than listed here — a hardcoded list is what let five of the
## seven real enemies go without sounds of their own while this suite passed.
const ENEMY_DIR := "res://data/enemies"
const ENEMY_EVENTS := ["windup", "attack", "hit", "death"]
const MUSIC := ["music_sunfall_explore", "music_sunfall_combat", "music_first_bell"]

const STEP := 1.0 / 60.0

var _pass := 0
var _fail := 0


var _director: AudioDirector
var _settings: _FakeSettings


func _initialize() -> void:
	print("\n=== AUDIO ACCEPTANCE ===\n")
	_settings = _FakeSettings.new()
	_director = AudioDirector.new()
	_director.settings_source = _settings
	root.add_child(_director)
	# Explicit rather than waiting on _ready, which has not fired yet here.
	_director.initialize()


## The checks run on the first processed frame rather than in _initialize.
##
## AudioStreamPlayer3D refuses to play until it is inside the tree, and nodes added
## during _initialize are not in-tree until the first frame. Running the checks
## early produced one "Playback can only happen when a node is inside the scene
## tree" per positional voice, and the positional path — which is what the whole
## game uses — went untested. One frame of patience tests the real thing.
func _process(_delta: float) -> bool:
	var d := _director
	if d.slot_count() == 0:
		_no("audio manifest", "no slots — run tools/make_placeholder_audio.py")
		_summary()
		return true

	_check_buses(d)
	_check_families(d)
	_check_priorities(d)
	_check_voice_starvation(d)
	_check_flood(d)
	_check_music(d)
	_check_volumes(d, _settings)
	_check_files_are_not_silent()

	_summary()
	return true


# ----------------------------------------------------------------------- buses

func _check_buses(d: AudioDirector) -> void:
	var names := d.bus_names()
	var missing: Array[String] = []
	for want in ["Master", "music", "sfx", "ui"]:
		if not (want in names):
			missing.append(want)
	if missing.is_empty():
		_ok("every documented bus exists", ", ".join(names))
	else:
		_no("buses", "missing %s (have %s)" % [", ".join(missing), ", ".join(names)])

	# Every slot has to route somewhere real, or it plays to a bus Godot invented.
	var bad: Array[String] = []
	for slot in d.slot_names():
		if not (d.bus_of(slot) in names):
			bad.append("%s -> %s" % [slot, d.bus_of(slot)])
	if bad.is_empty():
		_ok("every slot routes to a bus that exists", "%d slots" % d.slot_count())
	else:
		_no("slot routing", ", ".join(bad))


# -------------------------------------------------------------------- families

func _check_families(d: AudioDirector) -> void:
	var missing: Array[String] = []
	for family in REQUIRED_FAMILIES:
		for slot in REQUIRED_FAMILIES[family]:
			if not d.has_slot(StringName(slot)):
				missing.append(slot)
	var roster := _enemy_ids()
	for eid in roster:
		for event in ENEMY_EVENTS:
			var slot := "enemy_%s_%s" % [eid, event]
			if not d.has_slot(StringName(slot)):
				missing.append(slot)
	for slot in MUSIC:
		if not d.has_slot(StringName(slot)):
			missing.append(slot)

	if missing.is_empty():
		_ok("every SFX family in guide §14 has a slot",
			"%d slots, %d enemy species x %d events" % [
				d.slot_count(), roster.size(), ENEMY_EVENTS.size()])
	else:
		_no("SFX families", "%d missing: %s" % [missing.size(), ", ".join(missing)])


## Every enemy id in data/enemies/. `*_frames.tres` are SpriteFrames, not data.
func _enemy_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ENEMY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres") or f.get_basename().ends_with("_frames"):
			continue
		var data := load("%s/%s" % [ENEMY_DIR, f]) as EnemyData
		if data != null and data.id != &"":
			out.append(String(data.id))
	out.sort()
	return out


func _check_priorities(d: AudioDirector) -> void:
	# The two the guide singles out. Everything else can be argued about; these
	# two cannot, because they are what the player needs to hear to survive.
	var problems: Array[String] = []
	for slot in ["hero_hurt", "hero_low_health"]:
		var p := d.priority_of(StringName(slot))
		if p != AudioDirector.PRIORITY_PLAYER_DAMAGE:
			problems.append("%s at priority %d, should be %d" % [
				slot, p, AudioDirector.PRIORITY_PLAYER_DAMAGE])
	for eid in _enemy_ids():
		var slot := "enemy_%s_windup" % eid
		var p := d.priority_of(StringName(slot))
		if p > AudioDirector.PRIORITY_TELEGRAPH:
			problems.append("%s at priority %d, telegraphs must be <= %d" % [
				slot, p, AudioDirector.PRIORITY_TELEGRAPH])

	if problems.is_empty():
		_ok("damage warnings and telegraphs hold the top of the mix",
			"damage %d, telegraph %d, environment %d" % [
				AudioDirector.PRIORITY_PLAYER_DAMAGE,
				AudioDirector.PRIORITY_TELEGRAPH,
				AudioDirector.PRIORITY_ENVIRONMENT])
	else:
		_no("mix priority", ", ".join(problems))


# ----------------------------------------------------------- voice starvation

## The check this whole system exists for, and the one that was wrong first.
##
## Three properties, each with a mutant that must kill it:
##
##   1. A priority-1 damage warning gets a voice through a mix full of expendable
##      sounds, by stealing one.
##   2. An expendable sound is refused when everything playing outranks it.
##   3. An equal-priority sound is refused rather than stealing, so the mix does
##      not depend on call order.
##
## Getting this honest took two attempts. The first version filled the pool with
## footsteps, then "proved" property 2 by asking for another footstep — which was
## being dropped by *flood control*, not by priority. It passed with voice stealing
## entirely removed. Every fill below therefore uses distinct slots, and the sound
## under test is always one that has not been played yet in this run.
func _check_voice_starvation(d: AudioDirector) -> void:
	var by_priority := {}
	for slot in d.slot_names():
		var p := d.priority_of(slot)
		by_priority[p] = (by_priority.get(p, []) as Array) + [slot]

	# Held back from every fill below, so there is always a never-played slot to
	# test with. Without this the fill consumes the whole priority-6 family and
	# there is nothing left whose refusal could be about priority.
	var reserved := {}
	var peer_slot := _unused_slot_at(by_priority, AudioDirector.PRIORITY_ENVIRONMENT, reserved)
	reserved[peer_slot] = true
	var victim_slot := _unused_slot_at(by_priority, AudioDirector.PRIORITY_ENVIRONMENT, reserved)
	reserved[victim_slot] = true

	# ---- property 1: a damage warning gets through a full, expendable mix ----
	d.stop_all()
	var used := reserved.duplicate()
	var expendable := _without(
		_slots_at_or_below(by_priority, AudioDirector.PRIORITY_ATTACK, 99), reserved)
	var worst_filled := _fill(d, expendable, used)

	if d.active_voices() != d.max_voices:
		_no("voice pool", "only %d of %d voices busy with %d distinct slots — cannot "
			% [d.active_voices(), d.max_voices, expendable.size()]
			+ "test starvation at all")
		return
	_ok("the voice pool fills to its ceiling with distinct sounds",
		"%d voices, worst priority playing is %d" % [d.active_voices(), worst_filled])

	var before := d.stolen_count()
	if d.play(&"hero_hurt") and d.is_slot_active(&"hero_hurt"):
		_ok("a damage warning plays through a completely full mix",
			"priority 1 stole from priority %d (%d steal)" % [
				worst_filled, d.stolen_count() - before])
	else:
		_no("damage warning", "dropped or inaudible with the mix full of priority-%d "
			% worst_filled + "sounds — this is the one sound guide §14 says must "
			+ "always be heard")

	# ---- property 3: equal priority does not steal ----
	# Ask for a *fresh* sound at the same priority as the worst one playing. Under
	# correct code there is nothing strictly worse to take, so it is refused.
	d.stop_all()
	used = reserved.duplicate()
	worst_filled = _fill(d, expendable, used)
	var peer := peer_slot if d.priority_of(peer_slot) == worst_filled else &""
	if peer == &"":
		_no("equal priority", "no unused priority-%d slot left to test with" % worst_filled)
	elif d.active_voices() != d.max_voices:
		_no("equal priority", "pool not full (%d voices)" % d.active_voices())
	else:
		var stolen_before := d.stolen_count()
		var played := d.play_at(peer, Vector3.ZERO)
		if not played and d.stolen_count() == stolen_before:
			_ok("an equal-priority sound is refused rather than stealing",
				"%s at priority %d found nothing worse to take" % [peer, worst_filled])
		else:
			_no("equal priority", "%s %s — the mix would depend on call order" % [
				peer, "stole a voice" if d.stolen_count() > stolen_before else "played"])

	# ---- property 2: expendable cannot evict important ----
	d.stop_all()
	used = reserved.duplicate()
	var important := _without(
		_slots_at_or_below(by_priority, 0, AudioDirector.PRIORITY_TELEGRAPH), reserved)
	_fill(d, important, used)
	if d.active_voices() != d.max_voices:
		_no("priority inversion", "only %d of %d voices filled with priority<=%d "
			% [d.active_voices(), d.max_voices, AudioDirector.PRIORITY_TELEGRAPH]
			+ "sounds (%d distinct available)" % important.size())
	else:
		# A slot that has never been played this run, so flood control cannot be
		# the reason it is refused.
		var victim := victim_slot
		var stolen_before := d.stolen_count()
		var got := d.play_at(victim, Vector3.ZERO)
		if not got and d.stolen_count() == stolen_before:
			_ok("an expendable sound cannot evict a damage warning",
				"%s (priority %d) refused, %d priority<=%d voices untouched" % [
					victim, d.priority_of(victim), d.active_voices(),
					AudioDirector.PRIORITY_TELEGRAPH])
		else:
			_no("priority inversion", "%s (priority %d) %s with the mix full of "
				% [victim, d.priority_of(victim),
					"stole a voice" if d.stolen_count() > stolen_before else "played"]
				+ "priority-1 and priority-2 sounds")

	d.stop_all()
	if d.active_voices() == 0:
		_ok("stop_all releases every voice")
	else:
		_no("stop_all", "%d voices still held" % d.active_voices())


## Slots whose priority is within [best, worst], worst-first so a fill leaves the
## most expendable sounds occupying the pool.
func _slots_at_or_below(by_priority: Dictionary, best: int, worst: int) -> Array:
	var priorities: Array = by_priority.keys()
	priorities.sort()
	priorities.reverse()
	var out: Array = []
	for p in priorities:
		if p >= best and p <= worst:
			out.append_array(by_priority[p])
	return out


## Fills the pool from `slots`, using each slot up to its flood allowance.
##
## One play per slot is not enough: there are only thirteen distinct slots at
## priority 2 or better, against twenty-four voices. Repeating each up to
## max_same_slot stays inside flood control, so a later drop of a *different*
## slot can only be about priority.
##
## Returns the worst (numerically highest) priority actually playing.
func _fill(d: AudioDirector, slots: Array, used: Dictionary) -> int:
	var worst := 0
	for _round in d.max_same_slot:
		for slot in slots:
			if d.active_voices() >= d.max_voices:
				return worst
			if d.play_at(slot, Vector3.ZERO):
				used[slot] = true
				worst = maxi(worst, d.priority_of(slot))
	return worst


func _without(slots: Array, excluded: Dictionary) -> Array:
	var out: Array = []
	for slot in slots:
		if not excluded.has(slot):
			out.append(slot)
	return out


func _unused_slot_at(by_priority: Dictionary, priority: int, used: Dictionary) -> StringName:
	for slot in by_priority.get(priority, []):
		if not used.has(slot):
			return slot
	return &""


# ----------------------------------------------------------------------- flood

## A crawler pack lands many identical attacks on one frame. The fifth copy is
## not audible as a fifth copy, so it should never have been given a voice.
func _check_flood(d: AudioDirector) -> void:
	# Named from the roster, not hardcoded — a stale slot name here reports as a
	# flood-control failure, which is a confusing way to learn the roster changed.
	var roster := _enemy_ids()
	if roster.is_empty():
		_no("flood control", "no enemy roster to test with")
		return
	var slot := StringName("enemy_%s_attack" % roster[0])
	if not d.has_slot(slot):
		_no("flood control", "no slot '%s' — roster and audio set disagree" % slot)
		return

	d.stop_all()
	# Run the clock past the flood window first. The starvation check above played
	# this same slot to fill the pool, and stop_all does not clear flood history —
	# so without this the count starts at one and the assertion can only be a
	# loose "<=", which would also pass if flood control were broken open.
	for _i in int(d.flood_window_seconds / STEP) + 4:
		d.tick(STEP)

	var accepted := 0
	for _i in 40:
		if d.play_at(slot, Vector3.ZERO):
			accepted += 1

	if accepted == d.max_same_slot:
		_ok("forty simultaneous copies of one sound collapse to exactly the ceiling",
			"%d of 40 accepted, ceiling %d" % [accepted, d.max_same_slot])
	else:
		_no("flood control", "%d of 40 copies accepted, ceiling is %d" % [
			accepted, d.max_same_slot])

	# And it must recover: the same sound has to be playable again next second,
	# or a repeated attack goes permanently silent.
	d.stop_all()
	for _i in 30:
		d.tick(STEP)
	if d.play_at(slot, Vector3.ZERO):
		_ok("the flood window reopens", "playable again after %.2fs" % (30.0 * STEP))
	else:
		_no("flood window", "still suppressed half a second later")
	d.stop_all()


# ----------------------------------------------------------------------- music

func _check_music(d: AudioDirector) -> void:
	if not d.play_music(&"music_sunfall_explore"):
		_no("music", "could not start music_sunfall_explore")
		return
	if d.current_music() != &"music_sunfall_explore":
		_no("music", "current_music is '%s'" % d.current_music())
		return
	_ok("a music bed starts and reports itself", String(d.current_music()))

	# Re-requesting the same bed must not restart it — a room that announces its
	# own music on entry would otherwise stutter the track every doorway.
	var changes := [0]
	d.music_changed.connect(func(_s: StringName) -> void: changes[0] += 1)
	d.play_music(&"music_sunfall_explore")
	if changes[0] == 0:
		_ok("re-requesting the playing bed is a no-op")
	else:
		_no("music restart", "same bed re-triggered %d time(s)" % changes[0])

	if d.play_music(&"music_first_bell") and d.current_music() == &"music_first_bell":
		_ok("switching beds works", "explore -> first_bell")
	else:
		_no("music switch", "still on '%s'" % d.current_music())

	# The placeholder beds are written as whole bars so the seam lands on a beat;
	# that is worth nothing unless the stream is actually set to loop.
	var stream := load("res://assets/audio/music/music_first_bell.wav") as AudioStreamWAV
	if stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		_ok("music streams are set to loop", "loop_mode %d" % stream.loop_mode)
	elif stream == null:
		_no("music loop", "music_first_bell.wav did not load as AudioStreamWAV")
	else:
		_no("music loop", "loop_mode is %d, not LOOP_FORWARD" % stream.loop_mode)

	d.stop_music()
	if d.current_music() == &"":
		_ok("stop_music clears the current bed")
	else:
		_no("stop_music", "still reports '%s'" % d.current_music())


# --------------------------------------------------------------------- volumes

func _check_volumes(d: AudioDirector, settings: _FakeSettings) -> void:
	settings.values["volume_master"] = 1.0
	settings.values["volume_music"] = 0.5
	settings.values["volume_sfx"] = 0.8
	d.apply_volumes()

	var problems: Array[String] = []
	if absf(d.bus_volume_linear("music") - 0.5) > 0.02:
		problems.append("music at %.3f, set to 0.5" % d.bus_volume_linear("music"))
	if absf(d.bus_volume_linear("sfx") - 0.8) > 0.02:
		problems.append("sfx at %.3f, set to 0.8" % d.bus_volume_linear("sfx"))
	if problems.is_empty():
		_ok("the volume settings reach the buses", "music 0.5, sfx 0.8")
	else:
		_no("volumes", ", ".join(problems))

	# Zero has to be silence. linear_to_db(0) is -inf, which is easy to get wrong
	# and leaves a bus quietly audible instead of muted.
	settings.values["volume_master"] = 0.0
	d.apply_volumes()
	if d.bus_volume_linear("Master") == 0.0:
		_ok("a zero slider mutes rather than nearly-mutes")
	else:
		_no("mute", "Master at %.5f with the slider at zero" % d.bus_volume_linear("Master"))

	settings.values["volume_master"] = 1.0
	d.apply_volumes()
	if absf(d.bus_volume_linear("Master") - 1.0) > 0.02:
		_no("unmute", "Master stuck at %.3f" % d.bus_volume_linear("Master"))
	else:
		_ok("and unmutes again")


# ------------------------------------------------------------------ the files

## "Synthesised placeholder" licenses something rough, not an empty file. A silent
## placeholder cannot be told apart from an unwired hook, which is the whole
## reason these were synthesised instead of stubbed.
func _check_files_are_not_silent() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	var doc: Dictionary = JSON.parse_string(text)
	var silent: Array[String] = []
	var missing: Array[String] = []
	var checked := 0
	var shortest := 1e9
	var longest := 0.0

	for group in ["sfx", "music"]:
		for entry_v in doc.get(group, []):
			var e: Dictionary = entry_v
			var path := String(e["path"])
			if not ResourceLoader.exists(path):
				missing.append(String(e["slot"]))
				continue
			var stream := load(path) as AudioStreamWAV
			if stream == null:
				missing.append(String(e["slot"]))
				continue
			checked += 1
			var seconds := stream.get_length()
			shortest = minf(shortest, seconds)
			longest = maxf(longest, seconds)
			# Peak amplitude straight off the PCM. Anything this quiet is silence.
			var data := stream.data
			var peak := 0
			var i := 0
			while i + 1 < data.size():
				var sample := data.decode_s16(i)
				peak = maxi(peak, absi(sample))
				i += 256  # every 128th frame; a silent file is silent everywhere
			if peak < 328:  # 1% of full scale
				silent.append("%s (peak %d)" % [e["slot"], peak])

	if not missing.is_empty():
		# Not a failure: assets/ is gitignored, so a fresh checkout has none of
		# these. It is only a failure if some are present and some are not.
		if checked == 0:
			print("  SKIP  no audio files in this checkout (assets/ is gitignored)")
			print("        rebuild with ./tools/make_placeholder_audio.py")
			return
		_no("audio files", "%d of %d missing: %s" % [
			missing.size(), missing.size() + checked, ", ".join(missing)])
		return

	if silent.is_empty():
		_ok("every placeholder is real audio, not silence",
			"%d files, %.2fs to %.2fs" % [checked, shortest, longest])
	else:
		_no("silent placeholders", ", ".join(silent))


class _FakeSettings extends Object:
	signal settings_changed(key: String, value: Variant)

	var values := {
		"volume_master": 1.0,
		"volume_music": 0.8,
		"volume_sfx": 1.0,
	}

	func get_setting(key: String) -> Variant:
		return values.get(key)


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("AUDIO:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
