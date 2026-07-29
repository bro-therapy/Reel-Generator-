extends Node3D

## Phase 7 visual sandbox: all nine summon forms at once, one evolution line
## per row, Bound left to Ascendant right.
##
##   godot --path . scenes/tests/evolution_field.tscn
##   ./tools/screenshot.sh scenes/tests/evolution_field.tscn build/shots/evolution.png
##
## Exists so "evolution visibly changes the summon" can be judged by eye, not
## only asserted. phase7_acceptance.gd proves the swap happens and that it does
## not resize the creature; only a person can say whether it reads as a
## progression.

const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]
const SUMMON_SCENE := "res://scenes/actors/summon_base.tscn"

const COLUMN_SPACING := 3.1
const ROW_SPACING := 2.6


func _ready() -> void:
	var packed := load(SUMMON_SCENE) as PackedScene
	for row in SPIRITS.size():
		var data := load(SPIRITS[row]) as SpiritData
		if data == null:
			continue
		for tier in 3:
			var x := (float(tier) - 1.0) * COLUMN_SPACING
			var z := (float(row) - 1.0) * ROW_SPACING

			var anchor := Node3D.new()
			anchor.position = Vector3(x, 0.0, z)
			add_child(anchor)

			var summon := packed.instantiate() as SummonBase
			summon.data = data
			summon.form_index = tier
			summon.hero = anchor
			add_child(summon)

			# This is a display board, not a fight. Left running, each summon
			# steers to its species lane offset — three different offsets, so the
			# rows slide out of alignment. Freezing the physics after setup pins
			# every form to its cell; the sprite is driven directly below.
			summon.global_position = anchor.global_position
			summon.set_physics_process(false)
			_play_idle(summon)


## Starts the idle animation by hand, since the animation update normally runs
## from the physics step that this scene disables.
func _play_idle(node: Node) -> void:
	for child in node.get_children():
		if child is AnimatedSprite3D:
			var sprite := child as AnimatedSprite3D
			if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle"):
				sprite.play("idle")
			return
		_play_idle(child)
