class_name Examinable
extends Area3D
## Something to look at but not take (a mirror, a child's drawing). Plays a
## line of dialogue, or a document/flashback from data/memory_fragments.json.

signal examined

@export var prompt := "Examine"
@export var speaker := "Jason"
@export_multiline var line := ""
@export var fragment_id := ""
@export var size := Vector3(0.4, 0.4, 0.4)

var times_examined := 0


func _ready() -> void:
	collision_layer = GameState.LAYER_INTERACT
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)


func get_prompt() -> String:
	return prompt


func interact(_player: Player) -> void:
	times_examined += 1
	if not fragment_id.is_empty():
		GameState.flashback_requested.emit(fragment_id)
	elif not line.is_empty():
		GameState.say(speaker, line)
	examined.emit()
