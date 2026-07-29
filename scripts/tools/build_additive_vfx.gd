extends SceneTree

## Builds the AdditiveVfxData resources from the sheets the video pipeline made.
##
##   ./tools/vfx_from_video.py --sources <dir>
##   godot --headless --path . --script scripts/tools/build_additive_vfx.gd
##
## Grid, frame count, fps and aspect all come from docs/generated/vfx_sheets.json
## rather than being retyped here. They describe a texture that was built to
## those numbers, and a hand-typed copy that drifts would sample the wrong cells
## with nothing to catch it.
##
## The world sizes and energies below are the one part that is a judgement call,
## so they are stated in one place with their reasoning.

const META := "res://docs/generated/vfx_sheets.json"
const OUT_DIR := "res://data/vfx/realtime"

## Metres tall, and how hard the effect pushes light into the frame. The hero is
## 1.8 m for scale.
##
## Energy above 1.0 blows the core to white, which is what makes fire look hot
## rather than painted. The two hostile effects sit higher than the friendly ones
## on purpose: a red telegraph has to win the frame, and these are the things
## drawn on top of one.
const TUNING := {
	"fire": {"height": 2.4, "energy": 1.35, "fade": 0.0},
	"shockwave": {"height": 7.0, "energy": 1.5, "fade": 0.35},
	"beam": {"height": 4.5, "energy": 1.2, "fade": 0.0},
	"lightning": {"height": 4.0, "energy": 1.25, "fade": 0.3},
}


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(META)
	if text.is_empty():
		print("FAILED: cannot read %s - run tools/vfx_from_video.py first" % META)
		quit(1)
		return

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("FAILED: %s is not valid JSON" % META)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var effects: Array = (parsed as Dictionary).get("effects", [])
	var problems: Array[String] = []
	var built := 0

	for entry_v in effects:
		var e: Dictionary = entry_v
		var name := String(e.get("name", ""))
		var tex_path := String(e.get("texture", ""))

		if not ResourceLoader.exists(tex_path):
			problems.append("%s: texture missing at %s" % [name, tex_path])
			continue
		var tex := load(tex_path) as Texture2D
		if tex == null:
			problems.append("%s: %s did not load as a texture" % [name, tex_path])
			continue

		var cols := int(e.get("cols", 0))
		var rows := int(e.get("rows", 0))
		var count := int(e.get("frame_count", 0))
		var cell_w := int(e.get("cell_width", 0))
		var cell_h := int(e.get("cell_height", 0))

		# The metadata describes a texture built from it. If the file on disk has
		# a different size, one of the two is stale and every frame would sample
		# the wrong cell.
		if tex.get_width() != cols * cell_w or tex.get_height() != rows * cell_h:
			problems.append("%s: sheet is %dx%d but metadata says %dx%d" % [
				name, tex.get_width(), tex.get_height(), cols * cell_w, rows * cell_h])
			continue
		if count > cols * rows:
			problems.append("%s: %d frames will not fit a %dx%d grid" % [name, count, cols, rows])
			continue

		var d := AdditiveVfxData.new()
		d.id = StringName(name)
		d.texture = tex
		d.cols = cols
		d.rows = rows
		d.frame_count = count
		d.fps = float(e.get("fps", 24.0))
		d.loop = bool(e.get("loop", false))
		d.aspect = float(e.get("aspect", 1.0))
		match String(e.get("orientation", "upright")):
			"ground":
				d.facing = AdditiveVfxData.Facing.GROUND
			"view":
				d.facing = AdditiveVfxData.Facing.VIEW
			"upright":
				d.facing = AdditiveVfxData.Facing.UPRIGHT
			var other:
				problems.append("%s: unknown orientation '%s'" % [name, other])
				continue
		d.palette = AdditiveVfxData.Palette.HOSTILE \
			if String(e.get("palette", "hostile")) == "hostile" \
			else AdditiveVfxData.Palette.FRIENDLY

		var tune: Dictionary = TUNING.get(name, {})
		d.world_height = float(tune.get("height", 2.0))
		d.energy = float(tune.get("energy", 1.0))
		d.fade_out_fraction = float(tune.get("fade", 0.25))

		var out := "%s/%s.tres" % [OUT_DIR, name]
		var err := ResourceSaver.save(d, out)
		if err != OK:
			problems.append("%s: save failed (err %d)" % [name, err])
			continue

		built += 1
		var facing_name: String = ["upright", "view", "ground"][int(d.facing)]
		print("  %-10s %dx%d grid, %2d frames @ %.0f fps, %.2fs %s, %s, %s, priority %d" % [
			name, cols, rows, count, d.fps, d.duration(),
			"loop" if d.loop else "one-shot",
			"hostile" if d.is_hostile() else "friendly",
			facing_name, d.render_priority()])

	if not problems.is_empty():
		for p in problems:
			push_error(p)
		print("FAILED: %d problem(s)" % problems.size())
		quit(1)
		return

	print("Built %d effect resources in %s" % [built, OUT_DIR])
	quit(0)
