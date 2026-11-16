class_name CutsceneDirector
extends Node3D
## Third-person cutscenes for "scene" fragments (data/memory_fragments.json).
## While a scene plays, the camera leaves Jason's eyes, his full body (head
## included) is shown, and each subtitle line picks a shot and gestures:
##
##   {"speaker": "Daniel", "text": "...", "shot": "daniel_close",
##    "daniel": "show_hand", "jason": "idle", "at": "west_door", "approach": true}
##
## Shots: wide, daniel, jason, daniel_close, jason_close, jason_right, hand, moon, door.
## Without "shot", the speaker gets an over-the-shoulder shot (narration: wide).
## Without a gesture, the speaker talks and the other one listens.
## "at" names a point from `points` for "point" gestures and the door/moon shots.
## "approach" walks Daniel up to Jason.

## Named world points for shots and pointing (filled in by the level).
var points: Dictionary[String, Vector3] = {}
var daniel: Daniel
var camera: Camera3D
var active := false

var _shot := ""
var _at := ""
var _shot_time := 0.0
var _shot_length := 3.0
var _daniel_turns := 0


func _ready() -> void:
	GameState.scene_started.connect(_on_scene_started)
	GameState.scene_line.connect(_on_scene_line)
	GameState.scene_ended.connect(_on_scene_ended)


func _on_scene_started(_fragment_id: String) -> void:
	var player := GameState.player
	if player == null or daniel == null:
		return
	active = true
	GameState.third_person = true
	var jason := player.body
	if jason != null:
		jason.first_person = false
		jason.position = Vector3.ZERO
		jason.play("idle")
	daniel.directed = true
	daniel.play("idle")
	camera = Camera3D.new()
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	_daniel_turns = 0
	_cut("wide", 4.0)
	_process(0.0)


func _on_scene_line(_fragment_id: String, line: Dictionary) -> void:
	if not active:
		return
	var player := GameState.player
	var jason := player.body
	var speaker := String(line.get("speaker", "")).to_lower()
	_at = line.get("at", "")
	var target: Vector3 = points.get(_at, Vector3.INF)

	var daniel_gesture: String = line.get("daniel", "talk" if speaker == "daniel" else "idle")
	var jason_gesture: String = line.get("jason", "talk" if speaker == "jason" else "idle")
	if daniel_gesture == "point" and target == Vector3.INF:
		target = jason.head_position()
	daniel.play(daniel_gesture, target)
	if jason != null:
		var jason_target := target
		if jason_gesture == "point" and _at.is_empty():
			jason_target = daniel.bandaged_hand_position()
		jason.play(jason_gesture, jason_target)
	if line.get("approach", false):
		var to := daniel.global_position - player.global_position
		to.y = 0.0
		var stop := player.global_position + to.normalized() * 1.5
		stop.y = daniel.global_position.y
		daniel.move_to(stop, maxf(1.5, (to.length() - 1.5) / 1.3))

	var shot: String = line.get("shot", "")
	if shot.is_empty():
		match speaker:
			"daniel":
				# Alternate between over-the-shoulder and close-up.
				shot = "daniel" if _daniel_turns % 2 == 0 else "daniel_close"
				_daniel_turns += 1
			"jason":
				shot = "jason"
			_:
				shot = "wide"
	_cut(shot, line.get("duration", 3.0))


func _on_scene_ended(_fragment_id: String) -> void:
	if not active:
		return
	active = false
	GameState.third_person = false
	var player := GameState.player
	if player != null:
		player.camera.current = true
		if player.body != null:
			player.body.first_person = true
			player.body.position = Player.BODY_OFFSET
			player.body.play("idle")
			player.body.look_target = Vector3.INF
	if daniel != null:
		daniel.directed = false
		daniel.play("idle")
	if camera != null:
		camera.queue_free()
		camera = null


func _cut(shot: String, length: float) -> void:
	_shot = shot
	_shot_time = 0.0
	_shot_length = maxf(0.5, length)


