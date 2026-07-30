extends SceneTree

## Acceptance checks for the realistic additive effects.
##
##   godot --headless --path . --script scripts/tests/vfx_acceptance.gd
##
## What these can and cannot prove is worth being blunt about. They cannot say
## whether an effect looks good — that is what scenes/tests/vfx_showcase.tscn and
## a render are for, and looking at one is how three separate defects in this
## feature were found. What they can prove is everything that is a contract:
##
##   - colour ownership, measured on the shipped pixels, not on the prompt
##   - a friendly effect can never draw over a red telegraph
##   - the sheet metadata matches the texture it claims to describe
##   - the pool does not grow without bound and does not leak
##   - a one-shot ends, and a loop does not
##
## The colour check reads the texture rather than trusting docs/VFX_SOURCES.json,
## because the .json is an input to the build and the .png is what ships. Checking
## the input would pass happily against a texture nobody rebuilt.

const EFFECT_DIR := "res://data/vfx/realtime"
const META := "res://docs/generated/vfx_sheets.json"
const STEP := 1.0 / 60.0

## Hue bands in degrees, matching tools/vfx_from_video.py.
const WARM := [[0.0, 60.0], [330.0, 360.0]]
const COOL := [[200.0, 300.0]]
const VALUE_FLOOR := 0.15
const SAT_FLOOR := 0.25
## Same ceiling the build tool enforces. Measured wrong-side fractions on the
## shipped four are 0.000%, so this has two orders of magnitude of headroom.
const MAX_WRONG_FRACTION := 0.005

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n=== REALISTIC VFX ACCEPTANCE ===\n")
	var ids := _load_ids()
	if ids.is_empty():
		_no("effect resources", "nothing in %s — run build_additive_vfx.gd" % EFFECT_DIR)
		_summary()
		return

	# assets/ is gitignored while LFS upload is blocked from the build box, so a
	# fresh checkout has the resources and not the textures they point at. That is
	# a missing-asset state, not a broken build, and it is reported as such —
	# failing here would train people to ignore a red suite. A checkout with
	# *some* textures present is a real inconsistency and still fails.
	var with_texture := 0
	for id in ids:
		var d := _data(id)
		if d != null and d.texture != null:
			with_texture += 1
	if with_texture == 0:
		print("  SKIP  no effect textures in this checkout")
		print("        assets/ is gitignored — see docs/VFX_SOURCES.json to rebuild:")
		print("        ./tools/vfx_from_video.py --sources <dir with the four clips>")
		print("\nREALISTIC VFX:  skipped, %d resources with no textures\n" % ids.size())
		quit(0)
		return

	_check_metadata_matches_textures(ids)
	_check_colour_ownership(ids)
	_check_draw_order(ids)
	_check_playback(ids)
	_check_pool()
	_check_quality(ids)
	_summary()


