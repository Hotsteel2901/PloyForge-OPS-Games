class_name MainMenu
extends CanvasLayer

# 主菜单：标题、模式选择、地图卡片、玩家名、Bot 数量、阵营、开始/退出。

signal start_requested(opts: Dictionary)
signal quit_requested
signal settings_changed(settings: Dictionary)

const ACCENT := Color("ff8b3d")
const SETTINGS_PATH := "user://settings.cfg"

var _root: Control
var _mode_buttons: Array = []
var _map_buttons: Array = []
var _team_buttons: Array = []
var _map_hint_label: Label = null
var _name_edit: LineEdit
var _bots_slider: HSlider
var _bots_value: Label
var _mode: String = "defusal"
var _map_id: String = "vertex"
var _team_pref: String = "random"

var _settings_panel: Control = null
var _settings: Dictionary = {"fov": 74.0, "volume": 1.0, "bgm": true}
var _fov_slider: HSlider = null
var _vol_slider: HSlider = null
var _bgm_check: CheckButton = null
var _fov_value: Label = null
var _vol_value: Label = null


func _ready() -> void:
	_load_settings()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.07, 0.09, 0.14),
		Color(0.05, 0.06, 0.1),
		Color(0.09, 0.05, 0.04),
	])
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	bg.texture = tex
	_root.add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.custom_minimum_size = Vector2(760, 640)
	center.offset_left = -380
	center.offset_top = -320
	center.offset_right = 380
	center.offset_bottom = 320
	center.add_theme_constant_override("separation", 14)
	_root.add_child(center)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	center.add_child(title_row)
	var title_a := _mk_label("P O L Y F O R G E :", 42, Color(0.95, 0.97, 1.0), title_row)
	_make_glow(title_a)
	var title_b := _mk_label("O P S", 42, ACCENT, title_row)
	_make_glow(title_b)

	var subtitle := _mk_label("3A 级战术射击 · 本地 Bot 对战", 16, Color(0.6, 0.64, 0.72), center)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(HSeparator.new())
	center.add_child(HSeparator.new())

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 16)
	center.add_child(mode_row)
	_build_mode_buttons(mode_row)

	_mk_label("选择地图", 15, Color(0.7, 0.74, 0.82), center)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 18)
	center.add_child(map_row)
	_build_map_cards(map_row)
	# 禁用地图提示（拆弹模式下无安放点的图不可选）
	_map_hint_label = _mk_label("", 13, Color(1.0, 0.55, 0.35), center)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	center.add_child(name_row)
	_mk_label("玩家名", 16, Color(0.75, 0.78, 0.85), name_row)
	_name_edit = LineEdit.new()
	_name_edit.text = "Player1"
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(220, 34)
	var lesb := StyleBoxFlat.new()
	lesb.bg_color = Color(0.1, 0.12, 0.17, 0.9)
	lesb.border_color = Color(1.0, 1.0, 1.0, 0.25)
	lesb.set_border_width_all(1)
	lesb.set_corner_radius_all(6)
	_name_edit.add_theme_stylebox_override("normal", lesb)
	var lesb_f := lesb.duplicate()
	lesb_f.border_color = Color(ACCENT, 0.8)
	_name_edit.add_theme_stylebox_override("focus", lesb_f)
	name_row.add_child(_name_edit)

	var bot_row := HBoxContainer.new()
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_row.add_theme_constant_override("separation", 12)
	center.add_child(bot_row)
	_mk_label("Bot 数量", 16, Color(0.75, 0.78, 0.85), bot_row)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 4
	_bots_slider.max_value = 10
	_bots_slider.step = 1
	_bots_slider.value = 8
	_bots_slider.custom_minimum_size = Vector2(240, 28)
	_bots_slider.value_changed.connect(func(v: float): _bots_value.text = str(int(v)))
	bot_row.add_child(_bots_slider)
	_bots_value = _mk_label("8", 16, ACCENT, bot_row)

	var team_row := HBoxContainer.new()
	team_row.alignment = BoxContainer.ALIGNMENT_CENTER
	team_row.add_theme_constant_override("separation", 12)
	center.add_child(team_row)
	_mk_label("阵营", 16, Color(0.75, 0.78, 0.85), team_row)
	_build_team_buttons(team_row)

	center.add_child(HSeparator.new())

	var start_btn := _make_primary_button("开始游戏")
	start_btn.custom_minimum_size = Vector2(300, 52)
	start_btn.pressed.connect(_on_start)
	center.add_child(start_btn)

	var settings_btn := _make_ghost_button("设置")
	settings_btn.custom_minimum_size = Vector2(300, 40)
	settings_btn.pressed.connect(_show_settings)
	center.add_child(settings_btn)

	var quit_btn := _make_ghost_button("退出")
	quit_btn.custom_minimum_size = Vector2(300, 40)
	quit_btn.pressed.connect(func(): quit_requested.emit())
	center.add_child(quit_btn)

	_build_settings_panel()


