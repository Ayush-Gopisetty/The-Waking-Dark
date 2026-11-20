extends Node3D
## Renders preview shots of the spirit's body for art iteration.
## Run (needs a window, not --headless):
##   godot --path . res://tools/monster_preview.tscn -- <output_dir>
## Writes <output_dir>/monster_<shot>.png and quits.

const SHOTS := [
	# name, camera position, look-at, pose ("idle" / "walk" / "chase" / "burn"), flashlight
	["front", Vector3(0.0, 1.55, -2.6), Vector3(0.0, 1.05, 0.0), "idle", true],
	["three_quarter", Vector3(1.7, 1.5, -1.9), Vector3(0.0, 1.05, 0.0), "idle", true],
	["side", Vector3(2.6, 1.3, 0.0), Vector3(0.0, 1.0, 0.0), "idle", true],
	["walk", Vector3(-2.2, 1.4, -1.6), Vector3(0.0, 1.0, 0.0), "walk", true],
	["face", Vector3(0.12, 1.8, -1.05), Vector3(-0.04, 1.79, -0.36), "idle", true],
	["face_front", Vector3(-0.03, 1.85, -0.85), Vector3(-0.05, 1.83, -0.38), "idle", true],
	["chase", Vector3(0.4, 1.5, -2.4), Vector3(0.0, 1.1, 0.0), "chase", true],
	["burn", Vector3(0.3, 1.5, -2.4), Vector3(0.0, 1.1, 0.0), "burn", true],
	["push", Vector3(1.6, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "push", true],
	["avert", Vector3(1.6, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "avert", true],
	["avert_left", Vector3(-1.6, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "avert_left", true],
	["shy", Vector3(1.6, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "shy", true],
	["flee", Vector3(1.6, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "flee", true],
	["notice", Vector3(0.0, 1.5, -2.8), Vector3(0.0, 1.2, 0.0), "notice", true],
	["catch", Vector3(0.0, 1.5, -2.8), Vector3(0.0, 1.2, 0.0), "catch", true],
	["look_left", Vector3(0.0, 1.6, -2.4), Vector3(0.0, 1.5, 0.0), "look_left", true],
	["look_up", Vector3(1.6, 1.5, -2.2), Vector3(0.0, 1.5, 0.0), "look_up", true],
	["strike_wind", Vector3(1.8, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "strike:18", true],
	["strike_hit", Vector3(1.8, 1.5, -2.2), Vector3(0.0, 1.1, 0.0), "strike:23", true],
	["strike_side_wind", Vector3(-2.8, 1.4, -0.3), Vector3(0.0, 1.3, -0.2), "strike:15", true],
	["strike_side_hit", Vector3(-2.8, 1.4, -0.3), Vector3(0.0, 1.3, -0.2), "strike:22", true],
	["strike_side_back", Vector3(-2.8, 1.4, -0.3), Vector3(0.0, 1.3, -0.2), "strike:36", true],
	["walk_side_a", Vector3(2.6, 1.0, 0.0), Vector3(0.0, 0.9, 0.0), "walk", true, 100],
	["walk_side_b", Vector3(2.6, 1.0, 0.0), Vector3(0.0, 0.9, 0.0), "walk", true, 108],
	["walk_side_c", Vector3(2.6, 1.0, 0.0), Vector3(0.0, 0.9, 0.0), "walk", true, 116],
	["walk_side_d", Vector3(2.6, 1.0, 0.0), Vector3(0.0, 0.9, 0.0), "walk", true, 124],
	["corridor_dark", Vector3(0.6, 1.6, -5.5), Vector3(0.0, 1.2, 0.0), "walk", true],
]

var _body: MonsterBody
var _camera: Camera3D
var _flashlight: SpotLight3D


func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://"
	_build_stage()
	await _capture_all(out_dir)
	get_tree().quit()


func _capture_all(out_dir: String) -> void:
	for shot: Array in SHOTS:
		var cam_pos: Vector3 = shot[1]
		var target: Vector3 = shot[2]
		var pose: String = shot[3]
		_camera.look_at_from_position(cam_pos, target)
		_flashlight.visible = shot[4]
		# Let the pose settle (blends are time-based).
		_body.avert = 0.0
		_body.avert_side = 1.0
		_body.shy = 0.0
		_body.stumbling = false
		_body.notice = false
		_body.catching = false
		_body.look_yaw = 0.0
		_body.look_pitch = 0.0
		_body.look_weight = 0.0
		var frames: int = shot[5] if shot.size() > 5 else 90
		for i in frames:
			if pose == "push" and i == 84:
				_body.push_back()
			if pose.begins_with("strike:") and i == frames - int(pose.get_slice(":", 1)):
				_body.strike()
			_pose(pose, 1.0 / 60.0)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("monster_%s.png" % shot[0])
		image.save_png(path)
		print("saved ", path)


func _pose(pose: String, delta: float) -> void:
	match pose:
		"idle", "strike:18", "strike:23", "strike:15", "strike:22", "strike:36": _body.animate(delta, 0.0, false, 0.0)
		"walk": _body.animate(delta, 1.5, false, 0.0)
		"chase": _body.animate(delta, 3.2, true, 0.0)
		"burn": _body.animate(delta, 0.0, false, 1.0)
		"push": _body.animate(delta, 0.0, false, 0.5)
		"avert":
			_body.avert = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"avert_left":
			_body.avert = 1.0
			_body.avert_side = -1.0
			_body.animate(delta, 0.0, false, 0.0)
		"shy":
			_body.shy = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"notice":
			_body.notice = true
			_body.look_weight = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"catch":
			_body.catching = true
			_body.look_weight = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"look_left":
			_body.look_yaw = 0.9
			_body.look_weight = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"look_up":
			_body.look_pitch = 0.4
			_body.look_weight = 1.0
			_body.animate(delta, 0.0, false, 0.0)
		"flee":
			_body.stumbling = true
			_body.animate(delta, 3.6, false, 0.12)


func _build_stage() -> void:
	# Same environment as the game.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var env_node: WorldEnvironment = main.get_node("WorldEnvironment")
	var env := WorldEnvironment.new()
	env.environment = env_node.environment
	add_child(env)
	main.free()

	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.3, 0.3, 0.31)
	wall.roughness = 0.9
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.19, 0.18)
	_box(Vector3(0, -0.1, 0), Vector3(8, 0.2, 14), floor_mat)
	_box(Vector3(0, 1.5, 2.5), Vector3(8, 3, 0.2), wall)
	_box(Vector3(-3.0, 1.5, 0), Vector3(0.2, 3, 14), wall)
	_box(Vector3(3.0, 1.5, -1.0), Vector3(0.2, 3, 4), wall)

	_body = MonsterBody.new()
	add_child(_body)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.near = 0.03
	add_child(_camera)
	_camera.current = true

	# Flashlight held just below and right of the camera, like the player's.
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1, 0.94, 0.8)
	_flashlight.light_energy = 3.0
	_flashlight.light_volumetric_fog_energy = 1.5
	_flashlight.shadow_enabled = true
	_flashlight.spot_range = 14.0
	_flashlight.spot_angle = 24.0
	_flashlight.spot_attenuation = 1.2
	_flashlight.spot_angle_attenuation = 1.6
	_flashlight.position = Vector3(0.18, -0.15, -0.1)
	_camera.add_child(_flashlight)


func _box(center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = center
	add_child(mesh)
