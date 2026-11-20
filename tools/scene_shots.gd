extends Node
## Renders a few views of the real level (needs a window):
##   godot --path . res://tools/scene_shots.tscn -- <output_dir>
func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	var out: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	main.get_node("HUD").visible = false
	var player: Player = GameState.player
	GameState.cutscene = false
	player.lying = false
	var shots := [
		["hall", Vector3(1.0, 0, 4.5), PI / 2.0 * -1.0],
		["foyer", Vector3(8.5, 1.2, -2.0), 0.0],
		["daniel", Vector3(8.0, 1.2, -9.5), 0.0],
		["daniel_close", Vector3(8.0, 1.2, -9.5), 0.0],
	]
	for shot: Array in shots:
		player.global_position = shot[1]
		player.rotation.y = shot[2]
		if shot[0].begins_with("daniel"):
			var d: Node3D = main.get_node("Level").daniel
			var fwd := Vector3(-sin(shot[2]), 0, -cos(shot[2]))
			d.global_position = shot[1] - Vector3(0, 1.2, 0) + Vector3(0, 1.2, 0) + fwd * (1.3 if shot[0] == "daniel" else 0.8)
		player.flashlight.owned = true
		player.flashlight.on = true
		for i in 25:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(shot[0] + ".png"))
	get_tree().quit()
