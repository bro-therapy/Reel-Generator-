extends SceneTree

## Phase 10 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase10_acceptance.gd
##
## The three criteria:
##   - Player cannot be trapped after failure.
##   - Timer, core health, and reward state reset on a new run.
##   - Main route remains completable after skipping or failing the Rift.

const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]
const STAFF := "res://data/weapons/conjurer_staff.tres"

var _pass := 0
var _fail := 0
var _catalog: Array[SpiritData] = []


func _initialize() -> void:
	print("\n=== PHASE 10 ACCEPTANCE ===\n")
	for path in SPIRITS:
		var s := load(path) as SpiritData
		if s != null:
			_catalog.append(s)

	_check_entry_cost()
	_check_preview()
	_check_duration()
	_check_success()
	_check_failure_ejects()
	_check_not_trapped()
	_check_reset()
	_check_route_survives()
	_summary()


func _run_state() -> RunState:
	return RunState.new(load(STAFF) as FocusWeaponData)


func _check_entry_cost() -> void:
	# Guide §7 owns the number; the event must not carry its own copy.
	var want := int(Balance.stability().get("rift_entry_cost", -1))
	if RiftEvent.entry_cost() == want and want == 10:
		_ok("entry costs the balance's Stability", "%d Stability" % want)
	else:
		_no("entry cost", "%d, balance says %d" % [RiftEvent.entry_cost(), want])

	var s := _run_state()
	var before := s.stability
	var rift := RiftEvent.new(s)
	if rift.enter() and s.stability == before - want:
		_ok("entering spends the Stability", "%d -> %d" % [before, s.stability])
	else:
		_no("entry spend", "stability %d -> %d" % [before, s.stability])

	# Entering on fumes would end the run at the door. That is a trap, not a
	# choice, so it is refused.
	var low := _run_state()
	low.adjust_stability(-(low.stability - want))
	var rift2 := RiftEvent.new(low)
	if not rift2.can_enter():
		_ok("the Rift refuses entry that would end the run", "%d Stability, costs %d" % [low.stability, want])
	else:
		_no("entry guard", "allowed entry at %d Stability" % low.stability)


func _check_preview() -> void:
	# Guide §9: "rare Echo with a visible category preview before entry."
	var rift := RiftEvent.new(_run_state())
	if rift.state == RiftEvent.State.PREVIEW and rift.reward_preview() != "":
		_ok("the reward is previewed before entry", rift.reward_preview())
	else:
		_no("reward preview", "no preview available before entry")


func _check_duration() -> void:
	# Guide §9 and LEVEL1_BALANCE's optional_rift encounter both say 45 s.
	var encounter := EncounterData.from_balance("optional_rift")
	var want: float = encounter.duration_seconds if encounter != null else -1.0
	if is_equal_approx(RiftEvent.DURATION_SECONDS, want) and is_equal_approx(want, 45.0):
		_ok("the event runs for the balance duration", "%.0f s" % want)
	else:
		_no("duration", "%.1f s, balance says %.1f" % [RiftEvent.DURATION_SECONDS, want])


func _check_success() -> void:
	var s := _run_state()
	s.bond(_catalog[0])
	var rift := RiftEvent.new(s)
	rift.enter()

	var ticks := 0
	while rift.tick(1.0):
		ticks += 1
		if ticks > 100:
			break

	if rift.state == RiftEvent.State.SUCCESS and ticks == 44:
		_ok("surviving the timer succeeds", "%d one-second ticks" % (ticks + 1))
	else:
		_no("success", "state %d after %d ticks" % [rift.state, ticks])

	var card := rift.claim_reward(_catalog)
	if card != null and card.kind == RewardCard.Kind.ECHO and card.rarity == RewardCard.Rarity.RARE:
		_ok("success grants a rare Echo", card.title)
	else:
		_no("reward", "no rare Echo granted")

	# Claiming twice would double the payout.
	if rift.claim_reward(_catalog) == null:
		_ok("the Echo can only be claimed once", "a second claim returns nothing")
	else:
		_no("reward", "claimed twice")


