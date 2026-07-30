extends SceneTree

## Builds the hero locomotion SpriteFrames from the package split frames, and
## audits each frame's ground pivot.
##
##   godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
##
## Regenerate whenever the actor art is replaced. Grid and ordering come from
## docs/ASSET_MANIFEST.json — do not hand-edit the generated .tres.

const FRAME_DIR := "res://assets/actors/hero_locomotion_frames"
const ACTION_DIR := "res://assets/actors/hero_action_frames"
const OUT_PATH := "res://data/characters/tower_exile_frames.tres"
const PIVOT_REPORT := "res://docs/generated/hero_pivot_audit.json"
const OFFSET_PATH := "res://data/characters/tower_exile_pivot_offsets.json"

## ASSET_MANIFEST row_order for the locomotion atlas.
const DIRECTIONS := ["south", "southwest", "west", "northwest", "north", "northeast", "east", "southeast"]
## ASSET_MANIFEST column_order.
const COLUMNS := ["idle", "walk_contact", "walk_passing", "run_extension", "run_recovery"]

## Two gaits, not one. The package ships walk_contact/walk_passing (subtle weight
## shifts) and run_extension/run_recovery (full strides, scarf flying) — and this
## builder used to concatenate all four into a single "run" animation. Played as
## one cycle the hero alternates between barely moving and sprinting, which is
## precisely the "walking animation could be better" the owner reported. The frame
## names were telling us the answer the whole time.
##
## Walk is the two walk poses. Run is extension -> passing -> recovery -> passing:
## the passing pose is the standard in-between that keeps a two-extreme run from
## reading as a two-frame flicker, and using it doubles the run's apparent
## smoothness without needing art that does not exist.
const WALK_COLUMNS := [1, 2]           # walk_contact, walk_passing
const RUN_COLUMNS := [3, 2, 4, 2]      # extension, passing, recovery, passing
const IDLE_FPS := 4.0
const WALK_FPS := 7.0
const RUN_FPS := 12.0

## The dash, from the action atlas. Non-directional: the art is one east-facing
## lunge, and the player flips it for leftward dashes. Its canvas is 222x444
## against locomotion's 162x242, which is why its pivot corrections go through
## the canvas-aware formula rather than the plain baseline difference.
## 16 fps x 3 frames = 0.1875 s, matching dash_duration_seconds (0.18) so the
## recover pose lands as the dash ends rather than mid-flight.
const DASH_FILES := [
	"00_top__01_dash_or_focus",
	"00_top__02_dash_streak_or_convergence_start",
	"00_top__03_dash_recover_or_convergence",
]
const DASH_FPS := 16.0


