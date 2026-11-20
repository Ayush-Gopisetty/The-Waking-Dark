class_name SaveGame
extends RefCounted
## The save file: the last checkpoint, written to user://save.json. GameState saves
## it automatically at every checkpoint (item pickups, meeting Daniel) and the title
## screen's Continue loads it back into GameState.checkpoint.

const VERSION := 1

## Tests and capture tools point this elsewhere, or turn saving off, so they never
## touch the player's real save.
static var path := "user://save.json"
static var enabled := true


static func exists() -> bool:
	return enabled and FileAccess.file_exists(path)


## Writes a checkpoint (the dictionary GameState keeps) plus a little display info.
## Returns false if nothing was written.
static func write(checkpoint: Dictionary, room: String = "") -> bool:
	if not enabled or checkpoint.is_empty():
		return false
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"room": room,
		"position": _vec_to_array(checkpoint["position"]),
		"yaw": checkpoint["yaw"],
		"battery": checkpoint["battery"],
		"flashlight": checkpoint["flashlight"],
		"inventory": checkpoint["inventory"].keys(),
		"taken": checkpoint["taken"],
		"doors": checkpoint["doors"],
		"elapsed": checkpoint["elapsed"],
	}
	# Write to a temporary file and rename it, so a crash mid-save cannot ruin the old save.
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write the save file (%s)" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null or dir.rename(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		return false
	return true


## The saved checkpoint in GameState's own format, or {} when there is no usable save.
static func read() -> Dictionary:
	var data := _read_raw()
	if data.is_empty():
		return {}
	var inventory := {}
	for id: Variant in data["inventory"]:
		inventory[str(id)] = true
	return {
		"position": _array_to_vec(data["position"]),
		"yaw": float(data["yaw"]),
		"battery": float(data["battery"]),
		"flashlight": bool(data["flashlight"]),
		"inventory": inventory,
		"taken": _strings(data["taken"]),
		"doors": _strings(data["doors"]),
		"elapsed": float(data["elapsed"]),
	}


## Display info for the Continue button: {"room", "saved_at", "elapsed"}, or {}.
static func summary() -> Dictionary:
	var data := _read_raw()
	if data.is_empty():
		return {}
	return {
		"room": str(data.get("room", "")),
		"saved_at": str(data.get("saved_at", "")),
		"elapsed": float(data["elapsed"]),
	}


static func delete() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## "servants_hall" -> "Servants hall".
static func room_label(room: String) -> String:
	return room.replace("_", " ").capitalize() if not room.is_empty() else "Somewhere in the house"


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


static func _read_raw() -> Dictionary:
	if not exists():
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	# A damaged or hand-edited file is treated as no save instead of crashing the load.
	if int(data.get("version", 0)) != VERSION:
		return {}
	for key: String in ["position", "yaw", "battery", "flashlight", "inventory", "taken", "doors", "elapsed"]:
		if not data.has(key):
			return {}
	var pos: Variant = data["position"]
	if not pos is Array or pos.size() != 3:
		return {}
	for part: Variant in pos:
		if not (part is float or part is int):
			return {}
	for key: String in ["inventory", "taken", "doors"]:
		if not data[key] is Array:
			return {}
	for key: String in ["yaw", "battery", "elapsed"]:
		if not (data[key] is float or data[key] is int):
			return {}
	if not data["flashlight"] is bool:
		return {}
	return data


static func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in values:
		out.append(str(v))
	return out


static func _vec_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _array_to_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
