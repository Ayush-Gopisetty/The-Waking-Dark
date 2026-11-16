extends Node
## Autoload. Shared run state: inventory, win/lose, lit zones, subtitles,
## noise events, UI sounds and the input map.

signal subtitle_requested(speaker: String, text: String, duration: float)
## A subtitle line has just appeared on screen (characters move their mouths to it).
signal line_shown(speaker: String, text: String, duration: float)
signal hint_requested(text: String, duration: float)
signal flashback_requested(fragment_id: String)
signal noise_emitted(position: Vector3, radius: float)
signal inventory_changed
signal game_ended(won: bool)
signal checkpoint_saved
signal fragment_finished(fragment_id: String)
## Third-person cutscenes ("scene" fragments): the camera cuts away from Jason's eyes.
signal scene_started(fragment_id: String)
signal scene_line(fragment_id: String, line: Dictionary)
signal scene_ended(fragment_id: String)

# Physics layers (bit values). Names are set in project.godot.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_DOOR := 4
const LAYER_INTERACT := 8
const LAYER_SPIRIT := 16

const END_SCREEN_PATH := "res://scenes/ui/end_screen.tscn"
const FRAGMENTS_PATH := "res://data/memory_fragments.json"
const LOG_PATH := "user://playtest_log.csv"

## Display names for inventory items (HUD).
const ITEM_NAMES := {
	"id": "ID: Jason Hale",
	"furnace_key": "Furnace room key",
	"case_file_carter": "Case file: E. Carter",
	"drawer_key": "Small drawer key",
	"east_wing_key": "East wing key",
}

## Spirits keep this far from Daniel (they sense the minion he carries).
const DANIEL_REPEL_RADIUS := 3.0

var player: Player = null
var inventory: Dictionary = {}
var lit_zones: Array[AABB] = []
## Patrol points by zone name; each spirit patrols its own zone.
var patrol_points: Dictionary = {}
var hiding_spots: Array[Node3D] = []
var fragments: Dictionary = {}
var darkness_exposure := 0.0
var cutscene := false
## True while a cutscene camera shows Jason from outside.
var third_person := false
var ended := false
var won := false
var elapsed := 0.0
## Where Daniel stands; Vector3.INF when he's not in the scene.
var daniel_position := Vector3.INF

# Checkpoints (in memory for now; the plan's JSON saves come later).
## Names of level nodes changed this run, so a retry can replay them.
var taken_pickups: Array[String] = []
var unlocked_doors: Array[String] = []
var checkpoint: Dictionary = {}
## True while a scene is being rebuilt from a checkpoint.
var restoring := false
var deaths_since_checkpoint := 0

var _sfx: Dictionary = {}
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_fragments()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.max_polyphony = 6
	_sfx_player.volume_db = -8.0
	add_child(_sfx_player)


func _process(delta: float) -> void:
	if not ended and not cutscene and not get_tree().paused:
		elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var win := get_window()
		if win.mode == Window.MODE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
		else:
			win.mode = Window.MODE_FULLSCREEN


## Called by the level before it builds anything. Clears the previous run.
func begin_level() -> void:
	player = null
	inventory.clear()
	lit_zones.clear()
	patrol_points.clear()
	hiding_spots.clear()
	darkness_exposure = 0.0
	cutscene = false
	ended = false
	won = false
	elapsed = 0.0
	daniel_position = Vector3.INF
	taken_pickups.clear()
	unlocked_doors.clear()
	get_tree().paused = false


## Full restart from the beginning of Act 1.
func restart() -> void:
	checkpoint.clear()
	restoring = false
	deaths_since_checkpoint = 0
	get_tree().paused = false
	get_tree().reload_current_scene()


## Reload the act and put the player back at the last checkpoint.
func retry_from_checkpoint() -> void:
	prepare_retry()
	get_tree().reload_current_scene()


func prepare_retry() -> void:
	restoring = not checkpoint.is_empty()
	deaths_since_checkpoint += 1
	get_tree().paused = false


func save_checkpoint() -> void:
	if player == null or ended:
		return
	checkpoint = {
		"position": player.global_position,
		"yaw": player.rotation.y,
		"battery": player.flashlight.battery,
		"flashlight": player.flashlight.owned,
		"inventory": inventory.duplicate(),
		"taken": taken_pickups.duplicate(),
		"doors": unlocked_doors.duplicate(),
		"elapsed": elapsed,
	}
	deaths_since_checkpoint = 0
	checkpoint_saved.emit()


func checkpoint_position() -> Vector3:
	return checkpoint.get("position", Vector3.ZERO)


## Called by the level after it is built and before the navmesh bakes.
func restore_level(level: Node) -> void:
	if not restoring:
		return
	for node_name: String in checkpoint["taken"]:
		var node := level.get_node_or_null(NodePath(node_name))
		if node != null:
			node.free()
		taken_pickups.append(node_name)
	for node_name: String in checkpoint["doors"]:
		var door := level.get_node_or_null(NodePath(node_name)) as LockedDoor
		if door != null:
			door.restore_unlocked()
		unlocked_doors.append(node_name)
	inventory = checkpoint["inventory"].duplicate()
	elapsed = checkpoint["elapsed"]


