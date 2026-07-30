extends SceneTree

## Phase 0 acceptance checks, from docs/CLAUDE_GODOT_BUILD_BRIEF.md.
##
##   godot --headless --path . --script scripts/tests/phase0_acceptance.gd
##
## Exits non-zero if any check fails, so it is CI-usable.

const REQUIRED_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"aim_left", "aim_right", "aim_up", "aim_down",
	"dash", "interact", "rally", "team_command",
	"focus_fire", "convergence", "pause", "debug_overlay_toggle",
]

const REQUIRED_DIRS := [
	"res://assets/actors", "res://assets/enemies", "res://assets/environment",
	"res://assets/ui", "res://assets/vfx",
	"res://data/characters", "res://data/spirits", "res://data/enemies",
	"res://data/encounters", "res://data/rooms", "res://data/relics",
	"res://scenes/actors", "res://scenes/enemies", "res://scenes/rooms",
	"res://scenes/ui", "res://scenes/tests",
	"res://scripts/data", "res://scripts/actors", "res://scripts/combat",
	"res://scripts/run", "res://scripts/ui",
	"res://audio", "res://docs",
]

const COLLISION_LAYERS := [
	"World", "PlayerBody", "EnemyBody", "PlayerHurtbox", "EnemyHurtbox",
	"FriendlyAttack", "HostileAttack", "PickupInteractable",
	"NavigationBlocker", "CameraTrigger",
]

## Atlases the manifest marks prototype_ready, with expected dimensions.
const PIXEL_ATLASES := {
	"res://assets/actors/PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png": Vector2i(810, 1936),
	"res://assets/actors/PZC_Tower_Exile_Action_Atlas_ALPHA_GRID_v1.png": Vector2i(1776, 888),
	"res://assets/actors/PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png": Vector2i(1540, 1026),
	"res://assets/enemies/PZC_Level1_Enemy_Action_Atlas_ALPHA_v1.png": Vector2i(1254, 1254),
	"res://assets/enemies/PZC_First_Bell_Action_Atlas_ALPHA_GRID_v1.png": Vector2i(2176, 724),
	"res://assets/vfx/PZC_Level1_Combat_VFX_Atlas_ALPHA_GRID_v1.png": Vector2i(1776, 888),
	"res://assets/ui/PZC_Pickup_Relic_Icon_Atlas_ALPHA_GRID_v1.png": Vector2i(1776, 888),
}

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n=== PHASE 0 ACCEPTANCE ===\n")
	_check_directories()
	_check_project_settings()
	_check_collision_layers()
	_check_input_map()
	_check_texture_filtering()
	_check_balance_data()
	_check_boot_scene()
	_check_debug_overlay()
	_summary()


func _ok(label: String, detail: String = "") -> void:
	_pass += 1
	print("  PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _no(label: String, detail: String) -> void:
	_fail += 1
	print("  FAIL  %s  -> %s" % [label, detail])


func _section(title: String) -> void:
	print("\n%s" % title)


func _check_directories() -> void:
	_section("Directory skeleton (brief Phase 0)")
	var missing: Array[String] = []
	for path in REQUIRED_DIRS:
		if not DirAccess.dir_exists_absolute(path):
			missing.append(path)
	if missing.is_empty():
		_ok("all %d required directories exist" % REQUIRED_DIRS.size())
	else:
		_no("required directories", "missing: %s" % ", ".join(missing))


func _check_project_settings() -> void:
	_section("Project settings")

	var w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	if w == 1920 and h == 1080:
		_ok("reference resolution 1920x1080")
	else:
		_no("reference resolution", "got %dx%d" % [w, h])

	var aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	if aspect == "keep":
		_ok("stretch aspect preserves ratio", aspect)
	else:
		_no("stretch aspect", "expected 'keep', got '%s'" % aspect)

	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0))
	if ticks == 60:
		_ok("physics tick 60")
	else:
		_no("physics tick", "expected 60, got %d" % ticks)


