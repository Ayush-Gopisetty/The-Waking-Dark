class_name Subtitles
extends Label
## Bottom-of-screen subtitles with the speaker's name. Lines queue up and play
## in order.

var _queue: Array[Dictionary] = []
var _remaining := 0.0


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_theme_constant_override("outline_size", 6)
	text = ""
	GameState.subtitle_requested.connect(show_line)


func _process(delta: float) -> void:
	if _remaining > 0.0:
		_remaining -= delta
		if _remaining <= 0.0:
			_next()


func show_line(speaker: String, line: String, duration: float) -> void:
	_queue.append({"speaker": speaker, "text": line, "duration": duration})
	if _remaining <= 0.0:
		_next()


## Show a line immediately, dropping anything queued (used by flashbacks).
func show_now(speaker: String, line: String, duration: float) -> void:
	_queue.clear()
	_remaining = 0.0
	show_line(speaker, line, duration)


func _next() -> void:
	if _queue.is_empty():
		text = ""
		_remaining = 0.0
		return
	var entry: Dictionary = _queue.pop_front()
	var speaker: String = entry["speaker"]
	text = entry["text"] if speaker.is_empty() else "%s: %s" % [speaker.to_upper(), entry["text"]]
	_remaining = entry["duration"]
	GameState.line_shown.emit(speaker, entry["text"], entry["duration"])

