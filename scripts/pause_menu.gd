class_name PauseMenu
extends CanvasLayer
## Esc pauses the game: Resume, Restart from checkpoint, Settings, Quit to title.
## Lives in the main scene. It also pauses when the window loses focus, and applies
## the brightness setting to the world environment.

var is_open := false

var _root: Control
var _menu: VBoxContainer
var _settings: SettingsPanel
var _settings_holder: PanelContainer
var _resume: Button
var _restart: Button
var _note: Label
var _environment: Environment


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		_environment = world_env.environment
		Settings.apply_to_environment(_environment)
	Settings.changed.connect(_on_settings_changed)

	_root = Control.new()
	_root.theme = MenuStyle.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.02, 0.72)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	center.add_child(_menu)

	var title := MenuStyle.label("PAUSED", 48, Color(0.86, 0.87, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(title)
	_menu.add_child(Control.new())

	_resume = MenuStyle.button("Resume")
	_resume.pressed.connect(close)
	_menu.add_child(_resume)
	_restart = MenuStyle.button("Restart from checkpoint")
	_restart.pressed.connect(_on_restart)
	_menu.add_child(_restart)
	var settings := MenuStyle.button("Settings")
	settings.pressed.connect(_show_settings.bind(true))
	_menu.add_child(settings)
	var to_title := MenuStyle.button("Quit to title")
	to_title.pressed.connect(_on_quit_to_title)
	_menu.add_child(to_title)

	_note = MenuStyle.label("", 14, MenuStyle.DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(_note)

	_settings = SettingsPanel.new()
	_settings.back_pressed.connect(_show_settings.bind(false))
	_settings_holder = PanelContainer.new()
	_settings_holder.visible = false
	_settings_holder.add_child(_settings)
	center.add_child(_settings_holder)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open:
		if _settings_holder.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()
	elif _can_open():
		open()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Alt-tabbing away from a horror game should not leave you being hunted.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _can_open() and DisplayServer.get_name() != "headless":
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_restart.visible = not GameState.checkpoint.is_empty()
	var info := SaveGame.summary()
	if GameState.checkpoint.is_empty():
		_note.text = "Progress saves automatically at checkpoints (picking up items, meeting Daniel)."
	elif info.is_empty():
		_note.text = "Progress since the last checkpoint is lost if you quit."
	else:
		_note.text = "Last saved: %s. Progress since then is lost if you quit." % SaveGame.room_label(info["room"])
	_show_settings(false)
	_root.visible = true
	_resume.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	if not GameState.ended:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_open() -> bool:
	return not GameState.ended and not get_tree().paused and GameState.player != null


func _show_settings(show: bool) -> void:
	_menu.visible = not show
	_settings_holder.visible = show
	if show:
		_settings.focus_first()
	elif is_open:
		_resume.grab_focus()


func _on_settings_changed() -> void:
	Settings.apply_to_environment(_environment)


func _on_restart() -> void:
	close()
	GameState.load_checkpoint()


func _on_quit_to_title() -> void:
	close()
	GameState.quit_to_title()
