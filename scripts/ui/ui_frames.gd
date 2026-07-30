class_name UiFrames
extends RefCounted

## Ornate panel frames for the UI, from Kenney's CC0 Fantasy UI Borders.
##
## The playtest note this answers: "I just feel like it's too generic... I want
## it to look more game like", and about the upgrade screen, "looks like garbage
## ... I want like a fancier UI".
##
## Every tile in the pack is pure white with its shape carried entirely in alpha.
## That is exactly why this pack was chosen over the prettier ones: a pack with
## baked-in colour would drag beige parchment into a game whose palette is locked
## to violet/indigo (guide §4). These arrive colourless and are tinted here.
##
## Border and Panel are complementary halves of ONE frame, not alternatives:
##   Panel  = the solid field with the ornament knocked OUT of it
##   Border = the ornament alone
## Layered — Panel dark underneath, Border bright on top — they read as a lit
## arcane frame around a dark well. Used alone, either one looks broken.
##
## Everything degrades. `assets/` is fetched rather than committed (see
## tools/fetch_free_assets.sh), so a fresh checkout has no frames at all and the
## callers fall back to flat styleboxes. A missing pack must never be the
## difference between a game that runs and one that does not.

const DIR := "res://assets/ui/frames"
## The pack's ornament fits inside 20 px of a 96 px tile; the panel's inner field
## is uniform from 24. 24 satisfies both, so one margin serves every tile.
const MARGIN := 24

## Style names map to a (panel, border) pair of files.
const STYLES := {
	&"ornate": ["ornate_panel.png", "ornate_border.png"],
	&"plain": ["plain_panel.png", "plain_border.png"],
}

## The house palette. Body colours are near-black violet so world detail behind
## a translucent panel still reads; ornaments are the friendly indigo.
const BODY := Color(0.07, 0.06, 0.12, 0.88)
const BODY_DEEP := Color(0.05, 0.04, 0.09, 0.96)
const ORNAMENT := Color(0.62, 0.52, 0.98, 1.0)
const ORNAMENT_DIM := Color(0.42, 0.38, 0.62, 0.9)


static func available() -> bool:
	return ResourceLoader.exists("%s/ornate_panel.png" % DIR)


static func texture(file: String) -> Texture2D:
	var path := "%s/%s" % [DIR, file]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## A framed panel: dark body, lit ornament, sized by its parent.
##
## Returns a plain `Panel` with a flat stylebox when the pack is not installed,
## so callers get a usable Control either way and never have to branch.
static func panel(style: StringName = &"ornate", body: Color = BODY,
		ornament: Color = ORNAMENT) -> Panel:
	var node := Panel.new()
	node.name = "Frame"
	var files: Array = STYLES.get(style, STYLES[&"ornate"])
	var body_tex := texture(files[0])
	var border_tex := texture(files[1])

	if body_tex == null or border_tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = body
		flat.set_corner_radius_all(6)
		flat.set_border_width_all(2)
		flat.border_color = ornament
		node.add_theme_stylebox_override("panel", flat)
		return node

	node.add_theme_stylebox_override("panel", boxed(body_tex, body))

	# The ornament rides on top as its own node: a StyleBox carries one texture,
	# and these two have to composite.
	var trim := NinePatchRect.new()
	trim.name = "Ornament"
	trim.texture = border_tex
	trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trim.patch_margin_left = MARGIN
	trim.patch_margin_top = MARGIN
	trim.patch_margin_right = MARGIN
	trim.patch_margin_bottom = MARGIN
	trim.self_modulate = ornament
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(trim)
	return node


## Public: the level-up cards build their own state boxes from the same art.
static func boxed(tex: Texture2D, tint: Color) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = MARGIN
	box.texture_margin_top = MARGIN
	box.texture_margin_right = MARGIN
	box.texture_margin_bottom = MARGIN
	box.modulate_color = tint
	return box


## A horizontal rule for splitting a panel into sections. Null when the pack is
## absent — callers treat a missing divider as "no divider", not as an error.
##
## The pack's divider is DIRECTIONAL: it fades from nothing on the left to full
## on the right. Stretched across a panel on its own it reads as a stray line
## someone forgot to delete, which is how it first looked. Two of them, the
## second mirrored, put the bright end in the middle and the fade at both edges —
## which is what a centred rule is supposed to do.
static func rule(width: float, height: float = 10.0) -> Control:
	var tex := texture("divider.png")
	if tex == null:
		return null
	var holder := Control.new()
	holder.name = "Rule"
	holder.custom_minimum_size = Vector2(width, height)
	holder.size = Vector2(width, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var half := TextureRect.new()
		half.texture = tex
		half.stretch_mode = TextureRect.STRETCH_SCALE
		half.flip_h = i == 1
		half.position = Vector2(width * 0.5 * i, 0.0)
		half.size = Vector2(width * 0.5, height)
		half.self_modulate = ORNAMENT_DIM
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(half)
	return holder


## The bar look, shared by the HUD and any screen that shows a meter.
##
## Not a texture: the pack has no bar art, and more importantly the four meters
## are told apart by colour alone (guide §4 — red health, teal Stability, violet
## Convergence, gold experience). A textured fill would fight that. What lifts
## these above "generic" is the treatment — a lit top edge, a darker seated
## track, and a real border — not a bitmap.
static func bar_fill(colour: Color) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(2)
	fill.border_width_top = 2
	fill.border_color = colour.lightened(0.5)
	# A tight inner shadow gives the fill a rounded, lit-from-above read that a
	# flat rectangle cannot, and costs nothing in height — which the HUD has
	# none of to spare.
	fill.shadow_size = 3
	fill.shadow_color = Color(colour.r, colour.g, colour.b, 0.35)
	return fill


static func bar_track() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = BODY_DEEP
	bg.set_corner_radius_all(2)
	bg.set_border_width_all(1)
	bg.border_color = ORNAMENT_DIM
	return bg
