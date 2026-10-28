# 联机面板：局域网/中继建房、房间码加入、房间列表、状态显示。
# 设计目标：手机上一只手也能开房；桌面端可以直接输入 IP 直连。
class_name NetPanel
extends Control

signal closed()
signal start_host(opts: Dictionary)
signal start_join(url_or_code: String, opts: Dictionary)

const ACCENT := Color("5a9dff")
const BG := Color(0.04, 0.05, 0.08, 0.96)

var _name_edit: LineEdit
var _relay_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _list: VBoxContainer
var _lan_list: VBoxContainer
var _tabs: TabContainer
var _busy: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	Net.status_changed.connect(_on_status)
	Net.error_occurred.connect(func(t): _set_status("⚠ " + t, Color(1, 0.45, 0.4)))
	Net.room_list_updated.connect(_render_relay_rooms)


func open() -> void:
	visible = true
	_refresh()
	Net.fetch_rooms()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------------- UI ----------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 560)
	panel.position = -panel.custom_minimum_size * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	root.add_child(_label("联机对战", 28, Color.WHITE))
	root.add_child(_label("局域网零配置 · 公网走中继（无需端口映射）· 也可直连 IP", 13, Color(0.65, 0.7, 0.8)))

	var name_row := HBoxContainer.new()
	name_row.add_child(_label("昵称", 15, Color(0.8, 0.84, 0.92)))
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.get_str("gameplay", "player_name")
	_name_edit.custom_minimum_size = Vector2(240, 38)
	name_row.add_child(_name_edit)
	root.add_child(name_row)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 300)
	root.add_child(_tabs)

	# --- 局域网 / 直连 ---
	var p1 := VBoxContainer.new()
	p1.name = "局域网 / 直连"
	p1.add_theme_constant_override("separation", 8)
	_tabs.add_child(p1)
	p1.add_child(_label("同一 WiFi 下可直接开房；外网直连需要路由器端口映射 7777。", 12, Color(0.6, 0.66, 0.76)))
	var b1 := _button("创建局域网房间", ACCENT)
	b1.pressed.connect(_on_host_lan)
	p1.add_child(b1)
	var jrow := HBoxContainer.new()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "房主 IP，例如 192.168.1.20:7777"
	_code_edit.custom_minimum_size = Vector2(360, 38)
	jrow.add_child(_code_edit)
	var b2 := _button("加入", Color("7ddc8f"))
	b2.pressed.connect(_on_join_direct)
	jrow.add_child(b2)
	p1.add_child(jrow)
	p1.add_child(_label("附近房间（自动发现）", 13, Color(0.7, 0.75, 0.85)))
	_lan_list = VBoxContainer.new()
	p1.add_child(_lan_list)

	# --- 中继 ---
	var p2 := VBoxContainer.new()
	p2.name = "公网中继"
	p2.add_theme_constant_override("separation", 8)
	_tabs.add_child(p2)
	p2.add_child(_label("中继服务器地址（自建见 docs/NETWORKING.md）", 12, Color(0.6, 0.66, 0.76)))
	_relay_edit = LineEdit.new()
	_relay_edit.text = Net.relay_url
	_relay_edit.custom_minimum_size = Vector2(420, 38)
	p2.add_child(_relay_edit)
	var hrow := HBoxContainer.new()
	var b3 := _button("创建中继房间", Color("ffd83d"))
	b3.pressed.connect(_on_host_relay)
	hrow.add_child(b3)
	var b4 := _button("刷新房间列表", Color(0.6, 0.7, 0.85))
	b4.pressed.connect(func(): Net.fetch_rooms())
	hrow.add_child(b4)
	p2.add_child(hrow)
	var crow := HBoxContainer.new()
	var code2 := LineEdit.new()
	code2.placeholder_text = "4 位房间码"
	code2.custom_minimum_size = Vector2(160, 38)
	code2.name = "Code"
	crow.add_child(code2)
	var b5 := _button("加入房间", Color("7ddc8f"))
	b5.pressed.connect(func(): _on_join_relay(code2.text))
	crow.add_child(b5)
	p2.add_child(crow)
	_list = VBoxContainer.new()
	p2.add_child(_list)

	# --- 状态 ---
	_status = _label("", 13, Color(0.7, 0.8, 0.9))
	root.add_child(_status)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var back := _button("返回", Color(0.5, 0.55, 0.65))
	back.pressed.connect(close)
	bottom.add_child(back)
	root.add_child(bottom)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 40)
	b.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxFlat.new()
	n.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.3, 0.9)
	n.border_color = color
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	n.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.45, 0.95)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	return b


