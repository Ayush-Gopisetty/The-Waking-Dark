extends Node3D
## Renders Daniel and Jason (CharacterRig) idle, walking and in each cutscene
## gesture, lit like a flashlight beam.
##   godot --path . res://tools/daniel_preview.tscn -- <output_dir>

var _cam: Camera3D


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var daniel := Daniel.new()
	add_child(daniel)
	daniel.set_process(false)
	var jason := CharacterRig.new()
	jason.model_path = "res://assets/models/jason.glb"
	add_child(jason)
	jason.position = Vector3(-1.2, 0, 0)
	_lights()
	_cam = Camera3D.new()
	_cam.near = 0.02
	add_child(_cam)
	_cam.current = true

	# Both idle, full body, from the front (their front faces -Z).
	daniel.position = Vector3(0.6, 0, 0)
	jason.position = Vector3(-0.6, 0, 0)
	jason.look_target = Vector3(0, 1.6, -3.0)
	await _run(daniel, 1.5)
	await _shot(out, "pair_full", Vector3(0, 1.0, -4.2), Vector3(0, 0.95, 0), 40.0)
	await _shot(out, "pair_side", Vector3(4.0, 1.1, -0.5), Vector3(0, 0.95, 0), 40.0)

	# Gestures on Daniel alone.
	jason.visible = false
	daniel.position = Vector3.ZERO
	for g: Array in [["talk", 1.2], ["calm", 1.2], ["show_hand", 1.2], ["point", 1.0], ["after_you", 1.3], ["startle", 1.0]]:
		daniel.play(g[0], Vector3(-3.0, 1.4, -2.0))
		await _run(daniel, g[1])
		await _shot(out, "daniel_" + g[0], Vector3(0.5, 1.35, -2.2), Vector3(0, 1.15, 0), 40.0)
	# Pointing behind him: he turns most of the way toward it (as the cutscene
	# director does) and points with the near hand.
	var behind := Vector3(1.5, 1.3, 3.0)  # behind and to his left (he faces -Z)
	daniel.rotation.y = 0.0
	daniel.play("point", behind)
	for i in 60:
		var to := behind - daniel.global_position
		var diff := angle_difference(0.0, atan2(-to.x, -to.z))
		daniel.rotation.y = lerp_angle(daniel.rotation.y, diff * 0.6, minf(1.0, 2.5 / 30.0))
		await _run(daniel, 1.0 / 30.0)
	await _shot(out, "daniel_point_behind", Vector3(-2.2, 1.4, -1.6), Vector3(0, 1.2, 0), 45.0)
	await _shot(out, "daniel_point_behind_b", Vector3(2.6, 1.5, 1.2), Vector3(0, 1.2, 0), 45.0)
	daniel.rotation.y = 0.0
	daniel.play("idle")
	await _run(daniel, 1.0)

	# Hand close-ups, and the talk gesture over time (transitions should be smooth).
	for g: String in ["idle", "calm", "show_hand"]:
		daniel.play(g)
		await _run(daniel, 1.2)
		await _shot(out, "hands_" + g, Vector3(0.35, 1.2, -1.0), Vector3(0, 1.05, 0), 45.0)
	# The bandaged, bloodied hand up close (palm side, back, and from the wrist).
	daniel.play("show_hand")
	await _run(daniel, 1.4)
	var hand_at := daniel.bandaged_hand_position()
	for view: Array in [["front", Vector3(0.0, 0.08, -0.38)], ["side", Vector3(-0.38, 0.1, -0.1)], ["above", Vector3(0.1, 0.4, -0.15)]]:
		await _shot(out, "bandage_" + view[0], hand_at + view[1], hand_at + Vector3(0, -0.05, 0), 30.0)
	daniel.play("idle")
	await _run(daniel, 1.5)
	daniel.play("talk")
	for i in 4:
		await _run(daniel, 0.35)
		await _shot(out, "talk_seq_%d" % i, Vector3(0.35, 1.25, -1.3), Vector3(0, 1.1, 0), 45.0)
	daniel.play("idle")
	await _run(daniel, 1.5)
	await _shot(out, "daniel_face", Vector3(0, 1.72, -0.7), Vector3(0, 1.7, 0), 35.0)

	# Walk cycle: drive him along X and grab a side view mid-stride.
	for i in 40:
		daniel.position.x += 0.03
		daniel._process(1.0 / 30.0)
	await _shot(out, "daniel_walk", Vector3(daniel.position.x, 1.0, -3.0), Vector3(daniel.position.x, 0.9, 0), 40.0)

	# Jason: touching the wound; first-person view of his own body.
	daniel.visible = false
	jason.visible = true
	jason.position = Vector3.ZERO
	jason.holding = true  # as in the game: flashlight in his right hand, so the left hand rubs the wound
	jason.play("touch_head")
	var last := 0.0
	for t: float in [0.3, 0.5, 0.7, 0.9, 1.1, 1.4, 1.7, 2.0, 2.3, 2.5, 2.7, 2.9, 3.1, 3.6]:
		await _run(jason, t - last)
		last = t
		await _shot(out, "jason_touch_%.1f" % t, Vector3(0.9, 1.5, -1.6), Vector3(0, 1.4, 0), 40.0)
		await _shot(out, "jason_touch_front_%.1f" % t, Vector3(0.15, 1.55, -1.1), Vector3(0, 1.45, 0), 32.0)
	get_tree().quit()


func _run(rig: CharacterRig, seconds: float) -> void:
	var steps := int(seconds * 30.0)
	for i in steps:
		for c in get_children():
			if c is CharacterRig and c.visible:
				c._process(1.0 / 30.0)
	await get_tree().process_frame


func _shot(out: String, name: String, from: Vector3, at: Vector3, fov: float) -> void:
	_cam.fov = fov
	_cam.look_at_from_position(from, at)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _lights() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.03, 0.035)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.3, 0.33, 0.4)
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.2
	key.light_color = Color(1, 0.93, 0.8)
	add_child(key)
	key.look_at_from_position(Vector3(1.5, 3.0, -3.0), Vector3.ZERO)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