func _process(delta: float) -> void:
	if not active or camera == null:
		return
	_shot_time += delta
	var player := GameState.player
	var jason := player.body
	# Everyone looks at whoever they're talking to; Daniel keeps facing Jason.
	var d_head := daniel.head_position()
	var j_head := jason.head_position() if jason != null else player.camera.global_position
	daniel.look_target = j_head
	if jason != null:
		jason.look_target = d_head if _shot != "moon" else points.get("moon_window", d_head)
	var face := player.global_position - daniel.global_position
	if daniel.gesture == CharacterRig.Gesture.POINT and daniel.gesture_target != Vector3.INF and daniel._speed < 0.3:
		# Pointing somewhere else (even behind him): he turns most of the way toward
		# it, keeping Jason in view over his shoulder; the chest turns the rest.
		var to_point := daniel.gesture_target - daniel.global_position
		var yaw_j := atan2(-face.x, -face.z)
		var yaw_t := atan2(-to_point.x, -to_point.z)
		var diff := angle_difference(yaw_j, yaw_t)
		var turn := yaw_j + diff * 0.6 if absf(diff) > 0.6 else yaw_j
		daniel.rotation.y = lerp_angle(daniel.rotation.y, turn, minf(1.0, 2.5 * delta))
	elif face.length() > 0.1 and daniel._speed < 0.3:
		daniel.rotation.y = lerp_angle(daniel.rotation.y, atan2(-face.x, -face.z), minf(1.0, 4.0 * delta))
	elif daniel._speed >= 0.3:
		daniel.rotation.y = lerp_angle(daniel.rotation.y, atan2(-face.x, -face.z), minf(1.0, 8.0 * delta))

	var frame := _frame(_shot, d_head, j_head)
	var from: Vector3 = frame[0]
	var look: Vector3 = frame[1]
	# A slow push-in over the line.
	var push := smoothstep(0.0, 1.0, _shot_time / _shot_length) * 0.22
	from += (look - from).normalized() * push
	camera.fov = frame[2]
	camera.global_position = _unblocked(look, from)
	if not camera.global_position.is_equal_approx(look):
		camera.look_at(look, Vector3.UP)


## [camera position, look-at point, fov] for a shot.
func _frame(shot: String, d_head: Vector3, j_head: Vector3) -> Array:
	var ab := d_head - j_head
	ab.y = 0.0
	if ab.length() < 0.05:
		ab = Vector3.FORWARD
	ab = ab.normalized()
	var right := ab.cross(Vector3.UP)  # Jason's right while facing Daniel
	var gap := Vector2(d_head.x - j_head.x, d_head.z - j_head.z).length()
	# Close-ups sit off to the side so they never end up inside the other head.
	var close := minf(1.1, gap * 0.6)
	match shot:
		"daniel":
			return [j_head - ab * 0.95 + right * 0.55 + Vector3(0, 0.05, 0), d_head - Vector3(0, 0.12, 0), 40.0]
		"jason":
			return [d_head + ab * 0.95 - right * 0.55 + Vector3(0, 0.05, 0), j_head - Vector3(0, 0.12, 0), 40.0]
		"daniel_close":
			return [d_head - ab * close + right * 0.6 - Vector3(0, 0.05, 0), d_head - Vector3(0, 0.06, 0), 30.0]
		"jason_right":
			# From Jason's right, three-quarter front: shows his right hand at the back of his head.
			return [j_head + ab * 1.0 + right * 0.85 - Vector3(0, 0.05, 0), j_head - Vector3(0, 0.12, 0), 40.0]
		"jason_close":
			return [j_head + ab * close - right * 0.6 - Vector3(0, 0.05, 0), j_head - Vector3(0, 0.06, 0), 30.0]
		"hand":
			var hand := daniel.bandaged_hand_position()
			return [hand - ab * 0.8 + right * 0.3 + Vector3(0, 0.25, 0), hand + Vector3(0, 0.08, 0), 34.0]
		"moon":
			var moon: Vector3 = points.get("moon_window", d_head + Vector3(0, 2, 0))
			var back := (j_head - moon)
			back.y = 0.0
			back = back.normalized()
			return [j_head + back * 0.9 + Vector3(0, -0.1, 0) - right * 0.2, moon, 50.0]
		"door":
			var door: Vector3 = points.get(_at if not _at.is_empty() else "east_door", d_head)
			var mid := (d_head + j_head) * 0.5
			return [mid + (mid - door).normalized() * 1.6 + Vector3(0, 0.2, 0), door.lerp(mid, 0.35), 48.0]
	# Wide two-shot from whichever side has more room.
	var mid := (d_head + j_head) * 0.5
	var dist := maxf(2.2, d_head.distance_to(j_head) * 1.15)
	var side := right
	if _free_distance(mid, -right, dist) > _free_distance(mid, right, dist):
		side = -right
	return [mid + side * dist + Vector3(0, 0.05, 0), mid - Vector3(0, 0.2, 0), 50.0]


func _free_distance(from: Vector3, dir: Vector3, max_dist: float) -> float:
	var hit := _ray(from, from + dir * max_dist)
	return max_dist if hit.is_empty() else from.distance_to(hit.position)


## Pulls the camera in front of any wall between it and what it frames.
func _unblocked(look: Vector3, cam: Vector3) -> Vector3:
	var hit := _ray(look, cam)
	if hit.is_empty():
		return cam
	return hit.position + (look - cam).normalized() * 0.2


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, GameState.LAYER_WORLD | GameState.LAYER_DOOR)
	return get_world_3d().direct_space_state.intersect_ray(query)