func _initialize() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	var missing: Array[String] = []
	var pivots: Dictionary = {}

	for dir_index in DIRECTIONS.size():
		var dir_name: String = DIRECTIONS[dir_index]

		var idle_anim := "idle_%s" % dir_name
		frames.add_animation(idle_anim)
		frames.set_animation_loop(idle_anim, true)
		frames.set_animation_speed(idle_anim, IDLE_FPS)
		var idle_tex := _load_frame(dir_index, dir_name, 0, missing)
		if idle_tex != null:
			frames.add_frame(idle_anim, idle_tex)
			pivots[_frame_key(dir_index, dir_name, 0)] = _measure(idle_tex)

		var walk_anim := "walk_%s" % dir_name
		frames.add_animation(walk_anim)
		frames.set_animation_loop(walk_anim, true)
		frames.set_animation_speed(walk_anim, WALK_FPS)
		for col in WALK_COLUMNS:
			var wtex := _load_frame(dir_index, dir_name, col, missing)
			if wtex != null:
				frames.add_frame(walk_anim, wtex)
				pivots[_frame_key(dir_index, dir_name, col)] = _measure(wtex)

		var run_anim := "run_%s" % dir_name
		frames.add_animation(run_anim)
		frames.set_animation_loop(run_anim, true)
		frames.set_animation_speed(run_anim, RUN_FPS)
		for col in RUN_COLUMNS:
			var tex := _load_frame(dir_index, dir_name, col, missing)
			if tex != null:
				frames.add_frame(run_anim, tex)
				pivots[_frame_key(dir_index, dir_name, col)] = _measure(tex)

	# Dash is optional on purpose: a checkout with only the locomotion package
	# still builds, and the player falls back to run_* during a dash exactly as
	# it did before the action frames existed.
	var dash_pivots: Dictionary = {}
	frames.add_animation("dash")
	frames.set_animation_loop("dash", false)
	frames.set_animation_speed("dash", DASH_FPS)
	for fname in DASH_FILES:
		var path := "%s/%s.png" % [ACTION_DIR, fname]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		frames.add_frame("dash", tex)
		dash_pivots[fname] = _measure(tex)
	if frames.get_frame_count("dash") == 0:
		frames.remove_animation("dash")

	if not missing.is_empty():
		push_error("Missing %d frames: %s" % [missing.size(), ", ".join(missing)])
		print("FAILED: %d missing frames" % missing.size())
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute("res://data/characters")
	var err := ResourceSaver.save(frames, OUT_PATH)
	if err != OK:
		print("FAILED: could not save %s (err %d)" % [OUT_PATH, err])
		quit(1)
		return

	var report := _pivot_report(pivots)
	DirAccess.make_dir_recursive_absolute("res://docs/generated")
	var f := FileAccess.open(PIVOT_REPORT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()

	# Per-frame pivot correction so the feet sit on the origin in every frame.
	# ASSET_MANIFEST.json sanctions normalizing pivots in Godot; the underlying
	# art defect is recorded in docs/ART_CLEANUP_TODO.md rather than repainted.
	var offsets := _pivot_offsets(pivots, int(report["median_foot_row"]))
	_add_dash_offsets(offsets, dash_pivots, int(report["median_foot_row"]))
	var of := FileAccess.open(OFFSET_PATH, FileAccess.WRITE)
	if of != null:
		of.store_string(JSON.stringify(offsets, "  "))
		of.close()
	print("Wrote %s  (%d corrected frames)" % [OFFSET_PATH, int(offsets["corrected_frame_count"])])

	print("Built %s" % OUT_PATH)
	print("  animations: %d  (idle + walk + run for %d directions)" % [frames.get_animation_names().size(), DIRECTIONS.size()])
	print("  frames measured: %d" % pivots.size())
	print("  baseline spread: %d px   (max deviation from median foot row)" % report["baseline_spread_px"])
	print("  cell size: %s" % str(report["cell_size"]))
	print("Wrote %s" % PIVOT_REPORT)
	quit(0)


func _frame_key(dir_index: int, dir_name: String, col: int) -> String:
	return "%02d_%s__%02d_%s" % [dir_index, dir_name, col, COLUMNS[col]]


func _frame_path(dir_index: int, dir_name: String, col: int) -> String:
	return "%s/%s.png" % [FRAME_DIR, _frame_key(dir_index, dir_name, col)]


func _load_frame(dir_index: int, dir_name: String, col: int, missing: Array[String]) -> Texture2D:
	var path := _frame_path(dir_index, dir_name, col)
	if not ResourceLoader.exists(path):
		missing.append(path.get_file())
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		missing.append(path.get_file())
	return tex


## Opaque-pixel bounding box, used to detect ground-pivot drift between frames.
func _measure(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return {}
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.02:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_y < 0:
		return {"empty": true, "size": [w, h]}
	return {
		"size": [w, h],
		"bbox": [min_x, min_y, max_x, max_y],
		"foot_row": max_y,
		"head_row": min_y,
		"content_height": max_y - min_y + 1,
	}


func _pivot_report(pivots: Dictionary) -> Dictionary:
	var foot_rows: Array[int] = []
	var cell := [0, 0]
	for key in pivots:
		var m: Dictionary = pivots[key]
		if m.has("foot_row"):
			foot_rows.append(int(m["foot_row"]))
		if m.has("size"):
			cell = m["size"]
	foot_rows.sort()

	var median := 0
	if not foot_rows.is_empty():
		median = foot_rows[foot_rows.size() / 2]

	var spread := 0
	var outliers: Array = []
	for key in pivots:
		var m: Dictionary = pivots[key]
		if not m.has("foot_row"):
			continue
		var dev: int = absi(int(m["foot_row"]) - median)
		spread = maxi(spread, dev)
		if dev > 2:
			outliers.append({"frame": key, "foot_row": m["foot_row"], "deviation_px": dev})

	outliers.sort_custom(func(a, b): return int(a["deviation_px"]) > int(b["deviation_px"]))

	return {
		"_note": "Ground-pivot audit for hero locomotion frames. foot_row is the lowest opaque pixel row in each cell. Large deviations cause visible bob between idle and run.",
		"cell_size": cell,
		"median_foot_row": median,
		"baseline_spread_px": spread,
		"outlier_threshold_px": 2,
		"outlier_count": outliers.size(),
		"outliers": outliers,
		"frames": pivots,
	}


## Maps "<anim>/<frame_index>" -> vertical pixel correction that pulls each
## frame's lowest opaque row onto the shared baseline.
func _pivot_offsets(pivots: Dictionary, baseline: int) -> Dictionary:
	var map: Dictionary = {}
	var corrected := 0
	for dir_index in DIRECTIONS.size():
		var dir_name: String = DIRECTIONS[dir_index]

		var idle_key := _frame_key(dir_index, dir_name, 0)
		var idle_off := _offset_for(pivots, idle_key, baseline)
		map["idle_%s/0" % dir_name] = idle_off
		if idle_off != 0:
			corrected += 1

		# Every gait, not just run. The table is keyed "<anim>/<frame index>", so
		# splitting walk out of run renumbered every frame — and this loop only
		# emitting run_* keys left the walk frames uncorrected, which Phase 1
		# caught immediately as 7 px of pivot bob. Any future gait must be added
		# here too, or its frames will silently bob.
		for gait in [["walk", WALK_COLUMNS], ["run", RUN_COLUMNS]]:
			var prefix: String = gait[0]
			var columns: Array = gait[1]
			for i in columns.size():
				var col: int = columns[i]
				var off := _offset_for(pivots, _frame_key(dir_index, dir_name, col), baseline)
				map["%s_%s/%d" % [prefix, dir_name, i]] = off
				if off != 0:
					corrected += 1

	return {
		"_note": "Vertical pixel corrections applied at runtime by scripts/actors/player.gd so every frame's feet land on the same baseline. Generated by scripts/tools/build_hero_spriteframes.gd. The underlying art inconsistency is logged in docs/ART_CLEANUP_TODO.md.",
		"baseline_foot_row": baseline,
		"cell_height_px": 242,
		"corrected_frame_count": corrected,
		# The gait layout is published rather than left implicit. Phase 1 verifies
		# every correction by re-deriving which source column each animation frame
		# came from, and it used to hardcode [1,2,3,4] -> run_*. Splitting walk out
		# of run renumbered everything and the check started comparing corrections
		# against the wrong frames. Emitting the map means the two cannot drift.
		"gaits": {
			"idle": [0],
			"walk": WALK_COLUMNS,
			"run": RUN_COLUMNS,
		},
		"column_names": COLUMNS,
		"offsets": map,
	}


## Corrections for frames on a DIFFERENT canvas than the locomotion cell.
##
## The runtime applies `offset.y = cell_h/2 - correction` with cell_h fixed at
## the locomotion cell height, and SpriteBase3D centres each texture. So for a
## frame of canvas height H whose feet sit at row f, landing the feet on the
## locomotion baseline needs
##
##   offset_needed = (f - H/2) + (cell_h - baseline)
##   correction    = cell_h/2 - offset_needed
##
## which collapses to the plain `baseline - f` when H == cell_h — the existing
## locomotion formula, unchanged.
func _add_dash_offsets(offsets: Dictionary, dash_pivots: Dictionary, baseline: int) -> void:
	if dash_pivots.is_empty():
		return
	var map: Dictionary = offsets["offsets"]
	var actions: Dictionary = {"dash": []}
	var i := 0
	for fname in DASH_FILES:
		if not dash_pivots.has(fname):
			continue
		var m: Dictionary = dash_pivots[fname]
		var canvas_h := int(m["size"][1])
		var loco_cell_h := int(offsets.get("cell_height_px", 242))
		var foot := int(m["foot_row"])
		var offset_needed := (float(foot) - canvas_h / 2.0) + float(loco_cell_h - baseline)
		map["dash/%d" % i] = int(round(loco_cell_h / 2.0 - offset_needed))
		actions["dash"].append(fname)
		i += 1
	offsets["actions"] = actions


func _offset_for(pivots: Dictionary, key: String, baseline: int) -> int:
	var m: Dictionary = pivots.get(key, {})
	if not m.has("foot_row"):
		return 0
	return baseline - int(m["foot_row"])
