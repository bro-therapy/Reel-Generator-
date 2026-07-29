extends Node3D

## Phase 4 test room. Three summons, three separate enemies, and a hostile red
## telegraph, so species signatures, independent targeting, Rally convergence,
## and friendly-vs-hostile readability can all be measured in one scene.

const SUMMON_SCENE := preload("res://scenes/actors/summon_base.tscn")
const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]

var summons: Array[SummonBase] = []


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.RUN)
	var hero := get_node_or_null("Player") as Node3D
	if hero == null:
		return
	for path in SPIRITS:
		var spirit := load(path) as SpiritData
		var s := SUMMON_SCENE.instantiate() as SummonBase
		s.name = String(spirit.id)
		s.data = spirit
		s.hero = hero
		add_child(s)
		# Materialise in the lane rather than on the hero.
		s.snap_to_lane()
		summons.append(s)
