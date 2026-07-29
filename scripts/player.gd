extends CharacterBody2D

## Placeholder player. Top-down 8-directional movement so there's something
## on screen that responds to input — replace once the game has a direction.

@export var speed: float = 400.0
@export var acceleration: float = 3000.0
@export var friction: float = 2500.0


func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
