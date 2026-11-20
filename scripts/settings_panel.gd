class_name SettingsPanel
extends VBoxContainer
## The settings screen: sliders and toggles bound to the Settings autoload. Changes
## apply (and save) immediately. Used by the title screen and the pause menu.

signal back_pressed

var _back: Button
var _controls: Dictionary = {}


func _ready() -> void:
	theme = MenuStyle.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(520, 0)

	var title := MenuStyle.label("SETTINGS", 30, MenuStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	add_child(HSeparator.new())

	_add_slider("master_volume", "Master volume", 0.0, 1.0, 0.01, _percent)
	_add_slider("mouse_sensitivity", "Mouse sensitivity", 0.25, 3.0, 0.05, _times)
	_add_toggle("invert_y", "Invert vertical look")
	_add_slider("fov", "Field of view", 60.0, 100.0, 1.0, _degrees)
	_add_slider("brightness", "Brightness", 0.6, 1.6, 0.02, _percent)
	_add_toggle("fullscreen", "Fullscreen  (F11)")
	_add_toggle("subtitles", "Subtitles")

	add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var defaults := MenuStyle.button("Reset to defaults", 200)
	defaults.pressed.connect(_reset)
	row.add_child(defaults)
	_back = MenuStyle.button("Back", 200)
	_back.pressed.connect(back_pressed.emit)
	row.add_child(_back)

	Settings.changed.connect(_refresh)


func focus_first() -> void:
	_back.grab_focus()


func _add_slider(key: String, label_text: String, min_value: float, max_value: float, step: float, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var name_label := MenuStyle.label(label_text)
	name_label.custom_minimum_size = Vector2(210, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = Settings.get_value(key)
	slider.custom_minimum_size = Vector2(200, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := MenuStyle.label(fmt.call(slider.value))
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		Settings.set_value(key, v))
	_controls[key] = {"control": slider, "label": value_label, "format": fmt}


func _add_toggle(key: String, label_text: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = Settings.get_value(key)
	toggle.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	add_child(toggle)
	_controls[key] = {"control": toggle}


func _reset() -> void:
	Settings.reset_to_defaults()


## Brings the controls in line with the settings (after a reset or an F11 toggle).
func _refresh() -> void:
	for key: String in _controls:
		var entry: Dictionary = _controls[key]
		var control: Control = entry["control"]
		var value: Variant = Settings.get_value(key)
		if control is HSlider:
			if not is_equal_approx(control.value, value):
				control.set_value_no_signal(value)
			entry["label"].text = entry["format"].call(value)
		elif control is CheckButton:
			control.set_pressed_no_signal(value)


func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _times(v: float) -> String:
	return "%.2fx" % v


func _degrees(v: float) -> String:
	return "%d°" % roundi(v)
