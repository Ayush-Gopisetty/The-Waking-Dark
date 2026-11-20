extends Node
## Checks the Act 1 key graph: every key can be reached without passing the
## door it opens, and the goal room can be reached at all.
##   godot --headless --path . res://tools/validate_keys.tscn
## Exits 0 when the graph is valid, 1 otherwise.

func _ready() -> void:
	SaveGame.enabled = false  # never touch the player's save or settings
	Settings.persist = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var level: Node = main.get_node("Level")
	print("rooms: ", ", ".join(level.rooms.keys()))
	for node in level.get_children():
		if node.is_in_group("gates"):
			var gate: String = "sealed" if node.sealed else (node.key_id if not node.key_id.is_empty() else "open")
			var kind: String = "case" if node is DisplayCase else "door"
			print("  %s %-15s <-> %-15s [%s]" % [kind, node.room_a, node.room_b, gate])
	var problems: PackedStringArray = level.validate_key_graph()
	if problems.is_empty():
		print("key graph OK")
		get_tree().quit(0)
	else:
		for p in problems:
			print("PROBLEM: ", p)
		get_tree().quit(1)
