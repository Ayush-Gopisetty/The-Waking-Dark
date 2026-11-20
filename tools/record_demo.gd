extends Node
## Records a short gameplay reel of Act 1 (needs a window). Run with Godot's movie writer:
##
##   godot --path . res://tools/record_demo.tscn --write-movie /tmp/demo.avi --fixed-fps 30 --resolution 1280x720
##
## then encode it (see the README, "Gameplay video"). The default reel is spoiler-free: waking
## up, a walk down the servants' hall, taking a key and hiding in a wardrobe, the bright beam
## driving off a spirit, and a few silent
## seconds of Jason and Daniel meeting. Add `-- --full`
## after the scene path for the whole reel, which also plays the ID cutscene and the meeting
## with Daniel (story spoilers, so keep that one out of the README). It plays the real game
## (real controls, real cutscenes); only the movement between scenes is scripted, with quick
## fades. Nothing in the reel can end the run: the spirits are kept out of the walk and
## cannot catch.

var _fade: ColorRect
var _caption: Label
var _main: Node
var _level: Node
var _player: Player
var _frame := 0


## Safety net: never record a dead screen or run on for ever.
func _process(_delta: float) -> void:
	_frame += 1
	if GameState.ended:
		push_error("record_demo: the player was caught; stopping the recording")
		get_tree().quit(1)
	elif _frame > 30 * 400:
		push_error("record_demo: ran too long; stopping")
		get_tree().quit(1)


func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	_build_overlay()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_level = _main.get_node("Level")
	await _frames(20)
	_player = GameState.player

	# 1. Title, then waking up (the real opening cutscene).
	_fade.color.a = 1.0
	await _caption_for("THE WAKING DARK\nAct 1  ·  gameplay capture", 75)
	await _fade_to(0.0, 0.6)
	await _wait(func() -> bool: return not GameState.cutscene, 20.0)
	await _frames(20)

	# The spirits stay out of the walk (they are only brought back for the beam scene).
	var spirits := get_tree().get_nodes_in_group("spirits")
	for sp: Spirit in spirits:
		sp.catch_distance = 0.0  # nothing in the reel may end the run
		_stash(sp)

	# 2. A walk down the servants' hall with the flashlight.
	await _cut("The servants' hall")
	_player.flashlight.give()
	_player.flashlight.set_on(true)
	_place(Vector3(1.0, 0.05, 4.5), -PI / 2.0, -0.04)
	await _fade_to(0.0, 0.4)
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_release("move_forward")

	# 2b. Taking a key off its hook, then hiding in a wardrobe (no subtitles: they would name the key).
	var subtitles := _main.get_node("HUD").get("_subtitles") as Control
	if subtitles != null:
		subtitles.visible = false
	await _cut("A key, and somewhere to hide")
	_place(Vector3(3.5, 0.05, 0.95), 0.0, -0.42)  # close, looking down at the hook
	await _fade_to(0.0, 0.4)
	await _frames(45)
	for node in _level.get_children():
		var key := node as Pickup
		if key != null and key.kind == Pickup.Kind.KEY and key.item_id == "furnace_key":
			key.interact(_player)
			break
	await _frames(60)
	var wardrobe: HidingSpot = GameState.hiding_spots[0]
	var door_side := wardrobe.front_position()
	var toward := wardrobe.global_position - door_side
	_place(Vector3(door_side.x, door_side.y, door_side.z), atan2(-toward.x, -toward.z), -0.05)
	await _frames(35)
	wardrobe.interact(_player)  # climbs in; the view becomes the gaps between the doors
	await _frames(110)
	wardrobe.leave(_player)
	await _frames(25)

	# 3. A spirit notices you; the bright beam drives it off.
	await _cut("The bright beam")
	var spirit: Spirit = spirits[0]
	spirit.visible = true
	spirit.process_mode = Node.PROCESS_MODE_INHERIT
	spirit.global_position = Vector3(8.5, 0.0, 4.5)
	spirit.rotation.y = PI / 2.0  # facing west, down the hall toward Jason
	_place(Vector3(4.0, 0.05, 4.5), -PI / 2.0, -0.04)
	_player.flashlight.set_on(true)  # (hiding switches it off)
	await _fade_to(0.0, 0.4)
	await _frames(55)
	Input.action_press("bright")
	await _frames(50)
	Input.action_release("bright")
	await _frames(170)
	_stash(spirit)
	if not "--full" in OS.get_cmdline_user_args():
		await _teaser()
		get_tree().quit()
		return

	# 4. Finding the ID in the furnace (the real cutscene).
	await _cut("The furnace room")
	_place(Vector3(18.4, 0.05, 4.5), -PI / 2.0, -0.1)
	await _frames(20)
	await _fade_to(0.0, 0.4)
	await _frames(30)
	for node in _level.get_children():
		var pickup := node as Pickup
		if pickup != null and pickup.kind == Pickup.Kind.ID:
			pickup.interact(_player)
			break
	await _wait_scene_end("id_found", 60.0)
	await _frames(20)
	# Skip the flashback that follows, under black and muted.
	await _fade_to(1.0, 0.5)
	AudioServer.set_bus_mute(0, true)
	Engine.time_scale = 8.0
	await _wait(func() -> bool: return not GameState.cutscene, 400.0)
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0, false)

	# 5. Meeting Daniel in the parlour (the real cutscene).
	await _frames(10)
	_caption.text = "The parlour"
	await _frames(40)
	_caption.text = ""
	_place(Vector3(10.0, 1.25, -2.2), 0.0, 0.0)
	await _fade_to(0.0, 0.5)
	await _wait(func() -> bool: return GameState.cutscene, 8.0)
	await _wait(func() -> bool: return not GameState.cutscene and not _level.director.active, 90.0)
	await _frames(30)
	await _fade_to(1.0, 0.8)
	await _frames(15)
	get_tree().quit()


