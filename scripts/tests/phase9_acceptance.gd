extends SceneTree

## Phase 9 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase9_acceptance.gd
##
## The five criteria:
##   - Merchant cannot charge twice for one selection.
##   - Locked offer survives reroll.
##   - Unaffordable item communicates disabled state.
##   - Exiting returns control cleanly.
##   - Controller focus never disappears.

const STAFF := "res://data/weapons/conjurer_staff.tres"

var _pass := 0
var _fail := 0
var _screen: MerchantScreen
var _stage := -1


func _initialize() -> void:
	print("\n=== PHASE 9 ACCEPTANCE ===\n")
	_check_prices()
	_check_no_double_charge()
	_check_lock_survives_reroll()
	_check_unaffordable_state()
	_check_heal_once()
	_check_stability_purchase()
	_stage = 0


func _state() -> RunState:
	return RunState.new(load(STAFF) as FocusWeaponData)


func _check_prices() -> void:
	# Brief Phase 9: "One free reroll, then 15/25/40."
	if Merchant.REROLL_COSTS == [0, 15, 25, 40]:
		_ok("reroll ladder matches the brief", "0 / 15 / 25 / 40")
	else:
		_no("reroll ladder", str(Merchant.REROLL_COSTS))

	# Guide §7 owns the Stability numbers.
	var s := _state()
	var m := Merchant.new(s, 11)
	var block := Balance.stability()
	var want_price := int(block.get("spirit_well_restore_cost_currency", -1))
	var want_amount := int(block.get("spirit_well_restore_amount", -1))
	if m.stability_price() == want_price and m.stability_amount() == want_amount:
		_ok("Stability restore matches balance", "%d Stability for %d currency" % [want_amount, want_price])
	else:
		_no("stability pricing", "%d for %d" % [m.stability_amount(), m.stability_price()])

	if m.offers.size() == Merchant.OFFER_COUNT and Merchant.OFFER_COUNT == 5:
		_ok("the well stocks five offers", "%d" % m.offers.size())
	else:
		_no("offer count", "%d offers" % m.offers.size())


func _check_no_double_charge() -> void:
	var s := _state()
	s.add_currency(1000)
	var m := Merchant.new(s, 22)

	var offer := m.offers[0]
	var price := offer.price
	var before := s.currency

	var first := m.buy(0)
	var after_one := s.currency

	# Every way the same selection could arrive twice: a repeated signal, a
	# double click, a held button.
	var repeats := 0
	for _i in 5:
		if m.buy(0):
			repeats += 1

	if first and after_one == before - price and s.currency == after_one and repeats == 0:
		_ok("one selection charges exactly once", "%d -> %d, %d repeat attempts refused" % [before, s.currency, 5])
	else:
		_no("double charge", "currency %d -> %d after %d repeats" % [before, s.currency, repeats])

	# ...and the item is granted once, not five times.
	var owned := 0
	for r in s.relics:
		if r == offer.id:
			owned += 1
	if owned <= 1:
		_ok("a bought item is granted once", offer.title)
	else:
		_no("duplicate grant", "%s held %d times" % [offer.title, owned])


func _check_lock_survives_reroll() -> void:
	var s := _state()
	s.add_currency(1000)
	var m := Merchant.new(s, 33)

	m.set_locked(2, true)
	var held := m.offers[2]
	var before_ids: Array = []
	for o in m.offers:
		before_ids.append(o.id)

	if not m.reroll():
		_no("reroll", "first reroll refused with 1000 currency")
		return

	var still_there := false
	for o in m.offers:
		if o.id == held.id and o.locked:
			still_there = true
	if still_there:
		_ok("a locked offer survives the reroll", held.title)
	else:
		_no("lock", "%s did not survive" % held.title)

	# And the rest actually changed, or "survives" would be meaningless.
	var changed := 0
	for o in m.offers:
		if not before_ids.has(o.id):
			changed += 1
	if changed > 0:
		_ok("the unlocked offers do reroll", "%d of %d changed" % [changed, m.offers.size()])
	else:
		_no("reroll", "nothing changed, so the lock check proves nothing")

	# Locking a second offer releases the first — only one can be held.
	m.set_locked(0, true)
	m.set_locked(1, true)
	var locks := 0
	for o in m.offers:
		if o.locked:
			locks += 1
	if locks == 1 and m.locked_index() == 1:
		_ok("only one offer can be locked", "locking a second releases the first")
	else:
		_no("lock exclusivity", "%d offers locked" % locks)


func _check_unaffordable_state() -> void:
	# Brief: "Unaffordable item communicates disabled state." The model has to
	# say why, or the UI has nothing to render.
	var poor := _state()
	var m := Merchant.new(poor, 44)
	var offer := m.offers[0]

	if not offer.affordable(poor.currency) and offer.blocked_reason(poor.currency) != "":
		_ok("an unaffordable offer reports why", "\"%s\" at %d currency" % [offer.blocked_reason(poor.currency), poor.currency])
	else:
		_no("disabled state", "no reason given for an unaffordable offer")

	# ...and refuses to sell, without moving the currency.
	var before := poor.currency
	var sold := m.buy(0)
	if not sold and poor.currency == before:
		_ok("an unaffordable offer cannot be bought", "currency unchanged at %d" % before)
	else:
		_no("unaffordable purchase", "sold=%s currency %d -> %d" % [sold, before, poor.currency])

	# A sold offer reports its own state rather than looking merely expensive.
	var rich := _state()
	rich.add_currency(1000)
	var m2 := Merchant.new(rich, 44)
	m2.buy(0)
	if m2.offers[0].blocked_reason(rich.currency) == "Sold":
		_ok("a sold offer reads as sold", "not as unaffordable")
	else:
		_no("sold state", m2.offers[0].blocked_reason(rich.currency))


