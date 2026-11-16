class_name Flashlight
extends SpotLight3D
## Two-mode flashlight, battery, and the darkness-exposure timer.

@export_group("Battery")
## Seconds a full battery lasts in normal mode.
@export var normal_life_seconds := 480.0
## Seconds a full battery lasts in bright mode.
@export var bright_life_seconds := 30.0

@export_group("Darkness exposure")
## Seconds unlit before spirits sense roughly where you are.
@export var sense_threshold := 15.0
## Seconds unlit before spirits hunt you directly.
@export var hunt_threshold := 30.0
## Exposure seconds removed per second while lit.
@export var exposure_decay := 3.0
## Exposure seconds removed per second while hidden.
@export var exposure_decay_hidden := 2.0

@export_group("Beam")
@export var normal_energy := 3.0
@export var normal_angle := 24.0
@export var normal_range := 14.0
@export var bright_energy := 12.0
@export var bright_angle := 40.0
@export var bright_range := 18.0
## Faint glow left at 0% so the game is never fully black.
@export var empty_energy := 0.3
@export var empty_range := 4.0

var owned := false
var on := false
var bright := false
var battery := 100.0
var exposure := 0.0
var _warned_hiding := false


func _ready() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not owned or GameState.ended or GameState.cutscene:
		return
	var p := GameState.player
	if event.is_action_pressed("flashlight"):
		set_on(not on)
		if on and p != null and p.hidden and not _warned_hiding:
			# Allowed, but it gives you away.
			_warned_hiding = true
			GameState.hint("The light shows through the gaps. Anything close by will see it.", 6.0)
	elif event.is_action_pressed("bright") and not on:
		set_on(true)


func _physics_process(delta: float) -> void:
	if GameState.ended or GameState.cutscene:
		return
	var p := GameState.player
	var hiding := p != null and p.hidden

	bright = is_lighting() and not hiding and Input.is_action_pressed("bright")
	if is_lighting():
		var life := bright_life_seconds if bright else normal_life_seconds
		battery = maxf(0.0, battery - 100.0 / life * delta)
		if battery <= 0.0:
			bright = false

	_update_beam(delta)

	if p == null:
		return
	if hiding:
		exposure = maxf(0.0, exposure - exposure_decay_hidden * delta)
	elif is_lighting() or GameState.is_lit(p.global_position):
		exposure = maxf(0.0, exposure - exposure_decay * delta)
	else:
		exposure = minf(hunt_threshold + 5.0, exposure + delta)
	GameState.darkness_exposure = exposure


func _update_beam(delta: float) -> void:
	# Hidden while a cutscene camera has left Jason's eyes (it would light him up from inside).
	visible = owned and on and not GameState.third_person
	if not visible:
		return
	var energy := normal_energy
	var angle := normal_angle
	var reach := normal_range
	if battery <= 0.0:
		energy = empty_energy
		reach = empty_range
	elif bright:
		energy = bright_energy
		angle = bright_angle
		reach = bright_range
	elif battery < 15.0 and randf() < 0.06:
		energy *= 0.35  # dying-battery flicker
	var blend := minf(1.0, 14.0 * delta)
	light_energy = lerpf(light_energy, energy, blend)
	spot_angle = lerpf(spot_angle, angle, blend)
	spot_range = lerpf(spot_range, reach, blend)


## True while the flashlight is actually producing useful light.
func is_lighting() -> bool:
	return owned and on and battery > 0.0


func set_on(value: bool) -> void:
	if not owned or on == value:
		return
	on = value
	GameState.play_sfx("click")


func give() -> void:
	owned = true
	on = true


func add_battery(percent: float) -> void:
	battery = minf(100.0, battery + percent)


## True when the bright beam's cone reaches `point` (line of sight not checked).
func bright_covers(point: Vector3) -> bool:
	if not bright:
		return false
	var to := point - global_position
	if to.length() > bright_range:
		return false
	return (-global_basis.z).angle_to(to) <= deg_to_rad(bright_angle)
