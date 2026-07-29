extends SceneTree

## Builds one SpriteFrames per starter species from the package split frames,
## and measures each species' content box so the guide's on-screen size targets
## can be met.
##
##   godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
##
## Grid and ordering come from docs/ASSET_MANIFEST.json. Do not hand-edit the
## generated .tres files.

const OUT_DIR := "res://data/spirits"
const METRICS_PATH := "res://docs/generated/summon_metrics.json"

## ASSET_MANIFEST column_order. Shared by all three tiers.
const COLUMNS := ["idle", "move", "aim_or_windup", "attack", "attack_recover", "hit", "reform"]

## The three evolution lines, in guide §11 order. Each tier is its own row of
## split frames and its own SpriteFrames — evolution swaps the resource rather
## than adding animations to one set.
const TIERS := [
	{
		"tier": "bound",
		"dir": "res://assets/actors/summon_action_frames",
		"species": ["rune_hound", "sword_wisp", "gun_construct"],
	},
	{
		"tier": "awakened",
		"dir": "res://assets/actors/summon_awakened_frames",
		"species": ["volt_hound", "twin_oath_blades", "burst_golem"],
	},
	{
		"tier": "ascendant",
		"dir": "res://assets/actors/summon_ascendant_frames",
		"species": ["tempest_fenrir", "halo_blade_seraph", "arsenal_titan"],
	},
]

## Master guide §2 on-screen size targets, in pixels at 1080p, indexed by
## evolution line rather than by species name.
##
## The guide states these for the three starters only, and says evolution
## "changes the visible body and one behavior" without ever stating a size
## change — so every tier of a line inherits its starter's target instead of
## having a number invented for it. Raised in ART_REQUIREMENTS.md.
const TARGET_PX := [52.0, 58.0, 46.0]

## The hero anchors the scale: 242 px of cell reads as 88 px on screen at
## 1.8 world units, so one screen pixel is 1.8/88 world units.
const HERO_WORLD_HEIGHT := 1.8
const HERO_SCREEN_PX := 88.0

## One animation per column. Single-frame states hold; move and attack loop.
const LOOPING := {"idle": true, "move": true, "aim_or_windup": false, "attack": false, "attack_recover": false, "hit": false, "reform": true}
const FPS := 8.0


func _initialize() -> void:
	var metrics: Dictionary = {}
	var missing: Array[String] = []
	var world_per_screen_px := HERO_WORLD_HEIGHT / HERO_SCREEN_PX

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute("res://docs/generated")

	for tier_spec in TIERS:
		var tier: String = tier_spec["tier"]
		var frame_dir: String = tier_spec["dir"]
		var species_list: Array = tier_spec["species"]

		# A tier whose art has not landed yet is skipped, not reported missing.
		if not DirAccess.dir_exists_absolute(frame_dir):
			print("%-18s tier art not present, skipped" % tier)
			continue

		for species_index in species_list.size():
			var species: String = species_list[species_index]
			var frames := SpriteFrames.new()
			frames.remove_animation("default")

			var per_frame: Dictionary = {}
			var foot_rows: Array[int] = []
			var content_heights: Array[int] = []
			var cell := Vector2i.ZERO

			for col in COLUMNS.size():
				var col_name: String = COLUMNS[col]
				var path := "%s/%02d_%s__%02d_%s.png" % [frame_dir, species_index, species, col, col_name]
				if not ResourceLoader.exists(path):
					missing.append(path.get_file())
					continue
				var tex := load(path) as Texture2D
				if tex == null:
					missing.append(path.get_file())
					continue

				frames.add_animation(col_name)
				frames.set_animation_loop(col_name, bool(LOOPING.get(col_name, false)))
				frames.set_animation_speed(col_name, FPS)
				frames.add_frame(col_name, tex)

				var m := _measure(tex)
				per_frame[col_name] = m
				if m.has("foot_row"):
					foot_rows.append(int(m["foot_row"]))
					content_heights.append(int(m["content_height"]))
					cell = Vector2i(int(m["size"][0]), int(m["size"][1]))

			if frames.get_animation_names().is_empty():
				continue

			var out_path := "%s/%s_frames.tres" % [OUT_DIR, species]
			var err := ResourceSaver.save(frames, out_path)
			if err != OK:
				print("FAILED: could not save %s (err %d)" % [out_path, err])
				quit(1)
				return

			foot_rows.sort()
			var baseline := foot_rows[foot_rows.size() / 2] if not foot_rows.is_empty() else 0
			var spread := 0
			for r in foot_rows:
				spread = maxi(spread, absi(r - baseline))

			content_heights.sort()
			var median_content := content_heights[content_heights.size() / 2] if not content_heights.is_empty() else 1

			# Choose the world height for the whole cell such that the drawn content
			# lands on the guide's pixel target.
			var target_px: float = TARGET_PX[species_index]
			var content_world := target_px * world_per_screen_px
			var cell_world := content_world * (float(cell.y) / maxf(float(median_content), 1.0))

			# Per-frame pivot corrections, same approach as the hero.
			var offsets: Dictionary = {}
			var corrected := 0
			for col_name in per_frame:
				var m: Dictionary = per_frame[col_name]
				if not m.has("foot_row"):
					continue
				var off: int = baseline - int(m["foot_row"])
				offsets["%s/0" % col_name] = off
				if off != 0:
					corrected += 1

			metrics[species] = {
				"tier": tier,
				"evolution_line": TIERS[0]["species"][species_index],
				"cell": [cell.x, cell.y],
				"median_content_height_px": median_content,
				"baseline_foot_row": baseline,
				"baseline_spread_px": spread,
				"target_screen_px": target_px,
				"recommended_world_height_units": snappedf(cell_world, 0.0001),
				"corrected_frame_count": corrected,
				"pivot_offsets": offsets,
				"frames": per_frame,
			}

			print("%-18s %-10s cell=%s content=%dpx spread=%dpx  -> world_height %.4f u (target %.0f px)" % [
				species, tier, str(cell), median_content, spread, cell_world, target_px,
			])

	if not missing.is_empty():
		push_error("Missing %d frames: %s" % [missing.size(), ", ".join(missing)])
		print("FAILED: %d missing frames" % missing.size())
		quit(1)
		return

	var f := FileAccess.open(METRICS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"_note": "Generated by scripts/tools/build_summon_spriteframes.gd. recommended_world_height_units sizes the whole cell so the drawn creature meets the master guide §2 on-screen pixel target, using the hero (242px cell -> 1.8u -> 88px) as the scale anchor. pivot_offsets are applied at runtime by scripts/actors/summon_base.gd.",
			"species": metrics,
		}, "  "))
		f.close()
	print("Wrote %s" % METRICS_PATH)
	quit(0)


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
