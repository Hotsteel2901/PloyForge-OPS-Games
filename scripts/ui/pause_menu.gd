# PauseMenu: Esc 暂停菜单（恢复 / 返回主菜单 / 退出）。
class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal menu_requested
signal quit_requested

var _root: Control


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(340, 300)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.08, 0.11, 0.96)
	psb.border_color = Color(1, 1, 1, 0.18)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(10)
	psb.content_margin_left = 30
	psb.content_margin_right = 30
	psb.content_margin_top = 26
	psb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", psb)
	_root.add_child(panel)

	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 12)
	panel.add_child(vl)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	vl.add_child(title)

	vl.add_child(_btn("RESUME", resume_requested))
	vl.add_child(_btn("BACK TO MENU", menu_requested))
	vl.add_child(_btn("QUIT", quit_requested))


func _btn(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.18, 0.24, 0.95)
	normal.border_color = Color(1, 1, 1, 0.14)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.22, 0.30, 0.42, 0.95)
	hover.border_color = Color(1, 1, 1, 0.35)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.pressed.connect(func(): sig.emit())
	return b


func show_menu() -> void:
	_root.visible = true


func hide_menu() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible
