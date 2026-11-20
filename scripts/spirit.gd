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
# Light-reaction sounds (see _make_sounds).
var _fx_a: AudioStreamPlayer3D
var _fx_b: AudioStreamPlayer3D
var _burn_loop: AudioStreamPlayer3D
## The ground velocity it has built up (see _move).
var _ground := Vector3.ZERO
var _last_yaw := 0.0
var _snd_hiss: AudioStream
var _snd_thump: AudioStream
var _snd_rush: AudioStream
var _snd_whisper: AudioStream
var _breath_idle: AudioStreamPlayer3D
var _breath_hunt: AudioStreamPlayer3D
var _drone_gap := 0.0
var _drone_quiet := 0.0
var _edge_hissed := false
var _whisper_cooldown := 3.0
var _sees_player := false
var _lit_by_bright := false
var _was_bright := false
var _knock := Vector3.ZERO
var _shove_cooldown := 0.0
var _blocked_by_light := false
var _blocked_by_daniel := false
var _hunting := false
var _known_spot: Node3D = null
var _search_spot: Node3D = null
var _checked_spot := false
var _patrol_index := -1
var _target := Vector3.ZERO
var _has_target := false
var _started := false
var _notice_left := 0.0
var _catching := false
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
	voice.stream = SoundBank.pick("spirit", "shriek")
	_make_sounds()
	body.foot_planted.connect(_on_foot_planted)
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


## The sounds a spirit makes around light: a flinch, burning static while the beam
## holds, a thud and a rush of smoke when it breaks, a wounded keen as it flees, a
## suppressed hiss at the edge of candlelight and a hush near Daniel.
func _make_sounds() -> void:
	_snd_hiss = AudioGen.hiss()
	_snd_thump = AudioGen.thump()
	_snd_rush = AudioGen.smoke_rush()
	_snd_whisper = AudioGen.whisper()
	_fx_a = _fx_player(1.6, 6.0, 30.0)
	_fx_b = _fx_player(1.4, 6.0, 30.0)
	_burn_loop = _fx_player(1.4, 4.0, 20.0)
	_burn_loop.stream = AudioGen.crackle()
	_burn_loop.volume_db = -60.0
	_burn_loop.play()
	# Its breathing: a slow rasp while it patrols, a heavy hunting breath in a chase.
	_breath_idle = _breath_player("spirit/breath_idle.wav", -20.0)
	_breath_hunt = _breath_player("spirit/breath_hunt.wav", -60.0)


func _breath_player(path: String, volume_db: float) -> AudioStreamPlayer3D:
	var p := _fx_player(1.7, 3.0, 16.0)
	p.stream = SoundBank.loop(path)
	p.volume_db = volume_db
	if p.stream != null:
		p.play(randf() * 5.0)
	return p


