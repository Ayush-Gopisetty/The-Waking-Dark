extends CanvasLayer
## Escaped / caught screen with a restart button. Runs while the tree is paused.


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.02, 0.02, 0.03, 0.0)
	add_child(back)
	create_tween().tween_property(back, "color:a", 0.92, 0.8)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -140
	box.offset_bottom = 140
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var won := GameState.won
	var title := Label.new()
	title.text = "ACT 1 COMPLETE" if won else "CAUGHT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95) if won else Color(0.75, 0.15, 0.12))
	box.add_child(title)

	var detail := Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
	var line := "Jason Hale steps into the east wing. Somewhere in this house, Lily is waiting." if won \
		else "The dark closed in."
	detail.text = "%s\n\nTime %s" % [line, _format_time(GameState.elapsed)]
	box.add_child(detail)

	var retry: Button = null
	if not won and not GameState.checkpoint.is_empty():
		retry = Button.new()
		retry.text = "Retry from checkpoint"
		retry.custom_minimum_size = Vector2(260, 44)
		retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		retry.pressed.connect(GameState.retry_from_checkpoint)
		box.add_child(retry)

	var restart := Button.new()
	restart.text = "Restart Act 1"
	restart.custom_minimum_size = Vector2(200, 44)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(GameState.restart)
	box.add_child(restart)

	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(200, 44)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(GameState.quit_to_title)
	box.add_child(menu)

	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(200, 44)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	if OS.has_feature("web"):
		quit.hide()

	(retry if retry != null else restart).grab_focus.call_deferred()


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
