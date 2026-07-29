extends SceneTree

## Renders the game at combat density and reports what actually costs frames.
##
##   ./tools/bench.sh 250
##
## Two kinds of number come out of this, and they are not equally trustworthy:
##
##   Frame time is measured on llvmpipe, a software rasteriser. It is 50-100x
##   slower than any real GPU, so the absolute figure means nothing. It is
##   reported only so a change can be compared against the previous run on the
##   same machine.
##
##   Draw calls, material changes and primitive counts are hardware-independent.
##   They are what decides whether a real GPU holds 60 FPS, and they are the
##   numbers worth optimising against here.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const CRAWLER := "res://data/enemies/rift_crawler.tres"
const EFFECT_DIR := "res://data/vfx/realtime"
const WARM_FRAMES := 30
const MEASURE_FRAMES := 90

var _density := 150
## Realistic additive effects to run alongside the enemies.
##
## Worth measuring separately from draw calls, because their cost is not draw
## calls. A shockwave is one quad and seven metres across; additive blending
## cannot early-z reject, so every one of those pixels is shaded and blended
## whatever is already behind it. Overdraw, not geometry, is what would take this
## feature under 60 FPS, and it is invisible in a draw-call count.
var _vfx_count := 0
var _world: Node3D
var _hero: Node3D
var _enemies: Array[EnemyBase] = []
var _pool: AdditiveVfxPool
var _vfx_ids: Array = []
var _frame := 0
var _times: Array[float] = []
var _last_usec := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_density = int(args[0])
	if args.size() >= 2:
		_vfx_count = int(args[1])

	_world = Node3D.new()
	root.add_child(_world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_energy = 1.0
	env.environment = e
	_world.add_child(env)

	_hero = Node3D.new()
	_world.add_child(_hero)

	var cam := Camera3D.new()
	cam.fov = 50.0
	# Same reason: look_at_from_position needs a global transform, so the angle
	# is set directly rather than derived.
	# Basis columns: the camera looks along -z, so z points back towards the
	# viewer. Getting this backwards renders an empty frame and reports zero
	# draw calls, which looks like a wonderful optimisation and is not one.
	cam.transform = Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, 0.794, -0.607),
		Vector3(0, 0.607, 0.794),
		Vector3(0, 26, 34),
	)
	_world.add_child(cam)
	cam.make_current()

	var packed := load(ENEMY_SCENE) as PackedScene
	var data := load(CRAWLER) as EnemyData
	for i in _density:
		var enemy := packed.instantiate() as EnemyBase
		enemy.data = data
		_world.add_child(enemy)
		# A rough disc, so most of them are on screen and actually drawn.
		#
		# `position`, not `global_position`: nodes added during _initialize() are
		# not marked inside_tree until the first frame, so the global setter
		# queries a transform that does not exist yet and logs an error per
		# enemy. The parent sits at the origin, so the two are equivalent here.
		var a := TAU * float(i) / float(_density)
		var r := 4.0 + 14.0 * (float(i % 7) / 7.0)
		enemy.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		enemy.target = _hero
		_enemies.append(enemy)

	if _vfx_count > 0:
		_pool = AdditiveVfxPool.new()
		# The ceiling exists to stop a burst costing frames; this benchmark is
		# measuring what that burst would cost, so it is lifted here and only here.
		_pool.max_live_per_effect = _vfx_count
		_world.add_child(_pool)
		_pool.load_effects()
		_vfx_ids = _pool.effect_ids()
		for i in _vfx_count:
			var id: StringName = _vfx_ids[i % _vfx_ids.size()]
			var a := TAU * float(i) / float(_vfx_count)
			var r := 3.0 + 9.0 * (float(i % 5) / 5.0)
			_pool.play(id, Vector3(cos(a) * r, 0.02, sin(a) * r))

	print("density %d, vfx %d" % [_density, _vfx_count])
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _frame > WARM_FRAMES:
		_times.append(float(now - _last_usec) / 1000.0)
	_last_usec = now

	# One-shots finish during the run and would quietly stop being measured, so
	# the field is kept full. Otherwise the last third of the sample measures an
	# empty screen and reports it as a cheap one.
	if _pool != null and _pool.live_count() < _vfx_count:
		for i in _vfx_count - _pool.live_count():
			var id: StringName = _vfx_ids[(_frame + i) % _vfx_ids.size()]
			var a := TAU * float(_frame + i) / float(_vfx_count)
			var r := 3.0 + 9.0 * (float(i % 5) / 5.0)
			_pool.play(id, Vector3(cos(a) * r, 0.02, sin(a) * r))

	if _frame < WARM_FRAMES + MEASURE_FRAMES:
		return false

	_report()
	return true


func _report() -> void:
	_times.sort()
	var median := _times[_times.size() / 2]
	var worst := _times[_times.size() - 1]
	var p95 := _times[int(float(_times.size()) * 0.95)]

	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	print("  frame ms   median %.1f   p95 %.1f   worst %.1f   (llvmpipe, relative only)" % [median, p95, worst])
	print("  draw calls %d" % int(draw_calls))
	print("  objects    %d" % int(objects))
	print("  primitives %d" % int(primitives))
	print("  nodes      %d   orphans %d" % [int(nodes), int(orphans)])
	print("  per enemy: %.2f draw calls, %.0f primitives" % [
		draw_calls / maxf(float(_density), 1.0),
		primitives / maxf(float(_density), 1.0),
	])
