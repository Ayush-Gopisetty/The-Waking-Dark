class_name MenuStyle
extends RefCounted
## The look shared by the title screen, pause menu and settings: dark flat buttons,
## thin sliders, pale text.

const TEXT := Color(0.82, 0.83, 0.85)
const DIM := Color(0.55, 0.57, 0.62)
const ACCENT := Color(0.78, 0.84, 0.95)

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _box(fill: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(2)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


static func _build() -> Theme:
	var t := Theme.new()
	t.set_default_font_size(18)

	t.set_stylebox("normal", "Button", _box(Color(0.06, 0.065, 0.08, 0.78), Color(0.22, 0.24, 0.3)))
	t.set_stylebox("hover", "Button", _box(Color(0.1, 0.11, 0.14, 0.9), Color(0.55, 0.62, 0.78)))
	t.set_stylebox("focus", "Button", _box(Color(0.1, 0.11, 0.14, 0.9), Color(0.55, 0.62, 0.78)))
	t.set_stylebox("pressed", "Button", _box(Color(0.15, 0.16, 0.2, 0.95), Color(0.78, 0.84, 0.95)))
	t.set_stylebox("disabled", "Button", _box(Color(0.05, 0.05, 0.06, 0.5), Color(0.15, 0.16, 0.19)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.44))
	t.set_constant("h_separation", "Button", 10)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.2, 0.22, 0.27)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.7, 0.86)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	var panel := _box(Color(0.03, 0.035, 0.045, 0.94), Color(0.18, 0.2, 0.25))
	panel.content_margin_left = 30
	panel.content_margin_right = 30
	panel.content_margin_top = 26
	panel.content_margin_bottom = 26
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


## A menu button: wide, left-aligned text off, centred.
static func button(text: String, min_width: float = 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
