extends CanvasLayer
## HUD: post-processing, crosshair, interaction prompt, battery and stamina
## bars, hints, subtitles, the opening wake-up, memory flashbacks and the F3
## debug readout. Built in code so it is easy to tweak.

const POSTFX_SHADER := preload("res://shaders/postfx.gdshader")

var _postfx: ShaderMaterial
var _prompt: Label
var _hint: Label
var _hint_time := 0.0
var _battery_box: Control
var _battery_fill: ColorRect
var _battery_label: Label
var _stamina_fill: ColorRect
var _stamina_box: Control
var _crosshair: ColorRect
var _items: Label
var _debug: Label
var _subtitles: Subtitles
var _fade: ColorRect
## Cinematic bars for third-person cutscenes.
var _meters: Control
var _bars_top: ColorRect
var _bars_bottom: ColorRect
var _shown_dark_hint := false
var _saved_label: Label
var _saved_time := 0.0
var _shown_hide_hint := false


func _ready() -> void:
	layer = 1
	_build()
	GameState.hint_requested.connect(_show_hint)
	GameState.flashback_requested.connect(_play_flashback)
	GameState.inventory_changed.connect(_update_items)
	GameState.checkpoint_saved.connect(func() -> void: _saved_time = 2.5)
	if GameState.restoring:
		_retry_fade_in()
	else:
		_wake_up()


func _process(delta: float) -> void:
	var player := GameState.player
	if player == null:
		return
	var fl := player.flashlight

	var dark := clampf(fl.exposure / fl.hunt_threshold, 0.0, 1.0)
	_postfx.set_shader_parameter("exposure", dark)

	_prompt.text = player.get_prompt()
	_crosshair.visible = not player.hidden and not GameState.cutscene

	_battery_box.visible = fl.owned
	if fl.owned:
		var pct := fl.battery / 100.0
		_battery_fill.size.x = 156.0 * pct
		_battery_fill.color = Color(0.85, 0.3, 0.2) if pct < 0.2 else Color(0.85, 0.8, 0.55)
		_battery_label.text = "%d%%%s" % [roundi(fl.battery), "  BRIGHT" if fl.bright else ""]

	_stamina_box.visible = player.stamina < 0.999
	_stamina_fill.size.x = 156.0 * player.stamina
	_stamina_fill.color = Color(0.5, 0.25, 0.2) if player.exhausted else Color(0.6, 0.65, 0.7)

	if _saved_time > 0.0:
		_saved_time -= delta
	_saved_label.modulate.a = clampf(_saved_time, 0.0, 1.0)

	if _hint_time > 0.0:
		_hint_time -= delta
		_hint.modulate.a = clampf(_hint_time, 0.0, 1.0)

	if not _shown_dark_hint and fl.owned and fl.exposure >= fl.sense_threshold:
		_shown_dark_hint = true
		_show_hint("The dark is drawing something to you. Get back into the light.", 7.0)
	if not _shown_hide_hint and _any_spirit_chasing():
		_shown_hide_hint = true
		_show_hint("Run. Break line of sight, hide in a wardrobe [E], or hold the bright beam on it.", 8.0)

	if _debug.visible:
		_debug.text = _debug_text(player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_debug.visible = not _debug.visible


# --- Story moments ---------------------------------------------------------------

func _wake_up() -> void:
	GameState.cutscene = true
	_fade.color = Color(0, 0, 0, 1)
	var player := GameState.player
	if player != null:
		player.lying = true
	await get_tree().create_timer(1.0).timeout
	_subtitles.show_now("Jason", "Where... am I? My head...", 3.0)
	await get_tree().create_timer(1.5).timeout
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 2.5)
	await tween.finished
	if player != null:
		player.lying = false
	await get_tree().create_timer(1.6).timeout
	GameState.cutscene = false
	GameState.say("Jason", "Too dark to see a thing. Something's glinting on the bed.", 4.5)
	_show_hint("WASD move  ·  SHIFT sprint  ·  C crouch  ·  E interact  ·  ESC free mouse  ·  F3 debug", 10.0)


