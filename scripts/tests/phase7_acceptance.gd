extends SceneTree

## Phase 7 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase7_acceptance.gd
##
## The five criteria:
##   - Empty Bond slots receive a summon offer by the second reward.
##   - Equipped summon gets an Echo offer by the Spirit Well.
##   - No three-card offer is fully unusable.
##   - Evolution visibly changes the summon and one behaviour.
##   - Controller can select and confirm every card.
##
## Every expected value comes from docs/LEVEL1_BALANCE.json or the master guide,
## never from the resource under test — see README "Testing discipline".

const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]
const STAFF := "res://data/weapons/conjurer_staff.tres"
const SUMMON_SCENE := "res://scenes/actors/summon_base.tscn"
const TICK := 1.0 / 60.0

var _pass := 0
var _fail := 0

var _catalog: Array[SpiritData] = []
var _world: Node3D
var _hero: Node3D
var _summon: SummonBase
var _screen: RewardScreen

var _stage := -1
var _mark := 0.0
var _bound_anim_frames := 0
var _bound_pixel_size := 0.0
var _bound_display := ""
var _probe_camera: Camera3D
var _probes: Array[SummonBase] = []


func _initialize() -> void:
	print("\n=== PHASE 7 ACCEPTANCE ===\n")

	for path in SPIRITS:
		var s := load(path) as SpiritData
		if s == null:
			_no("spirit data", "could not load %s" % path)
			_summary()
			return
		_catalog.append(s)

	_check_forms_exist()
	_check_evolution_chain()
	_check_summon_pity()
	_check_echo_pity()
	_check_never_three_unusable()
	_check_no_fourth_summon()
	_check_ascendant_replaces_echo()
	_check_rarity_weights()

	_world = Node3D.new()
	root.add_child(_world)
	_hero = Node3D.new()
	_world.add_child(_hero)
	_stage = 0


# ------------------------------------------------------- static / data checks

func _check_forms_exist() -> void:
	# Guide §5: every starter evolves Bound -> Awakened -> Ascendant in the
	# first playtest, so three forms each is the spec, not two.
	var wrong: Array[String] = []
	for s in _catalog:
		if s.forms.size() != 3:
			wrong.append("%s has %d forms" % [s.id, s.forms.size()])
			continue
		for i in 3:
			var f := s.form(i)
			if f == null or int(f.tier) != i:
				wrong.append("%s form %d has tier %s" % [s.id, i, "null" if f == null else str(f.tier)])
			elif f.sprite_frames == null:
				wrong.append("%s form %d has no SpriteFrames" % [s.id, i])
			elif f.metrics_key == &"":
				wrong.append("%s form %d has no metrics_key" % [s.id, i])
	if wrong.is_empty():
		_ok("all three starters have Bound/Awakened/Ascendant forms", "9 forms, each with art and a pivot row")
	else:
		_no("evolution forms", "; ".join(wrong))


func _check_evolution_chain() -> void:
	# Stats must NOT change: guide §5 "Stat gain alone is never enough to
	# qualify as an evolution", and LEVEL1_BALANCE gives one damage number per
	# summon. Assert against the JSON so a drifted .tres cannot pass itself.
	var wrong: Array[String] = []
	for s in _catalog:
		var block: Dictionary = Balance.summon(String(s.id))
		if block.is_empty():
			wrong.append("%s missing from balance" % s.id)
			continue
		var want_damage := int(block.get("damage", -1))
		var want_range := float(block.get("range_units", -1.0))
		for i in s.forms.size():
			var f := s.form(i)
			if f.damage != want_damage:
				wrong.append("%s tier %d damage %d, balance says %d" % [s.id, i, f.damage, want_damage])
			if not is_equal_approx(f.range_units, want_range):
				wrong.append("%s tier %d range %.2f, balance says %.2f" % [s.id, i, f.range_units, want_range])
	if wrong.is_empty():
		_ok("evolution changes body and behaviour, not stats", "damage and range match LEVEL1_BALANCE at every tier")
	else:
		_no("evolution stats", "; ".join(wrong))

	# ...and the behaviour text must actually be the balance bonus string.
	var text_wrong: Array[String] = []
	for s in _catalog:
		var block: Dictionary = Balance.summon(String(s.id))
		var expected := {
			1: String(block.get("awakened_bonus", "")),
			2: String(block.get("ascendant_bonus", "")),
		}
		for tier in expected:
			var want: String = expected[tier]
			var got: String = s.form(tier).passive_description
			if want != "" and got != want:
				text_wrong.append("%s tier %d: %s" % [s.id, tier, got])
	if text_wrong.is_empty():
		_ok("each tier carries its balance behaviour", "awakened_bonus / ascendant_bonus verbatim")
	else:
		_no("tier behaviour text", "; ".join(text_wrong))


