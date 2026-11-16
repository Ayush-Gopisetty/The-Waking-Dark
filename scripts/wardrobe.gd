class_name HidingSpot
extends StaticBody3D
## A wardrobe the player can hide in. Origin is the floor centre; the doors
## face local -Z.

@export var width := 1.2
@export var depth := 0.8
@export var height := 2.2

var _model: Node3D


func _ready() -> void:
	collision_layer = GameState.LAYER_WORLD | GameState.LAYER_INTERACT
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, depth)
	shape.shape = box
	shape.position.y = height * 0.5
	add_child(shape)

	# A carved gothic wardrobe (model faces +Z; our doors face -Z, so turn it round).
	_model = Props.place(self, "wardrobe", Vector3.ZERO, Vector3(width, height, depth), PI, false, true)

	GameState.hiding_spots.append(self)


func get_prompt() -> String:
	return "Hide in wardrobe"


## While the player is inside, the cabinet itself isn't drawn: the HUD shows the
## dark inside of the doors with gaps to look (and shine the flashlight) through.
func _process(_delta: float) -> void:
	var player := GameState.player
	_model.visible = not (player != null and player.hidden and player.hiding_spot == self)


func interact(player: Player) -> void:
	# The camera sits just inside the doors, looking out through the gaps.
	var inside := global_position + global_basis * Vector3(0.0, 0.0, -depth * 0.5 + 0.25)
	player.enter_hiding(self, inside, global_rotation.y)


func leave(player: Player) -> void:
	player.exit_hiding(front_position())


## Floor position just in front of the doors.
func front_position() -> Vector3:
	return global_position + global_basis * Vector3(0.0, 0.0, -depth * 0.5 - 0.6)
