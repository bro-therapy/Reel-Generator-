extends Node3D

## Phase 2 test room. Player plus a spread of test targets at known positions
## and threat classes, so scoring and firing can be measured deterministically.


func _ready() -> void:
	SceneFlow.set_state(SceneFlow.State.RUN)