func _check_summon_pity() -> void:
	# Guide §6: "By the second reward, offer at least one missing summon if a
	# Bond slot is empty."
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	var system := RewardSystem.new(_catalog, 12345)

	state.rewards_taken = 1  # the next offer is the second
	var offer := system.build_offer(state)
	if _count_kind(offer, RewardCard.Kind.SUMMON) >= 1:
		_ok("second reward offers a missing summon", "%d bond slots empty" % RunState.BOND_SLOTS)
	else:
		_no("summon pity", "no summon card in the second offer")

	# The floor must hold whatever the RNG does, so sweep seeds.
	var misses := 0
	for seed_value in range(1, 60):
		var s2 := RunState.new(load(STAFF) as FocusWeaponData)
		s2.rewards_taken = 1
		var sys2 := RewardSystem.new(_catalog, seed_value)
		if _count_kind(sys2.build_offer(s2), RewardCard.Kind.SUMMON) < 1:
			misses += 1
	if misses == 0:
		_ok("summon pity holds across 59 seeds", "not a lucky roll")
	else:
		_no("summon pity", "%d of 59 seeds produced no summon card" % misses)


func _check_echo_pity() -> void:
	# Guide §6: "By the Spirit Well, offer at least one Echo for an equipped
	# summon."
	var misses := 0
	for seed_value in range(1, 60):
		var state := RunState.new(load(STAFF) as FocusWeaponData)
		state.bond(_catalog[0])
		state.reached_spirit_well = true
		var system := RewardSystem.new(_catalog, seed_value)
		if _count_kind(system.build_offer(state), RewardCard.Kind.ECHO) < 1:
			misses += 1
	if misses == 0:
		_ok("Spirit Well offers an Echo for an equipped summon", "59 seeds, always present")
	else:
		_no("echo pity", "%d of 59 seeds produced no Echo card" % misses)


func _check_never_three_unusable() -> void:
	# Guide §6: "Never show three unusable cards." Hardest case is a full,
	# fully-evolved team holding every relic — nothing left to give.
	var worst := RunState.new(load(STAFF) as FocusWeaponData)
	for s in _catalog:
		worst.bond(s)
		worst.apply_echo(s.id)
		worst.apply_echo(s.id)
	for entry in RewardSystem.SUMMON_RELICS:
		worst.add_relic(entry["id"])
	for entry in RewardSystem.GENERAL_RELICS:
		worst.add_relic(entry["id"])
	for entry in RewardSystem.FOCUS_UPGRADES:
		worst.add_relic(entry["id"])

	var dead := 0
	var short_offers := 0
	for seed_value in range(1, 120):
		var system := RewardSystem.new(_catalog, seed_value)
		var offer := system.build_offer(worst)
		if offer.size() != RewardSystem.CARDS_PER_OFFER:
			short_offers += 1
		var usable := 0
		for c in offer:
			if c.is_usable(worst):
				usable += 1
		if usable == 0:
			dead += 1
	if dead == 0 and short_offers == 0:
		_ok("no offer is ever fully unusable", "119 seeds against a maxed, fully-stocked run")
	else:
		_no("unusable offers", "%d dead offers, %d short offers" % [dead, short_offers])


