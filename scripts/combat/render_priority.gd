class_name RenderPriority
extends RefCounted

## Draw-order contract for combat visuals.
##
## Master guide §2 and §11: "Red telegraphs remain visible beneath all
## Convergence effects." Friendly violet must never occlude hostile red. Putting
## the numbers here — rather than scattering magic values across effect scenes —
## makes the rule assertable, which is what the Phase 4 acceptance check does.
##
## Higher priority draws later, i.e. on top.

const ENVIRONMENT_DECAL := -40
## Every friendly effect: staff impacts, summon signatures, Convergence.
const FRIENDLY_EFFECT := -20
const ACTOR := 0
const PICKUP := 10
## Hostile telegraphs sit above all friendly effects, by contract.
const HOSTILE_TELEGRAPH := 40
## Reserved for damage numbers and world-space UI.
const WORLD_UI := 60


## True when the friendly layer cannot occlude the hostile telegraph layer.
static func friendly_stays_below_hostile() -> bool:
	return FRIENDLY_EFFECT < HOSTILE_TELEGRAPH