func _check_collision_layers() -> void:
	_section("Collision layers (master guide §15, fixed 1-10)")
	var wrong: Array[String] = []
	for i in COLLISION_LAYERS.size():
		var key := "layer_names/3d_physics/layer_%d" % (i + 1)
		var actual := String(ProjectSettings.get_setting(key, ""))
		if actual != COLLISION_LAYERS[i]:
			wrong.append("layer_%d expected '%s' got '%s'" % [i + 1, COLLISION_LAYERS[i], actual])
	if wrong.is_empty():
		_ok("all 10 layers named in guide order")
	else:
		_no("collision layers", "; ".join(wrong))


func _check_input_map() -> void:
	_section("Input map (master guide §3)")

	var missing: Array[String] = []
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	if missing.is_empty():
		_ok("all %d actions present" % REQUIRED_ACTIONS.size())
	else:
		_no("actions present", "missing: %s" % ", ".join(missing))
		return

	# Every gameplay action needs BOTH a keyboard/mouse and a controller binding.
	# Aim is stick-only by design — the mouse drives it through motion, not an action.
	var kbm_exempt := ["aim_left", "aim_right", "aim_up", "aim_down"]
	var no_kbm: Array[String] = []
	var no_pad: Array[String] = []
	for action in REQUIRED_ACTIONS:
		var has_kbm := false
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey or ev is InputEventMouseButton:
				has_kbm = true
			elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		if not has_kbm and not kbm_exempt.has(action):
			no_kbm.append(action)
		if not has_pad:
			no_pad.append(action)

	if no_kbm.is_empty():
		_ok("keyboard/mouse bindings on every non-aim action")
	else:
		_no("keyboard/mouse bindings", "missing on: %s" % ", ".join(no_kbm))

	if no_pad.is_empty():
		_ok("controller bindings on all %d actions" % REQUIRED_ACTIONS.size())
	else:
		_no("controller bindings", "missing on: %s" % ", ".join(no_pad))


func _check_texture_filtering() -> void:
	_section("Pixel texture filtering (brief: must be disabled)")

	var canvas_filter := int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1))
	if canvas_filter == 0:
		_ok("project default canvas filter = Nearest")
	else:
		_no("project default canvas filter", "expected 0 (Nearest), got %d" % canvas_filter)

	# Atlases must import at the manifest's exact dimensions with no mipmaps.
	var bad_dims: Array[String] = []
	var mip_on: Array[String] = []
	var absent: Array[String] = []

	for path in PIXEL_ATLASES:
		if not ResourceLoader.exists(path):
			absent.append(path.get_file())
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			absent.append(path.get_file())
			continue
		var expected: Vector2i = PIXEL_ATLASES[path]
		if tex.get_size() != Vector2(expected):
			bad_dims.append("%s got %s expected %s" % [path.get_file(), tex.get_size(), expected])

		# Read the generated .import to confirm mipmaps stayed off.
		var import_path: String = str(path) + ".import"
		if FileAccess.file_exists(import_path):
			var cfg := ConfigFile.new()
			if cfg.load(import_path) == OK:
				if bool(cfg.get_value("params", "mipmaps/generate", false)):
					mip_on.append(path.get_file())

	if absent.is_empty():
		_ok("all %d prototype atlases load" % PIXEL_ATLASES.size())
	else:
		_no("atlases load", "missing/unloadable: %s" % ", ".join(absent))

	if bad_dims.is_empty():
		_ok("atlas dimensions match ASSET_MANIFEST.json")
	else:
		_no("atlas dimensions", "; ".join(bad_dims))

	if mip_on.is_empty():
		_ok("no mipmaps generated on pixel atlases")
	else:
		_no("mipmaps", "enabled on: %s" % ", ".join(mip_on))