func _fx_player(height: float, unit: float, distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.position = Vector3(0, height, 0)
	p.unit_size = unit
	p.max_distance = distance
	add_child(p)
	return p


func _play_fx(player: AudioStreamPlayer3D, stream: AudioStream, volume_db: float, pitch := 1.0) -> void:
	if stream == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Cuts the shriek off short, with a quick fade so it sounds torn away, not clipped.
func _cut_voice() -> void:
	if voice != null and voice.playing:
		var tween := create_tween()
		tween.tween_property(voice, "volume_db", -40.0, 0.1)
		tween.tween_callback(voice.stop)


func _play_keen() -> void:
	if state == State.RETREAT:
		_play_fx(_fx_b, SoundBank.pick("spirit", "pained"), 0.0, randf_range(0.85, 0.95))  # a pained, gasping cry as it flees


func _physics_process(delta: float) -> void:
	if GameState.ended:
		return
	if _catching:
		_tick_catch(delta)
		return
	if GameState.cutscene:
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
	# On patrol, don't stand at the edge of a light: pick another point soon.
	if state == State.PATROL and (_blocked_by_light or _blocked_by_daniel) and _blocked_time >= 1.2:
		_blocked_time = 0.0
		_next_patrol_point()
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
	_shove_cooldown = maxf(0.0, _shove_cooldown - delta)
	if _lit_by_bright and not _was_bright and _shove_cooldown <= 0.0:
		_shove(player, 1.6)  # the beam hits: it is pushed back a little
	_was_bright = _lit_by_bright
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
	var first_sight := state != State.CHASE
	if _screech_cooldown <= 0.0:
		voice.stream = SoundBank.pick("spirit", "shriek")
		voice.pitch_scale = randf_range(0.92, 1.08)
		voice.volume_db = 3.0
		voice.play()
		_screech_cooldown = 10.0
	_set_state(State.CHASE)
	last_known = player.global_position
	_lost_time = 0.0
	_known_spot = null
	if first_sight:
		_notice_left = 0.7  # the notice beat: it freezes, snaps its head round and opens its jaw


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


## The light throws it back, away from the player, in a smear of smoke.
func _shove(player: Player, strength: float) -> void:
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = -global_basis.z
	_knock = away.normalized() * strength * 0.6
	_shove_cooldown = 1.5
	body.push_back()
	_play_fx(_fx_a, _snd_hiss, 2.0)  # a sharp intake, then the shriek, cut off as if torn
	if not voice.playing:
		voice.stream = SoundBank.pick("spirit", "snarl")
		voice.pitch_scale = randf_range(1.1, 1.25)
		voice.volume_db = 2.0
		voice.play()
		get_tree().create_timer(0.35).timeout.connect(_cut_voice)


func _enter_retreat(player: Player) -> void:
	_set_state(State.RETREAT)
	_play_fx(_fx_a, _snd_thump, 4.0)
	_play_fx(_fx_b, _snd_rush, 0.0)
	_drone_gap = 0.7  # the drone cuts out as it breaks
	_drone_quiet = 18.0  # and comes back weaker
	get_tree().create_timer(0.6).timeout.connect(_play_keen)
	weaken_progress = 0.0
	_see_time = 0.0
	_lit_by_bright = false
	last_known = player.global_position
	# Flee to a patrol point well away from the player, by a route that doesn't pass
	# close to them (so it never runs at the player on its way out).
	var map := nav.get_navigation_map()
	var best := global_position
	var best_distance := -1.0
	var fallback := global_position
	var fallback_distance := -1.0
	for point: Vector3 in GameState.patrol_zone(zone):
		var d := point.distance_to(player.global_position)
		if d > fallback_distance:
			fallback_distance = d
			fallback = point
		var route := NavigationServer3D.map_get_path(map, global_position, point, true)
		var passes_player := false
		for i in route.size():
			var a2 := route[maxi(i - 1, 0)]
			var closest := Geometry3D.get_closest_point_to_segment(player.global_position, a2, route[i])
			if closest.distance_to(player.global_position) < 2.2:
				passes_player = true
				break
		if not passes_player and d > best_distance:
			best_distance = d
			best = point
	if best_distance < 0.0:
		best = fallback
	_go_to(best)


func _tick_patrol(delta: float) -> float:
	if not _arrived():
		return patrol_speed
	if not _waiting:
		_waiting = true
		_wait = randf_range(1.5, 3.5)
	_wait -= delta
	_look_around(delta, 0.5)
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
	_look_around(delta, 0.8)
	if _wait <= 0.0:
		_enter_patrol()
	return 0.0


func _tick_chase(delta: float, player: Player) -> float:
	if _notice_left > 0.0:
		_notice_left -= delta
		_face(player.global_position - global_position, delta, 7.0)
		return 0.0
	if player.hidden:
		if _known_spot != null:
			# It saw you climb in. It comes straight for the door.
			var front: Vector3 = _known_spot.call("front_position")
			_go_to(front)
			if _flat_distance(front) < 0.9 or _arrived():
				_face(_known_spot.global_position - global_position, delta)
				_wait += delta
				if _wait >= 0.8:
					_catch(player)
				return 0.0
			return chase_speed
		_lost_time += delta
	else:
		_known_spot = null
		_wait = 0.0
		if _sees_player or _hunting:
			last_known = player.global_position
			_lost_time = 0.0
			var distance := _flat_distance(player.global_position)
			# Close enough to swing at: the arm lashes out before it can grab.
			if distance < 1.7 and not body.is_striking() and not _blocked_by_light:
				body.strike()
				_play_fx(_fx_b, _snd_hiss, -6.0, 1.3)
			var in_reach := distance <= catch_distance
			if in_reach and not GameState.is_lit(player.global_position) and not GameState.repels(player.global_position):
				_catch(player)
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
		_look_around(delta, 0.9)
	if _wait <= 0.0:
		_waiting = false
		_pick_search_point()
	return 0.0


func _tick_retreat(delta: float) -> float:
	if _state_time >= retreat_time:
		# Recovering: a weak, rasping voice before it comes looking again.
		_play_fx(_fx_b, SoundBank.pick("spirit", "weak"), -2.0, 0.9)
		_enter_search(last_known)
		return investigate_speed
	if _arrived():
		# Cowering where it fled to, turned away from the light.
		var away := global_position - last_known
		away.y = 0.0
		if away.length() > 0.1:
			_face(away, delta, 2.5)
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


## It has you. The game holds for a beat: Jason's view swings up to its face while it
## rears up with its arms raised and its jaw wide, shrieks, and then the run ends.
func _catch(player: Player) -> void:
	if _catching or GameState.ended:
		return
	_catching = true
	body.strike()  # (no-op if the swing has already started)
	GameState.cutscene = true  # freezes Jason and the other spirits
	velocity = Vector3.ZERO
	voice.stream = SoundBank.pick("spirit", "shriek")
	voice.pitch_scale = 0.85
	voice.volume_db = 8.0
	voice.play()
	_play_fx(_fx_a, _snd_thump, 4.0)
	if not player.hidden:
		var face := global_position + Vector3(0, 1.85, 0)
		var eye := player.camera.global_position
		var d := face - eye
		var tween := create_tween().set_parallel(true)
		tween.tween_property(player, "rotation:y", player.rotation.y + angle_difference(player.rotation.y, atan2(-d.x, -d.z)), 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(player.head, "rotation:x", clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2), 0.35).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(1.3).timeout.connect(func() -> void: GameState.end_game(false))


func _tick_catch(delta: float) -> void:
	velocity = Vector3.ZERO
	var player := GameState.player
	if player != null:
		_face(player.global_position - global_position, delta, 8.0)
	_update_presentation(delta)


func _next_patrol_point() -> void:
	var points := GameState.patrol_zone(zone)
	if points.is_empty():
		_has_target = false
		return
	# Points inside a lit area can't be reached (it won't step into light): skip them.
	var open: Array[int] = []
	for i in points.size():
		if not GameState.is_lit(points[i]) and not GameState.repels(points[i]) and i != _patrol_index:
			open.append(i)
	var index: int
	if open.is_empty():
		index = randi() % points.size()
		if points.size() > 1 and index == _patrol_index:
			index = (index + 1) % points.size()
	else:
		index = open[randi() % open.size()]
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
	var blocked_by_light := false
	var blocked_by_daniel := false
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
				blocked_by_light = into_light
				if into_daniel and not into_light:
					# It stops and turns its back on Daniel. (It does not back away: stepping
					# out of his radius and straight back in made it shudder on the edge.)
					var away := global_position - GameState.daniel_position
					away.y = 0.0
					if away.length() > 0.01:
						direction = away.normalized()
					blocked_by_daniel = true
			else:
				motion = direction * speed
			_face(direction, delta, 2.5 if blocked_by_daniel else (4.0 if state == State.RETREAT else (8.0 if state == State.CHASE else 5.0)))
	_blocked_by_light = blocked and blocked_by_light
	_blocked_by_daniel = blocked and blocked_by_daniel
	if _blocked_by_light and _blocked_time > 0.35 and not _edge_hissed and state != State.RETREAT:
		_edge_hissed = true
		_play_fx(_fx_a, _snd_hiss, -10.0, 0.6)  # drawing back from the light: a low, held-in hiss
	elif not _blocked_by_light:
		_edge_hissed = false
	_blocked_time = _blocked_time + delta if blocked else 0.0
	# Gravity, so spirits can use the service stairs.
	var fall := 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	# It gathers speed and slows down like something with weight, instead of starting
	# and stopping dead; it is quicker to react while hunting or fleeing.
	var accel := 6.0 if (state == State.CHASE or state == State.RETREAT) else 2.6
	_ground = _ground.move_toward(motion, accel * delta)
	velocity = Vector3(_ground.x + _knock.x, fall, _ground.z + _knock.z)
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
	move_and_slide()

	# It is solid, so a closed door stops it. It shoves unlocked ones open.
	for i in get_slide_collision_count():
		var door := get_slide_collision(i).get_collider() as LockedDoor
		if door != null and not door.locked and not door.is_open:
			door.set_open(true, false)


## A foot came down in the walk animation: the heavy footfall you hear coming.
func _on_foot_planted(strength: float) -> void:
	var step_sound := SoundBank.pick("steps", GameState.surface_at(global_position))
	if step_sound != null:
		steps.stream = step_sound
	steps.volume_db = lerpf(-6.0, 4.0, strength)
	steps.pitch_scale = randf_range(0.55, 0.7) * (0.75 if _lit_by_bright else 1.0)  # dragging in the beam
	steps.play()


## Points the head at what it is paying attention to: the player in a chase (and at the
## notice beat), where it heard something, the hiding place it is checking, or, on patrol,
## the player if they are close and in front of it, otherwise the way ahead.
func _track_with_head() -> void:
	var player := GameState.player
	var target := Vector3.INF
	var weight := 0.0
	match state:
		State.CHASE, State.BLOCK:
			if player != null:
				target = player.camera.global_position
				weight = 1.0
		State.INVESTIGATE:
			target = last_known + Vector3(0, 1.5, 0)
			weight = 0.7
		State.SEARCH:
			target = (_search_spot.global_position + Vector3(0, 1.0, 0)) if _search_spot != null else last_known + Vector3(0, 1.5, 0)
			weight = 0.5
		State.PATROL:
			if player != null and _flat_distance(player.global_position) < 7.0 and _sees_player:
				target = player.camera.global_position
				weight = 0.6
			elif _has_target and not nav.is_navigation_finished():
				target = nav.get_next_path_position() + Vector3(0, 1.6, 0)
				weight = 0.25
	if _catching and player != null:
		target = player.camera.global_position
		weight = 1.0
	if target == Vector3.INF:
		body.look_yaw = 0.0
		body.look_pitch = 0.0
		body.look_weight = 0.0
		return
	var to := target - global_position
	var flat := Vector2(to.x, to.z).length()
	body.look_yaw = angle_difference(rotation.y, atan2(-to.x, -to.z)) if flat > 0.2 else 0.0
	body.look_pitch = atan2(target.y - (global_position.y + 1.8), maxf(flat, 0.5))
	body.look_weight = weight


## Turns slowly left and right (never a full circle) while it waits.
func _look_around(delta: float, amount: float) -> void:
	rotation.y += cos(_state_time * 0.8) * amount * delta


func _face(direction: Vector3, delta: float, rate := 8.0) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	var yaw := atan2(-direction.x, -direction.z)
	# Eases toward the heading, but never faster than a steady turn: no sudden spins or snaps.
	var diff := angle_difference(rotation.y, yaw)
	var cap := rate * 0.55 * delta
	rotation.y += clampf(diff * minf(1.0, rate * delta), -cap, cap)


func _flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length()


# --- Presentation --------------------------------------------------------------------

func _update_presentation(delta: float) -> void:
	var weak := clampf(weaken_progress / weaken_time, 0.0, 1.0)
	if state == State.RETREAT:
		# Burning at first, then a hunched stumbling run with its arms still up.
		weak = lerpf(1.0, 0.12, clampf(_state_time / 1.5, 0.0, 1.0))
	body.stumbling = state == State.RETREAT
	body.avert_side = 1.0 if get_instance_id() % 2 == 0 else -1.0
	body.avert = 1.0 if (_blocked_by_light and _blocked_time > 0.15 and state != State.RETREAT) else 0.0
	var shy_amount := 0.0
	if GameState.daniel_position != Vector3.INF and state != State.CHASE:
		shy_amount = clampf(1.0 - _flat_distance(GameState.daniel_position) / (GameState.DANIEL_REPEL_RADIUS + 1.5), 0.0, 1.0)
	body.shy = shy_amount
	body.notice = _notice_left > 0.0
	body.catching = _catching
	_track_with_head()
	var turn_rate := angle_difference(_last_yaw, rotation.y) / maxf(delta, 0.0001)
	_last_yaw = rotation.y
	body.animate(delta, get_real_velocity().length(), state == State.CHASE, weak, turn_rate)
	var chasing := state == State.CHASE
	var blend := minf(1.0, 3.0 * delta)
	var burn := clampf(weaken_progress / weaken_time, 0.0, 1.0) if _lit_by_bright else 0.0
	var pitch := 1.35 if chasing else 1.0
	if _lit_by_bright:
		pitch = 1.0 + 0.6 * burn + sin(_state_time * 18.0) * 0.08  # the drone climbs and wobbles
	drone.pitch_scale = lerpf(drone.pitch_scale, pitch, minf(1.0, 8.0 * delta))
	var loud := 4.0 if chasing else -2.0
	if GameState.near_daniel(global_position, 5.0):
		loud -= 14.0  # they go quiet near Daniel (they sense the minion)
	_drone_gap = maxf(0.0, _drone_gap - delta)
	_drone_quiet = maxf(0.0, _drone_quiet - delta)
	if _drone_quiet > 0.0:
		loud -= 8.0
	if _drone_gap > 0.0:
		drone.volume_db = -60.0
	else:
		drone.volume_db = lerpf(drone.volume_db, loud, blend)
	# Breathing: idle while it patrols, heavy when it hunts, held in near Daniel and while burning.
	var idle_db := -20.0
	var hunt_db := -9.0 if chasing else -60.0
	if _lit_by_bright or state == State.RETREAT:
		idle_db = -34.0
		hunt_db = -60.0
	if shy_amount > 0.45:
		idle_db -= 12.0
	if chasing:
		idle_db = -60.0
	_breath_idle.volume_db = lerpf(_breath_idle.volume_db, idle_db, blend)
	_breath_hunt.volume_db = lerpf(_breath_hunt.volume_db, hunt_db, blend)
	# Burning static grows while the beam holds on it.
	var burn_db := lerpf(-34.0, -3.0, burn) if _lit_by_bright else -60.0
	_burn_loop.volume_db = lerpf(_burn_loop.volume_db, burn_db, minf(1.0, 12.0 * delta))
	# Near Daniel it hushes: a breath of whisper now and then.
	_whisper_cooldown -= delta
	if shy_amount > 0.45 and _whisper_cooldown <= 0.0 and not _fx_b.playing:
		_whisper_cooldown = randf_range(5.0, 9.0)
		_play_fx(_fx_b, _snd_whisper, -10.0, randf_range(0.85, 1.0))
