class_name Pickup
extends Area3D
## A thing on the floor you can take: the flashlight, a battery, a key, or the ID.

enum Kind { FLASHLIGHT, BATTERY, KEY, ID, NOTE }

@export var kind: Kind = Kind.BATTERY
## Inventory id for keys (matches a door's key_id).
@export var item_id := ""
## Percent restored by a battery.
@export var battery_amount := 60.0
## Memory fragment / document played on pickup (see data/memory_fragments.json).
@export var fragment_id := "half_burned_id"
## What Jason says when he takes it (keys).
@export var line := ""
## Invisible until the bright beam lands on it (the library light puzzle).
## Safe to set after the pickup is in the tree.
@export var hidden_until_bright := false:
	set(value):
		hidden_until_bright = value
		if is_inside_tree():
			if value:
				set_available(false)
			set_physics_process(value)

## Keys: hang from a hook (tip down) instead of lying flat.
@export var hanging := false

signal taken

var available := true
var _visual: Node3D
## Faint additive sheen over the model so it can be found in the dark.
var _glint: StandardMaterial3D


func _ready() -> void:
	collision_layer = GameState.LAYER_INTERACT
	collision_mask = 0
	monitoring = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	add_child(shape)

	_glint = StandardMaterial3D.new()
	_glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint.albedo_color = Color(0.1, 0.09, 0.07)
	match kind:
		Kind.FLASHLIGHT:
			# Lying on its side, lens toward +X.
			_visual = Props.instance("flashlight")
			_visual.rotation = Vector3(0, PI / 2.0 - 0.35, 0)
			_visual.position = Vector3(-0.08, 0.026, 0.03)
		Kind.BATTERY:
			_visual = Props.instance("battery")
			_visual.rotation.y = randf_range(-0.6, 0.6)
		Kind.KEY:
			var model := "key_brass"
			if item_id == "east_wing_key":
				model = "key_iron_tag"
			elif item_id == "furnace_key":
				model = "key_brass_tag"
			_visual = Props.instance(model)
			if hanging:
				_visual.rotation.x = -PI / 2.0  # tip down, bow at the hook
				_visual.position.y = 0.09
			else:
				_visual.rotation.y = randf_range(-1.0, 1.0)
				_visual.position.y = 0.005
			_glint.albedo_color = Color(0.16, 0.13, 0.07)
		Kind.NOTE:
			_visual = _box(Vector3(0.22, 0.012, 0.3), Color(0.62, 0.55, 0.4), Color(0.9, 0.8, 0.55), 0.3)
		Kind.ID:
			# Jason's half-burned ID, lying in the grate.
			_visual = Props.instance("id_jason")
			_visual.rotation = Vector3(0.12, 0.5, 0.0)
			_visual.position.y = 0.004
			_glint.albedo_color = Color(0.22, 0.12, 0.05)  # catching the furnace glow
	add_child(_visual)
	if kind in [Kind.FLASHLIGHT, Kind.BATTERY, Kind.KEY, Kind.ID]:
		for mi: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = _glint
	if hidden_until_bright:
		set_available(false)
	set_physics_process(hidden_until_bright)


## Hide/show and enable/disable interaction (keys inside a locked case, etc).
func set_available(value: bool) -> void:
	available = value
	collision_layer = GameState.LAYER_INTERACT if value else 0
	if _visual != null:
		_visual.visible = value


func _physics_process(_delta: float) -> void:
	var player := GameState.player
	if player == null or not hidden_until_bright:
		return
	var fl := player.flashlight
	if not fl.bright_covers(global_position):
		return
	var query := PhysicsRayQueryParameters3D.create(fl.global_position, global_position, GameState.LAYER_WORLD)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	hidden_until_bright = false
	set_physics_process(false)
	set_available(true)
	_glint.albedo_color = Color(0.35, 0.28, 0.14)  # it catches the light
	GameState.play_sfx("pickup", -6.0)
	GameState.say("Jason", "Something glints where the light hits. A tiny key, tucked into the shelf.", 4.0)


## Papers (the ID, the case file) stay simple glowing cards.
func _box(size: Vector3, color: Color, glow: Color, energy: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	mesh.material_override = material
	return mesh


func get_prompt() -> String:
	match kind:
		Kind.FLASHLIGHT: return "Take flashlight"
		Kind.BATTERY: return "Take battery"
		Kind.KEY: return "Take key"
		Kind.ID: return "Take half-burned ID"
		Kind.NOTE: return "Read case file"
	return "Take"


func interact(player: Player) -> void:
	var fl := player.flashlight
	match kind:
		Kind.FLASHLIGHT:
			fl.give()
			GameState.add_item("flashlight")
			GameState.say("Jason", "A flashlight. Still works. The battery won't last, though.", 4.0)
			GameState.hint("F  flashlight on / off   ·   the battery won't last, so use the light wisely", 10.0)
		Kind.BATTERY:
			if not fl.owned:
				GameState.say("Jason", "Batteries. Nothing to put them in yet.", 3.0)
				return
			if fl.battery > 90.0:
				GameState.say("Jason", "Battery's nearly full. Better to leave these for later.", 3.0)
				return
			fl.add_battery(battery_amount)
		Kind.KEY:
			GameState.add_item(item_id)
			GameState.say("Jason", line if not line.is_empty() else "A key. This has to open something.", 3.5)
		Kind.ID:
			GameState.add_item("id")
			player.examine_id(fragment_id)  # he lifts it up and reads it, then the flashback
		Kind.NOTE:
			GameState.add_item(item_id)
			GameState.flashback_requested.emit(fragment_id)
	GameState.play_sfx("pickup")
	GameState.taken_pickups.append(name)
	taken.emit()
	if kind != Kind.BATTERY:
		GameState.save_checkpoint.call_deferred()
	queue_free()
