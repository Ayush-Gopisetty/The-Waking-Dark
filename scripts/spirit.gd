class_name Spirit
extends CharacterBody3D
## Spirit AI: patrol, investigate, chase, search, retreat.
## Senses: vision, hearing (player noise), and the darkness-exposure channel.
## It is a physical creature: walls and doors are solid to it, and it shoves
## unlocked doors open. Light is its weakness: the bright beam burns it and
## drives it off (it never dies), and it will not step into a lit area.

enum State { PATROL, INVESTIGATE, CHASE, SEARCH, RETREAT, BLOCK }

## Which patrol zone this spirit walks (see level.gd).
@export var zone := ""

@export_group("Speed (m/s)")
@export var patrol_speed := 1.2
@export var investigate_speed := 1.7
@export var chase_speed := 2.6
@export var retreat_speed := 3.6

@export_group("Senses")
@export var vision_range := 8.0
@export var vision_range_crouched := 4.0
@export var vision_half_angle_deg := 65.0
## Inside this distance it notices you regardless of facing.
@export var close_sense_range := 1.2
## Seconds in view before it commits to a chase.
@export var notice_time := 0.9
## Seconds without sight before a chase becomes a search.
@export var lose_sight_time := 2.0

@export_group("Light")
## Seconds of bright beam needed to weaken it.
@export var weaken_time := 0.8
## Seconds it stays driven off.
@export var retreat_time := 10.0
## Seconds it waits at the edge of a lit area before giving up.
@export var light_patience := 4.0

@export_group("Behaviour")
@export var catch_distance := 0.8
@export var search_time := 8.0
## Only spirits this close join a darkness hunt (so the whole house doesn't converge).
@export var hunt_range := 18.0

var state: State = State.PATROL
var weaken_progress := 0.0
var last_known := Vector3.ZERO

var _state_time := 0.0
var _wait := 0.0
var _waiting := false
var _see_time := 0.0
var _lost_time := 0.0
var _blocked_time := 0.0
var _sense_cooldown := 0.0
var _screech_cooldown := 0.0
var _sees_player := false
var _lit_by_bright := false
var _hunting := false
var _known_spot: Node3D = null
var _search_spot: Node3D = null
var _checked_spot := false
var _patrol_index := -1
var _target := Vector3.ZERO
var _has_target := false
var _started := false
var _stride := 0.0
var _block_pos := Vector3.ZERO
## Seconds a scripted block lasts before the spirit gives up (avoids soft-locks).
const BLOCK_TIMEOUT := 45.0

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var body: MonsterBody = $Body
@onready var steps: AudioStreamPlayer3D = $Steps
@onready var drone: AudioStreamPlayer3D = $Drone
@onready var voice: AudioStreamPlayer3D = $Voice


func _ready() -> void:
	GameState.noise_emitted.connect(_on_noise)
	drone.stream = AudioGen.drone()
	drone.play()
	voice.stream = AudioGen.screech()
	steps.stream = AudioGen.footstep()
	if GameState.restoring and global_position.distance_to(GameState.checkpoint_position()) < 10.0:
		var far := global_position
		var best := -1.0
		for point: Vector3 in GameState.patrol_zone(zone):
			var d := point.distance_to(GameState.checkpoint_position())
			if d > best:
				best = d
				far = point
		global_position = far


func _physics_process(delta: float) -> void:
	if GameState.ended or GameState.cutscene:
		return
	var player := GameState.player
	if player == null or not _nav_ready():
		return
	if not _started:
		_started = true
		_enter_patrol()

	_state_time += delta
	_screech_cooldown = maxf(0.0, _screech_cooldown - delta)
	_sense(delta, player)

	var speed := 0.0
	match state:
		State.PATROL: speed = _tick_patrol(delta)
		State.INVESTIGATE: speed = _tick_investigate(delta)
		State.CHASE: speed = _tick_chase(delta, player)
		State.SEARCH: speed = _tick_search(delta)
		State.RETREAT: speed = _tick_retreat(delta)
		State.BLOCK: speed = _tick_block(delta, player)
	if GameState.ended:
		return

	# Being held in the bright beam staggers it before it breaks.
	if _lit_by_bright:
		speed *= lerpf(1.0, 0.3, clampf(weaken_progress / weaken_time, 0.0, 1.0))

	_move(delta, speed)
	if _blocked_time >= light_patience and state != State.BLOCK:
		# It will not step into the light. Give up and drift off.
		if state == State.CHASE:
			_enter_search(global_position)
		else:
			_enter_patrol()
	_update_presentation(delta)