func show_menu() -> void:
	if _root != null:
		_root.visible = true
	_hide_settings()


func hide_menu() -> void:
	if _root != null:
		_root.visible = false
	_hide_settings()


func _on_start() -> void:
	_save_settings()
	start_requested.emit({
		"mode": _mode,
		"mapId": _map_id,
		"botCount": int(_bots_slider.value),
		"playerName": _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Player1",
		"teamPref": _team_pref,
	})


func get_settings() -> Dictionary:
	return _settings.duplicate()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_settings.fov = clampf(cfg.get_value("game", "fov", 74.0), 70.0, 110.0)
		_settings.volume = clampf(cfg.get_value("game", "volume", 1.0), 0.0, 1.0)
		_settings.bgm = bool(cfg.get_value("game", "bgm", true))
	else:
		_settings = {"fov": 74.0, "volume": 1.0, "bgm": true}


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "fov", _settings.fov)
	cfg.set_value("game", "volume", _settings.volume)
	cfg.set_value("game", "bgm", _settings.bgm)
	cfg.save(SETTINGS_PATH)


func _show_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = true
		_fov_slider.value = _settings.fov
		_vol_slider.value = _settings.volume
		_bgm_check.button_pressed = _settings.bgm
		_fov_value.text = str(int(_settings.fov))
		_vol_value.text = "%d%%" % int(_settings.volume * 100.0)


func _hide_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false


func _build_settings_panel() -> void:
	_settings_panel = Control.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 360)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.08, 0.11, 0.96)
	psb.border_color = Color(1, 1, 1, 0.18)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(12)
	psb.content_margin_left = 28
	psb.content_margin_right = 28
	psb.content_margin_top = 24
	psb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", psb)
	_settings_panel.add_child(panel)

	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 14)
	panel.add_child(vl)

	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	vl.add_child(title)

	vl.add_child(_make_slider_row("FOV", 70, 110, _settings.fov, func(v: float):
		_settings.fov = v
		_fov_value.text = str(int(v))
		settings_changed.emit(_settings.duplicate())
	))
	_fov_slider = _last_slider()
	_fov_value = _last_value_label()

	vl.add_child(_make_slider_row("主音量", 0, 100, int(_settings.volume * 100.0), func(v: float):
		_settings.volume = v / 100.0
		_vol_value.text = "%d%%" % int(v)
		settings_changed.emit(_settings.duplicate())
	))
	_vol_slider = _last_slider()
	_vol_value = _last_value_label()

	var bgm_row := HBoxContainer.new()
	bgm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bgm_row.add_theme_constant_override("separation", 12)
	vl.add_child(bgm_row)
	_mk_label("背景音乐", 16, Color(0.8, 0.83, 0.9), bgm_row)
	_bgm_check = CheckButton.new()
	_bgm_check.button_pressed = _settings.bgm
	_bgm_check.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	_bgm_check.toggled.connect(func(on: bool):
		_settings.bgm = on
		settings_changed.emit(_settings.duplicate())
	)
	bgm_row.add_child(_bgm_check)

	var close_btn := _make_ghost_button("关闭")
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(_hide_settings)
	vl.add_child(close_btn)


var _last_slider_ref: HSlider = null
var _last_value_label_ref: Label = null