func _check_failure_ejects() -> void:
	var s := _run_state()
	s.bond(_catalog[0])
	var rift := RiftEvent.new(s)
	rift.enter()

	rift.damage_core(RiftEvent.CORE_MAX_HEALTH)

	if rift.state == RiftEvent.State.FAILURE:
		_ok("losing the core fails the event", "core at %d" % rift.core_health)
	else:
		_no("failure", "state %d with the core destroyed" % rift.state)

	if rift.claim_reward(_catalog) == null:
		_ok("failure grants no reward", "no Echo on a loss")
	else:
		_no("failure reward", "an Echo was granted on a loss")

	if rift.eject(100) == RiftEvent.EJECT_HP:
		_ok("failure ejects the player at one HP", "%d HP" % RiftEvent.EJECT_HP)
	else:
		_no("eject", "%d HP" % rift.exit_hp(100))

	# Brief: "Stability remains spent."
	if s.stability == s.max_stability - RiftEvent.entry_cost() and rift.stability_spent:
		_ok("the Stability stays spent after a failure", "%d/%d" % [s.stability, s.max_stability])
	else:
		_no("stability refund", "%d/%d after failing" % [s.stability, s.max_stability])


func _check_not_trapped() -> void:
	# The criterion that matters most: after failing, the player is out, alive,
	# and the run continues.
	var s := _run_state()
	var rift := RiftEvent.new(s)
	rift.enter()
	rift.damage_core(RiftEvent.CORE_MAX_HEALTH)

	var hp := rift.eject(100)
	var stuck := rift.state == RiftEvent.State.ACTIVE or hp <= 0 or s.stability_is_spent()
	if not stuck:
		_ok("the player is not trapped after a failure", "out at %d HP with %d Stability" % [hp, s.stability])
	else:
		_no("trapped", "state %d, %d HP, %d Stability" % [rift.state, hp, s.stability])

	# Ticking a resolved event must not restart it.
	var restarted := rift.tick(1.0)
	if not restarted and rift.state == RiftEvent.State.FAILURE:
		_ok("a resolved Rift stays resolved", "further ticks do nothing")
	else:
		_no("resolution", "the event resumed after failing")


func _check_reset() -> void:
	# Brief: "Timer, core health, and reward state reset on a new run."
	var s := _run_state()
	s.bond(_catalog[0])
	var rift := RiftEvent.new(s)
	rift.enter()
	rift.damage_core(40)
	rift.tick(10.0)
	rift.damage_core(RiftEvent.CORE_MAX_HEALTH)

	var dirty := rift.time_left < RiftEvent.DURATION_SECONDS or rift.core_health < RiftEvent.CORE_MAX_HEALTH
	rift.reset()

	var clean := (
		rift.state == RiftEvent.State.PREVIEW
		and is_equal_approx(rift.time_left, RiftEvent.DURATION_SECONDS)
		and rift.core_health == RiftEvent.CORE_MAX_HEALTH
		and not rift.reward_granted
		and not rift.stability_spent
	)
	if dirty and clean:
		_ok("a new run resets timer, core and reward state", "45 s, %d core, unclaimed" % RiftEvent.CORE_MAX_HEALTH)
	else:
		_no("reset", "dirty=%s clean=%s" % [dirty, clean])

	# ...and a reset event can be won again, so reset is not just cosmetic.
	rift.enter()
	while rift.tick(5.0):
		pass
	if rift.state == RiftEvent.State.SUCCESS:
		_ok("a reset Rift can be played again", "second attempt succeeded")
	else:
		_no("replay", "state %d on the second attempt" % rift.state)


func _check_route_survives() -> void:
	# Brief: "Main route remains completable after skipping or failing the Rift."
	# WardLayout already keeps the Rift off the critical path; this proves the
	# run state agrees — the route is not gated behind the Rift's reward.
	if not WardLayout.critical_path().has(&"optional_rift"):
		_ok("the route does not pass through the Rift", "skipping it leaves the path intact")
	else:
		_no("route", "optional_rift sits on the critical path")

	var s := _run_state()
	var rift := RiftEvent.new(s)
	rift.enter()
	rift.damage_core(RiftEvent.CORE_MAX_HEALTH)
	rift.eject(100)

	# After the worst case, the player still has Stability and can still reach
	# the boss gate.
	var reachable := not s.stability_is_spent()
	var links_out := 0
	for link in WardLayout.links():
		if link.from == &"combat_a" and not link.optional:
			links_out += 1
	if reachable and links_out >= 1:
		_ok("the main route is completable after failing the Rift", "%d Stability, %d unmarked exit from Combat A" % [s.stability, links_out])
	else:
		_no("route after failure", "%d Stability, %d exits" % [s.stability, links_out])


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 10:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
