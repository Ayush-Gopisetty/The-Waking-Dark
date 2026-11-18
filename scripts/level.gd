extends NavigationRegion3D
## Gray-box Act 1 of Ashgrove Manor (the west wing, pale moon), following
## "Act 1 in detail" in the game plan. Built in code so the layout is quick to
## change. Top-down plan (x = east, z = south, 1 unit = 1 m):
##
##  UPSTAIRS (floor at y = 1.2)
##   +-------------+                   +======[x]=====+-------+
##   |   Library   |     Corridor      |    Foyer      [EW] East |
##   | x -16..-6   =  x -6..2, z -10..-6 = x 2..16    |  wing  |
##   | z -14..-2   |                   | z -13..-1     |-------+
##   | drawer key, |                   | Daniel,       |
##   | glass case  |                   | candles       |
##   +-------------+                   +------||------+
##                                     service stairs (x ~10, z -1..3)
##  DOWNSTAIRS (floor at y = 0)          ||
##               +-----------+ +---------++------------+-----------+
##               | Abandoned | | Storage  |             |  Furnace  |
##               |   room    | | (key)    |             |   room    |
##               | x -6..0   = +----=-----+  Servants'  = x 16..22  |
##               | z 2..7    |   hall: a corridor       |  ID       |
##               +-----------+   x 0..16, z 3..6        +-----------+
##                               +----=-----+
##                               | Kitchen  |
##                               +----------+
##
## Added since the plan (not drawn above): servants' quarters (downstairs,
## x 10..16, z 6..11, off the hall); and upstairs the parlour (x 6.5..13.5,
## z -5..-1, at the top of the service stairs: candle-lit, Daniel waits here),
## the gallery (x 16..22, z -5..-1, east of the foyer), the study (x -6..2,
## z -14..-10) and the dining room (x -6..2, z -6..-2), both off the corridor.
##
## Key chain: furnace key (storage) -> furnace door (the ID); stairs key
## (servants' quarters) -> service stairs door -> parlour (Daniel); study key
## (gallery) -> study; drawer key (study shelf, only visible in the bright
## beam) -> glass display case (library); east wing key (in the case) -> east
## wing door. [x] chained front doors. tools/validate_keys.tscn checks the chain.
##
## Everything solid is a child of this node so the navmesh bakes from it.

const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.2
const DOOR_WIDTH := 1.3
const DOOR_HEIGHT := 2.1
const UPSTAIRS := 1.2
const SPIRIT_SCENE := preload("res://scenes/spirit.tscn")
const START_ROOM := "abandoned_room"
const GOAL_ROOM := "east_wing"

## Daniel waits in the parlour (candle-lit: no spirit will come in), and
## afterwards keeps watch by its door.
const DANIEL_MEET := Vector3(8.0, UPSTAIRS, -3.8)
const DANIEL_WATCH := Vector3(11.7, UPSTAIRS, -4.1)
const DANIEL_EAST_WING := Vector3(14.6, UPSTAIRS, -8.8)
const FURNACE_BLOCK := Vector3(15.2, 0.0, 4.5)

## Room name -> Rect2 on the floor plan (x, z); floor height in _room_floor.
var rooms: Dictionary = {}
var daniel: Daniel
var director: CutsceneDirector
var east_wing_door: LockedDoor
var display_case: DisplayCase

## Doorless connections (the service stairs), for the key-graph check.
var _open_links := {
	"service_stairs": ["parlour"],
	"parlour": ["service_stairs"],
}
var _room_floor: Dictionary = {}
var _y := 0.0  # floor height of the rooms currently being built
var _wall_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _ceiling_material: StandardMaterial3D
var _wood_material: StandardMaterial3D
var _flame_material: StandardMaterial3D
var _metal_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _surfaces: Dictionary = {}  # name -> StandardMaterial3D (scanned textures)
var _flicker_lights: Array[OmniLight3D] = []
var _moon_lights: Array[SpotLight3D] = []
var _moon_glass: Array[StandardMaterial3D] = []
var _pickup_count := 0
var _door_count := 0
var _time := 0.0
var _tension: AudioStreamPlayer
var _chase: AudioStreamPlayer
var _chanting: AudioStreamPlayer
var _heartbeat: AudioStreamPlayer
var _breathing: AudioStreamPlayer
var _music_on := false
var _met_daniel := false
var _case_tried_at := -1.0
var _drawer_hint_shown := false


func _ready() -> void:
	GameState.begin_level()
	_make_materials()
	_y = 0.0
	_build_abandoned_room()
	_build_servants_hall()
	_build_storage()
	_build_kitchen()
	_build_furnace_room()
	_build_servants_quarters()
	_build_service_stairs()
	_y = UPSTAIRS
	_surface("plaster", "oak")
	_build_foyer()
	_build_parlour()
	_build_gallery()
	_build_corridor()
	_build_study()
	_build_dining_room()
	_build_library()
	_build_east_wing()
	_y = 0.0
	GameState.restore_level(self)
	_bake_navigation()
	_spawn_spirit("hall", Vector3(12, 0, 4.5))
	_spawn_spirit("foyer", Vector3(14.6, UPSTAIRS, -11.2))
	_spawn_spirit("library", Vector3(-11.8, UPSTAIRS, -5.75))
	_start_audio()
	_start_dust.call_deferred()
	GameState.fragment_finished.connect(_on_fragment_finished)
	if GameState.restoring:
		_restore_story_state()


## Drifting dust motes around the player: they catch the flashlight and moonbeams.
func _start_dust() -> void:
	var player := GameState.player
	if player == null:
		return
	var motes := GPUParticles3D.new()
	motes.amount = 220
	motes.lifetime = 12.0
	motes.preprocess = 12.0
	motes.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 5, 16))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(6, 1.6, 6)
	process.gravity = Vector3(0, -0.01, 0)
	process.direction = Vector3(0.3, 0.1, 0.2)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.1
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.08
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.78, 0.85, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	motes.draw_pass_1 = quad
	motes.top_level = true  # stay in world space; follow the player below
	motes.set_script(preload("res://scripts/follow_player.gd"))
	add_child(motes)


func _process(delta: float) -> void:
	_time += delta
	for i in _flicker_lights.size():
		var light := _flicker_lights[i]
		var base: float = light.get_meta("base_energy")
		light.light_energy = base * (1.0 + 0.2 * sin(_time * 9.0 + i) * sin(_time * 3.7 + i * 2.0)) + randf_range(-0.05, 0.05) * base
	_update_music(delta)
	# A nudge if the player is stuck on the library light puzzle.
	if _case_tried_at >= 0.0 and not _drawer_hint_shown and not GameState.has_item("drawer_key") \
			and GameState.elapsed - _case_tried_at > 75.0:
		_drawer_hint_shown = true
		GameState.hint("Some things in this house only show up in a strong light.", 8.0)


# --- Downstairs --------------------------------------------------------------------

## 1. Abandoned room: wake on the floor; flashlight on the bed; the door is stuck.
func _build_abandoned_room() -> void:
	_surface("plaster", "planks")
	_room("abandoned_room", Vector2(-6, 2), Vector2(0, 7))
	_wall(Vector2(-6, 2), Vector2(0, 2))
	_wall(Vector2(-6, 7), Vector2(0, 7))
	_wall(Vector2(-6, 2), Vector2(-6, 7))
	_wall(Vector2(0, 2), Vector2(0, 7), [2.5])
	var door := _door(Vector2(0, 4.5 - DOOR_WIDTH * 0.5), -PI / 2.0, 90.0, "abandoned_room", "servants_hall")
	door.stuck = true

	# A carved bed against the north wall. The flashlight lies on the mattress
	# (moved up from under the bed during playtesting: too hard to find).
	var bed := _prop("bed", Vector3(-5.13, 0, 3.15), Vector3(1.5, 1.55, 2.06), 0.0, false)
	var mattress := Props.top_height(bed, 0.3)
	_solid(Vector3(-5.13, mattress * 0.5, 3.15), Vector3(1.5, mattress, 2.06))
	_pickup(Pickup.Kind.FLASHLIGHT, Vector3(-5.0, mattress, 3.4))
	_prop("chair", Vector3(-0.6, 0, 6.5), Vector3(0.55, 1.25, 0.55), PI + 0.5)
	_rug(Vector2(-3.4, 4.6), Vector2(2.2, 1.6))

	_window(Vector3(-5.9, 1.75, 5.6), Vector3(0.03, 1.3, 1.1))
	_moonbeam(Vector3(-5.7, 2.0, 5.6), Vector3(-2.0, 0.0, 4.4), 2.2)
	_lit(Vector3(-6, 0, 2), Vector3(0, WALL_HEIGHT, 7))
	_surface("damaged", "planks")


