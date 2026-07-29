extends Node2D

## Root scene. Entry point for the game — wire up global setup here.


func _ready() -> void:
	print("Game booted. Godot %s" % Engine.get_version_info().string)
