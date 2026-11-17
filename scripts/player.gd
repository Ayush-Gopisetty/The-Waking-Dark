class_name Player
extends CharacterBody3D
## First-person controller: movement, stamina, crouch, noise, interaction, hiding.

@export_group("Movement")
@export var walk_speed := 2.5
@export var sprint_speed := 4.8
@export var crouch_speed := 1.2
@export var acceleration := 14.0
## Seconds of continuous sprint from a full bar.
@export var stamina_seconds := 8.0
## Seconds to refill an empty bar.
@export var stamina_recover_seconds := 5.0
@export var mouse_sensitivity := 0.0022

@export_group("Noise radius (metres)")
@export var noise_crouch := 1.5
@export var noise_walk := 4.0
@export var noise_sprint := 9.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.85
const GRAVITY := 9.8
## Jason's model is shrunk a touch so his eyes sit at STAND_EYE.
const BODY_SCALE := 0.93
## The body sits a little behind the camera so looking down shows chest and legs,
## not the inside of the neck.
const BODY_OFFSET := Vector3(0, 0, 0.15)
## Where the flashlight hand rests, relative to the head (before looking up or down).
## (Low and to the right, but inside the view, so you can see him holding it.)
const FLASHLIGHT_HAND := Vector3(0.2, -0.18, -0.33)
## The flashlight's grip, in the model's own space (lens toward +Z).
const FLASHLIGHT_GRIP := Vector3(0, 0, 0.085)
## Just in front of the lens: where the beam starts.
const FLASHLIGHT_LENS := Vector3(0, 0, 0.235)
## Beam origin (camera space) when the flashlight model isn't in view.
const BEAM_FALLBACK := Vector3(0.18, -0.15, -0.1)

var stamina := 1.0
var exhausted := false
var crouching := false
var sprinting := false
var hidden := false
var hiding_spot: Node3D = null
## Radius of the most recent movement noise; 0 when still.
var noise_radius := 0.0
## The interactable currently under the crosshair, if any.
var focus: Object = null
## Lying on the floor (the opening). Standing up from it is slow.
var lying := false
var _getting_up := false

var _step_distance := 0.0
var _bob_time := 0.0
var _hide_yaw := 0.0

## Jason's own body: visible when you look down, full (with head) in cutscenes.
var body: CharacterRig
## The flashlight model in his hand, and its glowing lens/bulb materials.
var _held: Node3D
var _lens: Array[BaseMaterial3D] = []
var _spill: OmniLight3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: Flashlight = $Head/Camera3D/Flashlight
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var footsteps: AudioStreamPlayer = $Footsteps