## 2. Servants' hall: a long corridor with side rooms. One slow spirit patrols it.
func _build_servants_hall() -> void:
	_room("servants_hall", Vector2(0, 3), Vector2(16, 6))
	_wall(Vector2(0, 3), Vector2(16, 3), [3.0, 10.0])  # north: storage, service stairs
	_wall(Vector2(0, 6), Vector2(16, 6), [7.0, 13.0])  # south: kitchen, servants' quarters

	_prop("shelf", Vector3(6.8, 0, 3.22), Vector3(0.8, 1.6, 0.22), 0.0, true, true)
	_pickup(Pickup.Kind.BATTERY, Vector3(6.8, 1.6, 3.22))  # battery #1, on top of the shelf
	_prop("crate", Vector3(15.1, 0, 5.68), Vector3(0.85, 0.36, 0.42), PI)  # crates
	Props.place(self, "crate", Vector3(15.15, _y + 0.36, 5.7), Vector3(0.85, 0.36, 0.42), PI + 0.12)
	_solid(Vector3(15.1, 0.36, 5.68), Vector3(0.9, 0.72, 0.45))
	_prop("chair", Vector3(1.4, 0, 5.62), Vector3(0.6, 1.3, 0.6), PI)
	_prop("painting", Vector3(4.6, 1.45, 3.11), Vector3(0.7, 0.55, 0.03), 0.0, false)
	_prop("painting", Vector3(11.2, 1.5, 5.89), Vector3(0.7, 0.55, 0.03), PI, false)

	# No music in the abandoned room; the tension track starts here.
	_story_trigger(Vector2(0.6, 3.4), Vector2(2.5, 5.6), "", "", func() -> void: _music_on = true)
	for point: Vector3 in [
		Vector3(1.5, 0, 4.5), Vector3(8.0, 0, 4.5), Vector3(14.5, 0, 4.5), Vector3(11.0, 0, 4.2),
	]:
		_patrol("hall", point)


## Side room off the hall. The furnace key hangs on the back wall.
func _build_storage() -> void:
	_room("storage", Vector2(1, 0), Vector2(6, 3))
	_wall(Vector2(1, 0), Vector2(6, 0))
	_wall(Vector2(1, 0), Vector2(1, 3))
	_wall(Vector2(6, 0), Vector2(6, 3))
	_door(Vector2(3.0 - DOOR_WIDTH * 0.5, 3), 0.0, -90.0, "servants_hall", "storage")
	Props.stock_bookcase(_prop("bookshelf", Vector3(1.45, 0, 1.2), Vector3(0.6, 2.0, 2.0), PI / 2.0), 11)  # shelves
	var rail := Furnishing.hook_rail(0.6)
	rail.position = Vector3(3.5, 1.2 + _y, 0.115)
	add_child(rail)
	var key := _pickup(Pickup.Kind.KEY, Vector3(3.5, 1.15, 0.2), "furnace_key", true)
	key.line = "A key on a hook. The tag says FURNACE."
	_wardrobe(Vector3(5.5, 0, 1.5), PI / 2.0)  # hiding spot 1 of the hall
	_patrol("hall", Vector3(3.2, 0, 1.4))


## Filler side room: kitchen, with a pantry to hide in.
func _build_kitchen() -> void:
	_surface("damaged", "concrete")
	_room("kitchen", Vector2(4, 6), Vector2(10, 12))
	_surface("damaged", "planks")
	_wall(Vector2(4, 12), Vector2(10, 12))
	_wall(Vector2(4, 6), Vector2(4, 12))
	_wall(Vector2(10, 6), Vector2(10, 12))
	_door(Vector2(7.0 - DOOR_WIDTH * 0.5, 6), 0.0, -90.0, "servants_hall", "kitchen")
	_furnish(Furnishing.counter(Vector3(5.6, 0.9, 0.6), _wood_material), Vector3(7.0, 0, 11.6), PI, Vector3(5.6, 0.9, 0.6))
	_furnish(Furnishing.table(Vector3(2.0, 0.8, 1.1), _wood_material), Vector3(6.6, 0, 9.0), 0.0, Vector3(2.0, 0.8, 1.1))
	_prop("chair", Vector3(5.25, 0, 9.0), Vector3(0.55, 1.2, 0.55), PI / 2.0)
	_prop("chair", Vector3(7.95, 0, 9.1), Vector3(0.55, 1.2, 0.55), -PI / 2.0 + 0.3)
	_prop("hutch", Vector3(4.42, 0, 7.6), Vector3(0.6, 2.1, 1.9), PI / 2.0)
	_furnish(Furnishing.stove(Vector3(0.8, 0.9, 0.7)), Vector3(4.45, 0, 10.2), PI / 2.0, Vector3(0.8, 0.9, 0.7))  # stove
	_wardrobe(Vector3(9.5, 0, 8.0), PI / 2.0)  # pantry: hiding spot 2 of the hall
	_patrol("hall", Vector3(5.5, 0, 7.4))
	_patrol("hall", Vector3(8.4, 0, 10.6))


## 3. Furnace room: locked with the furnace key. The ID is in the grate.
## Picking it up plays flashback 1, then the spirit blocks the door and the
## player has to drive it off with the bright beam.
func _build_furnace_room() -> void:
	_surface("brick", "concrete")
	_room("furnace_room", Vector2(16, 2), Vector2(22, 7))
	_wall(Vector2(16, 2), Vector2(22, 2))
	_wall(Vector2(16, 7), Vector2(22, 7))
	_wall(Vector2(22, 2), Vector2(22, 7))
	_wall(Vector2(16, 2), Vector2(16, 7), [2.5])
	var door := _door(Vector2(16, 4.5 - DOOR_WIDTH * 0.5), -PI / 2.0, 90.0, "servants_hall", "furnace_room", "furnace_key")
	door.locked_line = "Locked. Warmth coming through the gap under the door."

	_furnish(Furnishing.furnace(Vector3(1.0, 1.4, 1.6), _glow_material(Color(1.0, 0.4, 0.1), 2.5)), Vector3(21.4, 0, 4.5), 0.0, Vector3(1.0, 1.4, 1.6))
	_flicker(Vector3(20.4, 0.8, 4.5), Color(1.0, 0.5, 0.2), 2.4, 5.0, true)
	_lit(Vector3(18.8, 0, 2.9), Vector3(22, WALL_HEIGHT, 6.1))
	_pickup(Pickup.Kind.ID, Vector3(20.74, 0.285, 4.5))  # on the ash pan
	_surface("damaged", "planks")


## Servants' quarters, off the hall: two beds, a wardrobe to hide in, and the
## key to the service stairs on the table between the beds.
func _build_servants_quarters() -> void:
	_room("servants_quarters", Vector2(10, 6), Vector2(16, 11))
	_wall(Vector2(10, 11), Vector2(16, 11))
	_wall(Vector2(16, 7), Vector2(16, 11))  # (the furnace room's wall covers z 6..7)
	_door(Vector2(13.0 - DOOR_WIDTH * 0.5, 6), 0.0, -90.0, "servants_hall", "servants_quarters")
	for x: float in [10.95, 15.05]:
		var bed := _prop("bed", Vector3(x, 0, 9.75), Vector3(1.5, 1.55, 2.06), 0.0, false)
		var mattress := Props.top_height(bed, 0.3)
		_solid(Vector3(x, mattress * 0.5, 9.75), Vector3(1.5, mattress, 2.06))
	_furnish(Furnishing.table(Vector3(0.7, 0.7, 0.5), _wood_material), Vector3(13.0, 0, 10.6), 0.0, Vector3(0.7, 0.7, 0.5))  # table between the beds
	var key := _pickup(Pickup.Kind.KEY, Vector3(13.0, 0.71, 10.6), "stairs_key")
	key.line = "A key on a loop of string. The tag says STAIRS."
	_prop("chair", Vector3(12.0, 0, 10.5), Vector3(0.5, 1.15, 0.5), PI - 0.4)
	_rug(Vector2(13.0, 8.6), Vector2(2.0, 1.4))
	_wardrobe(Vector3(15.5, 0, 7.7), PI / 2.0)  # hiding spot 3 of the hall
	_pickup(Pickup.Kind.BATTERY, Vector3(10.5, 0.06, 6.6))
	_examinable(Vector3(10.14, 1.5, 7.6), "Look at the rota", "Jason",
		"A duty rota, still pinned up. Names and hours, and then nothing. Nobody ever took it down.",
		Vector3(0.3, 0.6, 0.8))
	_box(Vector3(10.12, 1.5, 7.6), Vector3(0.01, 0.4, 0.3), _paper_material(), false)
	_patrol("hall", Vector3(13.0, 0, 8.4))