## Called by the player as it enters the tree.
func restore_player(p: Player) -> void:
	if not restoring:
		return
	p.global_position = checkpoint["position"]
	p.rotation.y = checkpoint["yaw"]
	if checkpoint["flashlight"]:
		p.flashlight.give()
	# Mercy: each death since the last checkpoint gives back more battery.
	p.flashlight.battery = minf(100.0, maxf(checkpoint["battery"], 40.0 + 15.0 * deaths_since_checkpoint))


## Called by the HUD once the retry fade-in is done.
func finish_restore() -> void:
	restoring = false
	inventory_changed.emit()


# --- Inventory ---------------------------------------------------------------

func add_item(id: String) -> void:
	inventory[id] = true
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return inventory.has(id)


# --- Patrols -------------------------------------------------------------------

func add_patrol_point(zone: String, point: Vector3) -> void:
	if not patrol_points.has(zone):
		patrol_points[zone] = []
	patrol_points[zone].append(point)


## Points for one zone; every point in the house if the zone has none.
func patrol_zone(zone: String) -> Array:
	if patrol_points.has(zone) and not patrol_points[zone].is_empty():
		return patrol_points[zone]
	var all: Array = []
	for points: Array in patrol_points.values():
		all.append_array(points)
	return all


# --- Light -------------------------------------------------------------------

func add_lit_zone(min_corner: Vector3, max_corner: Vector3) -> void:
	# Extend below the floor so a point exactly at y = 0 counts as inside.
	min_corner.y -= 1.0
	lit_zones.append(AABB(min_corner, max_corner - min_corner))


## True when the position is inside a lit area (window moonlight, furnace glow).
func near_daniel(pos: Vector3, radius: float) -> bool:
	if daniel_position == Vector3.INF or absf(pos.y - daniel_position.y) > 2.0:
		return false
	return Vector2(pos.x - daniel_position.x, pos.z - daniel_position.z).length() < radius


## True where spirits won't go because Daniel is too close.
func repels(pos: Vector3) -> bool:
	return near_daniel(pos, DANIEL_REPEL_RADIUS)


func is_lit(pos: Vector3) -> bool:
	for zone in lit_zones:
		if zone.has_point(pos):
			return true
	return false


# --- Subtitles, hints, noise, sound -------------------------------------------

func say(speaker: String, text: String, duration: float = 0.0) -> void:
	if duration <= 0.0:
		duration = maxf(2.5, text.length() * 0.065)
	subtitle_requested.emit(speaker, text, duration)


func hint(text: String, duration: float = 8.0) -> void:
	hint_requested.emit(text, duration)


func emit_noise(pos: Vector3, radius: float) -> void:
	if radius > 0.0:
		noise_emitted.emit(pos, radius)


func play_sfx(sound: String, volume_db: float = 0.0) -> void:
	if not _sfx.has(sound):
		var stream: AudioStream = null
		match sound:
			"pickup": stream = AudioGen.pickup()
			"click": stream = AudioGen.click()
			"creak": stream = AudioGen.creak()
			"rattle": stream = AudioGen.rattle()
			"flashback": stream = AudioGen.flashback()
		_sfx[sound] = stream
	var cached: AudioStream = _sfx[sound]
	if cached == null:
		return
	_sfx_player.stream = cached
	_sfx_player.volume_db = -8.0 + volume_db
	_sfx_player.play()


# --- Win / lose ----------------------------------------------------------------

func end_game(victory: bool) -> void:
	if ended:
		return
	ended = true
	won = victory
	_log_result()
	game_ended.emit(victory)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var packed: PackedScene = load(END_SCREEN_PATH)
	var scene := get_tree().current_scene
	if packed != null and scene != null:
		scene.add_child(packed.instantiate())
	get_tree().paused = true


## Appends one line per run so playtests can be compared (battery at death etc).
func _log_result() -> void:
	var battery := -1.0
	if player != null and player.flashlight.owned:
		battery = player.flashlight.battery
	var is_new := not FileAccess.file_exists(LOG_PATH)
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if file == null:
		return
	if is_new:
		file.store_line("date,result,time_s,battery_pct,exposure_s,has_id,has_east_wing_key")
	file.seek_end()
	file.store_line("%s,%s,%.1f,%.0f,%.1f,%s,%s" % [
		Time.get_datetime_string_from_system(),
		"escaped" if won else "caught",
		elapsed,
		battery,
		darkness_exposure,
		has_item("id"),
		has_item("east_wing_key"),
	])
	file.close()


# --- Setup -------------------------------------------------------------------

func _load_fragments() -> void:
	if not FileAccess.file_exists(FRAGMENTS_PATH):
		push_warning("Missing %s" % FRAGMENTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENTS_PATH))
	if parsed is Dictionary:
		fragments = parsed
	else:
		push_warning("Could not parse %s" % FRAGMENTS_PATH)


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_C, KEY_CTRL])
	_bind("interact", [KEY_E])
	_bind("flashlight", [KEY_F])
	_bind("bright", [KEY_SPACE], [MOUSE_BUTTON_RIGHT])
	_bind("debug_toggle", [KEY_F3])
	_bind("toggle_fullscreen", [KEY_F11])


func _bind(action: String, keys: Array, mouse_buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button: MouseButton in mouse_buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		InputMap.action_add_event(action, mb)