# ---------------- 动作 ----------------

func _opts() -> Dictionary:
	var n: String = _name_edit.text.strip_edges()
	if n == "":
		n = "Operator"
	Settings.set_value("gameplay", "player_name", n)
	return {"name": n, "botCount": 6, "mode": "defusal", "mapId": "cinder", "team": "random"}


func _on_host_lan() -> void:
	if _busy:
		return
	_busy = true
	_set_status("正在开启端口 7777…", Color(0.8, 0.9, 1.0))
	var o: Dictionary = _opts()
	o["mode"] = "defusal"
	if Net.host_local(NetProtocol.PORT, o):
		_set_status("房间已开启：%s" % str(Net.lan.rooms()), Color(0.6, 1.0, 0.7))
		start_host.emit(o)
	else:
		_set_status("开房失败：" + Net.last_error, Color(1, 0.5, 0.4))
	_busy = false


func _on_host_relay() -> void:
	if _busy:
		return
	_busy = true
	var url: String = _relay_edit.text.strip_edges()
	if url == "":
		_set_status("请先填写中继地址", Color(1, 0.7, 0.4))
		_busy = false
		return
	Settings.set_value("network", "relay_url", url)
	_set_status("正在连接中继…", Color(0.8, 0.9, 1.0))
	var o: Dictionary = _opts()
	if Net.host_relay(url, "", o):
		_set_status("房间码：%s" % Net.room_code, Color(0.6, 1.0, 0.7))
		start_host.emit(o)
	else:
		_set_status("开房失败：" + Net.last_error, Color(1, 0.5, 0.4))
	_busy = false


func _on_join_direct() -> void:
	var t: String = _code_edit.text.strip_edges()
	if t == "":
		return
	_set_status("正在连接 %s…" % t, Color(0.8, 0.9, 1.0))
	if Net.join(t, _opts()):
		start_join.emit(t, _opts())


func _on_join_relay(code: String) -> void:
	var c: String = code.strip_edges().to_upper()
	if c == "":
		_set_status("请输入房间码", Color(1, 0.7, 0.4))
		return
	var url: String = _relay_edit.text.strip_edges()
	Settings.set_value("network", "relay_url", url)
	_set_status("正在加入 %s…" % c, Color(0.8, 0.9, 1.0))
	if Net.join(c, _opts()):
		start_join.emit(c, _opts())


func _refresh() -> void:
	_name_edit.text = Settings.get_str("gameplay", "player_name")
	_relay_edit.text = Net.relay_url


func _on_status(st: int, detail: String) -> void:
	match st:
		Net.Status.HOST:
			_set_status("房主 · " + detail, Color(0.6, 1.0, 0.7))
		Net.Status.CLIENT:
			_set_status("已连接 · " + detail, Color(0.6, 1.0, 0.7))
		Net.Status.CONNECTING:
			_set_status("连接中…", Color(1.0, 0.85, 0.4))
		_:
			_set_status(detail, Color(0.7, 0.75, 0.85))


func _set_status(text: String, color: Color) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _process(_d: float) -> void:
	if not visible:
		return
	# 局域网房间列表
	if _lan_list != null:
		var rooms: Array = Net.lan.rooms()
		if rooms.size() != _lan_list.get_child_count():
			for c in _lan_list.get_children():
				c.queue_free()
			for r in rooms:
				var b := _button("%s  ·  %s  ·  %s" % [str(r.get("room", "")), str(r.get("ip", "")), str(r.get("mode", ""))], Color("54d6d6"))
				var ip: String = str(r.get("ip", ""))
				var port: int = int(r.get("port", 7777))
				b.pressed.connect(func(): _code_edit.text = "%s:%d" % [ip, port])
				_lan_list.add_child(b)


func _render_relay_rooms(arr: Array) -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	if arr.is_empty():
		_list.add_child(_label("（暂无公开房间）", 12, Color(0.55, 0.6, 0.7)))
		return
	for r in arr:
		var code: String = str(r.get("code", ""))
		var txt: String = "%s  %s/%s  %d/%d  %dms" % [
			code, str(r.get("mode", "")), str(r.get("map", "")),
			int(r.get("players", 0)), int(r.get("max", 12)), int(r.get("ping", 0)),
		]
		var b := _button(txt, ACCENT)
		b.pressed.connect(func(): _on_join_relay(code))
		_list.add_child(b)
