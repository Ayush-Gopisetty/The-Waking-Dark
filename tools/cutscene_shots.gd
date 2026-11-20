extends Node
## Plays the real cutscenes and saves a frame from each line, plus Jason's
## first-person body (needs a window):
##   godot --path . res://tools/cutscene_shots.tscn -- <output_dir>
## Covers the ID find, the meeting with Daniel and the east wing moon finale.

var _out := ""
var _line := 0
var _scene := ""


func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	_out = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	await _wait(func() -> bool: return not GameState.cutscene, 15.0)  # the wake-up
	var level: Node = main.get_node("Level")
	var player: Player = GameState.player
	player.flashlight.give()
	player.flashlight.set_on(true)

	# First person: looking ahead, then down at Jason's own body, then crouched.
	player.global_position = Vector3(8.0, 1.25, -2.4)
	player.rotation.y = PI * 0.75
	await _frames(40)
	await _save("fp_ahead")
	player.head.rotation.x = -0.9
	await _frames(20)
	await _save("fp_down")
	player.head.rotation.x = -1.4
	await _frames(20)
	await _save("fp_feet")
	player.head.rotation.x = 0.0

	GameState.scene_line.connect(_on_line)

	# Finding the ID: Jason takes it from the furnace grate, holds it up and reads it.
	_scene = "id"
	_line = 0
	player.global_position = Vector3(18.4, 0.05, 4.5)
	player.rotation.y = -PI / 2.0  # facing the furnace
	await _frames(30)
	for node in level.get_children():
		var pickup := node as Pickup
		if pickup != null and pickup.kind == Pickup.Kind.ID:
			pickup.interact(player)
			break
	await _wait(func() -> bool: return GameState.cutscene, 3.0)
	await _wait(func() -> bool: return not GameState.cutscene, 90.0)
	await _frames(30)
	await _save("after_id")
	# Meeting Daniel: walk into the trigger at the top of the service stairs.
	_scene = "meet"
	_line = 0
	player.global_position = Vector3(10.0, 1.25, -2.2)
	player.rotation.y = 0.0
	await _wait(func() -> bool: return not GameState.cutscene and level._met_daniel and not level.director.active, 90.0)
	await _frames(60)
	await _save("after_meet")

	# The east wing finale.
	_scene = "moon"
	_line = 0
	level.daniel.move_to(level.DANIEL_EAST_WING)
	player.global_position = Vector3(15.2, 1.25, -7.4)
	player.rotation.y = -PI / 2.0
	await _frames(20)
	level._east_wing_finale()
	await _wait(func() -> bool: return GameState.ended, 40.0)
	get_tree().quit()


func _on_line(_id: String, line: Dictionary) -> void:
	var n := _line
	_line += 1
	var at := 1.9 if line.get("jason", "") == "touch_head" or line.get("daniel", "") == "point" else minf(1.6, float(line.get("duration", 3.0)) * 0.6)
	await get_tree().create_timer(at).timeout
	await _save("%s_%02d_%s" % [_scene, n, line.get("shot", "auto")])


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(cond: Callable, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
