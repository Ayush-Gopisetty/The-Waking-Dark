extends Node3D
## Keeps a world-space effect (dust motes) centred on the player.


func _process(_delta: float) -> void:
	var player := GameState.player
	if player != null:
		global_position = player.global_position + Vector3(0, 1.4, 0)
