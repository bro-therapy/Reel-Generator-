extends SceneTree

## Builds SpriteFrames for the combat VFX atlas rows.
##
##   godot --headless --path . --script scripts/tools/build_vfx_spriteframes.gd
##
## Grid and row order come from docs/ASSET_MANIFEST.json (8 columns, 4 rows,
## 222x222 cells). Do not hand-edit the generated .tres.

const FRAME_DIR := "res://assets/vfx/vfx_frames"
const OUT := "res://data/vfx/combat_vfx_frames.tres"
const ROWS := ["friendly_a", "friendly_b", "hostile", "pickup_status"]
const COLS := 8
const FPS := 16.0


func _initialize() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var missing: Array[String] = []

	for row in ROWS.size():
		var name: String = ROWS[row]
		frames.add_animation(name)
		frames.set_animation_loop(name, false)
		frames.set_animation_speed(name, FPS)
		for col in COLS:
			var path := "%s/%02d_%s__%02d_fx_%02d.png" % [FRAME_DIR, row, name, col, col + 1]
			if not ResourceLoader.exists(path):
				missing.append(path.get_file())
				continue
			var tex := load(path) as Texture2D
			if tex != null:
				frames.add_frame(name, tex)

	if not missing.is_empty():
		push_error("Missing %d VFX frames: %s" % [missing.size(), ", ".join(missing)])
		print("FAILED: %d missing" % missing.size())
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute("res://data/vfx")
	var err := ResourceSaver.save(frames, OUT)
	if err != OK:
		print("FAILED: save %s (err %d)" % [OUT, err])
		quit(1)
		return
	print("Built %s" % OUT)
	for name in ROWS:
		print("  %-16s %d frames" % [name, frames.get_frame_count(name)])
	quit(0)