func _check_no_fourth_summon() -> void:
	# Guide §6: "Do not offer a fourth summon in the vertical slice."
	var full := RunState.new(load(STAFF) as FocusWeaponData)
	for s in _catalog:
		full.bond(s)
	var offenders := 0
	for seed_value in range(1, 120):
		var system := RewardSystem.new(_catalog, seed_value)
		if _count_kind(system.build_offer(full), RewardCard.Kind.SUMMON) > 0:
			offenders += 1
	if offenders == 0:
		_ok("never offers a fourth summon", "119 seeds with all three bonded")
	else:
		_no("fourth summon", "%d seeds offered one" % offenders)

	# The offer layer and RunState guard this independently, so the card check
	# above still passes if only one of them breaks. Assert the state layer
	# directly rather than trusting the redundancy.
	#
	# The spirit has to be a genuinely new one: offering an already-bonded
	# spirit trips the duplicate guard instead and proves nothing about a full
	# team. The first version of this check made exactly that mistake.
	var stranger := _catalog[0].duplicate() as SpiritData
	stranger.id = &"test_fourth_spirit"

	var before := full.filled_slot_count()
	var occupants := full.bonded_ids().duplicate()
	var refused := full.bond(stranger) < 0
	if refused and full.filled_slot_count() == before and full.bonded_ids() == occupants:
		_ok("a fourth bond is refused by the run state", "%d slots stay filled, none overwritten" % before)
	else:
		_no("fourth bond", "slots %d -> %d, team now %s" % [before, full.filled_slot_count(), str(full.bonded_ids())])


func _check_ascendant_replaces_echo() -> void:
	# Guide §6: "When all three summons are Ascendant, replace Echo offers with
	# relics or Focus upgrades."
	var maxed := RunState.new(load(STAFF) as FocusWeaponData)
	for s in _catalog:
		maxed.bond(s)
		maxed.apply_echo(s.id)
		maxed.apply_echo(s.id)
	maxed.reached_spirit_well = true

	if not maxed.all_bonds_maxed():
		_no("ascendant state", "three double-Echoed summons are not all maxed")
		return

	var echoes := 0
	var substitutes := 0
	for seed_value in range(1, 120):
		var system := RewardSystem.new(_catalog, seed_value)
		for c in system.build_offer(maxed):
			if c.kind == RewardCard.Kind.ECHO:
				echoes += 1
			elif c.kind in [RewardCard.Kind.SUMMON_RELIC, RewardCard.Kind.GENERAL_RELIC, RewardCard.Kind.FOCUS_UPGRADE]:
				substitutes += 1
	if echoes == 0 and substitutes > 0:
		_ok("Ascendant team gets relics instead of Echoes", "%d substitute cards, 0 Echoes over 119 seeds" % substitutes)
	else:
		_no("ascendant substitution", "%d Echo cards still offered" % echoes)


func _check_rarity_weights() -> void:
	# Guide §6 prototype rarity table.
	var want := {
		RewardCard.Rarity.COMMON: 60,
		RewardCard.Rarity.UNCOMMON: 30,
		RewardCard.Rarity.RARE: 10,
	}
	if RewardCard.RARITY_WEIGHTS == want:
		_ok("rarity weights match the guide", "60 / 30 / 10")
	else:
		_no("rarity weights", str(RewardCard.RARITY_WEIGHTS))


# ------------------------------------------------------------- runtime checks

func _process(delta: float) -> bool:
	match _stage:
		0:
			_spawn_summon()
		1:
			_settle(delta)
		2:
			_capture_bound_form()
		3:
			_evolve_and_compare()
		4:
			_build_screen()
		5:
			_drive_controller()
		30:
			_mark += delta
			if _mark >= 0.1:
				_check_evolved_screen_sizes()
				_stage = 4
		99:
			_summary()
			return true
	return false


