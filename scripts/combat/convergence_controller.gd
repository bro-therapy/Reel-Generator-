class_name ConvergenceController
extends Node

## The Convergence meter. Guide §8 (`overdrive` in balance) and brief Phase 12.
##
##   - meter of 100
##   - four seconds active
##   - +15% move speed, +30% attack speed
##   - dash cooldown multiplier 0.65
##   - one signature attack per bonded summon
##
## Brief Phase 12 also requires that red telegraphs stay visible through a full
## Convergence. That is not enforced here — it is enforced by RenderPriority,
## which pins friendly effects to -20 and hostile telegraphs to +40 — but the
## signature effects this controller fires are the loudest friendly VFX in the
## game, so it is the thing most likely to break the rule.

signal charged(meter: float)
signal triggered(seconds: float)
signal signature_fired(spirit_id: StringName)
signal ended()

var meter := 0.0
var meter_max := 100.0
var active := false
var time_left := 0.0

var _duration := 4.0
var _move_multiplier := 1.15
var _attack_multiplier := 1.3
var _dash_multiplier := 0.65
var _gain_per_kill := 2.0
var _gain_per_near_miss := 3.0
var _gain_per_dash_dodge := 5.0


func _ready() -> void:
	var o := Balance.overdrive()
	meter_max = float(o.get("meter_max", 100))
	_duration = float(o.get("duration_seconds", 4.0))
	_move_multiplier = float(o.get("move_speed_multiplier", 1.15))
	_attack_multiplier = float(o.get("attack_speed_multiplier", 1.3))
	_dash_multiplier = float(o.get("dash_cooldown_multiplier", 0.65))
	_gain_per_kill = float(o.get("gain_per_kill", 2))
	_gain_per_near_miss = float(o.get("gain_per_near_miss", 3))
	_gain_per_dash_dodge = float(o.get("gain_per_dash_dodge", 5))


func duration() -> float:
	return _duration


func move_multiplier() -> float:
	return _move_multiplier if active else 1.0


func attack_multiplier() -> float:
	return _attack_multiplier if active else 1.0


func dash_cooldown_multiplier() -> float:
	return _dash_multiplier if active else 1.0


func is_full() -> bool:
	return meter >= meter_max


# ---------------------------------------------------------------- charging

func add(amount: float) -> float:
	if active:
		# Charge earned during a Convergence is dropped rather than banked, so
		# the meter cannot be full again the instant it ends.
		return meter
	meter = clampf(meter + amount, 0.0, meter_max)
	charged.emit(meter)
	return meter


func on_kill() -> float:
	return add(_gain_per_kill)


func on_near_miss() -> float:
	return add(_gain_per_near_miss)


func on_dash_dodge() -> float:
	return add(_gain_per_dash_dodge)


# ---------------------------------------------------------------- trigger

## Spends a full meter. Returns false when the meter is short or a Convergence
## is already running — brief Phase 12: "cannot be retriggered while active".
func trigger(bonded_ids: Array = []) -> bool:
	if active or not is_full():
		return false

	active = true
	time_left = _duration
	meter = 0.0
	charged.emit(meter)
	triggered.emit(_duration)

	# Guide §8: one signature attack per bonded summon, so a three-summon team
	# fires three and a one-summon team fires one.
	for id in bonded_ids:
		signature_fired.emit(id)
	return true


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	if time_left <= 0.0:
		active = false
		time_left = 0.0
		ended.emit()


## Draw priority for the signature effects. Friendly, so it must sit below a
## hostile telegraph however bright it gets.
func effect_render_priority() -> int:
	return RenderPriority.FRIENDLY_EFFECT