# --- Senses ------------------------------------------------------------------------

func _sense(delta: float, player: Player) -> void:
	var fl := player.flashlight
	_sees_player = _can_see(player)
	# A light shining out of a wardrobe gives the hiding place away.
	if player.hidden and fl.is_lighting() and player.hiding_spot != null \
			and state != State.RETREAT and state != State.BLOCK and _known_spot != player.hiding_spot:
		var front: Vector3 = player.hiding_spot.front_position() + Vector3(0, 1.2, 0)
		if global_position.distance_to(front) < 9.0 and _clear_line(_chest(), front):
			_known_spot = player.hiding_spot
			if state != State.CHASE:
				_enter_chase(player)
	_lit_by_bright = false
	if state == State.RETREAT:
		return

	_lit_by_bright = fl.bright_covers(_chest()) and _clear_line(fl.global_position, _chest())
	if _lit_by_bright:
		weaken_progress += delta
		if weaken_progress >= weaken_time:
			_enter_retreat(player)
			return
	else:
		weaken_progress = maxf(0.0, weaken_progress - delta * 0.5)

	# Darkness channel: long enough unlit and it knows exactly where you are.
	_hunting = not player.hidden and fl.exposure >= fl.hunt_threshold \
		and global_position.distance_to(player.global_position) <= hunt_range

	if _sees_player:
		_see_time += delta
	else:
		_see_time = maxf(0.0, _see_time - delta)

	if state == State.CHASE or state == State.BLOCK:
		return
	if _hunting or _see_time >= notice_time:
		_enter_chase(player)
	elif not player.hidden and fl.exposure >= fl.sense_threshold:
		# It senses roughly where you are and drifts that way.
		_sense_cooldown -= delta
		if _sense_cooldown <= 0.0:
			_sense_cooldown = 4.0
			var offset := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
			_enter_investigate(player.global_position + offset)


func _can_see(player: Player) -> bool:
	if player.hidden:
		return false
	var eye := global_position + Vector3(0.0, 1.7, 0.0)
	var target := player.global_position + Vector3(0.0, 0.6 if player.crouching else 1.2, 0.0)
	var to := target - eye
	var distance := to.length()
	var reach := vision_range_crouched if player.crouching else vision_range
	if distance > reach:
		return false
	if distance > close_sense_range:
		var flat := Vector3(to.x, 0.0, to.z)
		if (-global_basis.z).angle_to(flat) > deg_to_rad(vision_half_angle_deg):
			return false
	return _clear_line(eye, target)


## True when nothing solid (walls, furniture, closed doors) is between two points.
func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, GameState.LAYER_WORLD | GameState.LAYER_DOOR)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _chest() -> Vector3:
	return global_position + Vector3(0.0, 1.2, 0.0)


func _on_noise(pos: Vector3, radius: float) -> void:
	if not _started or GameState.ended or GameState.cutscene:
		return
	if state == State.CHASE or state == State.RETREAT or state == State.BLOCK:
		return
	if global_position.distance_to(pos) <= radius:
		_enter_investigate(pos)


## Called (via the "spirits" group) the moment the player climbs into a hiding spot.
func on_player_hid(spot: Node3D) -> void:
	if state == State.CHASE and (_sees_player or _lost_time < 1.0):
		_known_spot = spot  # it watched you get in


# --- States ------------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_wait = 0.0
	_waiting = false
	_blocked_time = 0.0


func _enter_patrol() -> void:
	_set_state(State.PATROL)
	_next_patrol_point()


func _enter_investigate(pos: Vector3) -> void:
	_set_state(State.INVESTIGATE)
	last_known = pos
	_go_to(pos)


