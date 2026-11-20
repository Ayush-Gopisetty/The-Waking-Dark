extends Node
## Renders a top-down, evenly lit map of the level (ceilings cut away), with
## spirits and pickups visible. Needs a window:
##   godot --path . res://tools/map_preview.tscn -- <output.png>

func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	var out: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.get_node("HUD").visible = false
	var env: Environment = main.get_node("WorldEnvironment").environment.duplicate()
	env.ambient_light_energy = 1.2
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.volumetric_fog_enabled = false
	main.get_node("WorldEnvironment").environment = env
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.6
	main.add_child(sun)
	sun.look_at_from_position(Vector3(0, 10, 0), Vector3(0.3, 0, 0.5))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 30.0
	cam.near = 0.05
	cam.far = 10.0
	main.add_child(cam)
	cam.look_at_from_position(Vector3(3.0, 2.95, -1.0), Vector3(3.0, 0, -1.0), Vector3(0, 0, -1))
	cam.current = true
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