## The service stairs from the hall up to the parlour (a ramp under the steps).
## The door at the bottom is locked; the key is in the servants' quarters.
func _build_service_stairs() -> void:
	var stairs_door := _door(Vector2(10.0 - DOOR_WIDTH * 0.5, 3), 0.0, -90.0, "servants_hall", "service_stairs", "stairs_key")
	stairs_door.locked_line = "Locked. The servants' stairs. One of the staff would have kept a key."
	_room("service_stairs", Vector2(9.35, -1), Vector2(10.65, 3), false)
	_wall(Vector2(9.35, -1), Vector2(9.35, 3), [], UPSTAIRS + WALL_HEIGHT)
	_wall(Vector2(10.65, -1), Vector2(10.65, 3), [], UPSTAIRS + WALL_HEIGHT)
	_box(Vector3(10.0, UPSTAIRS + WALL_HEIGHT + 0.1, 1.0), Vector3(1.5, 0.2, 4.2), _ceiling_material, false)
	_ramp(9.35, 10.65, 3.0, -1.0, UPSTAIRS)
	for i in 8:  # the visible steps
		var depth := 4.0 / 8.0
		var top := UPSTAIRS * (i + 1) / 8.0
		_box(Vector3(10.0, top * 0.5, 3.0 - depth * (i + 0.5)), Vector3(1.3, top, depth), _wood_material, false)


# --- Upstairs ----------------------------------------------------------------------

## 4. Foyer: dark, with two candle-lit pockets. A spirit circles it but won't
## enter the candlelight. The parlour (Daniel) opens off its south side.
func _build_foyer() -> void:
	_room("foyer", Vector2(2, -13), Vector2(16, -1))
	_wall(Vector2(2, -13), Vector2(16, -13), [11.5])  # north: chained front doors
	_wall(Vector2(2, -13), Vector2(2, -1), [5.0])     # west: corridor (z = -8)
	_wall(Vector2(16, -13), Vector2(16, -1), [6.0, 10.0])  # east: east wing (z = -7), gallery (z = -3)
	_wall(Vector2(2, -1), Vector2(16, -1), [8.0])     # south: service stairs (x = 10)

	var front := _door(Vector2(13.5 - DOOR_WIDTH * 0.5, -13), 0.0, 90.0, "foyer", "outside")
	front.sealed = true
	front.locked_line = "Chained shut from the outside. I'm not getting out this way."
	_door(Vector2(2, -8.0 - DOOR_WIDTH * 0.5), -PI / 2.0, -90.0, "foyer", "corridor")

	# Collapsed grand staircase on the north wall.
	for i in 8:
		var h := 0.2 * (i + 1)
		_box(Vector3(9.0, h * 0.5, -9.2 - i * 0.45), Vector3(3.6, h, 0.45), _wood_material)
	_solid(Vector3(8.2, 1.85, -11.4), Vector3(1.4, 0.5, 0.9))  # rubble
	var pile := Furnishing.rubble(Vector3(1.4, 0.5, 0.9), _wood_material, _surfaces["concrete"], 5)
	pile.position = Vector3(8.2, 1.85 + _y, -11.4)
	add_child(pile)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(9.0 + side * 1.85, 1.3, -10.8), Vector3(0.08, 0.9, 3.4), _wood_material, false)
	_box(Vector3(5.0, WALL_HEIGHT * 0.5, -11.0), Vector3(0.6, WALL_HEIGHT, 0.6), _wall_material)  # pillar
	_box(Vector3(12.4, WALL_HEIGHT * 0.5, -10.6), Vector3(0.6, WALL_HEIGHT, 0.6), _wall_material)  # pillar
	_furnish(Furnishing.chandelier(Vector3(1.6, 0.5, 1.2)), Vector3(12.6, 0, -8.6), 0.0, Vector3(1.6, 0.5, 1.2))  # fallen chandelier (clear of the routes past the stairs)
	_furnish(Furnishing.bench(Vector3(1.4, 1.0, 0.6), _wood_material), Vector3(14.6, 0, -2.0), 0.0, Vector3(1.4, 1.0, 0.6))    # bench
	_rug(Vector2(12.4, -7.6), Vector2(3.0, 2.2))
	_prop("painting", Vector3(16 - 0.11, 1.55, -11.2), Vector3(0.03, 0.6, 0.8), -PI / 2.0, false)

	# Candles: the safe pockets out in the foyer. One in the west half, one by
	# the east wing door. (The parlour is lit throughout.)
	_candles(Vector3(5.5, 1.05, -5.2), Vector3(3.9, 0, -8.1), Vector3(7.1, WALL_HEIGHT, -4.9))
	_furnish(Furnishing.pedestal(Vector3(0.5, 1.0, 0.5), _wood_material), Vector3(5.5, 0, -5.2), 0.0, Vector3(0.5, 1.0, 0.5))
	_candles(Vector3(15.6, 1.05, -8.6), Vector3(13.8, 0, -9.0), Vector3(16, WALL_HEIGHT, -5.4))
	_furnish(Furnishing.pedestal(Vector3(0.5, 1.0, 0.5), _wood_material), Vector3(15.6, 0, -8.6), 0.0, Vector3(0.5, 1.0, 0.5))

	# High window: pale moon now, orange when Act 1 ends.
	_window(Vector3(6.5, 2.3, -12.88), Vector3(1.0, 1.2, 0.03))
	_moonbeam(Vector3(6.5, 2.6, -12.6), Vector3(7.5, 0.0, -9.0), 1.6)

	# The mirror: Jason sees his head wound.
	_prop("mirror", Vector3(2.12, 1.1, -3.5), Vector3(0.05, 1.0, 0.7), PI / 2.0, false)
	_examinable(Vector3(2.25, 1.6, -3.5), "Look in the mirror", "Jason",
		"Is that me? There's a gash on the back of my head. Dried blood all down my neck. Somebody hit me. Hard.",
		Vector3(0.3, 1.0, 0.8))

	_wardrobe(Vector3(2.5, 0, -11.9), -PI / 2.0)  # hiding spot
	_pickup(Pickup.Kind.BATTERY, Vector3(15.3, 0.06, -12.3))  # battery #2, dark corner

	director = CutsceneDirector.new()
	add_child(director)
	director.points = {
		"west_door": Vector3(2.0, UPSTAIRS + 1.3, -8.0),
		"parlour_door": Vector3(10.0, UPSTAIRS + 1.2, -5.0),
		"east_door": Vector3(16.0, UPSTAIRS + 1.2, -7.0),
		"moon_window": Vector3(6.5, UPSTAIRS + 2.3, -12.88),
	}
	for point: Vector3 in [
		Vector3(3.2, 0, -2.4), Vector3(14.7, 0, -3.7), Vector3(3.4, 0, -10.0),
		Vector3(6.4, 0, -9.8), Vector3(13.8, 0, -11.2), Vector3(11.4, 0, -6.2),
	]:
		_patrol("foyer", point)