func _make_slider_row(label: String, min_v: int, max_v: int, value: float, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_mk_label(label, 16, Color(0.8, 0.83, 0.9), row)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 1
	slider.value = value
	slider.custom_minimum_size = Vector2(180, 28)
	slider.value_changed.connect(changed)
	row.add_child(slider)
	_last_slider_ref = slider
	var val := _mk_label(str(int(value)), 16, ACCENT, row)
	_last_value_label_ref = val
	return row


func _last_slider() -> HSlider:
	return _last_slider_ref


func _last_value_label() -> Label:
	return _last_value_label_ref


# ---------- 构建 ----------
func _build_mode_buttons(parent: Node) -> void:
	var modes: Array = [
		["defusal", "拆弹模式"],
		["zombie", "生化模式"],
	]
	for m in modes:
		var id: String = m[0]
		var label: String = m[1]
		var btn := _make_toggle_button(label)
		btn.pressed.connect(func(): _select_mode(id, btn))
		parent.add_child(btn)
		_mode_buttons.append(btn)
	_select_mode("defusal", _mode_buttons[0])


func _select_mode(id: String, selected: Button) -> void:
	_mode = id
	_refresh_toggles(_mode_buttons, selected)


func _select_team(id: String, selected: Button) -> void:
	_team_pref = id
	_refresh_toggles(_team_buttons, selected)


# 显式刷新一组 toggle 按钮的选中样式（Button 的 pressed 样式绘制有时不刷新，
# 直接替换 normal/hover 样式保证选中态一眼可见）
func _refresh_toggles(buttons: Array, selected: Button) -> void:
	for b in buttons:
		var is_sel: bool = b == selected
		b.button_pressed = is_sel
		var sb_n: StyleBoxFlat = b.get_meta("sb_normal", null)
		var sb_on: StyleBoxFlat = b.get_meta("sb_on", null)
		if sb_n != null and sb_on != null:
			b.add_theme_stylebox_override("normal", sb_on if is_sel else sb_n)
			b.add_theme_stylebox_override("hover", sb_on if is_sel else sb_n)
			b.add_theme_stylebox_override("pressed", sb_on)
			b.add_theme_stylebox_override("hover_pressed", sb_on)


func _build_map_cards(parent: Node) -> void:
	var ids: Array = []
	if MapData != null and MapData.has_method("get_map_ids"):
		ids = MapData.get_map_ids()
	else:
		ids = ["vertex", "containment", "obsidian"]
	for id in ids:
		var m: Dictionary = {}
		if MapData != null and MapData.has_method("get_map"):
			m = MapData.get_map(str(id))
		var name: String = str(m.get("name", id))
		var sky: Dictionary = m.get("sky", {}) if m.has("sky") else {}
		var c1: Color = sky.get("top", Color(0.16, 0.2, 0.32))
		var c2: Color = sky.get("bottom", Color(0.3, 0.34, 0.42))
		# 拆弹模式禁用无安放点的地图（如实验室 containment），否则 bot 会在
		# 空 sites 数组上除零/越界导致卡死闪退。禁用的卡片点击无效并提示。
		var mode: String = m.get("mode", "defusal")
		var valid: bool = mode != "defusal" or not m.get("sites", []).is_empty()
		_map_buttons.append(_make_map_card(str(id), name, c1, c2, parent, valid))
	_map_id = str(ids[0]) if not ids.is_empty() else "vertex"
	if not _map_buttons.is_empty():
		_select_map(_map_id, _map_buttons[0] as Button)


func _make_map_card(id: String, name: String, c1: Color, c2: Color, parent: Node, valid: bool = true) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(210, 120)
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_constant_override("outline_size", 0)
	card.disabled = not valid
	card.set_meta("map_valid", valid)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 1.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([c1, c2])
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	var bg_tex := TextureRect.new()
	bg_tex.texture = tex
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg_tex)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shade)
	var l := Label.new()
	l.text = name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(l)
	# "已选"角标：选中时显示，未选中隐藏
	var sel_tag := Label.new()
	sel_tag.text = "✓ 已选"
	sel_tag.add_theme_font_size_override("font_size", 13)
	sel_tag.add_theme_color_override("font_color", Color("ffd08a"))
	sel_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sel_tag.add_theme_constant_override("outline_size", 3)
	sel_tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sel_tag.position = Vector2(-8, 4)
	sel_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_tag.visible = false
	card.add_child(sel_tag)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.0)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.22)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.border_color = Color(1.0, 1.0, 1.0, 0.6)
	var on := normal.duplicate()
	on.border_color = Color(ACCENT, 1.0)
	on.bg_color = Color(ACCENT, 0.16)
	on.set_border_width_all(3)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", on)
	card.add_theme_stylebox_override("hover_pressed", on)
	card.add_theme_stylebox_override("focus", normal)
	# 记录样式与角标引用，_select_map 里显式刷新选中态
	card.set_meta("sb_normal", normal)
	card.set_meta("sb_on", on)
	card.set_meta("sel_tag", sel_tag)
	card.pressed.connect(func(): _select_map(id, card))
	parent.add_child(card)
	return card