func _enter_chase(player: Player) -> void:
	if _screech_cooldown <= 0.0:
		voice.play()
		_screech_cooldown = 10.0
	_set_state(State.CHASE)
	last_known = player.global_position
	_lost_time = 0.0
	_known_spot = null


func _enter_search(center: Vector3) -> void:
	_set_state(State.SEARCH)
	last_known = center
	_checked_spot = false
	_pick_search_point()


## Sends it to the far end of its patrol, out of sight (used while the screen is
## black at the start of a cutscene, so it isn't frozen at Jason's shoulder).
func banish_from(pos: Vector3) -> void:
	var best := global_position
	var best_distance := -1.0
	for point: Vector3 in GameState.patrol_zone(zone):
		var d := point.distance_to(pos)
		if d > best_distance:
			best_distance = d
			best = point
	global_position = best
	velocity = Vector3.ZERO
	_see_time = 0.0
	weaken_progress = 0.0
	_lit_by_bright = false
	_enter_patrol()


func _enter_retreat(player: Player) -> void:
	_set_state(State.RETREAT)
	weaken_progress = 0.0
	_see_time = 0.0
	_lit_by_bright = false
	last_known = player.global_position
	# Flee to whichever patrol point is farthest from the player.
	var best := global_position
	var best_distance := -1.0
	for point: Vector3 in GameState.patrol_zone(zone):
		var d := point.distance_to(player.global_position)
		if d > best_distance:
			best_distance = d
			best = point
	_go_to(best)


func _tick_patrol(delta: float) -> float:
	if not _arrived():
		return patrol_speed
	if not _waiting:
		_waiting = true
		_wait = randf_range(1.5, 3.5)
	_wait -= delta
	rotation.y += 0.6 * delta
	if _wait <= 0.0:
		_waiting = false
		_next_patrol_point()
	return 0.0


func _tick_investigate(delta: float) -> float:
	if not _arrived():
		return investigate_speed
	if not _waiting:
		_waiting = true
		_wait = 2.5
	_wait -= delta
	rotation.y += 1.1 * delta
	if _wait <= 0.0:
		_enter_patrol()
	return 0.0


func _tick_chase(delta: float, player: Player) -> float:
	if player.hidden:
		if _known_spot != null:
			# It saw you climb in. It comes straight for the door.
			var front: Vector3 = _known_spot.call("front_position")
			_go_to(front)
			if _flat_distance(front) < 0.9 or _arrived():
				_face(_known_spot.global_position - global_position, delta)
				_wait += delta
				if _wait >= 0.8:
					GameState.end_game(false)
				return 0.0
			return chase_speed
		_lost_time += delta
	else:
		_known_spot = null
		_wait = 0.0
		if _sees_player or _hunting:
			last_known = player.global_position
			_lost_time = 0.0
			var in_reach := _flat_distance(player.global_position) <= catch_distance
			if in_reach and not GameState.is_lit(player.global_position) and not GameState.repels(player.global_position):
				GameState.end_game(false)
				return 0.0
		else:
			_lost_time += delta

	_go_to(last_known)
	if _lost_time >= lose_sight_time or (_lost_time > 0.5 and _arrived()):
		_enter_search(last_known)
		return investigate_speed
	return chase_speed


func _tick_search(delta: float) -> float:
	if _state_time >= search_time:
		_enter_patrol()
		return patrol_speed
	if not _arrived():
		return investigate_speed
	if not _waiting:
		_waiting = true
		_wait = 2.8 if _search_spot != null else 1.4
	_wait -= delta
	if _search_spot != null:
		# Stand in front of the hiding spot and stare at it.
		_face(_search_spot.global_position - global_position, delta)
	else:
		rotation.y += 1.3 * delta
	if _wait <= 0.0:
		_waiting = false
		_pick_search_point()
	return 0.0


func _tick_retreat(delta: float) -> float:
	if _state_time >= retreat_time:
		_enter_search(last_known)
		return investigate_speed
	if _arrived():
		rotation.y += 2.0 * delta
		return 0.0
	return retreat_speed


## Scripted beat: stand in a doorway and refuse to move until weakened by
## the bright beam (or until BLOCK_TIMEOUT passes).
func block_at(pos: Vector3) -> void:
	_set_state(State.BLOCK)
	_block_pos = pos
	_go_to(pos)