## The parlour, at the top of the service stairs: candle-lit from end to end,
## so no spirit comes in. Daniel is waiting here (cutscene), and keeps watch by
## the door afterwards. A safe room to come back to.
func _build_parlour() -> void:
	_rooms_add("parlour", Vector2(6.5, -5), Vector2(13.5, -1))  # (the foyer's floor and ceiling cover it)
	_wall(Vector2(6.5, -5), Vector2(13.5, -5), [3.5])  # north: the foyer (door at x = 10)
	_wall(Vector2(6.5, -5), Vector2(6.5, -1))
	_wall(Vector2(13.5, -5), Vector2(13.5, -1))
	_door(Vector2(10.0 - DOOR_WIDTH * 0.5, -5), 0.0, 90.0, "parlour", "foyer")

	_candles(Vector3(8.7, 0.9, -1.4), Vector3(6.5, 0, -5), Vector3(13.5, WALL_HEIGHT, -1))
	_furnish(Furnishing.table(Vector3(0.6, 0.9, 0.4), _wood_material), Vector3(8.7, 0, -1.4), 0.0, Vector3(0.6, 0.9, 0.4))
	_furnish(Furnishing.table(Vector3(0.8, 0.8, 0.5), _wood_material), Vector3(12.9, 0, -4.45), 0.0, Vector3(0.8, 0.8, 0.5))  # side table
	_prop("candleholders", Vector3(12.9, 0.8, -4.45), Vector3(0.7, 0.55, 0.3), 0.0, false)
	_flicker(Vector3(12.9, 1.5, -4.3), Color(1.0, 0.68, 0.38), 1.2, 4.5, true)
	_flicker(Vector3(7.4, 1.6, -3.0), Color(1.0, 0.68, 0.38), 0.8, 4.0, false)
	_prop("clock", Vector3(13.16, 0, -2.6), Vector3(0.45, 2.2, 0.65), -PI / 2.0)
	_prop("chair", Vector3(7.2, 0, -4.3), Vector3(0.6, 1.3, 0.6), 0.6)
	_prop("chair", Vector3(7.2, 0, -1.8), Vector3(0.6, 1.3, 0.6), PI - 0.6)
	_rug(Vector2(10.0, -3.2), Vector2(3.4, 2.2))
	_prop("painting", Vector3(6.61, 1.55, -3.0), Vector3(0.03, 0.6, 0.8), PI / 2.0, false)
	_prop("painting", Vector3(11.9, 1.55, -1.11), Vector3(0.8, 0.6, 0.03), PI, false)

	daniel = Daniel.new()
	add_child(daniel)
	daniel.global_position = DANIEL_MEET
	director.daniel = daniel
	_story_trigger(Vector2(8.6, -3.4), Vector2(11.4, -1.1), "", "", _meet_daniel)


## The gallery, east of the foyer: family portraits, moonlight, and the key to
## the study on a plinth at the far end. The foyer spirit wanders in here.
func _build_gallery() -> void:
	_room("gallery", Vector2(16, -5), Vector2(22, -1))
	_wall(Vector2(16, -5), Vector2(22, -5))
	_wall(Vector2(16, -1), Vector2(22, -1))
	_wall(Vector2(22, -5), Vector2(22, -1))
	_door(Vector2(16, -3.0 - DOOR_WIDTH * 0.5), -PI / 2.0, 90.0, "foyer", "gallery")
	for x: float in [17.4, 19.0, 20.6]:
		_prop("painting", Vector3(x, 1.5, -4.89), Vector3(0.9, 0.7, 0.03), 0.0, false)
		_prop("painting", Vector3(x, 1.5, -1.11), Vector3(0.9, 0.7, 0.03), PI, false)
	_examinable(Vector3(19.0, 1.5, -4.8), "Look at the portrait", "Jason",
		"A family, painted in front of this house. Someone has scratched out the faces. Every one but the child's.",
		Vector3(1.0, 0.8, 0.3))
	_furnish(Furnishing.pedestal(Vector3(0.5, 1.0, 0.5), _wood_material), Vector3(21.3, 0, -3.0), 0.0, Vector3(0.5, 1.0, 0.5))  # plinth
	var key := _pickup(Pickup.Kind.KEY, Vector3(21.3, 1.0, -3.0), "study_key")
	key.line = "A small key on a brass fob. The fob is stamped STUDY."
	_prop("chair", Vector3(16.7, 0, -1.6), Vector3(0.6, 1.3, 0.6), PI - 0.5)
	_prop("crate", Vector3(18.2, 0, -1.5), Vector3(0.85, 0.36, 0.42), PI)
	_rug(Vector2(19.0, -3.0), Vector2(4.4, 1.4))
	_window(Vector3(21.89, 2.0, -3.0), Vector3(0.03, 1.3, 1.1))
	_moonbeam(Vector3(21.7, 2.3, -3.0), Vector3(18.4, 0.0, -3.0), 1.5)
	_pickup(Pickup.Kind.BATTERY, Vector3(16.5, 0.06, -4.5))
	_patrol("foyer", Vector3(18.6, 0, -3.0))


func _build_corridor() -> void:
	_room("corridor", Vector2(-6, -10), Vector2(2, -6))
	_wall(Vector2(-6, -10), Vector2(2, -10), [6.5])  # north: study (x = 0.5)
	_wall(Vector2(-6, -6), Vector2(2, -6), [4.0])    # south: dining room (x = -2)
	_furnish(Furnishing.table(Vector3(1.2, 0.8, 0.45), _wood_material), Vector3(-2.0, 0, -9.65), 0.0, Vector3(1.2, 0.8, 0.45))  # console table
	_prop("oil_lamp", Vector3(-2.35, 0.8, -9.65), Vector3(0.2, 0.42, 0.2), 0.0, false)
	_rug(Vector2(-2.0, -8.0), Vector2(6.6, 1.1))
	_prop("painting", Vector3(-4.2, 1.45, -9.89), Vector3(0.7, 0.55, 0.03), 0.0, false)
	_prop("painting", Vector3(0.6, 1.5, -6.11), Vector3(0.6, 0.48, 0.03), PI, false)
	_patrol("library", Vector3(-1.0, 0, -8.0))
	_patrol("library", Vector3(-4.5, 0, -7.0))


## The study, off the corridor: locked (key in the gallery). The drawer key is
## tucked into its bookshelf and only shows in the bright beam.
func _build_study() -> void:
	_room("study", Vector2(-6, -14), Vector2(2, -10))
	_wall(Vector2(-6, -14), Vector2(2, -14))
	_wall(Vector2(2, -14), Vector2(2, -13))  # (the foyer's west wall covers z -13..-10)
	var door := _door(Vector2(0.5 - DOOR_WIDTH * 0.5, -10), 0.0, 90.0, "corridor", "study", "study_key")
	door.locked_line = "Locked. A brass plate on the door: STUDY."
	_furnish(Furnishing.desk(Vector3(1.8, 0.8, 0.8), _wood_material), Vector3(-2.6, 0, -13.2), 0.0, Vector3(1.8, 0.8, 0.8))  # desk
	_prop("chair", Vector3(-2.6, 0, -12.3), Vector3(0.6, 1.3, 0.6), 0.0)
	_prop("oil_lamp", Vector3(-1.95, 0.8, -13.3), Vector3(0.2, 0.42, 0.2), 0.0, false)
	_box(Vector3(-2.9, 0.805, -13.1), Vector3(0.3, 0.01, 0.22), _paper_material(), false)
	_examinable(Vector3(-2.9, 0.85, -13.1), "Read the ledger", "Jason",
		"Household accounts. Wages for a full staff, then half of them, then nobody at all. The last line isn't a number. It says: 'She won't stop humming.'",
		Vector3(0.4, 0.15, 0.3))
	Props.stock_bookcase(_prop("bookshelf", Vector3(-5.6, 0, -12.0), Vector3(0.6, 2.2, 2.2), PI / 2.0), 23, [4])  # row 4 holds the hidden key
	_prop("hutch", Vector3(1.55, 0, -11.6), Vector3(0.6, 2.1, 1.9), -PI / 2.0)
	_rug(Vector2(-2.4, -11.6), Vector2(3.0, 1.8))
	_prop("painting", Vector3(-0.6, 1.55, -13.89), Vector3(0.8, 0.6, 0.03), 0.0, false)
	_window(Vector3(-4.2, 2.0, -13.89), Vector3(1.0, 1.2, 0.03))
	_moonbeam(Vector3(-4.2, 2.3, -13.6), Vector3(-3.4, 0.0, -11.2), 1.2)

	# The drawer key: hidden on the shelf until the bright beam finds it.
	var drawer := _pickup(Pickup.Kind.KEY, Vector3(-5.22, 1.25, -12.0), "drawer_key")
	drawer.hidden_until_bright = true
	drawer.line = "A small brass key. It has to be for that glass case in the library."


