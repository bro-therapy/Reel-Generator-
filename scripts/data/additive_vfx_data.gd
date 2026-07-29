class_name AdditiveVfxData
extends Resource

## One realistic effect sheet: what it looks like, how it animates, and which
## side of the colour split it belongs to.
##
## Generated from docs/VFX_SOURCES.json by tools/vfx_from_video.py, then written
## out by scripts/tools/build_additive_vfx.gd. Do not hand-edit the .tres files —
## the grid and frame count have to match the texture that was actually built,
## and there is no way for the game to notice if they drift apart.

## Not named `Orientation`: that identifier is already taken by an engine type in
## GDScript 4.3, and `var orientation: Orientation` fails to parse with a
## confusing "cannot assign Orientation as Orientation". The same declaration
## under any other name compiles. Do not rename it back.
## Values are the `facing` uniform in additive_vfx.gdshader — keep them in step.
enum Facing {
	## Turns about the vertical axis only, so the effect stands up in the world.
	## Fire and beams: they belong to the room, not to the screen.
	UPRIGHT = 0,
	## Aligns to the view plane, always flat-on at full size. For anything that
	## reads as a disc facing the player — a radial burst, an impact flash. An
	## upright quad would present these foreshortened and leaning.
	VIEW = 1,
	## No billboarding; the node keeps its own rotation. Lies flat in XZ, which is
	## what an effect shot looking straight down needs.
	GROUND = 2,
}

enum Palette {
	## Violet / indigo / blue-white. Belongs to the player.
	FRIENDLY,
	## Red / orange / warm-white. Belongs to whatever is trying to kill them.
	HOSTILE,
}

@export var id: StringName = &""
@export var texture: Texture2D
@export var cols: int = 4
@export var rows: int = 6
@export var frame_count: int = 24
@export var fps: float = 24.0
@export var loop: bool = false

## Width divided by height of a single cell. The quad is built from this so a
## cropped effect is not stretched back to square.
@export var aspect: float = 1.0

## World height of the effect in metres. The hero is 1.8, for scale.
@export var world_height: float = 2.0

@export var facing: Facing = Facing.UPRIGHT
@export var palette: Palette = Palette.HOSTILE

## Multiplies the light added to the frame. Above 1.0 blows the core out to white,
## which is what sells a hot effect.
@export var energy: float = 1.0

## Fraction of the animation spent fading out, so a one-shot does not vanish on a
## hard cut. Loops ignore it — they are stopped explicitly.
@export_range(0.0, 1.0) var fade_out_fraction: float = 0.25


func duration() -> float:
	return float(frame_count) / maxf(fps, 0.001)


## Draw priority, taken from the shared contract rather than chosen per effect.
## This is what keeps a bright violet Convergence burst underneath a red
## telegraph — see RenderPriority and master guide §2.
##
## Note that a hostile effect resolves to HOSTILE_EFFECT, not HOSTILE_TELEGRAPH.
## Being warm-coloured buys it the top of the effect stack, not the right to
## cover the thing the player is supposed to dodge.
func render_priority() -> int:
	return RenderPriority.HOSTILE_EFFECT if palette == Palette.HOSTILE \
		else RenderPriority.FRIENDLY_EFFECT


func is_hostile() -> bool:
	return palette == Palette.HOSTILE