func _ready() -> void:
	GameState.player = self
	GameState.restore_player(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	footsteps.stream = AudioGen.footstep()
	body = CharacterRig.new()
	body.name = "Body"
	body.model_path = "res://assets/models/jason.glb"
	body.model_scale = BODY_SCALE
	body.bandaged_left = false
	body.speaker_name = "Jason"
	body.id_model = "id_jason"
	body.first_person = true
	body.position = BODY_OFFSET
	body.process_priority = -10  # pose the arm first, then put the flashlight in the hand
	add_child(body)
	_held = Props.instance("flashlight")
	_held.top_level = true
	_held.visible = false
	add_child(_held)
	# A real flashlight leaks a little light back onto the hand holding it.
	_spill = OmniLight3D.new()
	_spill.light_color = Color(1.0, 0.93, 0.8)
	_spill.omni_range = 0.3
	_spill.omni_attenuation = 2.0
	_spill.light_energy = 0.0
	_spill.position = FLASHLIGHT_LENS - Vector3(0, -0.02, 0.05)
	_held.add_child(_spill)
	for mi: MeshInstance3D in _held.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and (src.resource_name == "Lens" or src.resource_name == "Bulb"):
				var glow := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				glow.emission_enabled = true
				glow.emission = Color(1.0, 0.94, 0.8)
				mi.set_surface_override_material(s, glow)
				_lens.append(glow)


func _process(delta: float) -> void:
	if body == null:
		return
	body.visible = not lying and not hidden
	body.crouch = move_toward(body.crouch, 1.0 if crouching else 0.0, delta * 4.0)
	if body.first_person:
		# Free hand hangs; the other holds the light out in front.
		if flashlight.owned and body.gesture != CharacterRig.Gesture.FLASHLIGHT:
			body.play("flashlight")
		elif not flashlight.owned and body.gesture != CharacterRig.Gesture.IDLE:
			body.play("idle")
		# The hand follows the yaw fully but only some of the pitch, so it stays in
		# front of the chest instead of swinging into it when looking down.
		var pitch := head.rotation.x
		var hand := head.position + FLASHLIGHT_HAND + Vector3(0, sin(pitch) * 0.16, 0)
		body.gesture_target = global_transform * hand
		# The grip: the barrel points where you look, and the palm wraps it from
		# above and to the right (fingers curl under it, thumb over the top).
		var cam := camera.global_basis
		body.grip_point = body.gesture_target if flashlight.owned else Vector3.INF
		body.grip_axis = (-cam.z - cam.x * 0.06).normalized()
		body.grip_palm = (-cam.y * 0.9 - cam.x * 0.45).normalized()
		# Looking down, slide the body back so the camera never sees inside the collar.
		body.position = BODY_OFFSET + Vector3(0, 0, maxf(0.0, -pitch - 0.5) * 0.3)
		body.look_target = Vector3.INF
	else:
		body.grip_point = Vector3.INF
	body.holding = flashlight.owned
	_hold_flashlight()


## Puts the flashlight model in Jason's right hand (CharacterRig poses the grip).
## In first person it points where you look and the beam comes out of its lens.
## The lens glows when it's on, brighter on high beam.
func _hold_flashlight() -> void:
	var sk := body.skeleton
	_held.visible = flashlight.owned and body.visible and sk != null
	if not _held.visible:
		flashlight.transform = Transform3D(Basis.IDENTITY, BEAM_FALLBACK)
		return
	# Rigidly in the grip: wherever the hand actually is this frame, the barrel
	# runs through the curled fingers, so it can't drift through them.
	_held.global_transform = body.held_transform(FLASHLIGHT_GRIP.z)
	# The beam starts at the lens (still aimed straight down the view).
	var lens: Vector3 = _held.global_transform * FLASHLIGHT_LENS
	if body.first_person:
		# First person: from the lens, aimed straight down the view (gameplay aim).
		flashlight.transform = Transform3D(Basis.IDENTITY, camera.global_transform.affine_inverse() * lens)
	else:
		# Cutscenes: the beam goes wherever the flashlight in his hand points
		# (a spotlight shines along its -Z; the model's lens faces +Z).
		flashlight.global_transform = Transform3D(_held.global_basis.orthonormalized() * Basis(Vector3.UP, PI), lens)
	var glow := 0.0
	if flashlight.is_lighting():
		glow = 6.0 if flashlight.bright else 2.0
	elif flashlight.on:
		glow = 0.3  # flat battery: a dim ember
	for m in _lens:
		m.emission_energy_multiplier = glow
	_spill.light_energy = 0.0 if glow < 1.0 else (0.12 if flashlight.bright else 0.06)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.ended:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var motion := event as InputEventMouseMotion
	if motion != null:
		if captured and not GameState.cutscene:
			_look(motion.relative)
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.is_pressed() and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("crouch"):
		if not hidden and not GameState.cutscene:
			crouching = not crouching


func _look(relative: Vector2) -> void:
	rotation.y -= relative.x * mouse_sensitivity
	head.rotation.x = clampf(head.rotation.x - relative.y * mouse_sensitivity, -1.45, 1.45)
	if hidden:
		# Peeking: only a narrow arc while inside a hiding spot.
		rotation.y = _hide_yaw + clampf(angle_difference(_hide_yaw, rotation.y), -0.6, 0.6)
		head.rotation.x = clampf(head.rotation.x, -0.5, 0.5)


func _physics_process(delta: float) -> void:
	_update_focus()
	if GameState.ended or GameState.cutscene or hidden:
		velocity = Vector3.ZERO
		sprinting = false
		noise_radius = 0.0
		_recover_stamina(delta)
		_update_stance(delta)
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	direction = direction.normalized()
	var moving := direction.length() > 0.1

	sprinting = moving and not crouching and not exhausted and Input.is_action_pressed("sprint")
	if sprinting:
		stamina = maxf(0.0, stamina - delta / stamina_seconds)
		if stamina <= 0.0:
			exhausted = true
	else:
		_recover_stamina(delta)

	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif sprinting:
		speed = sprint_speed

	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if ground_speed > 0.4:
		if crouching:
			noise_radius = noise_crouch
		elif sprinting:
			noise_radius = noise_sprint
		else:
			noise_radius = noise_walk
		_step(ground_speed * delta)
	else:
		noise_radius = 0.0
		_step_distance = 0.0

	_update_stance(delta)
	_update_bob(delta, ground_speed)


func _recover_stamina(delta: float) -> void:
	stamina = minf(1.0, stamina + delta / stamina_recover_seconds)
	if exhausted and stamina >= 0.35:
		exhausted = false


## One footstep per stride: plays the sound and tells spirits about the noise.
func _step(distance: float) -> void:
	_step_distance += distance
	var stride := 0.55 if crouching else (1.0 if sprinting else 0.8)
	if _step_distance < stride:
		return
	_step_distance = 0.0
	footsteps.volume_db = -26.0 if crouching else (-8.0 if sprinting else -15.0)
	footsteps.pitch_scale = randf_range(0.85, 1.15)
	footsteps.play()
	GameState.emit_noise(global_position, noise_radius)


func _update_stance(delta: float) -> void:
	var shape := collider.shape as CapsuleShape3D
	var target_height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if shape != null and not is_equal_approx(shape.height, target_height):
		shape.height = target_height
		collider.position.y = target_height * 0.5
	var eye := CROUCH_EYE if crouching else STAND_EYE
	var rate := 10.0
	if lying:
		eye = 0.3
		_getting_up = true
	elif _getting_up:
		rate = 1.6
		if absf(head.position.y - eye) < 0.03:
			_getting_up = false
	head.position.y = lerpf(head.position.y, eye, minf(1.0, rate * delta))


func _update_bob(delta: float, ground_speed: float) -> void:
	if ground_speed > 0.4:
		_bob_time += delta * ground_speed * 2.6
		camera.position.y = sin(_bob_time * 2.0) * 0.025
		camera.position.x = cos(_bob_time) * 0.015
	else:
		camera.position.y = lerpf(camera.position.y, 0.0, minf(1.0, 8.0 * delta))
		camera.position.x = lerpf(camera.position.x, 0.0, minf(1.0, 8.0 * delta))


# --- Interaction -----------------------------------------------------------------

func _update_focus() -> void:
	focus = null
	if hidden or GameState.cutscene or GameState.ended:
		return
	if interact_ray.is_colliding():
		var hit := interact_ray.get_collider()
		if hit != null and hit.has_method("interact"):
			focus = hit


func _interact() -> void:
	if GameState.cutscene:
		return
	if hidden:
		if hiding_spot != null:
			hiding_spot.call("leave", self)
		return
	if focus != null and is_instance_valid(focus):
		focus.call("interact", self)


## Text for the HUD prompt, or "" when there is nothing to interact with.
func get_prompt() -> String:
	if hidden:
		return "[E] Step out"
	if focus != null and is_instance_valid(focus) and focus.has_method("get_prompt"):
		var text: String = focus.call("get_prompt")
		return "" if text.is_empty() else "[E] " + text
	return ""


# --- Hiding ------------------------------------------------------------------------

func enter_hiding(spot: Node3D, inside_position: Vector3, yaw: float) -> void:
	hidden = true
	hiding_spot = spot
	crouching = false
	velocity = Vector3.ZERO
	collider.set_deferred("disabled", true)
	global_position = inside_position
	rotation.y = yaw
	_hide_yaw = yaw
	head.rotation.x = 0.0
	flashlight.set_on(false)
	get_tree().call_group("spirits", "on_player_hid", spot)


func exit_hiding(exit_position: Vector3) -> void:
	global_position = exit_position
	collider.set_deferred("disabled", false)
	hidden = false
	hiding_spot = null