func _spawn_summon() -> void:
	var packed := load(SUMMON_SCENE) as PackedScene
	if packed == null:
		_no("summon scene", "could not load %s" % SUMMON_SCENE)
		_stage = 99
		return
	_summon = packed.instantiate() as SummonBase
	_summon.data = _catalog[0]
	_summon.hero = _hero
	_world.add_child(_summon)
	_mark = 0.0
	_stage = 1


func _settle(delta: float) -> void:
	_mark += delta
	if _mark >= 0.3:
		_stage = 2


func _capture_bound_form() -> void:
	if _summon.form == null:
		_no("summon form", "no form after spawn")
		_stage = 99
		return
	var sprite := _find_sprite(_summon)
	if sprite == null:
		_no("summon sprite", "no AnimatedSprite3D")
		_stage = 99
		return
	_bound_display = _summon.form.display_name
	_bound_pixel_size = sprite.pixel_size
	_bound_anim_frames = sprite.sprite_frames.get_frame_count("idle") if sprite.sprite_frames.has_animation("idle") else -1
	_stage = 3


func _evolve_and_compare() -> void:
	var sprite := _find_sprite(_summon)
	var bound_texture := sprite.sprite_frames.get_frame_texture("idle", 0)

	if not _summon.set_form_index(1):
		_no("evolution", "set_form_index(1) refused")
		_stage = 99
		return

	var awakened_texture := sprite.sprite_frames.get_frame_texture("idle", 0)
	var changed_art := bound_texture != awakened_texture
	var changed_name := _summon.form.display_name != _bound_display

	if changed_art and changed_name:
		_ok("evolution visibly changes the summon", "%s -> %s, new SpriteFrames" % [_bound_display, _summon.form.display_name])
	else:
		_no("evolution visuals", "art changed=%s name changed=%s" % [changed_art, changed_name])

	# One behaviour, from balance.
	var bonus := String(Balance.summon(String(_catalog[0].id)).get("awakened_bonus", ""))
	if bonus != "" and _summon.form.passive_description == bonus:
		_ok("evolution grants one behaviour", bonus)
	else:
		_no("evolution behaviour", "got '%s'" % _summon.form.passive_description)

	# The pivot table must follow the tier, or the Bound row's correction lands
	# on art that does not need it.
	#
	# This asks the summon what it loaded, not what the audit file says. An
	# earlier version compared two numbers straight out of the JSON and passed
	# happily with the lookup hard-wired back to the Bound row.
	var metrics: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/generated/summon_metrics.json"))
	var species: Dictionary = (metrics as Dictionary).get("species", {}) if typeof(metrics) == TYPE_DICTIONARY else {}
	var awakened_row: Dictionary = species.get(String(_summon.form.metrics_key), {}).get("pivot_offsets", {})
	var bound_row: Dictionary = species.get(String(_catalog[0].id), {}).get("pivot_offsets", {})

	var mismatched: Array[String] = []
	var differs_from_bound := false
	for key in awakened_row:
		var anim := String(key).get_slice("/", 0)
		var want := int(awakened_row[key])
		var got := _summon.pivot_correction_px(anim)
		if got != want:
			mismatched.append("%s got %d want %d" % [anim, got, want])
		if int(bound_row.get(key, 0)) != want:
			differs_from_bound = true

	if mismatched.is_empty() and differs_from_bound:
		_ok("evolved tier loads its own pivot row", "%d corrections match the Awakened audit, not the Bound one" % awakened_row.size())
	elif not differs_from_bound:
		# Guards the check itself: if the two rows were identical this would
		# pass no matter which one the code read.
		_no("pivot row", "Bound and Awakened corrections are identical, so this check proves nothing")
	else:
		_no("pivot row", "; ".join(mismatched))

	# Ascendant too, so the chain is proven end to end rather than one step.
	if _summon.set_form_index(2) and _summon.form.tier == SpiritFormData.Tier.ASCENDANT:
		_ok("chain reaches Ascendant", _summon.form.display_name)
	else:
		_no("ascendant", "could not advance to tier 2")

	if not _summon.set_form_index(3):
		_ok("evolution stops at Ascendant", "a fourth tier is refused")
	else:
		_no("evolution clamp", "advanced past Ascendant")

	_summon.queue_free()
	_summon = null
	_build_size_probe()
	_mark = 0.0
	_stage = 30


