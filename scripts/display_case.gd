class_name DisplayCase
extends StaticBody3D
## A glass display case on a pedestal, locked with a small key. Opening it
## makes the pickup inside available. Counts as a gate in the key graph
## (room_a -> room_b), with the contents sitting in room_b.

signal opened
## Fired when the player tries the case without the key.
signal examined_locked

@export var key_id := ""
@export var locked_line := "Locked. A tiny brass keyhole."
var room_a := ""
var room_b := ""
var sealed := false  # key-graph interface shared with LockedDoor
var locked := true
var contents: Pickup = null

const PEDESTAL := Vector3(0.7, 1.0, 0.5)
const DOME := Vector3(0.6, 0.35, 0.42)

var _glass: MeshInstance3D
var _dome_shape: CollisionShape3D


func _ready() -> void:
	add_to_group("gates")
	collision_layer = GameState.LAYER_WORLD | GameState.LAYER_INTERACT
	collision_mask = 0

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.16, 0.11)
	wood.roughness = 0.6
	var pedestal_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PEDESTAL
	pedestal_mesh.mesh = box
	pedestal_mesh.position.y = PEDESTAL.y * 0.5
	pedestal_mesh.material_override = wood
	add_child(pedestal_mesh)
	var pedestal_shape := CollisionShape3D.new()
	var pedestal_box := BoxShape3D.new()
	pedestal_box.size = PEDESTAL
	pedestal_shape.shape = pedestal_box
	pedestal_shape.position.y = PEDESTAL.y * 0.5
	add_child(pedestal_shape)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.7, 0.8, 0.85, 0.18)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 1.0
	_glass = MeshInstance3D.new()
	var dome := BoxMesh.new()
	dome.size = DOME
	_glass.mesh = dome
	_glass.position.y = PEDESTAL.y + DOME.y * 0.5
	_glass.material_override = glass_mat
	add_child(_glass)
	# While locked, the glass is solid so you can't reach the key through it.
	_dome_shape = CollisionShape3D.new()
	var dome_box := BoxShape3D.new()
	dome_box.size = DOME
	_dome_shape.shape = dome_box
	_dome_shape.position.y = _glass.position.y
	add_child(_dome_shape)


## Where the contents sit (on the velvet, under the glass).
func content_position() -> Vector3:
	return global_position + Vector3(0, PEDESTAL.y + 0.04, 0)


func get_prompt() -> String:
	if not locked:
		return ""
	return "Unlock the case" if GameState.has_item(key_id) else "Display case (locked)"


func interact(_player: Player) -> void:
	if not locked:
		return
	if not GameState.has_item(key_id):
		GameState.play_sfx("rattle", -6.0)
		GameState.say("Jason", locked_line, 4.0)
		examined_locked.emit()
		return
	locked = false
	GameState.play_sfx("click")
	_glass.visible = false
	_dome_shape.set_deferred("disabled", true)
	collision_layer = GameState.LAYER_WORLD  # nothing left to interact with
	if contents != null:
		contents.set_available(true)
	opened.emit()
	GameState.save_checkpoint()