## A few seconds of Jason and Daniel meeting, with no subtitles and cut off before anyone
## speaks or reacts: it shows the two of them and the room, and nothing of the story.
func _teaser() -> void:
	await _cut("A candle-lit room")
	_place(Vector3(10.0, 1.25, -2.2), 0.0, 0.0)
	await _fade_to(0.0, 0.5)
	await _wait(func() -> bool: return GameState.cutscene, 8.0)
	await _frames(100)  # the opening wide shot only (the first line's shot is 5 s long)
	await _fade_to(1.0, 0.6)
	await _frames(15)


# --- helpers ---------------------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_color", Color(0.86, 0.84, 0.8))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_caption)


func _caption_for(text: String, frames: int) -> void:
	_caption.text = text
	await _frames(frames)
	_caption.text = ""


## Fade out, show a scene caption on black for a moment, ready for the next scene.
func _cut(title: String) -> void:
	await _fade_to(1.0, 0.4)
	_caption.text = title
	await _frames(40)
	_caption.text = ""


func _fade_to(alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


## Parks a spirit out of the way (and out of play).
func _stash(sp: Spirit) -> void:
	sp.visible = false
	sp.process_mode = Node.PROCESS_MODE_DISABLED
	sp.global_position = Vector3(-14.0, -40.0, -8.0)


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	_player.global_position = pos
	_player.rotation.y = yaw
	_player.head.rotation.x = pitch
	_player.velocity = Vector3.ZERO


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(cond: Callable, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.001)


func _wait_scene_end(fragment_id: String, seconds: float) -> void:
	var state := {"done": false}
	var on_end := func(id: String) -> void:
		if id == fragment_id:
			state["done"] = true
	GameState.scene_ended.connect(on_end)
	await _wait(func() -> bool: return state["done"], seconds)
	GameState.scene_ended.disconnect(on_end)
