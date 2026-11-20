extends Control
## The title screen: Continue (from the autosave), New Game, Settings, Quit.

const FOG := preload("res://shaders/menu_fog.gdshader")

var _menu: VBoxContainer
var _settings: SettingsPanel
var _continue: Button
var _new_game: Button
var _confirm: ConfirmationDialog
var _fade: ColorRect
var _starting := false


func _ready() -> void:
	theme = MenuStyle.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false

	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog := ShaderMaterial.new()
	fog.shader = FOG
	back.material = fog
	add_child(back)

	var title := MenuStyle.label("THE WAKING DARK", 76, Color(0.86, 0.87, 0.9))
	title.position = Vector2(96, 120)
	add_child(title)
	var subtitle := MenuStyle.label("ACT 1", 20, MenuStyle.DIM)
	subtitle.position = Vector2(102, 214)
	add_child(subtitle)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(96, 320)
	_menu.add_theme_constant_override("separation", 12)
	add_child(_menu)

	_continue = MenuStyle.button("Continue")
	_continue.pressed.connect(_on_continue)
	_menu.add_child(_continue)
	_new_game = MenuStyle.button("New game")
	_new_game.pressed.connect(_on_new_game)
	_menu.add_child(_new_game)
	var settings := MenuStyle.button("Settings")
	settings.pressed.connect(_show_settings.bind(true))
	_menu.add_child(settings)
	var quit := MenuStyle.button("Quit")
	quit.pressed.connect(get_tree().quit)
	_menu.add_child(quit)
	if OS.has_feature("web"):
		quit.hide()

	_settings = SettingsPanel.new()
	_settings.hide()
	_settings.back_pressed.connect(_show_settings.bind(false))
	var holder := PanelContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BOTH
	holder.add_child(_settings)
	holder.visible = false
	holder.name = "SettingsHolder"
	add_child(holder)

	var version := MenuStyle.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0"), 14, MenuStyle.DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 24
	version.offset_top = -40
	add_child(version)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "New game"
	_confirm.dialog_text = "Start over from the beginning?\nYour saved progress stays until the first checkpoint of the new run replaces it."
	_confirm.ok_button_text = "Start over"
	_confirm.cancel_button_text = "Cancel"
	_confirm.confirmed.connect(_start_new)
	add_child(_confirm)

	_refresh_continue()

	var wind := AudioStreamPlayer.new()
	wind.stream = SoundBank.loop("ambience/wind_loop.wav")
	wind.volume_db = -60.0
	wind.autoplay = false
	add_child(wind)
	if wind.stream != null:
		wind.play()
		create_tween().tween_property(wind, "volume_db", -18.0, 3.0)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)

	_focus_menu.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings.visible:
		_show_settings(false)
		get_viewport().set_input_as_handled()


func _refresh_continue() -> void:
	var info := SaveGame.summary()
	var has_save := not info.is_empty() and not SaveGame.read().is_empty()
	_continue.visible = has_save
	if has_save:
		_continue.text = "Continue   ·   %s  ·  %s" % [SaveGame.room_label(info["room"]), SaveGame.format_time(info["elapsed"])]
		_continue.custom_minimum_size.x = 420


func _focus_menu() -> void:
	(_continue if _continue.visible else _new_game).grab_focus()


func _show_settings(show: bool) -> void:
	_menu.visible = not show
	_settings.get_parent().visible = show
	_settings.visible = show
	if show:
		_settings.focus_first()
	else:
		_focus_menu()


func _on_continue() -> void:
	if _starting:
		return
	if not GameState.load_save():
		_refresh_continue()  # the file went bad since the screen opened
		_focus_menu()
		return
	_begin()


func _on_new_game() -> void:
	if SaveGame.exists():
		_confirm.popup_centered()
	else:
		_start_new()


func _start_new() -> void:
	if _starting:
		return
	GameState.prepare_new_game()
	_begin()


func _begin() -> void:
	_starting = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.6)
	await tween.finished
	get_tree().change_scene_to_file(GameState.MAIN_SCENE_PATH)
