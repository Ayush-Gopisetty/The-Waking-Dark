extends Node
## Autoload. Player settings, kept in user://settings.cfg and applied as they change.
## The pause menu and the title screen both edit them through SettingsPanel.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "game"

## Defaults; also the list of every saved setting.
const DEFAULTS := {
	"master_volume": 1.0,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov": 72.0,
	"brightness": 1.0,
	"fullscreen": false,
	"subtitles": true,
}

## 0..1, applied to the master audio bus.
var master_volume := 1.0
## A multiplier on the player's base mouse sensitivity.
var mouse_sensitivity := 1.0
var invert_y := false
## Vertical field of view in degrees.
var fov := 72.0
## 1.0 is the designed look; applied to the world environment.
var brightness := 1.0
var fullscreen := false
var subtitles := true

## Tests and capture tools turn this off so they never write the player's files.
var persist := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	apply_system()


func get_value(key: String) -> Variant:
	return get(key)


## Changes one setting, applies it, and saves.
func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown setting: %s" % key)
		return
	set(key, _clean(key, value))
	apply_system()
	changed.emit()
	save_to_disk()


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set(key, DEFAULTS[key])
	apply_system()
	changed.emit()
	save_to_disk()


## The master volume and the window mode (everything else is read by whoever uses it).
func apply_system() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	var is_full := win.mode == Window.MODE_FULLSCREEN
	if fullscreen != is_full:
		win.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


## Sets the world environment's brightness (called by whatever owns the environment).
func apply_to_environment(env: Environment) -> void:
	if env == null:
		return
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness


func load_from_disk() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		set(key, _clean(key, file.get_value(SECTION, key, DEFAULTS[key])))


func save_to_disk() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	for key: String in DEFAULTS:
		file.set_value(SECTION, key, get(key))
	file.save(PATH)


## Coerces a stored or incoming value to the right type and range (a hand-edited
## settings file must never break the game).
func _clean(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	match key:
		"master_volume":
			return clampf(float(value) if _is_number(value) else fallback, 0.0, 1.0)
		"mouse_sensitivity":
			return clampf(float(value) if _is_number(value) else fallback, 0.25, 3.0)
		"fov":
			return clampf(float(value) if _is_number(value) else fallback, 60.0, 100.0)
		"brightness":
			return clampf(float(value) if _is_number(value) else fallback, 0.6, 1.6)
		_:
			return bool(value) if value is bool else fallback


func _is_number(value: Variant) -> bool:
	return value is float or value is int