func _load_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(EFFECT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


func _data(id: String) -> AdditiveVfxData:
	return load("%s/%s.tres" % [EFFECT_DIR, id]) as AdditiveVfxData


# ------------------------------------------------------------------ metadata

## The grid is used to index into the texture. If the two ever disagree, every
## frame samples the wrong rectangle — and it still renders, so nothing else
## would notice.
func _check_metadata_matches_textures(ids: Array) -> void:
	var bad: Array[String] = []
	for id in ids:
		var d := _data(id)
		if d == null or d.texture == null:
			bad.append("%s: no texture" % id)
			continue
		var w := d.texture.get_width()
		var h := d.texture.get_height()
		if w % d.cols != 0 or h % d.rows != 0:
			bad.append("%s: %dx%d does not divide into %dx%d cells" % [id, w, h, d.cols, d.rows])
			continue
		if d.frame_count > d.cols * d.rows:
			bad.append("%s: %d frames in a %dx%d grid" % [id, d.frame_count, d.cols, d.rows])
			continue
		# The cell aspect the quad is built from has to be the cell's real shape,
		# or a cropped effect gets stretched back towards square.
		var real := float(w / d.cols) / float(h / d.rows)
		if absf(real - d.aspect) > 0.01:
			bad.append("%s: aspect %.3f, cells are %.3f" % [id, d.aspect, real])

	if bad.is_empty():
		_ok("every sheet matches the grid it declares", "%d effects" % ids.size())
	else:
		_no("sheet metadata", ", ".join(bad))


# ------------------------------------------------------------ colour ownership

## Master guide §2. Violet and blue-white belong to the player, red and orange to
## whatever is trying to kill them. The player reads the split before they read
## anything else, so it is measured on the shipped pixels every run.
func _check_colour_ownership(ids: Array) -> void:
	var offenders: Array[String] = []
	var report: Array[String] = []

	for id in ids:
		var d := _data(id)
		if d == null or d.texture == null:
			continue
		var img := d.texture.get_image()
		if img == null:
			offenders.append("%s: texture has no image" % id)
			continue

		var own_bands: Array = WARM if d.is_hostile() else COOL
		var wrong_bands: Array = COOL if d.is_hostile() else WARM
		var chromatic := 0
		var wrong := 0
		var own := 0

		# Every fourth pixel on each axis. A 1024x1536 sheet is 1.5M pixels and
		# the statistic is uniform across it; sampling keeps the check quick
		# enough to run with the rest of the suite.
		var x := 0
		while x < img.get_width():
			var y := 0
			while y < img.get_height():
				var c := img.get_pixel(x, y)
				y += 4
				var v: float = maxf(c.r, maxf(c.g, c.b))
				var mn: float = minf(c.r, minf(c.g, c.b))
				if v <= VALUE_FLOOR:
					continue
				var s := (v - mn) / maxf(v, 0.0001)
				if s <= SAT_FLOOR:
					continue
				chromatic += 1
				var hue := c.h * 360.0
				if _in_bands(hue, own_bands):
					own += 1
				elif _in_bands(hue, wrong_bands):
					wrong += 1
			x += 4

		if chromatic == 0:
			offenders.append("%s: no chromatic pixels at all" % id)
			continue
		var wrong_fraction := float(wrong) / float(chromatic)
		report.append("%s %s %.3f%% wrong" % [
			id, "hostile" if d.is_hostile() else "friendly", wrong_fraction * 100.0])
		if wrong_fraction > MAX_WRONG_FRACTION:
			offenders.append("%s: %.3f%% of chromatic pixels are the wrong side" % [
				id, wrong_fraction * 100.0])
		elif float(own) / float(chromatic) < 0.9:
			offenders.append("%s: only %.1f%% of chromatic pixels are on its own side" % [
				id, float(own) / float(chromatic) * 100.0])

	if offenders.is_empty():
		_ok("every effect stays on its own side of the palette", ", ".join(report))
	else:
		_no("colour ownership", ", ".join(offenders))


func _in_bands(hue: float, bands: Array) -> bool:
	for band in bands:
		if hue >= float((band as Array)[0]) and hue <= float((band as Array)[1]):
			return true
	return false


# ---------------------------------------------------------------- draw order

func _check_draw_order(ids: Array) -> void:
	var offenders: Array[String] = []
	for id in ids:
		var d := _data(id)
		if d == null:
			continue
		if d.render_priority() >= RenderPriority.HOSTILE_TELEGRAPH:
			offenders.append("%s at %d" % [id, d.render_priority()])

	if offenders.is_empty():
		_ok("no effect can draw over a red telegraph",
			"telegraph at %d, effects at %d and %d" % [
				RenderPriority.HOSTILE_TELEGRAPH,
				RenderPriority.FRIENDLY_EFFECT,
				RenderPriority.HOSTILE_EFFECT])
	else:
		_no("effect draw order", ", ".join(offenders))

	# The contract itself, not just today's resources. A warm effect gets the top
	# of the effect stack; it does not get to cover the thing being dodged.
	if RenderPriority.telegraphs_stay_on_top():
		_ok("the priority contract keeps telegraphs on top",
			"friendly %d < hostile-effect %d < telegraph %d" % [
				RenderPriority.FRIENDLY_EFFECT,
				RenderPriority.HOSTILE_EFFECT,
				RenderPriority.HOSTILE_TELEGRAPH])
	else:
		_no("priority contract", "hostile effects at %d vs telegraph %d" % [
			RenderPriority.HOSTILE_EFFECT, RenderPriority.HOSTILE_TELEGRAPH])

	# The material is what the renderer actually obeys; the resource is only what
	# the material was built from. Assert on the built node.
	var built_wrong: Array[String] = []
	for id in ids:
		var d := _data(id)
		var fx := AdditiveVfx.new()
		fx.configure(d)
		if fx.render_priority_value() != d.render_priority():
			built_wrong.append("%s: material %d, data %d" % [
				id, fx.render_priority_value(), d.render_priority()])
		fx.free()
	if built_wrong.is_empty():
		_ok("the built material carries the priority its data asks for")
	else:
		_no("material priority", ", ".join(built_wrong))


# ----------------------------------------------------------------- playback

func _check_playback(ids: Array) -> void:
	var problems: Array[String] = []

	for id in ids:
		var d := _data(id)
		var fx := AdditiveVfx.new()
		fx.configure(d)
		fx.play(Vector3.ZERO)
		# The node's own _process is not running here, so nothing advances except
		# the explicit ticks below — which is the point of tick() being public.
		var elapsed := 0.0
		var limit := d.duration() * 3.0 + 1.0
		var seen_last := false
		while elapsed < limit and fx.is_playing():
			fx.tick(STEP)
			elapsed += STEP
			if fx.current_frame() == d.frame_count - 1:
				seen_last = true

		if d.loop:
			if fx.is_playing():
				_okq("%s loops past its own duration" % id)
			else:
				problems.append("%s: a looping effect stopped on its own" % id)
			# A loop must reach its last frame rather than stalling early.
			if not seen_last:
				problems.append("%s: never reached frame %d" % [id, d.frame_count - 1])
			fx.stop()
			if fx.is_playing():
				problems.append("%s: stop() left it playing" % id)
		else:
			if fx.is_playing():
				problems.append("%s: a one-shot never finished (%.2fs limit)" % [id, limit])
			elif absf(elapsed - d.duration()) > 0.05:
				problems.append("%s: ran %.2fs, declares %.2fs" % [id, elapsed, d.duration()])
			else:
				_okq("%s ends within a frame of its declared %.2fs" % [id, d.duration()])
			if not seen_last:
				problems.append("%s: finished without showing its last frame" % id)

		# Every frame index must be inside the grid — an out-of-range index does
		# not error, it silently samples a neighbouring cell.
		if fx.current_frame() >= d.cols * d.rows:
			problems.append("%s: frame %d outside a %dx%d grid" % [
				id, fx.current_frame(), d.cols, d.rows])
		fx.free()

	if problems.is_empty():
		_ok("loops loop and one-shots end", "%d effects driven to completion" % ids.size())
	else:
		_no("playback", ", ".join(problems))

	_check_fade(ids)


## A one-shot ramps its light down over its tail rather than cutting to nothing.
func _check_fade(ids: Array) -> void:
	var problems: Array[String] = []
	for id in ids:
		var d := _data(id)
		if d.loop or d.fade_out_fraction <= 0.0:
			continue
		var fx := AdditiveVfx.new()
		fx.configure(d)
		fx.play(Vector3.ZERO)

		var start := fx.fade_value()
		# Step to just before the end and confirm the light has come down.
		var elapsed := 0.0
		var target := d.duration() - STEP * 2.0
		while elapsed < target:
			fx.tick(STEP)
			elapsed += STEP
		var ending := fx.fade_value()

		if not is_equal_approx(start, 1.0):
			problems.append("%s: starts at %.2f rather than full" % [id, start])
		if ending >= 0.2:
			problems.append("%s: still at %.2f light on its last frame" % [id, ending])
		fx.free()

	if problems.is_empty():
		_ok("one-shots fade out instead of cutting")
	else:
		_no("fade out", ", ".join(problems))


# --------------------------------------------------------------------- pool

func _check_pool() -> void:
	var pool := AdditiveVfxPool.new()
	root.add_child(pool)
	var loaded := pool.load_effects()
	if loaded <= 0:
		_no("pool", "loaded no effects")
		pool.queue_free()
		return
	_check_tint_ownership(pool)

	var id: StringName = pool.effect_ids()[0]
	var one_shot: StringName = &""
	for candidate in pool.effect_ids():
		if not pool.data_for(candidate).loop:
			one_shot = candidate
			break

	# Ceiling. The pool drops rather than queues, so a burst cannot cost frames.
	for _i in pool.max_live_per_effect + 6:
		pool.play(id, Vector3.ZERO)
	if pool.live_count(id) <= pool.max_live_per_effect:
		_ok("the pool holds its ceiling under a burst", "%d live, %d dropped, ceiling %d" % [
			pool.live_count(id), pool.dropped_count(), pool.max_live_per_effect])
	else:
		_no("pool ceiling", "%d live against a ceiling of %d" % [
			pool.live_count(id), pool.max_live_per_effect])

	# Reuse. Node count must not grow across repeated bursts — this is the Phase
	# 15 "no increasing node count after repeated room clears" criterion, for the
	# one system that spawns per hit.
	pool.stop_all()
	var nodes_after_first := pool.get_child_count()
	for _round in 12:
		for _i in pool.max_live_per_effect:
			pool.play(id, Vector3.ZERO)
		pool.stop_all()
	var nodes_after_many := pool.get_child_count()

	if nodes_after_many == nodes_after_first:
		_ok("twelve more bursts allocate no further nodes", "%d nodes, %d plays" % [
			nodes_after_many, pool.started_count()])
	else:
		_no("pool reuse", "%d nodes after one burst, %d after thirteen" % [
			nodes_after_first, nodes_after_many])

	if pool.live_count() == 0:
		_ok("stop_all leaves nothing running", "%d pooled and idle" % pool.pooled_count())
	else:
		_no("stop_all", "%d still live" % pool.live_count())

	# A one-shot returns itself to the pool when it ends, without stop_all being
	# called. If it does not, a room that runs long leaks every effect it fired.
	if one_shot != &"":
		var d := pool.data_for(one_shot)
		var fx := pool.play(one_shot, Vector3.ZERO)
		if fx == null:
			_no("self-return", "pool refused to start %s" % one_shot)
		else:
			var elapsed := 0.0
			while elapsed < d.duration() + 0.2 and fx.is_playing():
				fx.tick(STEP)
				elapsed += STEP
			if pool.live_count(one_shot) == 0:
				_okq("%s returned itself to the pool when it ended" % one_shot)
				_ok("a finished one-shot frees its slot without help")
			else:
				_no("self-return", "%s still counted live after finishing" % one_shot)

	# An unknown id must not crash or silently play something else.
	var missing := pool.play(&"no_such_effect", Vector3.ZERO)
	if missing == null:
		_ok("an unknown effect id returns null instead of guessing")
	else:
		_no("unknown id", "got %s" % missing)

	pool.queue_free()


# ------------------------------------------------------------------- quality

## A settings screen that changes a dictionary and no pixels is worse than none,
## because it looks like it worked. These assert on the objects the renderer
## reads, never on the settings dictionary — reading the dictionary back would
## pass with the whole controller deleted.
func _check_quality(ids: Array) -> void:
	var scene := Node3D.new()
	root.add_child(scene)

	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	scene.add_child(light)

	var particles := GPUParticles3D.new()
	particles.emitting = true
	scene.add_child(particles)

	var prop := MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	scene.add_child(prop)

	var fx := AdditiveVfx.new()
	fx.configure(_data(ids[0]))
	scene.add_child(fx)

	var settings := _FakeSettings.new()
	var q := QualityController.new()
	q.settings_source = settings
	root.add_child(q)

	# Everything on: nothing may be switched off behind the player's back.
	var counts := q.apply_to(scene)
	if light.shadow_enabled and particles.visible and fx.energy_scale == 1.0:
		_ok("full quality leaves shadows, particles and effects alone",
			"%d lights, %d particle systems, %d effects, %d casters" % [
				counts["lights"], counts["particles"], counts["effects"], counts["casters"]])
	else:
		_no("full quality", "shadows %s, particles %s, energy %.2f" % [
			light.shadow_enabled, particles.visible, fx.energy_scale])

	# Shadows off must reach both the lights that cast them and the meshes that
	# feed them. Turning off only the light leaves every mesh still submitted to a
	# shadow pass that no longer exists.
	settings.values["quality_shadows"] = false
	q.apply_to(scene)
	if not light.shadow_enabled and prop.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_ok("shadows off reaches both the light and the casters")
	else:
		_no("shadow toggle", "light %s, prop cast_shadow %d" % [
			light.shadow_enabled, prop.cast_shadow])

	settings.values["quality_particles"] = false
	q.apply_to(scene)
	if not particles.emitting and not particles.visible:
		_ok("particles off stops emission, not just visibility",
			"a hidden emitter still simulates, which is the cost being removed")
	else:
		_no("particle toggle", "emitting %s, visible %s" % [particles.emitting, particles.visible])

	# reduced_flashes is the setting these effects most need to obey — additive
	# light blowing out to white is exactly what it is asking not to see.
	settings.values["reduced_flashes"] = true
	q.apply_to(scene)
	var dimmed := fx.energy_scale
	if dimmed <= QualityController.REDUCED_FLASH_ENERGY and dimmed > 0.0:
		_ok("reduced flashes dims additive effects without removing them",
			"energy scale %.2f" % dimmed)
	else:
		_no("reduced flashes", "energy scale %.2f" % dimmed)

	# The shader has to receive it, not just the node. The material is what the
	# renderer obeys.
	var mat := fx.shader_material()
	var expected: float = fx.data.energy * dimmed
	var actual := float(mat.get_shader_parameter("energy"))
	if is_equal_approx(actual, expected):
		_ok("the dimmed energy reaches the shader", "%.3f on the material" % actual)
	else:
		_no("shader energy", "material has %.3f, expected %.3f" % [actual, expected])

	# Restoring the setting must restore the effect. A one-way dimmer would leave
	# the game dark until a restart.
	settings.values["reduced_flashes"] = false
	settings.values["effect_opacity"] = 1.0
	q.apply_to(scene)
	if is_equal_approx(fx.energy_scale, 1.0):
		_ok("turning reduced flashes back off restores full energy")
	else:
		_no("restore", "energy scale stuck at %.2f" % fx.energy_scale)

	q.queue_free()
	scene.queue_free()


## Stands in for the GameSettings autoload, which does not exist under `--script`.
class _FakeSettings extends Object:
	signal settings_changed(key: String, value: Variant)

	var values := {
		"quality_shadows": true,
		"quality_particles": true,
		"quality_volumetrics": true,
		"effect_opacity": 1.0,
		"reduced_flashes": false,
	}

	func get_setting(key: String) -> Variant:
		return values.get(key)


# ------------------------------------------------------------------ reporting

func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


## A note under the current check rather than a check of its own, so the count
## reflects properties asserted and not lines printed.
func _okq(label: String) -> void:
	print("        - %s" % label)


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])