func _retry_fade_in() -> void:
	GameState.cutscene = true
	_fade.color = Color(0, 0, 0, 1)
	_update_items()
	await get_tree().create_timer(0.4).timeout
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 1.2)
	await tween.finished
	GameState.cutscene = false
	GameState.finish_restore()
	GameState.say("Jason", "Not again. Keep to the light.", 2.5)


func _play_flashback(fragment_id: String) -> void:
	var fragment: Dictionary = GameState.fragments.get(fragment_id, {})
	if fragment.is_empty():
		push_warning("Unknown memory fragment: %s" % fragment_id)
		return
	GameState.cutscene = true
	var style: String = fragment.get("style", "")
	var is_document := style == "document"
	var is_scene := style == "scene"  # in-world dialogue: no tint
	var tint := Color(0.06, 0.05, 0.04, 0.88) if is_document else Color(0.12, 0.08, 0.05, 0.82)
	if is_scene:
		tint = Color(0, 0, 0, 0)
	var flash := create_tween()
	if is_scene:
		# Dip to black, cut to the cutscene camera, bars in.
		flash.tween_property(_fade, "color", Color(0, 0, 0, 1), 0.35)
		flash.tween_callback(GameState.scene_started.emit.bind(fragment_id))
		flash.tween_callback(_letterbox.bind(true))
		flash.tween_property(_fade, "color", Color(0, 0, 0, 0), 0.5)
	elif is_document:
		flash.tween_property(_fade, "color", tint, 0.5)
	else:
		GameState.play_sfx("flashback", 2.0)
		flash.tween_property(_fade, "color", Color(0.9, 0.85, 0.75, 0.95), 0.25)
		flash.tween_property(_fade, "color", tint, 0.8)
	await flash.finished

	for line: Dictionary in fragment.get("lines", []):
		var duration: float = line.get("duration", 3.0)
		if is_scene:
			GameState.scene_line.emit(fragment_id, line)
		_subtitles.show_now(line.get("speaker", ""), line.get("text", ""), duration)
		await get_tree().create_timer(duration).timeout

	var out := create_tween()
	if is_scene:
		# Dip to black and back into Jason's eyes.
		out.tween_property(_fade, "color", Color(0, 0, 0, 1), 0.45)
		out.tween_callback(GameState.scene_ended.emit.bind(fragment_id))
		out.tween_callback(_letterbox.bind(false))
		out.tween_property(_fade, "color", Color(0, 0, 0, 0), 0.6)
	else:
		out.tween_property(_fade, "color", Color(tint.r, tint.g, tint.b, 0.0), 1.2)
	await out.finished
	GameState.cutscene = false
	for line: Dictionary in fragment.get("after", []):
		GameState.say(line.get("speaker", ""), line.get("text", ""), line.get("duration", 0.0))
	GameState.fragment_finished.emit(fragment_id)


# --- Helpers -------------------------------------------------------------------------

func _letterbox(on: bool) -> void:
	var height := get_viewport().get_visible_rect().size.y * 0.11 if on else 0.0
	_meters.visible = not on
	var tween := create_tween().set_parallel()
	tween.tween_property(_bars_top, "offset_bottom", height, 0.4)
	tween.tween_property(_bars_bottom, "offset_top", -height, 0.4)


func _show_hint(text: String, duration: float) -> void:
	_hint.text = text
	_hint_time = duration


func _update_items() -> void:
	var names: Array[String] = []
	for id: String in GameState.ITEM_NAMES:
		if GameState.has_item(id):
			names.append(GameState.ITEM_NAMES[id])
	_items.text = "\n".join(names)


func _any_spirit_chasing() -> bool:
	for spirit in get_tree().get_nodes_in_group("spirits"):
		if spirit is Spirit and spirit.state == Spirit.State.CHASE:
			return true
	return false


