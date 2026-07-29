extends SceneTree

## Renders a scene off-screen and writes a PNG, so the look of the game can be
## checked without a human at a monitor.
##
##   ./tools/screenshot.sh scenes/tests/species_field.tscn build/shots/species.png 120
##
## Args, after `--`: <scene> <output png> [warmup frames] [more frames...]
##
## Passing several frame counts captures the same run at several moments, which
## is how you catch an animation or a telegraph rather than a static pose. The
## output gets `_<frame>` appended for the second and later captures.
##
## This needs a real (if virtual) display — see tools/screenshot.sh, which wraps
## it in Xvfb with software GL. It will not work under --headless, whose dummy
## renderer draws nothing.

var _scene_path: String = ""
var _out_path: String = ""
var _marks: Array[int] = []
var _frame := 0
var _taken := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: capture_scene.gd -- <scene.tscn> <out.png> [frame ...]")
		quit(1)
		return

	_scene_path = args[0]
	_out_path = args[1]
	for i in range(2, args.size()):
		_marks.append(int(args[i]))
	if _marks.is_empty():
		_marks.append(90)
	_marks.sort()

	var packed := load(_scene_path) as PackedScene
	if packed == null:
		print("FAILED: could not load %s" % _scene_path)
		quit(1)
		return

	var node := packed.instantiate()
	if node == null:
		print("FAILED: could not instantiate %s" % _scene_path)
		quit(1)
		return
	get_root().add_child(node)
	print("loaded %s" % _scene_path)


func _process(_delta: float) -> bool:
	_frame += 1
	if _taken >= _marks.size():
		return true
	if _frame < _marks[_taken]:
		return false

	var image := get_root().get_texture().get_image()
	if image == null:
		print("FAILED: no viewport image at frame %d" % _frame)
		quit(1)
		return true

	var path := _out_path
	if _taken > 0:
		path = "%s_%d.%s" % [_out_path.get_basename(), _frame, _out_path.get_extension()]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	if err != OK:
		print("FAILED: could not write %s (err %d)" % [path, err])
		quit(1)
		return true

	print("frame %-4d -> %s  (%dx%d)" % [_frame, path, image.get_width(), image.get_height()])
	_taken += 1
	return _taken >= _marks.size()


func _finalize() -> void:
	if _taken > 0:
		print("captured %d frame(s)" % _taken)
