extends SceneTree

## Builds one SpriteFrames per enemy role from the package split frames, and
## measures each row's ground pivot.
##
##   godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
##
## Grid and ordering come from docs/ASSET_MANIFEST.json (6x6, 209x209 cells).

const FRAME_DIR := "res://assets/enemies/enemy_action_frames"
const OUT_DIR := "res://data/enemies"
const METRICS := "res://docs/generated/enemy_metrics.json"

const ROLES := ["rift_crawler", "lantern_hexer", "bellguard", "nest_idol", "blade_mite", "siphon_eye"]
const COLUMNS := ["idle", "move_contact", "move_passing", "attack_windup", "attack_active", "death"]

## Animations assembled from the six columns.
const LOOPING := {"idle": true, "move": true, "attack_windup": false, "attack_active": false, "death": false}

## Hero anchor: 242 px of cell reads 88 px on screen at 1.8 world units.
const HERO_WORLD_HEIGHT := 1.8
const HERO_SCREEN_PX := 88.0
## Master guide §10 gives no explicit pixel targets per enemy, so they are scaled
## relative to the 88 px hero: chasers read smaller, the tank reads larger.
const TARGET_PX := {
	"rift_crawler": 46.0, "lantern_hexer": 58.0, "bellguard": 78.0,
	"nest_idol": 66.0, "blade_mite": 44.0, "siphon_eye": 50.0,
}


func _initialize() -> void:
	var metrics: Dictionary = {}
	var missing: Array[String] = []
	var world_per_px := HERO_WORLD_HEIGHT / HERO_SCREEN_PX

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute("res://docs/generated")

	for row in ROLES.size():
		var role: String = ROLES[row]
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var per_frame: Dictionary = {}
		var foot_rows: Array[int] = []
		var contents: Array[int] = []
		var cell := Vector2i.ZERO
		var textures: Dictionary = {}

		for col in COLUMNS.size():
			var col_name: String = COLUMNS[col]
			var path := "%s/%02d_%s__%02d_%s.png" % [FRAME_DIR, row, role, col, col_name]
			if not ResourceLoader.exists(path):
				missing.append(path.get_file())
				continue
			var tex := load(path) as Texture2D
			if tex == null:
				missing.append(path.get_file())
				continue
			textures[col_name] = tex
			var m := _measure(tex)
			per_frame[col_name] = m
			if m.has("foot_row"):
				foot_rows.append(int(m["foot_row"]))
				contents.append(int(m["content_height"]))
				cell = Vector2i(int(m["size"][0]), int(m["size"][1]))

		# idle / move / attack_windup / attack_active / death
		_add(frames, "idle", [textures.get("idle")], true)
		_add(frames, "move", [textures.get("move_contact"), textures.get("move_passing")], true)
		_add(frames, "attack_windup", [textures.get("attack_windup")], false)
		_add(frames, "attack_active", [textures.get("attack_active")], false)
		_add(frames, "death", [textures.get("death")], false)
		# Hit reuses the windup pose; the package ships no dedicated hit cell for
		# enemies, unlike the summon rows. Logged in ART_CLEANUP_TODO.md.
		_add(frames, "hit", [textures.get("attack_windup")], false)

		var out := "%s/%s_frames.tres" % [OUT_DIR, role]
		if ResourceSaver.save(frames, out) != OK:
			print("FAILED saving %s" % out)
			quit(1)
			return

		foot_rows.sort()
		contents.sort()
		var baseline := foot_rows[foot_rows.size() / 2] if not foot_rows.is_empty() else 0
		var spread := 0
		for r in foot_rows:
			spread = maxi(spread, absi(r - baseline))
		var median_content := contents[contents.size() / 2] if not contents.is_empty() else 1
		var target: float = TARGET_PX.get(role, 50.0)
		var cell_world := (target * world_per_px) * (float(cell.y) / maxf(float(median_content), 1.0))

		var offsets: Dictionary = {}
		var corrected := 0
		for anim in ["idle", "move", "attack_windup", "attack_active", "death", "hit"]:
			var src: String = anim
			if anim == "move":
				src = "move_contact"
			elif anim == "hit":
				src = "attack_windup"
			var m: Dictionary = per_frame.get(src, {})
			if not m.has("foot_row"):
				continue
			var off: int = baseline - int(m["foot_row"])
			offsets["%s/0" % anim] = off
			if off != 0:
				corrected += 1
		if per_frame.has("move_passing"):
			var mp: Dictionary = per_frame["move_passing"]
			if mp.has("foot_row"):
				offsets["move/1"] = baseline - int(mp["foot_row"])

		metrics[role] = {
			"cell": [cell.x, cell.y],
			"median_content_height_px": median_content,
			"baseline_foot_row": baseline,
			"baseline_spread_px": spread,
			"target_screen_px": target,
			"recommended_world_height_units": snappedf(cell_world, 0.0001),
			"corrected_frame_count": corrected,
			"pivot_offsets": offsets,
			"frames": per_frame,
		}
		print("%-14s cell=%s content=%dpx spread=%2dpx -> world_height %.4f u" % [role, str(cell), median_content, spread, cell_world])

	if not missing.is_empty():
		push_error("Missing %d enemy frames" % missing.size())
		print("FAILED: %d missing frames: %s" % [missing.size(), ", ".join(missing)])
		quit(1)
		return

	var f := FileAccess.open(METRICS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"_note": "Generated by scripts/tools/build_enemy_spriteframes.gd. 'hit' reuses the attack_windup cell — the package ships no dedicated hit frame for enemies.",
			"roles": metrics,
		}, "  "))
		f.close()
	print("Wrote %s" % METRICS)
	quit(0)


func _add(frames: SpriteFrames, anim: String, textures: Array, loops: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_loop(anim, loops)
	frames.set_animation_speed(anim, 8.0)
	for t in textures:
		if t != null:
			frames.add_frame(anim, t as Texture2D)


func _measure(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return {}
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w; var max_x := -1; var min_y := h; var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.02:
				min_x = mini(min_x, x); max_x = maxi(max_x, x)
				min_y = mini(min_y, y); max_y = maxi(max_y, y)
	if max_y < 0:
		return {"empty": true, "size": [w, h]}
	return {"size": [w, h], "bbox": [min_x, min_y, max_x, max_y], "foot_row": max_y, "head_row": min_y, "content_height": max_y - min_y + 1}