func _check_heal_once() -> void:
	# Guide §9: heal 20%, once per run.
	var s := _state()
	var m := Merchant.new(s, 55)
	var first := m.heal(50, 100)
	var second := m.heal(50, 100)
	if first == 20 and second == 0:
		_ok("the well heals 20% once per run", "%d HP, then nothing" % first)
	else:
		_no("well heal", "first %d, second %d" % [first, second])

	# Healing never overshoots the hero's maximum.
	var s2 := _state()
	var m2 := Merchant.new(s2, 56)
	var topped := m2.heal(95, 100)
	if topped == 5:
		_ok("healing stops at full health", "5 HP from 95/100")
	else:
		_no("heal overshoot", "%d HP from 95/100" % topped)


func _check_stability_purchase() -> void:
	var s := _state()
	s.add_currency(100)
	s.adjust_stability(-40)
	var m := Merchant.new(s, 66)

	var before_stability := s.stability
	var before_currency := s.currency
	var bought := m.buy_stability()

	if bought and s.stability == before_stability + m.stability_amount() and s.currency == before_currency - m.stability_price():
		_ok("Stability can be bought at the well", "%d -> %d for %d" % [before_stability, s.stability, m.stability_price()])
	else:
		_no("stability purchase", "stability %d -> %d" % [before_stability, s.stability])

	# Guide §7: Stability can never exceed its maximum, so a top-up at full is
	# refused rather than wasting the currency.
	var full := _state()
	full.add_currency(100)
	var m2 := Merchant.new(full, 67)
	var spent_before := full.currency
	if not m2.buy_stability() and full.currency == spent_before:
		_ok("a full bar refuses the top-up", "no currency spent at %d/%d" % [full.stability, full.max_stability])
	else:
		_no("stability cap", "bought at full, currency %d -> %d" % [spent_before, full.currency])


# ------------------------------------------------------------------- UI stage

func _process(_delta: float) -> bool:
	match _stage:
		0:
			_build_screen()
			_stage = 1
		1:
			_check_focus_never_lost()
			_stage = 99
		99:
			_summary()
			return true
	return false


func _build_screen() -> void:
	var s := RunState.new(load(STAFF) as FocusWeaponData)
	s.add_currency(1000)
	_screen = MerchantScreen.new()
	root.add_child(_screen)
	_screen.open(Merchant.new(s, 77), s)


## Brief: "Controller focus never disappears" and "Exiting returns control
## cleanly." Focus is the controller's cursor, so losing it strands the player.
func _check_focus_never_lost() -> void:
	var buttons := _screen.focusable_controls()
	if buttons.is_empty():
		_no("merchant focus", "no focusable controls")
		return

	if _screen.focused_index() >= 0:
		_ok("the merchant takes focus when it opens", "%d focusable controls" % buttons.size())
	else:
		_no("initial focus", "nothing focused after open()")

	# Walking the row must reach every control the player can actually use.
	# Disabled controls are deliberately skipped — landing on one is exactly how
	# a controller gets stuck — so the target is the enabled set, not all of them.
	var enabled := 0
	for b in buttons:
		if not b.disabled:
			enabled += 1
	var seen := {}
	for _i in buttons.size() * 2:
		var at := _screen.focused_index()
		if at >= 0:
			seen[at] = true
		_screen.focus_next()
	if seen.size() == enabled and enabled > 0:
		_ok("focus reaches every usable control", "%d enabled of %d, disabled ones skipped" % [enabled, buttons.size()])
	else:
		_no("focus navigation", "reached %d, %d enabled of %d" % [seen.size(), enabled, buttons.size()])

	# The dangerous case: buying the focused item disables it. Focus has to move
	# rather than sit on a dead control.
	var idx := _screen.focused_index()
	_screen.buy_focused()
	if _screen.focused_index() >= 0 and not _screen.focused_is_disabled():
		_ok("focus moves off an item once it is bought", "was %d, now %d" % [idx, _screen.focused_index()])
	else:
		_no("focus after purchase", "focus left on a disabled control (index %d)" % _screen.focused_index())

	# Rerolling rebuilds every card; focus must survive that too.
	_screen.reroll()
	if _screen.focused_index() >= 0:
		_ok("focus survives a reroll", "index %d" % _screen.focused_index())
	else:
		_no("focus after reroll", "focus lost when the offers were rebuilt")

	# Exiting hands control back exactly once.
	# An Array, not an int: GDScript lambdas capture locals by value, so a
	# captured counter increments a copy and always reads zero afterwards.
	var exits: Array = []
	_screen.closed.connect(func() -> void: exits.append(1))
	_screen.close()
	if exits.size() == 1 and not _screen.visible:
		_ok("exiting returns control cleanly", "one close signal, screen hidden")
	else:
		_no("exit", "%d close signals, visible=%s" % [exits.size(), _screen.visible])


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 9:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