## The dining room, off the corridor: still laid for dinner. A wardrobe to hide
## in and a battery; the library spirit drifts through.
func _build_dining_room() -> void:
	_room("dining_room", Vector2(-6, -6), Vector2(2, -2))
	_wall(Vector2(-6, -2), Vector2(2, -2))
	_door(Vector2(-2.0 - DOOR_WIDTH * 0.5, -6), 0.0, -90.0, "corridor", "dining_room")
	_furnish(Furnishing.table(Vector3(4.0, 0.8, 1.1), _wood_material), Vector3(-2.6, 0, -3.7), 0.0, Vector3(4.0, 0.8, 1.1))  # the table
	for x: float in [-4.0, -2.6, -1.2]:
		_prop("chair", Vector3(x, 0, -4.6), Vector3(0.5, 1.2, 0.5), 0.0)
		_prop("chair", Vector3(x + 0.15, 0, -2.8), Vector3(0.5, 1.2, 0.5), PI + 0.2)
	_prop("candleholders", Vector3(-2.6, 0.8, -3.7), Vector3(0.9, 0.6, 0.3), 0.0, false)
	_pickup(Pickup.Kind.BATTERY, Vector3(-4.2, 0.81, -3.7))
	_examinable(Vector3(-1.4, 0.9, -3.7), "Look at the table", "Jason",
		"Laid for dinner. Nobody cleared the plates. Whatever happened here, it happened in the middle of a meal.",
		Vector3(1.2, 0.3, 1.0))
	_prop("hutch", Vector3(-5.55, 0, -4.0), Vector3(0.6, 2.1, 1.9), PI / 2.0)
	_wardrobe(Vector3(1.5, 0, -3.2), PI / 2.0)  # hiding spot
	_rug(Vector2(-2.6, -3.7), Vector2(5.0, 2.6))
	_patrol("library", Vector3(-2.0, 0, -5.2))


## 5. Library: case file 1 and a child's drawing on the desk; Lily humming
## behind the wall; the east wing key in a locked glass case (the drawer key
## for it is in the study). Taking the east wing key sets off a chase back
## to the foyer.
func _build_library() -> void:
	_room("library", Vector2(-16, -14), Vector2(-6, -2))
	_wall(Vector2(-16, -14), Vector2(-6, -14))
	_wall(Vector2(-16, -2), Vector2(-6, -2))
	_wall(Vector2(-16, -14), Vector2(-16, -2))
	_wall(Vector2(-6, -14), Vector2(-6, -2), [6.0])  # east: corridor (z = -8)
	_door(Vector2(-6, -8.0 - DOOR_WIDTH * 0.5), -PI / 2.0, 90.0, "corridor", "library")

	for z: float in [-12.0, -9.5, -7.0, -4.5]:
		_solid(Vector3(-11.8, 1.2, z), Vector3(5.6, 2.4, 0.5))
		for i in 4:
			var x := -11.8 - 2.1 + i * 1.4
			for side: float in [1.0, -1.0]:
				var unit := Props.place(self, "bookshelf", Vector3(x, _y, z + side * 0.125), Vector3(1.4, 2.4, 0.25), 0.0 if side > 0.0 else PI, false, true)
				Props.stock_bookcase(unit, int(x * 10.0) + int(z * 7.0) + (3 if side > 0.0 else 0))
	_rug(Vector2(-8.8, -8.2), Vector2(1.8, 6.4))

	# Reading desk with a candle: case file 1 and a child's drawing.
	_furnish(Furnishing.desk(Vector3(1.2, 0.8, 0.7), _wood_material), Vector3(-7.0, 0, -13.3), 0.0, Vector3(1.2, 0.8, 0.7))
	var desk_candle := Furnishing.candle_cluster(_flame_material if _flame_material != null else _glow_material(Color(1.0, 0.75, 0.4), 4.0))
	desk_candle.position = Vector3(-6.6, 0.8 + _y, -13.45)
	desk_candle.scale = Vector3.ONE * 0.6
	add_child(desk_candle)
	_flicker(Vector3(-6.6, 1.1, -13.3), Color(1.0, 0.7, 0.4), 1.3, 3.6, true)
	_lit(Vector3(-8.4, 0, -14), Vector3(-6, WALL_HEIGHT, -12.0))
	var case_file := _pickup(Pickup.Kind.NOTE, Vector3(-7.25, 0.82, -13.25), "case_file_carter")
	case_file.fragment_id = "case_file_carter"
	_box(Vector3(-6.85, 0.81, -13.1), Vector3(0.2, 0.005, 0.15), _paper_material(), false)
	var drawing := _examinable(Vector3(-6.85, 0.85, -13.1), "Look at the drawing", "", "", Vector3(0.3, 0.15, 0.3))
	drawing.fragment_id = "child_drawing"

	# The glass display case with the east wing key.
	display_case = DisplayCase.new()
	display_case.key_id = "drawer_key"
	display_case.room_a = "library"
	display_case.room_b = "display_case"
	display_case.locked_line = "Locked. A tiny brass keyhole. A key that small would be kept somewhere private. A desk drawer. A study."
	display_case.position = Vector3(-7.0, _y, -3.0)
	add_child(display_case)
	_rooms_add("display_case", Vector2(-7.35, -3.25), Vector2(-6.65, -2.75))
	var east_key := _pickup(Pickup.Kind.KEY, display_case.content_position() - Vector3(0, _y, 0), "east_wing_key")
	east_key.line = "A heavy iron key. The tag reads EAST WING."
	east_key.set_available(false)
	display_case.contents = east_key
	display_case.opened.connect(func() -> void: GameState.emit_noise(display_case.global_position, 14.0))
	display_case.examined_locked.connect(func() -> void:
		if _case_tried_at < 0.0:
			_case_tried_at = GameState.elapsed)
	east_key.taken.connect(_on_east_wing_key_taken)

	_wardrobe(Vector3(-15.5, 0, -3.0), -PI / 2.0)  # hiding spot
	_pickup(Pickup.Kind.BATTERY, Vector3(-11.8, 0.06, -8.25))   # battery #3
	_pickup(Pickup.Kind.BATTERY, Vector3(-15.3, 0.06, -13.3))   # battery #4

	# Lily's first sign: humming behind the west wall.
	var hum := AudioStreamPlayer3D.new()
	hum.stream = AudioGen.humming()
	hum.position = Vector3(-16.3, _y + 1.5, -9.0)
	hum.volume_db = -14.0
	hum.unit_size = 4.0
	hum.max_distance = 14.0
	hum.autoplay = true
	add_child(hum)
	_story_trigger(Vector2(-8.4, -9.6), Vector2(-6.2, -6.4), "Jason",
		"Is someone... humming? It's coming from behind the wall.")

	for point: Vector3 in [
		Vector3(-7.6, 0, -8.6), Vector3(-7.8, 0, -5.4), Vector3(-15.3, 0, -12.6),
		Vector3(-15.3, 0, -5.8), Vector3(-11.8, 0, -10.75), Vector3(-11.8, 0, -5.75),
		Vector3(-11.8, 0, -13.1),
	]:
		_patrol("library", point)


## 6. East wing door: Daniel waits; the moon turns orange; "After you."
func _build_east_wing() -> void:
	_room("east_wing", Vector2(16, -8.5), Vector2(19, -5.5))
	_wall(Vector2(16, -8.5), Vector2(19, -8.5))
	_wall(Vector2(16, -5.5), Vector2(19, -5.5))
	_wall(Vector2(19, -8.5), Vector2(19, -5.5))
	east_wing_door = _door(Vector2(16, -7.0 - DOOR_WIDTH * 0.5), -PI / 2.0, 90.0, "foyer", "east_wing", "east_wing_key")
	east_wing_door.locked_line = "The east wing. Locked tight. Daniel said if there's a key, it's in the library."
	east_wing_door.unlocked.connect(_east_wing_finale)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.65, 0.35)  # warmer beyond: Act 2's orange moon
	glow.light_energy = 0.6
	glow.omni_range = 3.5
	glow.position = Vector3(18.0, _y + 2.2, -7.0)
	add_child(glow)


# --- Story beats --------------------------------------------------------------------

## Cutscene 3: meeting Daniel (subtitles, first person).
func _meet_daniel() -> void:
	if _met_daniel:
		return
	_met_daniel = true
	var player := GameState.player
	GameState.cutscene = true
	if player != null:
		var to := daniel.global_position - player.global_position
		var tween := create_tween().set_parallel()
		tween.tween_property(player, "rotation:y", atan2(-to.x, -to.z), 1.2).set_trans(Tween.TRANS_SINE)
		tween.tween_property(player.head, "rotation:x", 0.0, 1.2)
		await tween.finished
	var known := GameState.has_item("id")
	GameState.flashback_requested.emit("daniel_meeting" if known else "daniel_meeting_unknown")


