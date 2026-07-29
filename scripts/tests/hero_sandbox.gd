extends Node3D

## Phase 1 hero sandbox. A flat floor, a fixed camera framed for the 88 px
## gameplay target, and the player. No enemies — Phase 5 owns those.


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.RUN)