## Spawns all nine forms in front of a camera matching summon_field's framing.
## Measured a frame later, once the camera is actually inside a viewport —
## unproject_position is meaningless before that.
func _build_size_probe() -> void:
	_probe_camera = Camera3D.new()
	_probe_camera.fov = 40.0
	_probe_camera.transform = Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, 0.819152, 0.573576),
		Vector3(0, -0.573576, 0.819152),
		Vector3(0, 14.25, 20.36),
	)
	_world.add_child(_probe_camera)
	_probe_camera.make_current()

	var probe := load(SUMMON_SCENE) as PackedScene
	for data in _catalog:
		for tier in 3:
			var s := probe.instantiate() as SummonBase
			s.data = data
			s.hero = _hero
			s.form_index = tier
			_world.add_child(s)
			# Every form is measured at the same point, so position cannot
			# explain a difference between tiers.
			s.global_position = Vector3.ZERO
			_probes.append(s)


## Every tier has to meet the same guide §2 on-screen target as its Bound form.
##
## This check exists because the builder's `recommended_world_height_units`
## assumes an idealised camera (1.8 u reads 88 px). The real camera is
## perspective, so the value that hits the target depends on the framing —
## trusting the recommendation pushed the Sword Wisp to 62.8 px against a 58 px
## target and broke Phase 3. Measure through a camera; do not believe the number.
func _check_evolved_screen_sizes() -> void:
	var metrics: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/generated/summon_metrics.json"))
	var species: Dictionary = (metrics as Dictionary).get("species", {}) if typeof(metrics) == TYPE_DICTIONARY else {}

	# Measured as drawn world height, not projected pixels.
	#
	# Every probe stands at the same point, so on-screen size is proportional to
	# drawn world height under any camera — which makes this exact and immune to
	# the framing and viewport-size questions that a projection would drag in.
	# Phase 3 already pins the *absolute* size of the Bound tier against guide
	# §2; what evolution has to guarantee is that a tier swap does not resize the
	# creature, and that is what this measures.
	var drawn: Dictionary = {}   # species id -> {tier: world height}
	var off: Array[String] = []
	var report: Array[String] = []
	var distinct := {}

	for s in _probes:
		if s == null or not is_instance_valid(s) or s.form == null:
			off.append("a probe never resolved its form")
			continue
		var key := String(s.form.metrics_key)
		distinct[key] = true
		var content := float(species.get(key, {}).get("median_content_height_px", 0.0))
		if content <= 0.0:
			off.append("%s has no metrics row" % key)
			continue

		var world_h: float = content * s.form.pixel_size()
		var id := String(s.data.id)
		if not drawn.has(id):
			drawn[id] = {}
		drawn[id][int(s.form.tier)] = world_h

	for id in drawn:
		var tiers: Dictionary = drawn[id]
		if not tiers.has(0):
			off.append("%s has no Bound tier to compare against" % id)
			continue
		var base_h: float = tiers[0]
		report.append("%s %.4f u" % [id, base_h])
		for tier in tiers:
			var ratio: float = float(tiers[tier]) / maxf(base_h, 0.0001)
			# 1% — the values agree to four decimals when the data is right, so
			# this is loose enough to be stable and tight enough to have caught
			# the 9.5% Sword Wisp error.
			if absf(ratio - 1.0) > 0.01:
				off.append("%s tier %d draws %.1f%% of its Bound size" % [id, tier, ratio * 100.0])

	# A silent form_index failure would make all three tiers identical and the
	# size check would then be measuring one form three times.
	if distinct.size() != 9:
		off.append("only %d distinct forms spawned, expected 9" % distinct.size())

	for s in _probes:
		if s != null and is_instance_valid(s):
			s.queue_free()
	_probes.clear()
	if _probe_camera != null:
		_probe_camera.queue_free()
		_probe_camera = null

	if off.is_empty():
		_ok("evolving never resizes the summon", "9 forms, every tier within 1% of its Bound size (" + ", ".join(report) + ")")
	else:
		_no("evolved screen sizes", "; ".join(off))