func _on_fragment_finished(fragment_id: String) -> void:
	match fragment_id:
		"id_found":
			GameState.flashback_requested.emit("half_burned_id")  # the memory it brings back
		"half_burned_id":
			_furnace_ambush()
		"daniel_meeting", "daniel_meeting_unknown":
			daniel.move_to(DANIEL_WATCH, 5.0)  # "I'll watch the door."
			GameState.save_checkpoint()
		"east_wing_moon":
			GameState.end_game(true)


## After flashback 1: the hall spirit blocks the way back; bright mode lesson.
func _furnace_ambush() -> void:
	var spirit := _spirit_in("hall")
	if spirit == null:
		return
	spirit.global_position = Vector3(13.0, 0, 4.5)
	spirit.block_at(FURNACE_BLOCK)
	GameState.say("Jason", "Something's in the doorway. It's waiting for me.", 3.0)
	GameState.hint("Hold RIGHT MOUSE or SPACE: the bright beam burns them. Hold it on the spirit to drive it back.", 10.0)


## Taking the east wing key: the library spirit gives chase, the noise draws
## the foyer spirit in, the chanting grows, and Daniel goes to the east wing.
func _on_east_wing_key_taken() -> void:
	var library_spirit := _spirit_in("library")
	if library_spirit != null:
		library_spirit.force_chase()
	var foyer_spirit := _spirit_in("foyer")
	if foyer_spirit != null:
		foyer_spirit._enter_investigate(display_case.global_position)
	daniel.move_to(DANIEL_EAST_WING)
	if _chanting != null:
		create_tween().tween_property(_chanting, "volume_db", -20.0, 4.0)
	GameState.say("Jason", "Something's coming. Back to the foyer, to the candles!", 3.0)


## Cutscene 4: the moon turns orange at the east wing door.
func _east_wing_finale() -> void:
	GameState.cutscene = true
	var player := GameState.player
	var orange := Color(1.0, 0.55, 0.2)
	var tween := create_tween().set_parallel()
	for light in _moon_lights:
		tween.tween_property(light, "light_color", orange, 5.0)
	for glass in _moon_glass:
		tween.tween_property(glass, "emission", orange, 5.0)
	if player != null:
		var to := daniel.global_position - player.global_position
		tween.tween_property(player, "rotation:y", atan2(-to.x, -to.z), 1.5).set_trans(Tween.TRANS_SINE)
	GameState.flashback_requested.emit("east_wing_moon")


## On a checkpoint retry, put Daniel and the music where the story had them.
func _restore_story_state() -> void:
	if GameState.has_item("east_wing_key"):
		_met_daniel = true
		daniel.move_to(DANIEL_EAST_WING)
	elif GameState.checkpoint_position().y > UPSTAIRS - 0.5:
		_met_daniel = true
		daniel.move_to(DANIEL_WATCH)
	_music_on = room_at(GameState.checkpoint_position()) != START_ROOM


func _spirit_in(zone: String) -> Spirit:
	for node in get_children():
		if node is Spirit and node.zone == zone:
			return node
	return null


# --- Key graph -----------------------------------------------------------------------

## Checks the plan's rule: every key is reachable without passing the gate it
## opens, and the goal room is reachable. Returns a list of problems (empty = OK).
func validate_key_graph() -> PackedStringArray:
	var problems := PackedStringArray()
	var gates: Array = []
	var key_rooms: Dictionary = {}
	for node in get_children():
		if node.is_in_group("gates"):
			gates.append(node)
			for room: String in [node.room_a, node.room_b]:
				if room != "outside" and not rooms.has(room):
					problems.append("gate between '%s' and '%s' names an unknown room" % [node.room_a, node.room_b])
		elif node is Pickup and node.kind == Pickup.Kind.KEY:
			var room := room_at(node.global_position)
			if room.is_empty():
				problems.append("key '%s' is not inside any room" % node.item_id)
			key_rooms[node.item_id] = room

	for gate in gates:
		if gate.sealed or gate.key_id.is_empty():
			continue
		if not key_rooms.has(gate.key_id):
			problems.append("no pickup for key '%s'" % gate.key_id)
			continue
		var reached := _reachable(gates, gate)
		if not reached.has(key_rooms[gate.key_id]):
			problems.append("key '%s' (in %s) is locked behind its own gate" % [gate.key_id, key_rooms[gate.key_id]])

	if not _reachable(gates, null).has(GOAL_ROOM):
		problems.append("goal room '%s' is unreachable" % GOAL_ROOM)
	return problems


## Rooms reachable from the start, collecting keys along the way.
## `blocked` is a gate to treat as impassable.
func _reachable(gates: Array, blocked: Node) -> Dictionary:
	var reached := {START_ROOM: true}
	var keys := {}
	var changed := true
	while changed:
		changed = false
		for node in get_children():
			if node is Pickup and node.kind == Pickup.Kind.KEY and reached.has(room_at(node.global_position)):
				keys[node.item_id] = true
		for a: String in _open_links:
			if not reached.has(a):
				continue
			for b: String in _open_links[a]:
				if not reached.has(b):
					reached[b] = true
					changed = true
		for gate in gates:
			if gate == blocked or gate.sealed:
				continue
			if not gate.key_id.is_empty() and not keys.has(gate.key_id):
				continue
			var ra := reached.has(gate.room_a)
			var rb := reached.has(gate.room_b)
			if ra != rb:
				reached[gate.room_b if ra else gate.room_a] = true
				changed = true
	return reached


## The smallest room containing `pos` (floors are told apart by height).
func room_at(pos: Vector3) -> String:
	var best := ""
	var best_area := INF
	for room: String in rooms:
		var rect: Rect2 = rooms[room]
		var floor_y: float = _room_floor.get(room, 0.0)
		if pos.y < floor_y - 0.5 or pos.y > floor_y + WALL_HEIGHT:
			continue
		if rect.grow(0.05).has_point(Vector2(pos.x, pos.z)) and rect.get_area() < best_area:
			best = room
			best_area = rect.get_area()
	return best


# --- Builders (positions are relative to the current floor, _y) ----------------------

func _room(room_name: String, min_corner: Vector2, max_corner: Vector2, with_floor: bool = true) -> void:
	_rooms_add(room_name, min_corner, max_corner)
	if with_floor:
		_room_floor_and_ceiling(min_corner, max_corner)


func _rooms_add(room_name: String, min_corner: Vector2, max_corner: Vector2) -> void:
	rooms[room_name] = Rect2(min_corner, max_corner - min_corner)
	_room_floor[room_name] = _y


## A box with a mesh and (optionally) a solid collider on the world layer.
func _box(center: Vector3, size: Vector3, material: Material, solid: bool = true) -> Node3D:
	center.y += _y
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	if not solid:
		mesh.position = center
		add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.collision_layer = GameState.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(mesh)
	body.position = center
	add_child(body)
	return body


