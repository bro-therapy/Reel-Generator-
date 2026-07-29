extends Node3D

## Phase 3 test field. Spawns all three starters from the SAME SummonBase scene
## with different SpiritData, which is the acceptance criterion "one generic
## base scene drives all three species".

const SUMMON_SCENE := preload("res://scenes/actors/summon_base.tscn")

const SPIRITS := [
	"res://data/spirits/rune_hound.tres",
	"res://data/spirits/sword_wisp.tres",
	"res://data/spirits/gun_construct.tres",
]

var summons: Array[SummonBase] = []


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.RUN)
	spawn_team()


func spawn_team() -> void:
	var hero := get_node_or_null("Player") as Node3D
	if hero == null:
		push_error("summon_field: no Player")
		return
	for path in SPIRITS:
		var spirit := load(path) as SpiritData
		if spirit == null:
			push_error("summon_field: cannot load %s" % path)
			continue
		var s := SUMMON_SCENE.instantiate() as SummonBase
		s.name = String(spirit.id)
		s.data = spirit
		s.hero = hero
		add_child(s)
		# Materialise in the lane rather than on the hero.
		s.snap_to_lane()
		summons.append(s)


func summon_named(id: String) -> SummonBase:
	for s in summons:
		if s.name == id:
			return s
	return null
