extends Node
## Renders the title screen, its settings, and the pause menu (needs a window):
##   godot --path . res://tools/menu_shots.tscn -- <output_dir>
func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	var out: String = OS.get_cmdline_user_args()[0]
	var title: Control = load(GameState.TITLE_SCENE_PATH).instantiate()
	add_child(title)
	await _shot(out, "title", 120)
	title._show_settings(true)
	await _shot(out, "title_settings", 10)
	title.queue_free()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 40:
		await get_tree().process_frame
	main.get_node("PauseMenu").open()
	await _shot(out, "pause", 5)
	main.get_node("PauseMenu")._show_settings(true)
	await _shot(out, "pause_settings", 5)
	get_tree().paused = false
	get_tree().quit()


func _shot(out: String, shot_name: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(shot_name + ".png"))