func _debug_text(player: Player) -> String:
	var fl := player.flashlight
	var lines: Array[String] = [
		"FPS %d" % Engine.get_frames_per_second(),
		"battery %.1f%%  on:%s bright:%s" % [fl.battery, fl.on, fl.bright],
		"exposure %.1fs  (sense %.0f / hunt %.0f)" % [fl.exposure, fl.sense_threshold, fl.hunt_threshold],
		"lit area: %s  hidden: %s" % [GameState.is_lit(player.global_position), player.hidden],
		"stamina %.0f%%  noise %.1fm" % [player.stamina * 100.0, player.noise_radius],
	]
	for spirit in get_tree().get_nodes_in_group("spirits"):
		if spirit is Spirit:
			lines.append("spirit %s  weaken %.1f/%.1f  dist %.1fm" % [
				Spirit.State.keys()[spirit.state], spirit.weaken_progress, spirit.weaken_time,
				spirit.global_position.distance_to(player.global_position)])
	return "\n".join(lines)


func _build() -> void:
	# Post-processing first so it draws underneath the UI.
	var fx := ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_postfx = ShaderMaterial.new()
	_postfx.shader = POSTFX_SHADER
	fx.material = _postfx
	add_child(fx)

	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.35)
	_crosshair.size = Vector2(4, 4)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = -_crosshair.size * 0.5
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_prompt = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = 40
	_prompt.offset_bottom = 70
	add_child(_prompt)

	_hint = _label(17, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -500
	_hint.offset_right = 500
	_hint.offset_top = 24
	_hint.offset_bottom = 80
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	add_child(_hint)

	_subtitles = Subtitles.new()
	_subtitles.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitles.offset_left = -520
	_subtitles.offset_right = 520
	_subtitles.offset_top = -150
	_subtitles.offset_bottom = -60
	_subtitles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitles)

	_meters = _bars_panel()
	add_child(_meters)

	_items = _label(16, HORIZONTAL_ALIGNMENT_RIGHT)
	_items.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_items.offset_left = -320
	_items.offset_right = -24
	_items.offset_top = 24
	_items.offset_bottom = 100
	_items.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	add_child(_items)

	_saved_label = _label(15, HORIZONTAL_ALIGNMENT_RIGHT)
	_saved_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_saved_label.offset_left = -260
	_saved_label.offset_right = -24
	_saved_label.offset_top = -56
	_saved_label.offset_bottom = -30
	_saved_label.text = "Progress saved"
	_saved_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_saved_label.modulate.a = 0.0
	add_child(_saved_label)

	_debug = _label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_debug.position = Vector2(16, 16)
	_debug.size = Vector2(600, 200)
	_debug.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_debug.visible = false
	add_child(_debug)

	_bars_top = ColorRect.new()
	_bars_top.color = Color.BLACK
	_bars_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bars_top.offset_bottom = 0.0
	add_child(_bars_top)
	_bars_bottom = ColorRect.new()
	_bars_bottom.color = Color.BLACK
	_bars_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bars_bottom.offset_top = 0.0
	add_child(_bars_bottom)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	add_child(_fade)
	# Subtitles must stay readable over the flashback tint.
	move_child(_subtitles, -1)


func _bars_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.position = Vector2(24, -84)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_battery_box = Control.new()
	root.add_child(_battery_box)
	var battery_back := ColorRect.new()
	battery_back.color = Color(0, 0, 0, 0.5)
	battery_back.size = Vector2(160, 12)
	_battery_box.add_child(battery_back)
	_battery_fill = ColorRect.new()
	_battery_fill.position = Vector2(2, 2)
	_battery_fill.size = Vector2(156, 8)
	_battery_box.add_child(_battery_fill)
	_battery_label = _label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_battery_label.position = Vector2(170, -5)
	_battery_box.add_child(_battery_label)

	_stamina_box = Control.new()
	_stamina_box.position = Vector2(0, 22)
	root.add_child(_stamina_box)
	var stamina_back := ColorRect.new()
	stamina_back.color = Color(0, 0, 0, 0.5)
	stamina_back.size = Vector2(160, 6)
	_stamina_box.add_child(stamina_back)
	_stamina_fill = ColorRect.new()
	_stamina_fill.position = Vector2(2, 1)
	_stamina_fill.size = Vector2(156, 4)
	_stamina_box.add_child(_stamina_fill)
	return root


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 5)
	return label
