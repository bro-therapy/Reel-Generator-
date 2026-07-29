extends Control

## Phase 7 visual sandbox: a real three-card offer, built by RewardSystem from a
## real RunState.
##
##   godot --path . scenes/tests/reward_demo.tscn
##   ./tools/screenshot.sh scenes/tests/reward_demo.tscn build/shots/reward.png
##
## Left/Right moves the selection, Enter or the gamepad's accept button takes
## the card and rolls the next offer, so the no-mouse path can be exercised by
## hand as well as by phase7_acceptance.gd.

const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]
const STAFF := "res://data/weapons/conjurer_staff.tres"

var _state: RunState
var _system: RewardSystem
var _screen: RewardScreen
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var catalog: Array[SpiritData] = []
	for path in SPIRITS:
		var s := load(path) as SpiritData
		if s != null:
			catalog.append(s)

	_state = RunState.new(load(STAFF) as FocusWeaponData)
	# Start on the second reward so the summon pity floor is visible straight
	# away rather than needing a click first.
	_state.rewards_taken = 1
	_system = RewardSystem.new(catalog, 20260729)

	_screen = RewardScreen.new()
	add_child(_screen)
	_screen.card_chosen.connect(_on_chosen)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -96.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	add_child(_status)

	_next_offer()


func _next_offer() -> void:
	_screen.present(_system.build_offer(_state), _state)
	_refresh_status()


func _on_chosen(card: RewardCard, _index: int) -> void:
	_system.take(_state, card)
	# The Spirit Well sits around the third reward in the guide's cadence, and
	# flipping it here shows the Echo pity floor without playing a whole run.
	if _state.rewards_taken >= 3:
		_state.reached_spirit_well = true
	_next_offer()


func _refresh_status() -> void:
	var team: Array[String] = []
	for b in _state.bonds:
		if b == null:
			team.append("[empty]")
		else:
			var tier := _state.tier_of(b.id)
			team.append("%s (%s)" % [b.form(tier).display_name, b.form(tier).tier_name()])
	_status.text = "Reward %d   ·   Bonds: %s   ·   Relics: %d   ·   Currency: %d" % [
		_state.rewards_taken + 1, "  |  ".join(team), _state.relics.size(), _state.currency,
	]