## An invisible collider on the world layer (furniture models sit inside these,
## so movement and the navmesh stay simple boxes).
func _solid(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameState.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = center + Vector3(0, _y, 0)
	add_child(body)


## A furniture model standing at `floor_point` (on the current floor), its front
## facing `yaw`, fitted into `size`. With `solid`, a matching collider too.
func _prop(model: String, floor_point: Vector3, size: Vector3, yaw: float = 0.0, solid: bool = true, by_height: bool = false) -> Node3D:
	var holder := Props.place(self, model, floor_point + Vector3(0, _y, 0), size, yaw, by_height)
	if solid:
		_solid(floor_point + Vector3(0, size.y * 0.5, 0), size)
	return holder


## A worn rug on the floor (visual only).
func _rug(center: Vector2, size: Vector2) -> void:
	_box(Vector3(center.x, 0.006, center.y), Vector3(size.x, 0.012, size.y), _surfaces["carpet"], false)


func _room_floor_and_ceiling(min_corner: Vector2, max_corner: Vector2) -> void:
	var size := max_corner - min_corner
	var mid := (min_corner + max_corner) * 0.5
	_box(Vector3(mid.x, -0.1, mid.y), Vector3(size.x, 0.2, size.y), _floor_material)
	_box(Vector3(mid.x, WALL_HEIGHT + 0.1, mid.y), Vector3(size.x + 0.4, 0.2, size.y + 0.4), _ceiling_material, false)


## Axis-aligned wall from `a` to `b` (x, z). `doorways` lists the distance from
## `a` to the centre of each door opening.
func _wall(a: Vector2, b: Vector2, doorways: Array = [], height: float = WALL_HEIGHT) -> void:
	var length := a.distance_to(b)
	var direction := (b - a) / length
	var sorted := doorways.duplicate()
	sorted.sort()
	var cursor := 0.0
	for centre: float in sorted:
		var start := centre - DOOR_WIDTH * 0.5
		var end := centre + DOOR_WIDTH * 0.5
		_wall_piece(a, direction, cursor, start, 0.0, height)
		_wall_piece(a, direction, start, end, DOOR_HEIGHT, height)  # lintel
		cursor = end
	_wall_piece(a, direction, cursor, length, 0.0, height)


func _wall_piece(a: Vector2, direction: Vector2, from: float, to: float, bottom: float, top: float) -> void:
	if to - from < 0.01:
		return
	var mid := a + direction * (from + to) * 0.5
	var along := to - from
	var size := Vector3(along, top - bottom, WALL_THICKNESS)
	if absf(direction.y) > 0.5:
		size = Vector3(WALL_THICKNESS, top - bottom, along)
	_box(Vector3(mid.x, (bottom + top) * 0.5, mid.y), size, _wall_material)
	_wall_trim(mid, direction, along, bottom, top)


## Visual-only dressing for a wall piece: skirting board, wainscot panel with a
## chair rail, and crown moulding. Pieces over a doorway only get the crown.
func _wall_trim(mid: Vector2, direction: Vector2, along: float, bottom: float, top: float) -> void:
	var across := absf(direction.y) > 0.5
	var full_height := bottom <= 0.0
	var crown_y := top - 0.06
	var layers: Array = []  # [centre_y, height, extra_thickness, material]
	if full_height:
		layers.append([0.09, 0.18, 0.05, _trim_material])  # skirting
		layers.append([0.6, 0.78, 0.015, _wood_material])  # wainscot panel
		layers.append([1.03, 0.06, 0.06, _trim_material])  # chair rail
	if top >= WALL_HEIGHT - 0.01:
		layers.append([crown_y, 0.12, 0.07, _trim_material])  # crown moulding
	for layer: Array in layers:
		var thickness: float = WALL_THICKNESS + layer[2] * 2.0
		# A few millimetres short at each end, so the trim's end faces are never in the same
		# plane as the wall's (that flickered at every doorway jamb).
		var trim_length := along - 0.008
		var size := Vector3(trim_length, layer[1], thickness)
		if across:
			size = Vector3(thickness, layer[1], trim_length)
		_box(Vector3(mid.x, layer[0], mid.y), size, layer[3], false)


## Walkable slope from z_low (floor height _y) to z_high (_y + rise), x0..x1 wide.
func _ramp(x0: float, x1: float, z_low: float, z_high: float, rise: float) -> void:
	var run := absf(z_high - z_low)
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise) + 0.3
	var body := StaticBody3D.new()
	body.collision_layer = GameState.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, 0.2, length)
	shape.shape = box
	body.add_child(shape)
	var surface_mid := Vector3((x0 + x1) * 0.5, _y + rise * 0.5, (z_low + z_high) * 0.5)
	var up := Vector3(0, cos(angle), signf(z_low - z_high) * sin(angle))
	body.position = surface_mid - up * 0.1
	body.rotation.x = angle * signf(z_low - z_high)
	add_child(body)


func _door(hinge: Vector2, closed_yaw: float, open_angle_deg: float, room_a: String, room_b: String, key_id: String = "") -> LockedDoor:
	var door := LockedDoor.new()
	_door_count += 1
	door.name = "Door%d" % _door_count  # stable names let checkpoints refer to them
	door.key_id = key_id
	door.width = DOOR_WIDTH
	door.height = DOOR_HEIGHT
	door.open_angle_deg = open_angle_deg
	door.room_a = room_a
	door.room_b = room_b
	door.position = Vector3(hinge.x, _y, hinge.y)
	door.rotation.y = closed_yaw
	add_child(door)
	door.unlocked.connect(_on_door_unlocked)
	return door


func _pickup(kind: Pickup.Kind, pos: Vector3, item_id: String = "", hanging: bool = false) -> Pickup:
	var pickup := Pickup.new()
	_pickup_count += 1
	pickup.name = "Pickup%d" % _pickup_count
	pickup.kind = kind
	pickup.item_id = item_id
	pickup.hanging = hanging
	pickup.position = pos + Vector3(0, _y, 0)
	add_child(pickup)
	return pickup


func _examinable(pos: Vector3, prompt: String, speaker: String, line: String, size: Vector3) -> Examinable:
	var e := Examinable.new()
	e.prompt = prompt
	e.speaker = speaker
	e.line = line
	e.size = size
	e.position = pos + Vector3(0, _y, 0)
	add_child(e)
	return e


func _wardrobe(pos: Vector3, yaw: float) -> HidingSpot:
	var wardrobe := HidingSpot.new()
	wardrobe.position = pos + Vector3(0, _y, 0)
	wardrobe.rotation.y = yaw
	add_child(wardrobe)
	return wardrobe


func _patrol(zone: String, point: Vector3) -> void:
	GameState.add_patrol_point(zone, point + Vector3(0, _y, 0))


func _lit(min_corner: Vector3, max_corner: Vector3) -> void:
	GameState.add_lit_zone(min_corner + Vector3(0, _y, 0), max_corner + Vector3(0, _y, 0))


func _spawn_spirit(zone: String, pos: Vector3) -> Spirit:
	var spirit: Spirit = SPIRIT_SCENE.instantiate()
	spirit.zone = zone
	spirit.name = "Spirit_" + zone.capitalize()
	spirit.position = pos
	add_child(spirit)
	return spirit


## Runs once, the first time the player walks into an area: a line of
## dialogue, a callback, or both.
func _story_trigger(min_corner: Vector2, max_corner: Vector2, speaker: String, line: String, callback: Callable = Callable()) -> void:
	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = GameState.LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size := max_corner - min_corner
	box.size = Vector3(size.x, 2.0, size.y)
	shape.shape = box
	trigger.add_child(shape)
	var mid := (min_corner + max_corner) * 0.5
	trigger.position = Vector3(mid.x, _y + 1.0, mid.y)
	trigger.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and not GameState.cutscene:
			if not line.is_empty():
				GameState.say(speaker, line)
			if callback.is_valid():
				callback.call()
			trigger.queue_free())
	add_child(trigger)


func _candles(pos: Vector3, lit_min: Vector3, lit_max: Vector3) -> void:
	if _flame_material == null:
		_flame_material = _glow_material(Color(1.0, 0.75, 0.4), 4.0)
	var cluster := Furnishing.candle_cluster(_flame_material)
	cluster.position = pos + Vector3(0, _y - 0.03, 0)
	add_child(cluster)
	_flicker(pos + Vector3(0, 0.35, 0), Color(1.0, 0.68, 0.38), 1.4, 3.8, false)
	_lit(lit_min, lit_max)


func _window(center: Vector3, size: Vector3) -> void:
	var glass := _glow_material(Color(0.55, 0.68, 1.0), 1.4)
	_moon_glass.append(glass)
	# Thin along X: a side wall (west faces +X, east faces -X); thin along Z faces +Z.
	var x_thin := size.x < size.z
	var yaw := 0.0
	if x_thin:
		yaw = PI / 2.0 if center.x < 10.0 else -PI / 2.0
	var win := Furnishing.window(Vector2(size.z if x_thin else size.x, size.y), glass)
	# Sit exactly on the inner face of the wall (so nothing is coplanar with it).
	var face := center
	if x_thin:
		face.x = roundf(center.x) + (0.5 * WALL_THICKNESS if center.x < 10.0 else -0.5 * WALL_THICKNESS)
	else:
		face.z = roundf(center.z) + 0.5 * WALL_THICKNESS
	win.position = face + Vector3(0, _y, 0)
	win.rotation.y = yaw
	add_child(win)


## Adds a Furnishing piece at a floor point (turned by yaw) with a box collider.
func _furnish(piece: Node3D, floor_point: Vector3, yaw: float, size: Vector3) -> void:
	piece.position = floor_point + Vector3(0, _y, 0)
	piece.rotation.y = yaw
	add_child(piece)
	_solid(floor_point + Vector3(0, size.y * 0.5, 0), size if absf(sin(yaw)) < 0.5 else Vector3(size.z, size.y, size.x))