## Scripted beat: start chasing the player right now.
func force_chase() -> void:
	if GameState.player != null:
		_enter_chase(GameState.player)


func _tick_block(delta: float, player: Player) -> float:
	if _state_time >= BLOCK_TIMEOUT:
		_enter_patrol()
		return patrol_speed
	if not _arrived():
		return chase_speed
	_face(player.global_position - global_position, delta)
	# Step forward and grab a player who walks up to it in the dark.
	if _sees_player and _flat_distance(player.global_position) < 1.6 and not GameState.is_lit(player.global_position):
		_enter_chase(player)
	return 0.0


func _next_patrol_point() -> void:
	var points := GameState.patrol_zone(zone)
	if points.is_empty():
		_has_target = false
		return
	var index := randi() % points.size()
	if points.size() > 1 and index == _patrol_index:
		index = (index + 1) % points.size()
	_patrol_index = index
	_go_to(points[index])


func _pick_search_point() -> void:
	_search_spot = null
	if not _checked_spot:
		_checked_spot = true
		var nearest: Node3D = null
		var nearest_distance := 7.0
		for spot in GameState.hiding_spots:
			var d := spot.global_position.distance_to(last_known)
			if d < nearest_distance:
				nearest_distance = d
				nearest = spot
		if nearest != null and randf() < 0.75:
			_search_spot = nearest
			var front: Vector3 = nearest.call("front_position")
			_go_to(front)
			return
	_go_to(last_known + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)))


# --- Movement ----------------------------------------------------------------------

func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0


func _go_to(pos: Vector3) -> void:
	if _has_target and _target.distance_to(pos) < 0.25:
		return
	_target = pos
	_has_target = true
	nav.target_position = NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), pos)


func _arrived() -> bool:
	return not _has_target or nav.is_navigation_finished()


func _move(delta: float, speed: float) -> void:
	var motion := Vector3.ZERO
	var blocked := false
	if speed > 0.0 and _has_target and not nav.is_navigation_finished():
		var direction := nav.get_next_path_position() - global_position
		direction.y = 0.0
		if direction.length() > 0.01:
			direction = direction.normalized()
			# Spirits will not step from darkness into a lit area, or near Daniel.
			var ahead := global_position + direction * 0.6
			var into_light := GameState.is_lit(ahead) and not GameState.is_lit(global_position)
			var into_daniel := GameState.repels(ahead) and not GameState.repels(global_position)
			if into_light or into_daniel:
				blocked = true
			else:
				motion = direction * speed
			_face(direction, delta)
	_blocked_time = _blocked_time + delta if blocked else 0.0
	# Gravity, so spirits can use the service stairs.
	var fall := 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	velocity = Vector3(motion.x, fall, motion.z)
	move_and_slide()

	# It is solid, so a closed door stops it. It shoves unlocked ones open.
	for i in get_slide_collision_count():
		var door := get_slide_collision(i).get_collider() as LockedDoor
		if door != null and not door.locked and not door.is_open:
			door.set_open(true, false)

	# Heavy footfalls you can hear coming.
	_stride += get_real_velocity().length() * delta
	if _stride >= 0.95:
		_stride = 0.0
		steps.pitch_scale = randf_range(0.5, 0.62)
		steps.play()


func _face(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	var yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, 8.0 * delta))


func _flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length()


# --- Presentation --------------------------------------------------------------------

func _update_presentation(delta: float) -> void:
	var weak := 1.0 if state == State.RETREAT else clampf(weaken_progress / weaken_time, 0.0, 1.0)
	body.animate(delta, get_real_velocity().length(), state == State.CHASE, weak)
	var chasing := state == State.CHASE
	var blend := minf(1.0, 3.0 * delta)
	drone.pitch_scale = lerpf(drone.pitch_scale, 1.35 if chasing else 1.0, blend)
	var loud := 4.0 if chasing else -2.0
	if GameState.near_daniel(global_position, 5.0):
		loud -= 14.0  # they go quiet near Daniel (they sense the minion)
	drone.volume_db = lerpf(drone.volume_db, loud, blend)
