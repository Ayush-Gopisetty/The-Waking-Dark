extends Node3D
## Renders the head and jaw alone (front, profile, three-quarter) for sculpt
## iteration. Needs a window:
##   godot --path . res://tools/head_preview.tscn -- <output_dir> [flat]
## Pass "flat" to render unlit vertex-colour paint only.
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var body := MonsterBody.new()
	add_child(body)
	var head_mesh: Mesh = load("res://assets/monster/head.res")
	var jaw_mesh: Mesh = load("res://assets/monster/jaw.res")
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.vertex_color_use_as_albedo = true
	head.material_override = flat if OS.get_cmdline_user_args().size() > 1 else body._skin
	add_child(head)
	var jaw := MeshInstance3D.new()
	jaw.mesh = jaw_mesh
	jaw.material_override = body._skin
	jaw.position = Vector3(0, 0.025, -0.005)
	jaw.rotation.x = -0.08
	add_child(jaw)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.013
		sm.height = 0.026
		eye.mesh = sm
		eye.material_override = body._hollow
		eye.position = Vector3(0.03 * side, 0.07, -0.07)
		eye.scale = Vector3(1.0, 1.1, 0.8)
		add_child(eye)
	body.visible = false
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.3, 0.3, 0.32)
	add_child(env)
	var light := DirectionalLight3D.new()
	add_child(light)
	light.look_at_from_position(Vector3(0.3, 0.4, -0.6), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.fov = 35
	cam.near = 0.01
	add_child(cam)
	cam.current = true
	for shot: Array in [["head_front", Vector3(0, 0.08, -0.55)], ["head_profile", Vector3(0.55, 0.08, -0.05)], ["head_34", Vector3(0.32, 0.12, -0.42)]]:
		cam.look_at_from_position(shot[1], Vector3(0, 0.08, -0.02))
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(shot[0] + ".png"))
	get_tree().quit()
