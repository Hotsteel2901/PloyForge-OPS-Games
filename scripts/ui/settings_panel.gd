# 设置面板（v2）：完全由 Settings.SCHEMA 驱动，6 个分类、45+ 项。
# 新增一个设置项只需改 scripts/core/settings.gd 的 SCHEMA，这里自动出现控件。
class_name SettingsPanel
extends CanvasLayer

signal closed()

const SECTIONS: Array = [
	{"id": "graphics", "label": "画面", "desc": "分辨率、后处理、特效开关"},
	{"id": "audio", "label": "声音", "desc": "总线音量与 3D 定位"},
	{"id": "controls", "label": "操作", "desc": "鼠标、触屏、陀螺仪与辅助瞄准"},
	{"id": "gameplay", "label": "玩法", "desc": "准星、命中反馈、界面信息"},
	{"id": "network", "label": "联机", "desc": "中继、直连与延迟"},
	{"id": "accessibility", "label": "辅助", "desc": "色盲、动效与字号"},
]

const ENUM_LABELS: Dictionary = {
	"graphics/quality": ["土豆", "低", "中", "高", "极致"],
	"gameplay/crosshair_style": ["十字", "点", "圆环", "三角"],
	"gameplay/crosshair_color": ["青色", "绿色", "红色", "黄色", "白色", "品红"],
	"accessibility/colorblind": ["关闭", "红色盲", "绿色盲", "蓝黄色盲"],
}

const ACCENT := Color("ff8b3d")

var _root: Control
var _content: VBoxContainer
var _tabs: Array = []
var _current: String = "graphics"
var _title: Label
var _toast: Label
var _toast_t: float = 0.0
var _build_token: int = 0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 24
	panel.offset_right = -40
	panel.offset_bottom = -24
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.065, 0.09, 0.99)
	psb.border_color = Color(1, 1, 1, 0.16)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(14)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 16
	psb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", psb)
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	# ----- 标题行 -----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	outer.add_child(head)
	_title = Label.new()
	_title.text = "设置"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1, 1, 1))
	head.add_child(_title)
	var hint := Label.new()
	hint.text = "改动即时生效并自动保存"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_top := _flat_button("✕", 38)
	close_top.pressed.connect(close)
	head.add_child(close_top)

	outer.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)

	# ----- 左侧分类 -----
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(176, 0)
	nav.add_theme_constant_override("separation", 6)
	body.add_child(nav)
	for s in SECTIONS:
		var b := Button.new()
		b.text = str(s.label)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("sid", str(s.id))
		b.pressed.connect(func() -> void: _select(str(s.id)))
		nav.add_child(b)
		_tabs.append(b)
	var nav_hint := Label.new()
	nav_hint.text = "共 %d 项" % _count_items()
	nav_hint.add_theme_font_size_override("font_size", 12)
	nav_hint.add_theme_color_override("font_color", Color(0.45, 0.5, 0.58))
	nav_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	nav.add_child(nav_hint)

	# ----- 右侧滚动内容 -----
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	outer.add_child(HSeparator.new())

	# ----- 底部 -----
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	outer.add_child(foot)
	var reset_btn := _flat_button("恢复默认", 92)
	reset_btn.pressed.connect(_on_reset)
	foot.add_child(reset_btn)
	var export_btn := _flat_button("导出配置", 100)
	export_btn.pressed.connect(_on_export)
	foot.add_child(export_btn)
	var import_btn := _flat_button("导入配置", 100)
	import_btn.pressed.connect(_on_import)
	foot.add_child(import_btn)
	_toast = Label.new()
	_toast.text = ""
	_toast.add_theme_font_size_override("font_size", 13)
	_toast.add_theme_color_override("font_color", Color("7ddc8f"))
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_toast)
	var done := _flat_button("完成", 116)
	done.add_theme_stylebox_override("normal", _accent_style(ACCENT))
	done.pressed.connect(close)
	foot.add_child(done)

	set_process(true)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
		if _toast_t <= 0.0:
			_toast.text = ""


func _count_items() -> int:
	var n: int = 0
	for s in SECTIONS:
		n += Settings.schema(str(s.id)).size()
	return n


func open(section: String = "") -> void:
	_root.visible = true
	if section != "":
		_current = section
	_rebuild()
	_refresh_tabs()


func close() -> void:
	_root.visible = false
	Settings.flush()
	closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


func _select(sid: String) -> void:
	if _current == sid:
		return
	_current = sid
	_rebuild()
	_refresh_tabs()


func _refresh_tabs() -> void:
	for b in _tabs:
		var sel: bool = str(b.get_meta("sid", "")) == _current
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.22) if sel else Color(1, 1, 1, 0.04)
		sb.border_color = Color(ACCENT, 0.9) if sel else Color(1, 1, 1, 0.10)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", sb)
		var hov := sb.duplicate()
		hov.bg_color = Color(ACCENT, 0.30) if sel else Color(1, 1, 1, 0.10)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_color_override("font_color", Color(1, 1, 1) if sel else Color(0.78, 0.82, 0.9))
		b.add_theme_font_size_override("font_size", 16)


func _rebuild() -> void:
	_build_token += 1
	for c in _content.get_children():
		c.queue_free()
	var sec: Dictionary = _section_by_id(_current)
	_title.text = "设置 · %s" % str(sec.get("label", _current))
	var desc := Label.new()
	desc.text = str(sec.get("desc", ""))
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_content.add_child(desc)

	var schema: Dictionary = Settings.schema(_current)
	for key in schema:
		var spec: Dictionary = schema[key]
		_content.add_child(_make_row(_current, str(key), spec))
	# 每类补一条说明，避免"设置项没实现"的观感
	var note := Label.new()
	note.text = _section_note(_current)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.45, 0.5, 0.58))
	_content.add_child(note)


