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
## Warm-coloured effects that are not telegraphs — burning hazards, the plume
## after a slam has already landed. They own the hostile side of the palette, but
## they are not the thing the player has to dodge, so they still sit *below* the
## telegraph layer. "Red telegraphs remain visible beneath all effects" means all
## of them, not only the violet ones.
const HOSTILE_EFFECT := 20
## Hostile telegraphs sit above every effect on either side, by contract.
const HOSTILE_TELEGRAPH := 40
## Reserved for damage numbers and world-space UI.
const WORLD_UI := 60


## True when the friendly layer cannot occlude the hostile telegraph layer.
static func friendly_stays_below_hostile() -> bool:
	return FRIENDLY_EFFECT < HOSTILE_TELEGRAPH


## True when nothing in the effect layer, either side of the palette, can occlude
## a telegraph. This is the stronger statement and the one the guide actually
## makes; `friendly_stays_below_hostile` is the half of it that predates the
## warm-coloured effects.
static func telegraphs_stay_on_top() -> bool:
	return maxi(FRIENDLY_EFFECT, HOSTILE_EFFECT) < HOSTILE_TELEGRAPH