## Act 1 moonlight: pale, cold blue.
func _moonbeam(from: Vector3, to: Vector3, energy: float) -> void:
	var moon := SpotLight3D.new()
	moon.light_color = Color(0.6, 0.72, 1.0)
	moon.light_energy = energy
	moon.spot_range = 10.0
	moon.spot_angle = 55.0
	moon.shadow_enabled = true
	add_child(moon)
	moon.look_at_from_position(from + Vector3(0, _y, 0), to + Vector3(0, _y, 0))
	_moon_lights.append(moon)


func _flicker(pos: Vector3, color: Color, energy: float, reach: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = shadows  # shadow budget: 1-2 shadowed lights per room
	light.position = pos + Vector3(0, _y, 0)
	light.set_meta("base_energy", energy)
	add_child(light)
	_flicker_lights.append(light)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color * 0.8
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _paper_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.72, 0.62)
	m.roughness = 0.95
	return m


func _make_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.5, 0.5))
	ramp.set_color(1, Color(1, 1, 1))
	var grime := NoiseTexture2D.new()
	grime.noise = noise
	grime.color_ramp = ramp
	grime.seamless = true
	grime.width = 256
	grime.height = 256

	var bump_noise := FastNoiseLite.new()
	bump_noise.frequency = 0.03
	bump_noise.fractal_octaves = 3
	var plaster_normal := NoiseTexture2D.new()
	plaster_normal.noise = bump_noise
	plaster_normal.as_normal_map = true
	plaster_normal.bump_strength = 2.0
	plaster_normal.seamless = true
	plaster_normal.width = 256
	plaster_normal.height = 256

	# Scanned surfaces (Poly Haven, CC0) in assets/textures, mapped in world space.
	_surfaces = {
		"plaster": _pbr("painted_plaster_wall", Color(0.8, 0.76, 0.7), 0.5),
		"damaged": _pbr("damaged_plaster", Color(0.72, 0.7, 0.66), 0.5),
		"brick": _pbr("brick_wall_10", Color(0.85, 0.8, 0.76), 0.55),
		"oak": _pbr("old_wooden_floor_02", Color(0.72, 0.66, 0.62), 0.4),
		"planks": _pbr("dark_wooden_planks", Color(0.75, 0.7, 0.66), 0.45),
		"concrete": _pbr("concrete_floor_worn_001", Color(0.62, 0.6, 0.58), 0.4),
		"carpet": _pbr("dirty_carpet", Color(0.7, 0.55, 0.5), 0.7),
	}
	_ceiling_material = _pbr("damaged_plaster", Color(0.3, 0.29, 0.28), 0.45)
	_wood_material = _pbr("dark_wooden_planks", Color(0.5, 0.38, 0.3), 0.9)
	_trim_material = _pbr("old_wooden_floor_02", Color(0.42, 0.32, 0.25), 1.2)
	_metal_material = _material(Color(0.16, 0.16, 0.17), grime)
	_metal_material.metallic = 0.6
	_metal_material.roughness = 0.6
	_metal_material.normal_enabled = true
	_metal_material.normal_texture = plaster_normal
	_metal_material.normal_scale = 0.4
	_surface("damaged", "planks")


## Picks the wall and floor surfaces for the rooms built next.
func _surface(walls: String, floor_name: String) -> void:
	_wall_material = _surfaces[walls]
	_floor_material = _surfaces[floor_name]


## A PBR material from one of the scanned texture sets. `tiles` = repeats per metre.
func _pbr(set_name: String, tint: Color, tiles: float) -> StandardMaterial3D:
	var base := "res://assets/textures/%s/%s_" % [set_name, set_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.roughness_texture = load(base + "rough_2k.jpg")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * tiles
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _material(color: Color, grime: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = grime
	material.roughness = 0.92
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)
	return material


func _bake_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.125
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.375
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.1  # under the collapsed staircase's 0.2 m steps (bodies can't climb them)
	mesh.agent_max_slope = 30.0
	mesh.region_min_size = 16.0  # drop tiny islands (tops of furniture)
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = GameState.LAYER_WORLD
	navigation_mesh = mesh
	bake_navigation_mesh(false)


## A locked door is a wall to the navmesh; once it opens, rebake (on a thread)
## so spirits can follow through it.
func _on_door_unlocked() -> void:
	if is_baking():
		await bake_finished
	bake_navigation_mesh(true)


# --- Audio --------------------------------------------------------------------------

## What the floor is made of under a point (footstep sounds).
func _surface_at(pos: Vector3) -> String:
	match room_at(pos):
		"abandoned_room", "servants_hall", "storage", "kitchen":
			return "concrete"
		"furnace_room":
			return "metal"
		"service_stairs":
			return "stairs"
		"library", "study":
			return "carpet"
	return "wood"


func _start_audio() -> void:
	GameState.surface_provider = _surface_at
	var ambience := AudioStreamPlayer.new()
	ambience.stream = AudioGen.ambience()
	ambience.volume_db = -22.0
	add_child(ambience)
	ambience.play()

	# Recorded wind through the house, over the low room tone.
	var wind_stream := SoundBank.loop("ambience/wind_loop.wav")
	if wind_stream != null:
		var wind := AudioStreamPlayer.new()
		wind.stream = wind_stream
		wind.volume_db = -14.0
		add_child(wind)
		wind.play()

	# Jason's own body: a heartbeat that quickens as a spirit closes in, and his
	# breathing when he runs out of breath or hides with one nearby.
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = AudioGen.heartbeat()
	_heartbeat.volume_db = -60.0
	add_child(_heartbeat)
	_heartbeat.play()
	_breathing = AudioStreamPlayer.new()
	_breathing.stream = AudioGen.breathing()
	_breathing.volume_db = -60.0
	add_child(_breathing)
	_breathing.play()

	# Father Crane's chanting: faint from the start, louder after the library.
	_chanting = AudioStreamPlayer.new()
	_chanting.stream = AudioGen.chanting()
	_chanting.volume_db = -20.0 if GameState.has_item("east_wing_key") else -30.0
	add_child(_chanting)
	_chanting.play()

	# Music states: none in the abandoned room; tension from the servants' hall
	# on; a chase layer while a spirit is chasing.
	_tension = AudioStreamPlayer.new()
	_tension.stream = AudioGen.tension()
	_tension.volume_db = -60.0
	add_child(_tension)
	_tension.play()
	_chase = AudioStreamPlayer.new()
	_chase.stream = AudioGen.chase()
	_chase.volume_db = -60.0
	add_child(_chase)
	_chase.play()


func _update_body_sounds(delta: float) -> void:
	var player := GameState.player
	if _heartbeat == null or player == null:
		return
	var nearest := INF
	for node in get_children():
		var spirit := node as Spirit
		if spirit != null and spirit.state != Spirit.State.RETREAT and absf(spirit.global_position.y - player.global_position.y) < 2.5:
			nearest = minf(nearest, spirit.global_position.distance_to(player.global_position))
	var fear := clampf(1.0 - (nearest - 2.0) / 9.0, 0.0, 1.0) if nearest < INF else 0.0
	var blend := minf(1.0, 2.5 * delta)
	_heartbeat.volume_db = lerpf(_heartbeat.volume_db, lerpf(-60.0, -7.0, fear * fear) if fear > 0.05 else -60.0, blend)
	_heartbeat.pitch_scale = lerpf(_heartbeat.pitch_scale, lerpf(0.9, 1.6, fear), blend)
	var out_of_breath := player.exhausted or (player.sprinting and player.stamina < 0.5)
	var held_breath := player.hidden and fear > 0.3
	var breathing_db := -60.0
	if out_of_breath:
		breathing_db = -8.0
	elif held_breath:
		breathing_db = -18.0 + 8.0 * fear
	_breathing.volume_db = lerpf(_breathing.volume_db, breathing_db, blend)
	_breathing.pitch_scale = lerpf(_breathing.pitch_scale, 1.35 if out_of_breath else 1.0, blend)


func _update_music(delta: float) -> void:
	_update_body_sounds(delta)
	if _tension == null:
		return
	var chasing := false
	for node in get_children():
		if node is Spirit and node.state == Spirit.State.CHASE:
			chasing = true
			break
	var blend := minf(1.0, 1.5 * delta)
	_tension.volume_db = lerpf(_tension.volume_db, -22.0 if _music_on else -60.0, blend * 0.5)
	_chase.volume_db = lerpf(_chase.volume_db, -12.0 if chasing else -60.0, blend)