func _section_note(sid: String) -> String:
	match sid:
		"graphics":
			return "低画质会关闭 SSAO / SSR / 体积雾并降低阴影分辨率；自适应分辨率会在掉帧时自动降 3D 分辨率（UI 不受影响）。"
		"controls":
			return "触屏设备上鼠标相关项自动隐藏；陀螺仪需要设备有传感器；辅助瞄准仅在触屏/手柄生效。"
		"network":
			return "中继地址留空则使用内置公网中继；局域网发现通过 UDP 广播，同一 Wi-Fi 下可直接看到房间。"
		"accessibility":
			return "色盲模式会替换血量/队伍/准星配色；减少动效会关闭屏幕震动与镜头晃动。"
		_:
			return ""


func _make_row(section: String, key: String, spec: Dictionary) -> Control:
	var kind: String = str(spec.get("kind", "float"))
	var label_text: String = str(spec.get("label", key))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 38)

	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	row.add_child(l)

	match kind:
		"bool":
			var cb := CheckButton.new()
			cb.button_pressed = Settings.get_bool(section, key)
			cb.size_flags_horizontal = Control.SIZE_SHRINK_END
			cb.toggled.connect(func(on: bool) -> void:
				Settings.set_value(section, key, on)
				Settings.apply()
			)
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pad)
			row.add_child(cb)
		"enum":
			var ob := OptionButton.new()
			var labels: Array = ENUM_LABELS.get("%s/%s" % [section, key], [])
			var lo: int = int(spec.get("min", 0))
			var hi: int = int(spec.get("max", 3))
			for i in range(lo, hi + 1):
				var idx: int = i - lo
				ob.add_item(str(labels[idx]) if idx < labels.size() else str(i), i)
			ob.selected = clampi(Settings.get_int(section, key) - lo, 0, maxi(0, ob.item_count - 1))
			ob.custom_minimum_size = Vector2(180, 32)
			ob.item_selected.connect(func(i: int) -> void:
				Settings.set_value(section, key, lo + i)
				Settings.apply()
			)
			var pad2 := Control.new()
			pad2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pad2)
			row.add_child(ob)
		"string":
			var le := LineEdit.new()
			le.text = Settings.get_str(section, key)
			le.custom_minimum_size = Vector2(240, 32)
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_submitted.connect(func(t: String) -> void: Settings.set_value(section, key, t))
			le.focus_exited.connect(func() -> void: Settings.set_value(section, key, le.text))
			row.add_child(le)
		_:
			# int / float：滑块 + 数值
			var is_int: bool = kind == "int"
			var lo: float = float(spec.get("min", 0.0))
			var hi: float = float(spec.get("max", 1.0))
			var step: float = float(spec.get("step", 1.0 if is_int else 0.01))
			var slider := HSlider.new()
			slider.min_value = lo
			slider.max_value = hi
			slider.step = step
			slider.value = Settings.get_float(section, key)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.custom_minimum_size = Vector2(160, 26)
			var val := Label.new()
			val.custom_minimum_size = Vector2(74, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val.add_theme_font_size_override("font_size", 14)
			val.add_theme_color_override("font_color", ACCENT)
			val.text = _fmt(slider.value, is_int, section, key)
			slider.value_changed.connect(func(v: float) -> void:
				Settings.set_value(section, key, v)
				Settings.apply()
				val.text = _fmt(v, is_int, section, key)
			)
			row.add_child(slider)
			row.add_child(val)
	return row


func _fmt(v: float, is_int: bool, section: String, key: String) -> String:
	if is_int:
		if section == "graphics" and key == "fps_limit":
			return "不限" if int(v) <= 0 else "%d" % int(v)
		return "%d" % int(v)
	if section == "graphics" and key == "render_scale":
		return "%d%%" % int(round(v * 100.0))
	if section == "audio" or key.ends_with("sens") or key == "aim_assist" or key == "touch_opacity":
		return "%d%%" % int(round(v * 100.0))
	if key == "gamma":
		return "%.2f" % v
	return "%.2f" % v


func _section_by_id(sid: String) -> Dictionary:
	for s in SECTIONS:
		if str(s.id) == sid:
			return s
	return {"label": sid, "desc": ""}


func _flat_button(text: String, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _accent_style(Color(1, 1, 1, 0.07)))
	b.add_theme_stylebox_override("hover", _accent_style(Color(1, 1, 1, 0.14)))
	b.add_theme_stylebox_override("pressed", _accent_style(Color(1, 1, 1, 0.2)))
	b.add_theme_color_override("font_color", Color(0.88, 0.91, 0.96))
	return b


func _accent_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


func _on_reset() -> void:
	Settings.reset_all()
	_rebuild()
	_toast_msg("已恢复默认设置")


func _on_export() -> void:
	var js: String = Settings.export_json()
	var f := FileAccess.open("user://settings_export.json", FileAccess.WRITE)
	if f != null:
		f.store_string(js)
		f.close()
	DisplayServer.clipboard_set(js)
	_toast_msg("已导出（并复制到剪贴板）")


func _on_import() -> void:
	if not FileAccess.file_exists("user://settings_export.json"):
		_toast_msg("未找到导出的配置文件")
		return
	var f := FileAccess.open("user://settings_export.json", FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	if Settings.import_json(txt):
		_rebuild()
		_toast_msg("配置已导入")
	else:
		_toast_msg("配置格式错误")


func _toast_msg(s: String) -> void:
	if _toast != null:
		_toast.text = s
		_toast_t = 3.0