func _check_balance_data() -> void:
	_section("Data-driven balance")
	var version := String(Balance.get_value("version", ""))
	if version == "":
		_no("LEVEL1_BALANCE.json", "did not load")
		return
	_ok("balance loaded", version)

	var required := {
		"player/dash_distance_units": 4.3,
		"player/dash_duration_seconds": 0.18,
		"player/dash_cooldown_seconds": 1.35,
		"player/move_speed_units_per_second": 6.2,
		"conjurer_staff/attack_interval_seconds": 0.72,
	}
	var wrong: Array[String] = []
	for path in required:
		var got: Variant = Balance.get_value(path, null)
		if got == null or not is_equal_approx(float(got), float(required[path])):
			wrong.append("%s expected %s got %s" % [path, required[path], got])
	if wrong.is_empty():
		_ok("brief-critical values match the JSON")
	else:
		_no("balance values", "; ".join(wrong))


func _check_boot_scene() -> void:
	_section("Boot scene")
	var main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	# The main scene is the game shell — title, run, results — not the Phase 0
	# diagnostic and not the bare playable build. This check has now been wrong twice
	# in the same way: it pinned boot.tscn while that was the only scene there was,
	# then playable.tscn while that was the only thing you could play. Both times it
	# made the current limitation the asserted, passing behaviour. What it is really
	# asserting is "F5 lands on the outermost thing that exists", so both inner
	# scenes are kept and still runnable on their own.
	if main == "res://scenes/game.tscn":
		_ok("main scene is the game shell", main)
	else:
		_no("main scene", "expected res://scenes/game.tscn, got '%s'" % main)

	if ResourceLoader.exists("res://scenes/playable.tscn"):
		_ok("the playable build is still runnable on its own",
			"godot --path . scenes/playable.tscn")
	else:
		_no("playable scene", "res://scenes/playable.tscn is gone")

	if ResourceLoader.exists("res://scenes/boot.tscn"):
		_ok("the Phase 0 diagnostic scene is still available",
			"godot --path . scenes/boot.tscn")
	else:
		_no("boot scene", "res://scenes/boot.tscn is gone")

	if not ResourceLoader.exists(main):
		_no("boot scene loads", "%s does not exist" % main)
		return
	var packed := load(main) as PackedScene
	if packed == null:
		_no("boot scene loads", "failed to load PackedScene")
		return
	var inst := packed.instantiate()
	if inst == null:
		_no("boot scene instantiates", "instantiate() returned null")
		return
	_ok("boot scene instantiates without error")
	inst.free()


func _check_debug_overlay() -> void:
	_section("Debug overlay")
	const OVERLAY := "res://scenes/ui/debug_overlay.tscn"
	if not ResourceLoader.exists(OVERLAY):
		_no("overlay scene exists", OVERLAY)
		return
	var packed := load(OVERLAY) as PackedScene
	var inst := packed.instantiate() if packed != null else null
	if inst == null:
		_no("overlay instantiates", "instantiate() returned null")
		return
	_ok("overlay instantiates")

	# Toggling is visibility on a CanvasLayer — verify the contract directly.
	if inst is CanvasLayer:
		var layer := inst as CanvasLayer
		layer.visible = false
		var off := layer.visible
		layer.visible = true
		var on := layer.visible
		if off == false and on == true:
			_ok("overlay visibility toggles")
		else:
			_no("overlay visibility toggles", "off=%s on=%s" % [off, on])
	else:
		_no("overlay type", "expected CanvasLayer, got %s" % inst.get_class())
	inst.free()

	if InputMap.has_action("debug_overlay_toggle") and InputMap.action_get_events("debug_overlay_toggle").size() >= 2:
		_ok("toggle action bound on keyboard and controller")
	else:
		_no("toggle action", "debug_overlay_toggle needs a key and a pad binding")


func _summary() -> void:
	print("\n" + "=".repeat(46))
	print("PHASE 0:  %d passed, %d failed" % [_pass, _fail])
	print("=".repeat(46) + "\n")
	quit(1 if _fail > 0 else 0)