func _select_map(id: String, selected: Button) -> void:
	# 拆弹模式下禁用的地图（无安放点）点击无效，提示用户
	if not bool(selected.get_meta("map_valid", true)):
		if _map_hint_label != null:
			_map_hint_label.text = "该地图无安放点，拆弹模式不可用"
		return
	if _map_hint_label != null:
		_map_hint_label.text = ""
	_map_id = id
	for b in _map_buttons:
		var is_sel: bool = b == selected
		b.button_pressed = is_sel
		var sb_n: StyleBoxFlat = b.get_meta("sb_normal", null)
		var sb_on: StyleBoxFlat = b.get_meta("sb_on", null)
		if sb_n != null and sb_on != null:
			# 显式切换 normal 样式：Button 的 pressed 状态会显示 pressed 样式，
			# 但为避免 toggle 绘制不刷新，直接把 normal/hover 也换成选中样式
			b.add_theme_stylebox_override("normal", sb_on if is_sel else sb_n)
			b.add_theme_stylebox_override("hover", sb_on if is_sel else sb_n)
			b.add_theme_stylebox_override("pressed", sb_on)
			b.add_theme_stylebox_override("hover_pressed", sb_on)
		var tag: Control = b.get_meta("sel_tag", null)
		if tag != null:
			tag.visible = is_sel


func _build_team_buttons(parent: Node) -> void:
	var teams: Array = [
		["random", "随机"],
		["ct", "CT"],
		["t", "T"],
	]
	for tm in teams:
		var id: String = tm[0]
		var label: String = tm[1]
		var btn := _make_toggle_button(label)
		btn.pressed.connect(func(): _select_team(id, btn))
		parent.add_child(btn)
		_team_buttons.append(btn)
	_select_team("random", _team_buttons[0])


func _make_toggle_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 40)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.12, 0.17, 0.9)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.25)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.18, 0.25, 0.95)
	hover.border_color = Color(1.0, 1.0, 1.0, 0.5)
	var on := normal.duplicate()
	on.bg_color = Color(ACCENT, 0.25)
	on.border_color = Color(ACCENT, 0.95)
	var pressed_sb := on.duplicate()
	pressed_sb.bg_color = Color(ACCENT, 0.35)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("hover_pressed", pressed_sb)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_stylebox_override("focus_hover", hover)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.set_meta("sb_normal", normal)
	btn.set_meta("sb_on", on)
	return btn


func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT
	normal.border_color = Color(1.0, 1.0, 1.0, 0.3)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color("ffa05a")
	hover.border_color = Color(1.0, 1.0, 1.0, 0.55)
	var pressed_sb := normal.duplicate()
	pressed_sb.bg_color = Color("e07630")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("hover_pressed", pressed_sb)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.12, 0.07, 0.03))
	return btn


func _make_ghost_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.12, 0.17, 0.9)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.2)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.2, 0.27, 0.95)
	hover.border_color = Color(1.0, 1.0, 1.0, 0.45)
	var pressed_sb := hover.duplicate()
	pressed_sb.bg_color = Color(0.22, 0.24, 0.31, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
	return btn


func _make_glow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.2, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 6)


func _mk_label(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
