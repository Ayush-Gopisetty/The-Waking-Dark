extends Node
## Headless smoke test. Loads Act 1, checks every system once, then plays the
## plan's beats in order: stuck door -> furnace key -> furnace room (ID,
## flashback, spirit blocks the door, bright beam) -> service stairs -> Daniel
## -> library (case file, drawing, light puzzle, display case, chase) -> east
## wing door (orange moon) -> checkpoint retry.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## Exits 0 on success, 1 on any failed check.

const UP := 1.2

var _failures: Array[String] = []
var _main: Node
var _level: Node


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures.append(label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Waits until `condition` is true or `seconds` pass. Returns the final value.
func _wait_for(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _place(player: Player, pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.head.rotation.x = pitch


func _run() -> void:
	print("smoke test: The Waking Dark, Act 1 (plan's room-by-room beats)")
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_level = _main.get_node("Level")
	await _frames(5)

	var player: Player = GameState.player
	var hall := _spirit("hall")
	var foyer := _spirit("foyer")
	var library := _spirit("library")
	_check(player != null, "player registered")
	_check(_spirits().size() == 3, "three spirits (plan: 2-3 individuals)")
	_check(GameState.hiding_spots.size() == 4, "four hiding spots: hall 2, foyer 1, library 1 (%d)" % GameState.hiding_spots.size())
	_check(_count(Pickup.Kind.BATTERY) == 4, "four battery pickups (%d)" % _count(Pickup.Kind.BATTERY))
	_check(_keys().size() == 3, "three keys: furnace, drawer, east wing (%d)" % _keys().size())
	var problems: PackedStringArray = _level.validate_key_graph()
	_check(problems.is_empty(), "key graph valid %s" % str(problems))

	# Waking on the floor.
	await _frames(20)
	_check(player.head.position.y < 0.7, "Jason wakes lying on the floor (eye %.2fm)" % player.head.position.y)
	_check(await _wait_for(func() -> bool: return not GameState.cutscene, 8.0), "wake-up cutscene ends")
	await _frames(90)
	_check(player.head.position.y > 1.3, "Jason gets up (eye %.2fm)" % player.head.position.y)

	# Navigation across both floors.
	var nav_map: RID = hall.nav.get_navigation_map()
	_check(_path_reaches(nav_map, Vector3(2, 0, 4.5), Vector3(8, UP, -4)), "spirits can path up the service stairs to the foyer")
	_check(_path_reaches(nav_map, Vector3(8, UP, -4), Vector3(-11.8, UP, -8.25)), "spirits can path foyer -> corridor -> library")
	_check(not _path_reaches(nav_map, Vector3(14, 0, 4.5), Vector3(19, 0, 4.5)), "locked furnace door blocks navigation")
	_check(not _path_reaches(nav_map, Vector3(14, UP, -7), Vector3(18, UP, -7)), "locked east wing door blocks navigation")
	var starts: Array[Vector3] = []
	for s in _spirits():
		starts.append(s.global_position)
	await _frames(420)
	var moved := 0
	for i in _spirits().size():
		if _spirits()[i].global_position.distance_to(starts[i]) > 0.3:
			moved += 1
	_check(moved == 3, "all three spirits patrol (%d moved)" % moved)
	_check(absf(foyer.global_position.y - UP) < 0.3 and absf(library.global_position.y - UP) < 0.3, "upstairs spirits stay on the upper floor")

	# Lit areas: moonlit room, furnace, candles, library desk.
	_check(GameState.is_lit(Vector3(-3, 0, 4.6)), "abandoned room is lit (moonlight)")
	_check(GameState.is_lit(Vector3(20.5, 0, 4.5)), "furnace glow is lit")
	_check(GameState.is_lit(Vector3(5.5, UP, -6.5)), "foyer candles are lit")
	_check(GameState.is_lit(Vector3(-7.0, UP, -13.0)), "library desk is lit")
	_check(not GameState.is_lit(Vector3(8, 0, 4.5)), "servants' hall is dark")

	# --- 1. Abandoned room ------------------------------------------------------
	_find_pickup(Pickup.Kind.FLASHLIGHT).interact(player)
	await _frames(2)
	_check(player.flashlight.owned and player.flashlight.on, "flashlight picked up and on")
	var before := player.flashlight.battery
	await _frames(120)
	var drained := before - player.flashlight.battery
	var expected := 200.0 / player.flashlight.normal_life_seconds
	_check(absf(drained - expected) < expected * 0.4, "battery drain matches tuning (%.2f%% in 2s)" % drained)

	var stuck_door := _door_between("abandoned_room", "servants_hall")
	stuck_door.interact(player)
	await _frames(2)
	_check(not stuck_door.is_open, "abandoned room door is stuck on the first try")
	stuck_door.interact(player)
	await _frames(40)
	_check(stuck_door.is_open, "second push forces it open")

	# --- System checks with only the hall spirit awake --------------------------
	foyer.process_mode = Node.PROCESS_MODE_DISABLED
	library.process_mode = Node.PROCESS_MODE_DISABLED
	player.flashlight.set_on(false)
	_place(player, Vector3(8, 0, 4.5), 0.0)
	hall.global_position = Vector3(20, 0, 4.5)  # out of the way (furnace room is locked)
	hall.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(120)
	_check(player.flashlight.exposure > 1.5, "darkness exposure builds (%.1fs)" % player.flashlight.exposure)
	player.flashlight.set_on(true)
	var exposure := player.flashlight.exposure
	await _frames(60)
	_check(player.flashlight.exposure < exposure, "exposure decays in light")
	var wardrobe: HidingSpot = GameState.hiding_spots[0]
	wardrobe.interact(player)
	await _frames(5)
	_check(player.hidden and not player.flashlight.on, "hiding in a wardrobe")
	wardrobe.leave(player)
	await _frames(5)
	player.flashlight.set_on(true)  # hiding switched it off
	hall.process_mode = Node.PROCESS_MODE_INHERIT
	hall.global_position = Vector3(12, 0, 4.5)
	hall._enter_patrol()
	GameState.emit_noise(Vector3(10, 0, 4.5), 6.0)
	_check(hall.state == Spirit.State.INVESTIGATE, "noise draws the hall spirit")

	# --- 2/3. Furnace key, furnace room, flashback, the block ---------------------
	var furnace_door := _door_between("servants_hall", "furnace_room")
	_check(furnace_door.locked, "furnace door starts locked")
	_find_key("furnace_key").interact(player)
	furnace_door.interact(player)
	await _frames(40)
	_check(not furnace_door.locked and furnace_door.is_open, "furnace key opens the furnace room")
	_place(player, Vector3(19.5, 0, 4.5), -PI / 2.0)
	_find_pickup(Pickup.Kind.ID).interact(player)
	await _frames(10)
	_check(GameState.has_item("id") and GameState.cutscene, "ID plays flashback 1")
	_check(await _wait_for(func() -> bool: return not GameState.cutscene, 25.0), "flashback ends")
	await _frames(5)
	_check(hall.state == Spirit.State.BLOCK, "the spirit blocks the furnace door (state %s)" % Spirit.State.keys()[hall.state])
	await _wait_for(func() -> bool: return hall.global_position.distance_to(_level.FURNACE_BLOCK) < 0.8, 6.0)
	await _frames(30)
	_check(hall.state == Spirit.State.BLOCK, "it stays in the doorway instead of giving up")
	_place(player, Vector3(18.2, 0, 4.5), PI / 2.0, -0.12)  # face west, toward the door
	Input.action_press("bright")
	await _frames(100)
	Input.action_release("bright")
	_check(hall.state == Spirit.State.RETREAT, "bright beam drives it off (state %s)" % Spirit.State.keys()[hall.state])
	hall.process_mode = Node.PROCESS_MODE_DISABLED

	# --- 4. Service stairs and Daniel ------------------------------------------------
	_place(player, Vector3(10.0, 0.05, 2.6), 0.0)  # bottom of the stairs, facing north
	for i in 140:
		Input.action_press("move_forward")
		await get_tree().physics_frame
		if player.global_position.y > UP - 0.05 and player.global_position.z < -1.2:
			break
	Input.action_release("move_forward")
	_check(player.global_position.y > UP - 0.1, "walking up the service stairs reaches the foyer (y %.2f)" % player.global_position.y)
	_check(await _wait_for(func() -> bool: return GameState.cutscene, 3.0), "meeting Daniel starts at the top of the stairs")
	var director: CutsceneDirector = _level.director
	_check(await _wait_for(func() -> bool: return director.active and director.camera != null and director.camera.current, 3.0), "the meeting cuts to a third-person camera")
	_check(not player.body.first_person, "Jason's full body (head included) shows in the cutscene")
	var daniel: Daniel = _level.daniel
	_check(await _wait_for(func() -> bool: return daniel.global_position.distance_to(player.global_position) < 1.8, 25.0), "Daniel walks up to Jason")
	_check(await _wait_for(func() -> bool: return daniel.gesture == CharacterRig.Gesture.SHOW_HAND, 40.0), "Daniel shows his bandaged hand")
	await get_tree().create_timer(1.2).timeout
	var hand_y := daniel.bandaged_hand_position().y - daniel.global_position.y
	_check(hand_y > 1.05, "the hand comes up to chest height (%.2f m)" % hand_y)
	_check(await _wait_for(func() -> bool: return not GameState.cutscene, 40.0), "Daniel cutscene ends")
	_check(player.camera.current and player.body.first_person, "back to first person after the cutscene")
	var relaxed_y := daniel.bone_position("RightHand").y - daniel.global_position.y
	_check(relaxed_y < 1.0, "Daniel's arms hang relaxed, not in the A-pose (hand at %.2f m)" % relaxed_y)
	await get_tree().create_timer(6.0).timeout
	_check(_gestures_smooth(), "every gesture moves smoothly (no arm flips or snaps)")
	_check(daniel.global_position.distance_to(_level.DANIEL_WATCH) < 0.3, "Daniel goes to watch the door")
	_check(GameState.repels(daniel.global_position + Vector3(1.5, 0, 0)), "spirits keep away from Daniel")
	_check(not GameState.checkpoint.is_empty() and GameState.checkpoint_position().y > UP - 0.5, "checkpoint saved after the foyer")
	_check(_door_between("foyer", "outside").locked, "front doors are chained")

	# --- 5. Library ---------------------------------------------------------------------
	_find_pickup(Pickup.Kind.NOTE).interact(player)
	await _frames(10)
	_check(GameState.has_item("case_file_carter") and GameState.cutscene, "case file 1 opens for reading")
	_check(await _wait_for(func() -> bool: return not GameState.cutscene, 25.0), "case file closes")
	var case: DisplayCase = _level.display_case
	case.interact(player)
	_check(case.locked, "display case is locked without the drawer key")
	var east_key := _find_key("east_wing_key")
	_check(not east_key.available, "east wing key can't be taken through the glass")
	var drawer := _find_key("drawer_key")
	_check(not drawer.available, "drawer key is invisible in normal light")
	# Normal beam on it: still hidden.
	_place(player, Vector3(-14.4, UP, -11.0), deg_to_rad(10.0), -0.1)
	_aim_at(player, drawer.global_position)
	await _frames(20)
	_check(not drawer.available, "normal beam doesn't reveal it")
	Input.action_press("bright")
	await _frames(20)
	Input.action_release("bright")
	_check(drawer.available, "the bright beam reveals the drawer key")
	drawer.interact(player)
	case.interact(player)
	await _frames(5)
	_check(not case.locked and east_key.available, "drawer key opens the display case")
	library.process_mode = Node.PROCESS_MODE_INHERIT
	foyer.process_mode = Node.PROCESS_MODE_INHERIT
	_place(player, Vector3(-7.6, UP, -3.6), PI)
	east_key.interact(player)
	await _frames(3)
	_check(library.state == Spirit.State.CHASE, "taking the key sets off a chase")
	_check(foyer.state == Spirit.State.INVESTIGATE, "the noise draws the second spirit")
	_check(daniel.global_position.distance_to(_level.DANIEL_EAST_WING) < 0.3, "Daniel heads to the east wing door")
	library.process_mode = Node.PROCESS_MODE_DISABLED
	foyer.process_mode = Node.PROCESS_MODE_DISABLED

	# --- 6. East wing door ---------------------------------------------------------------
	var east_door: LockedDoor = _level.east_wing_door
	_place(player, Vector3(14.8, UP, -7.0), -PI / 2.0)
	east_door.interact(player)
	await _frames(5)
	_check(GameState.cutscene, "unlocking the east wing door starts the finale")
	_check(await _wait_for(func() -> bool: return GameState.ended, 25.0), "the moon cutscene ends Act 1")
	_check(GameState.won, "Act 1 complete")
	var moon: SpotLight3D = _level._moon_lights[0]
	_check(moon.light_color.r > moon.light_color.b, "the moon turned orange")

	# --- Checkpoint retry ------------------------------------------------------------------
	var saved: Dictionary = GameState.checkpoint
	GameState.prepare_retry()
	for child in get_children():
		child.free()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_level = _main.get_node("Level")
	await _frames(5)
	player = GameState.player
	_check(player.global_position.distance_to(saved["position"]) < 0.6, "retry puts the player back at the checkpoint")
	_check(GameState.has_item("east_wing_key") and GameState.has_item("furnace_key"), "retry keeps the inventory")
	_check(_find_key("east_wing_key") == null and _find_pickup(Pickup.Kind.ID) == null, "taken items stay taken")
	_check(not _door_between("servants_hall", "furnace_room").locked, "unlocked doors stay unlocked")
	_check(_level.daniel.global_position.distance_to(_level.DANIEL_EAST_WING) < 0.3, "Daniel is back at the east wing door")
	_check(player.flashlight.owned and player.flashlight.battery >= 55.0, "flashlight back with mercy battery (%.0f%%)" % player.flashlight.battery)
	var nearest := 1e9
	for s in _spirits():
		nearest = minf(nearest, s.global_position.distance_to(player.global_position))
	_check(nearest > 6.0, "no spirit starts on top of the player (nearest %.1fm)" % nearest)
	_check(await _wait_for(func() -> bool: return not GameState.restoring and not GameState.cutscene, 5.0), "retry fade-in finishes")

	get_tree().paused = false
	print("")
	if _failures.is_empty():
		print("ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		print("%d CHECK(S) FAILED: %s" % [_failures.size(), ", ".join(_failures)])
		get_tree().quit(1)


func _aim_at(player: Player, target: Vector3) -> void:
	var eye := player.camera.global_position
	var to := target - eye
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _path_reaches(nav_map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav_map, from, to, true)
	return path.size() > 1 and path[-1].distance_to(to) < 1.0


func _spirits() -> Array[Spirit]:
	var out: Array[Spirit] = []
	for node in get_tree().get_nodes_in_group("spirits"):
		out.append(node)
	return out


func _spirit(zone: String) -> Spirit:
	for s in _spirits():
		if s.zone == zone:
			return s
	return null


func _count(kind: Pickup.Kind) -> int:
	var n := 0
	for node in _level.get_children():
		if node is Pickup and node.kind == kind:
			n += 1
	return n


func _keys() -> Array:
	var out := []
	for node in _level.get_children():
		if node is Pickup and node.kind == Pickup.Kind.KEY:
			out.append(node)
	return out


func _find_pickup(kind: Pickup.Kind) -> Pickup:
	for node in _level.get_children():
		if node is Pickup and node.kind == kind:
			return node
	return null


func _find_key(item_id: String) -> Pickup:
	for node in _level.get_children():
		if node is Pickup and node.kind == Pickup.Kind.KEY and node.item_id == item_id:
			return node
	return null


func _door_between(a: String, b: String) -> LockedDoor:
	for node in _level.get_children():
		if node is LockedDoor and ((node.room_a == a and node.room_b == b) or (node.room_a == b and node.room_b == a)):
			return node
	return null


## Plays every gesture on a spare Jason and checks no arm bone jumps more than
## 6 cm in a 60 fps frame (the old IK flipped the elbow when the hand went behind
## the head).
func _gestures_smooth() -> bool:
	var rig := CharacterRig.new()
	rig.model_path = "res://assets/models/jason.glb"
	rig.set_process(false)
	_level.add_child(rig)
	rig.global_position = Vector3(0, -50, 0)
	var ok := true
	for gesture: String in ["idle", "touch_head", "point", "talk", "calm", "show_hand", "after_you", "startle", "idle"]:
		rig.play(gesture, rig.global_position + Vector3(-1.0, 1.2, -2.0))
		var prev := {}
		for i in 240:
			rig._process(1.0 / 60.0)
			for bone: String in ["RightLowerArm", "RightHand", "RightMiddleProximal", "LeftLowerArm", "LeftHand", "LeftMiddleProximal"]:
				var p := rig.bone_position(bone)
				if prev.has(bone) and p.distance_to(prev[bone]) > 0.06:
					print("    %s: %s jumped %.3f m at %.2fs" % [gesture, bone, p.distance_to(prev[bone]), i / 60.0])
					ok = false
				prev[bone] = p
	rig.queue_free()
	return ok