## Colour ownership, asserted on the RESOURCE rather than the source sheet.
##
## The four authored sheets were validated at build time by hue histogram
## (tools/vfx_from_video.py refuses to write a wrong-side sheet). The CC0 pixel
## sheets are deliberately near-white and take their side from the resource's
## tint instead — so the guarantee has to be re-checked here, at the layer that
## actually decides what the player sees.
func _check_tint_ownership(pool: AdditiveVfxPool) -> void:
	var wrong: Array[String] = []
	for id in pool.effect_ids():
		var d: AdditiveVfxData = pool.data_for(id)
		if d == null:
			continue
		var t := d.tint
		var warm := t.r > t.b + 0.12
		var cool := t.b > t.r + 0.12
		if d.palette == AdditiveVfxData.Palette.FRIENDLY and warm:
			wrong.append("%s is FRIENDLY but tinted warm %s" % [id, t])
		elif d.palette == AdditiveVfxData.Palette.HOSTILE and cool:
			wrong.append("%s is HOSTILE but tinted cool %s" % [id, t])
		# A cell overrun renders garbage from the next row.
		if d.cell_for(d.frame_count - 1) >= d.cols * d.rows:
			wrong.append("%s plays past its last cell (%d of %d)"
				% [id, d.cell_for(d.frame_count - 1), d.cols * d.rows])
	if wrong.is_empty():
		_ok("every effect's tint matches its declared side",
			"%d effects checked" % pool.effect_ids().size())
	else:
		_no("colour ownership", "; ".join(wrong))


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("REALISTIC VFX:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