func _build_screen() -> void:
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	state.rewards_taken = 1
	var system := RewardSystem.new(_catalog, 4242)
	var offer := system.build_offer(state)

	_screen = RewardScreen.new()
	root.add_child(_screen)
	_screen.present(offer, state)

	if _screen.card_buttons().size() == RewardSystem.CARDS_PER_OFFER:
		_ok("reward screen renders three cards", "Godot Control nodes, not a mockup")
	else:
		_no("reward screen", "%d buttons" % _screen.card_buttons().size())
	_stage = 5


func _drive_controller() -> void:
	# Acceptance: "Controller can select and confirm every card." Focus is the
	# controller's cursor, so this walks the row by focus and confirms.
	var buttons := _screen.card_buttons()
	if buttons.is_empty():
		_no("controller focus", "no cards")
		_stage = 99
		return

	var all_focusable := true
	for b in buttons:
		if b.focus_mode != Control.FOCUS_ALL:
			all_focusable = false
	if all_focusable:
		_ok("every card is focusable", "%d cards, FOCUS_ALL" % buttons.size())
	else:
		_no("card focus", "a card cannot take focus")

	# Walking right from any card must reach every other card and come back —
	# a broken neighbour link would strand the controller on one end.
	var seen := {}
	var index := _screen.focused_index()
	if index < 0:
		_no("initial focus", "nothing focused after present()")
		_stage = 99
		return
	for _i in buttons.size():
		seen[index] = true
		index = _screen.focus_next_card()
	if seen.size() == buttons.size():
		_ok("controller reaches every card", "focus wraps the row")
	else:
		_no("controller navigation", "reached %d of %d cards" % [seen.size(), buttons.size()])

	# Confirming has to actually resolve the offer.
	var chosen: Array = []
	_screen.card_chosen.connect(func(card: RewardCard, _idx: int) -> void: chosen.append(card))
	var confirmed := _screen.confirm_focused()
	if confirmed >= 0 and chosen.size() == 1:
		_ok("controller confirms a card", "%s" % chosen[0].title)
	else:
		_no("controller confirm", "confirm returned %d, %d emissions" % [confirmed, chosen.size()])

	# And taking it must change the run.
	var state := RunState.new(load(STAFF) as FocusWeaponData)
	var system := RewardSystem.new(_catalog, 99)
	state.rewards_taken = 1
	var offer := system.build_offer(state)
	var before := state.filled_slot_count()
	var summon_card: RewardCard = null
	for c in offer:
		if c.kind == RewardCard.Kind.SUMMON:
			summon_card = c
	if summon_card != null and system.take(state, summon_card) and state.filled_slot_count() == before + 1:
		_ok("taking a summon card fills a Bond slot", "%d -> %d" % [before, state.filled_slot_count()])
	else:
		_no("card application", "bond slots %d -> %d" % [before, state.filled_slot_count()])

	if state.rewards_taken == 2:
		_ok("taking a card advances the reward counter", "drives the pity floors")
	else:
		_no("reward counter", "rewards_taken = %d" % state.rewards_taken)

	_stage = 99


# ---------------------------------------------------------------- helpers

func _find_sprite(node: Node) -> AnimatedSprite3D:
	for child in node.get_children():
		if child is AnimatedSprite3D:
			return child as AnimatedSprite3D
		var found := _find_sprite(child)
		if found != null:
			return found
	return null


func _count_kind(cards: Array[RewardCard], kind: RewardCard.Kind) -> int:
	var n := 0
	for c in cards:
		if c != null and c.kind == kind:
			n += 1
	return n


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	print("\n" + "=".repeat(46))
	print("PHASE 7:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
