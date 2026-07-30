extends Node3D

## Colour ownership, measured off the RENDERED FRAME.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" \
##     godot --display-driver x11 --rendering-driver opengl3 \
##       --path . scenes/tests/render_acceptance.tscn
##
## Every other suite asserts on data: this resource declares FRIENDLY, that
## resource's tint is cool, the pool loaded nine effects. All true, and all of it
## was true while the effects rendered pure white on screen.
##
## The gap: these sheets are CC0 pixel art that is 97% near-white by design, and
## additive blending multiplies. At the energy the authored sheets use (1.5) every
## channel saturated, so a violet friendly hit and a warm hostile hit were both
## just white light. The declared palette was right, the tint was right, the thing
## the player saw was wrong — and no data assertion can see that.
##
## So this suite renders two effects from the SAME white sheet over a near-black
## background and reads the viewport back. Dark background on purpose: additive
## light over the ward's bright sandstone floor washes out regardless, which is a
## separate readability question. What is under test here is that the tint reaches
## the screen at all.
##
## Needs a real renderer. `--headless` uses a dummy driver that hands back an
## empty viewport, so this suite is run under xvfb by tools/check_project.sh and
## reports SKIP rather than failing when no GPU is available.

const SETTLE_FRAMES := 6
## Frame the effects are sampled on. Early enough that the one-shots have not
## faded, late enough that they have actually started.
const SAMPLE_FRAME := 10

var _pass := 0
var _fail := 0
var _frames := 0
var _pool: AdditiveVfxPool


func _ready() -> void:
	print("\n=== RENDER ACCEPTANCE ===\n")

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.05, 0.06)
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 9.0)
	add_child(cam)
	cam.make_current()

	_pool = AdditiveVfxPool.new()
	add_child(_pool)
	_pool.load_effects()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == SETTLE_FRAMES:
		# One effect per side, both from 10_weaponhit.png — the whole point is
		# that identical art takes its side from the resource.
		_pool.play(&"pixel_hit_friendly", Vector3(-2.5, 0.0, 0.0), 1.0)
		_pool.play(&"pixel_hit_hostile", Vector3(2.5, 0.0, 0.0), 1.0)
		return
	if _frames != SETTLE_FRAMES + SAMPLE_FRAME:
		return

	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_width() == 0:
		print("SKIP: no renderable viewport (dummy driver — run under xvfb)")
		print("\n0 passed, 0 failed\n")
		get_tree().quit(0)
		return

	_check_side(image, "friendly", 0, image.get_width() / 2, true)
	_check_side(image, "hostile", image.get_width() / 2, image.get_width(), false)
	_check_not_washed_out(image)

	print("\n%d passed, %d failed\n" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


## Averages the lit pixels on one half of the frame and checks which way the hue
## leans. Averaging rather than sampling one pixel: a sprite-sheet frame has a
## bright core and dim edges, and one pixel could land on either.
func _check_side(image: Image, label: String, x0: int, x1: int, expect_cool: bool) -> void:
	var total := Vector3.ZERO
	var lit := 0
	for y in range(0, image.get_height(), 2):
		for x in range(x0, x1, 2):
			var c := image.get_pixel(x, y)
			if c.r + c.g + c.b > 0.25:
				total += Vector3(c.r, c.g, c.b)
				lit += 1
	if lit == 0:
		_no(label, "nothing was drawn on this half of the frame")
		return
	var mean := total / float(lit)
	var cool := mean.z > mean.x + 0.05
	var warm := mean.x > mean.z + 0.05

	if expect_cool and cool:
		_ok("%s effect renders cool on screen" % label,
			"mean RGB (%.2f, %.2f, %.2f) over %d lit px" % [mean.x, mean.y, mean.z, lit])
	elif not expect_cool and warm:
		_ok("%s effect renders warm on screen" % label,
			"mean RGB (%.2f, %.2f, %.2f) over %d lit px" % [mean.x, mean.y, mean.z, lit])
	else:
		_no("%s colour ownership" % label,
			"expected %s, rendered mean RGB (%.2f, %.2f, %.2f) — the tint is not "
			% ["cool" if expect_cool else "warm", mean.x, mean.y, mean.z]
			+ "reaching the screen (energy too high saturates every channel)")


## The specific failure this suite was written for: a tint so diluted by additive
## energy that the effect reads as white light.
##
## This check took THREE attempts, and the first two both passed the regression:
##
##   1. "count pixels with every channel > 0.93" — measured 0% at the saturating
##      energy, because the pale mean (0.88, 0.65, 0.93) rarely had all three hot.
##   2. "mean per-pixel saturation" — barely moved either, and the reason is
##      causal: the shader computes `colour = texel * tint * energy`, which scales
##      every channel by the SAME factor. Saturation is mathematically invariant
##      under that scaling. It cannot detect an energy change at all.
##
## What actually destroys the hue is CLIPPING. Once a channel is driven past 1.0
## it stops rising while the others catch up, and every colour converges on white.
## So the quantity to measure is the fraction of lit pixels whose strongest channel
## is pinned at the ceiling. With a 97%-white sheet, tint blue 1.0 and energy 1.6,
## blue clips almost everywhere; at energy 0.85 nothing can reach 1.0 at all.
const MAX_CLIPPED_FRACTION := 0.25

func _check_not_washed_out(image: Image) -> void:
	var clipped := 0
	var lit := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if c.r + c.g + c.b > 0.25:
				lit += 1
				if maxf(c.r, maxf(c.g, c.b)) >= 0.99:
					clipped += 1
	if lit == 0:
		_no("wash-out", "nothing drawn")
		return
	var fraction := float(clipped) / float(lit)
	if fraction <= MAX_CLIPPED_FRACTION:
		_ok("effects keep their hue instead of clipping to white",
			"%.0f%% of %d lit px at the channel ceiling" % [fraction * 100.0, lit])
	else:
		_no("wash-out", "%.0f%% of lit pixels have a channel pinned at 1.0 — the hue "
			% (fraction * 100.0)
			+ "converges on white; lower the effects' energy")


func _ok(what: String, detail: String = "") -> void:
	_pass += 1
	print("  ok   %s%s" % [what, "" if detail == "" else "  (%s)" % detail])


func _no(what: String, why: String) -> void:
	_fail += 1
	print("  FAIL %s: %s" % [what, why])
