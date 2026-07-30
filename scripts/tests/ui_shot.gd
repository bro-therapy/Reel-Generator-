extends Control

## Renders a UI screen to a PNG so it can actually be LOOKED at.
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --display-driver x11 --rendering-driver opengl3 \
##     --resolution 1920x1080 scenes/tests/ui_shot.tscn -- --screen=hud
##
## The acceptance suites measure rects, and rects are not the whole story: a
## layout can satisfy every safe-area and centre-clear rule and still look
## wrong, which is exactly the report that started this pass ("the UI ... looks
## like garbage"). Numbers cannot answer that. A picture can.
##
## Writes to OUT_DIR and quits. Not part of check_project.sh — it needs a real
## GL context, and its output is for a human.

const OUT_DIR := "/tmp/ui_shots"

## screen name -> builder method on this node.
const SCREENS := {
	"hud": "_build_hud",
	"levelup": "_build_level_up",
	"title": "_build_title",
	"summonpick": "_build_summon_pick",
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport().get_visible_rect().size
	size = vp

	# A muted world-coloured plate, not black: a HUD judged against black flatters
	# itself, because every translucent panel reads as opaque.
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.13, 0.20)
	bg.size = vp
	add_child(bg)

	var which := _requested_screen()
	if not SCREENS.has(which):
		push_error("ui_shot: unknown screen '%s' — have %s" % [which, SCREENS.keys()])
		get_tree().quit(1)
		return

	call(SCREENS[which], vp)

	# Three frames: one to enter the tree, one for containers to sort, one to
	# draw the sorted result. Two is enough most of the time and produces an
	# unstyled first frame the rest of it.
	for i in 3:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/%s.png" % [OUT_DIR, which]
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("ui_shot: could not write %s (%d)" % [path, err])
	else:
		print("[ui_shot] wrote %s" % path)
	get_tree().quit(0 if err == OK else 1)


func _requested_screen() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			return arg.substr("--screen=".length())
	return "hud"


func _build_hud(vp: Vector2) -> void:
	var hud := CombatHUD.new()
	add_child(hud)
	hud.size = vp
	hud.relayout()
	# Mid-fight values rather than full bars: a bar at 100% hides the track, and
	# the track is half of what was restyled.
	hud.set_health(72, 120)
	hud.set_stability(63)
	hud.set_convergence(41.0)
	hud.set_experience(5, 37, 90)


func _build_level_up(vp: Vector2) -> void:
	var screen := LevelUpScreen.new()
	add_child(screen)
	screen.size = vp
	var catalog := UpgradeCatalog.new()
	# All three species unlocked, so the offer can include summon upgrades and
	# the cards show the longest text they will ever have to hold.
	screen.open(6, catalog.roll_offer(
		[&"rune_hound", &"sword_wisp", &"gun_construct"]))


func _build_summon_pick(vp: Vector2) -> void:
	var screen := LevelUpScreen.new()
	add_child(screen)
	screen.size = vp
	screen.open_summon_choice(3,
		[&"rune_hound", &"sword_wisp", &"gun_construct"])


func _build_title(vp: Vector2) -> void:
	var screen := TitleScreen.new()
	add_child(screen)
	screen.size = vp
