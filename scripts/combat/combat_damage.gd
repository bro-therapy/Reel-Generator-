class_name CombatDamage
extends RefCounted

## One place that applies damage, so every attacker passes an origin the same way.
##
## Directional defences need to know where a hit came from — the Bellguard's
## shield halves frontal damage only. Not every damage receiver cares, and test
## doubles may take only an amount, so this adapts to the receiver's signature
## rather than forcing every target to grow a parameter it ignores.
static func apply(target: Object, amount: int, from_position: Variant = null) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("take_damage"):
		return false

	var method: Callable = Callable(target, "take_damage")
	if method.get_argument_count() >= 2:
		target.call("take_damage", amount, from_position)
	else:
		target.call("take_damage", amount)
	return true
