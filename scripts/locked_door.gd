class_name LockedDoor
extends StaticBody3D
## A hinged door. Leave key_id empty for a plain door; set it to require a key.
## The node's origin is the hinge; the leaf extends along local +X when closed.
##
## A closed door is solid to spirits and blocks their sight, but they shove
## unlocked doors open when their path runs through one.

signal unlocked

@export var key_id := ""
## A door that never opens (chained front doors and the like). Safe to set
## after the door is in the tree.
@export var sealed := false:
	set(value):
		sealed = value
		if is_inside_tree():
			locked = sealed or not key_id.is_empty()
			_apply_layers()
## Not locked, just stuck: the first push fails, the second bursts it open.
@export var stuck := false
## Rooms on either side, for the key-graph check (tools/validate_keys.gd).
var room_a := ""
var room_b := ""
@export var width := 1.3
@export var height := 2.1
## Degrees the leaf swings when opened (sign picks the side).
@export var open_angle_deg := 90.0
## Put the closed door on the world layer so the navmesh treats it as a wall.
@export var blocks_navigation := false
@export var locked_line := "Locked. There has to be a key somewhere."

var locked := false
var is_open := false

var _closed_yaw := 0.0
var _tween: Tween


func _ready() -> void:
	locked = sealed or not key_id.is_empty()
	_closed_yaw = rotation.y
	add_to_group("gates")
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.1)
	shape.shape = box
	shape.position = Vector3(width * 0.5, height * 0.5, 0.0)
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var leaf := BoxMesh.new()
	leaf.size = Vector3(width - 0.04, height - 0.02, 0.07)
	mesh.mesh = leaf
	mesh.position = shape.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.2, 0.2) if locked else Color(0.24, 0.2, 0.17)
	material.roughness = 0.8
	mesh.material_override = material
	add_child(mesh)

	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.04
	knob_mesh.height = 0.08
	knob.mesh = knob_mesh
	knob.position = Vector3(width - 0.14, 1.0, 0.0)
	knob.scale = Vector3(1.0, 1.0, 3.2)
	var knob_material := StandardMaterial3D.new()
	knob_material.albedo_color = Color(0.6, 0.5, 0.25)
	knob_material.metallic = 0.8
	knob_material.roughness = 0.4
	knob.material_override = knob_material
	add_child(knob)

	_apply_layers()


func _apply_layers() -> void:
	if is_open:
		# Open: still clickable, but nothing collides with the leaf.
		collision_layer = GameState.LAYER_INTERACT
	elif locked or blocks_navigation:
		# Locked: a wall as far as spirits and the navmesh are concerned.
		collision_layer = GameState.LAYER_INTERACT | GameState.LAYER_WORLD
	else:
		collision_layer = GameState.LAYER_INTERACT | GameState.LAYER_DOOR


func get_prompt() -> String:
	if locked:
		if not sealed and GameState.has_item(key_id):
			return "Unlock door"
		return "Door (locked)"
	return "Close door" if is_open else "Open door"


func interact(player: Player) -> void:
	if locked:
		if not sealed and GameState.has_item(key_id):
			locked = false
			GameState.play_sfx("click")
			set_open(true)
			GameState.unlocked_doors.append(name)
			unlocked.emit()
			GameState.save_checkpoint()
		else:
			GameState.play_sfx("rattle")
			GameState.say("Jason", locked_line, 3.0)
			GameState.emit_noise(global_position, 5.0)  # rattling the handle is loud
		return
	if stuck:
		stuck = false
		GameState.play_sfx("rattle")
		GameState.say("Jason", "Stuck. Not locked, just stuck. Put some weight into it.", 3.0)
		return
	if is_open and _doorway_center().distance_to(player.global_position) < 0.9:
		return  # don't shut the door on yourself
	set_open(not is_open)


## Checkpoint restore: unlocked and open, no sound, no animation.
func restore_unlocked() -> void:
	locked = false
	is_open = true
	rotation.y = _closed_yaw + deg_to_rad(open_angle_deg)
	_apply_layers()


## `alert` is false when a spirit opens the door, so it doesn't investigate itself.
func set_open(value: bool, alert: bool = true) -> void:
	if is_open == value:
		return
	is_open = value
	_apply_layers()
	GameState.play_sfx("creak", -4.0)
	if alert:
		GameState.emit_noise(global_position, 4.0)
	if _tween != null:
		_tween.kill()
	var target := _closed_yaw + (deg_to_rad(open_angle_deg) if is_open else 0.0)
	_tween = create_tween()
	_tween.tween_property(self, "rotation:y", target, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _doorway_center() -> Vector3:
	return global_position + Vector3(cos(_closed_yaw), 0.0, -sin(_closed_yaw)) * width * 0.5
