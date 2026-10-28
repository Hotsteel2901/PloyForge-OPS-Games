# 移动端虚拟手柄：左摇杆移动 + 右侧拖拽视角 + 全套功能键。
# 直接写入 InputHandler 的 input/edge，桌面与触屏共用同一套输入管线。
class_name TouchControls
extends Control

signal pause_pressed()

const DEADZONE: float = 0.16

var handler: InputHandler = null
var enabled: bool = false
var scale_factor: float = 1.0
var opacity: float = 0.55
var left_handed: bool = false
var auto_fire: bool = false

var _joy_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _look_id: int = -1
var _look_last: Vector2 = Vector2.ZERO
var _pressed: Dictionary = {}      # touch_index -> button id
var _toggle_state: Dictionary = {}
var _buttons: Array = []           # {id,pos,r,label,kind}
var _layout_dirty: bool = true
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(true)


func setup(h: InputHandler) -> void:
	handler = h


func refresh_from_settings() -> void:
	scale_factor = Settings.get_float("controls", "touch_scale")
	opacity = Settings.get_float("controls", "touch_opacity")
	left_handed = Settings.get_bool("controls", "touch_left_handed")
	_layout_dirty = true
	queue_redraw()


func set_active(on: bool) -> void:
	enabled = on
	visible = on
	if not on:
		_release_all()
	_layout_dirty = true


func _process(delta: float) -> void:
	_t += delta
	if _layout_dirty:
		_layout()
		_layout_dirty = false
	queue_redraw()


# ---------------- 布局 ----------------

func _layout() -> void:
	_buttons.clear()
	var vs: Vector2 = get_viewport_rect().size
	var s: float = clampf(minf(vs.x, vs.y) / 900.0, 0.75, 1.35) * scale_factor
	var safe_top: float = Platform.safe_top()
	var safe_bot: float = Platform.safe_bottom()
	var pad: float = 26.0 * s
	var r: float = 44.0 * s
	var side: float = -1.0 if left_handed else 1.0
	# 右/左手主要功能键
	var bx: float = vs.x * 0.5 - side * (vs.x * 0.5 - pad - r * 1.4)
	var by: float = vs.y - safe_bot - pad - r * 1.4
	_btn("fire", Vector2(bx, by), r * 1.25, "开火", "hold")
	_btn("ads", Vector2(bx - side * r * 2.6, by - r * 0.6), r * 0.8, "瞄准", "hold")
	_btn("jump", Vector2(bx - side * r * 1.1, by - r * 2.5), r * 0.78, "跳", "tap")
	_btn("crouch", Vector2(bx - side * r * 2.9, by - r * 2.2), r * 0.72, "蹲", "toggle")
	_btn("reload", Vector2(bx - side * r * 3.0, by + r * 0.4), r * 0.7, "换弹", "tap")
	_btn("use", Vector2(bx - side * r * 1.4, by + r * 1.5), r * 0.72, "使用", "hold")
	_btn("skill", Vector2(bx - side * r * 3.2, by - r * 1.2), r * 0.64, "技能", "tap")
	# 左上：小地图/计分
	_btn("score", Vector2(pad + r * 0.7, safe_top + pad + r * 0.7), r * 0.62, "TAB", "tap")
	_btn("pause", Vector2(vs.x - pad - r * 0.6, safe_top + pad + r * 0.6), r * 0.55, "II", "tap")
	# 底部：武器槽
	var slot_y: float = vs.y - safe_bot - pad - r * 0.55
	for i in 4:
		_btn("slot%d" % (i + 1), Vector2(vs.x * 0.5 + side * (i - 1.5) * r * 1.25, slot_y), r * 0.5, str(i + 1), "tap")
	# 摇杆中心
	var joy_r: float = 82.0 * s
	_joy_origin = Vector2(pad + joy_r, vs.y - safe_bot - pad - joy_r) if not left_handed else Vector2(vs.x - pad - joy_r, vs.y - safe_bot - pad - joy_r)
	_joy_pos = _joy_origin
	set_meta("joy_r", joy_r)


func _btn(id: String, pos: Vector2, r: float, label: String, kind: String) -> void:
	_buttons.append({"id": id, "pos": pos, "r": r, "label": label, "kind": kind})


func _joy_r() -> float:
	return float(get_meta("joy_r", 80.0))


# ---------------- 输入 ----------------

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position, event.relative)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(99, event.position, event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and _look_id == 99:
		_handle_drag(99, event.position, event.relative)
		accept_event()


func _handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if idx == _joy_id:
			_joy_id = -1
			_joy_pos = _joy_origin
			handler.input.mv = [0, 0, 0, 0]
		if idx == _look_id:
			_look_id = -1
		if _pressed.has(idx):
			_release_button(str(_pressed[idx]))
			_pressed.erase(idx)
		return
	# 摇杆优先
	if _joy_id < 0 and pos.distance_to(_joy_origin) < _joy_r() * 1.45:
		_joy_id = idx
		_joy_pos = pos
		return
	# 按钮
	for b in _buttons:
		if pos.distance_to(b.pos) <= b.r * 1.05:
			_pressed[idx] = b.id
			_press_button(str(b.id), str(b.kind))
			return
	# 右侧空白 → 视角
	if _look_id < 0:
		_look_id = idx
		_look_last = pos


func _handle_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_id:
		_joy_pos = pos
		var d: Vector2 = pos - _joy_origin
		var r: float = _joy_r()
		if d.length() > r:
			d = d.normalized() * r
		var v: Vector2 = d / r
		var mv: Array = [0, 0, 0, 0]
		if v.y < -DEADZONE:
			mv[0] = 1
		if v.y > DEADZONE:
			mv[1] = 1
		if v.x < -DEADZONE:
			mv[2] = 1
		if v.x > DEADZONE:
			mv[3] = 1
		handler.input.mv = mv
		handler.input.s = d.length() > r * 0.86
		return
	if idx == _look_id:
		var sens: float = 0.0032 * float(Settings.get_float("controls", "sensitivity"))
		handler.aim_delta(-rel.x * sens, -rel.y * sens)


func aim_delta(dx: float, dy: float) -> void:
	pass


func _press_button(id: String, kind: String) -> void:
	match id:
		"fire":
			handler.input.fire = true
		"ads":
			handler.input.ads = true
		"use":
			handler.input.u = true
			handler.edge.u = true
		"jump":
			handler.edge.j = true
			handler.input.j = true
		"reload":
			handler.edge.r = true
		"skill":
			handler.edge.skill = true
		"crouch":
			var on: bool = not bool(_toggle_state.get("crouch", false))
			_toggle_state["crouch"] = on
			handler.input.c = on
		"slot1":
			handler.edge.sw = 2
		"slot2":
			handler.edge.sw = 1
		"slot3":
			handler.edge.sw = 0
		"slot4":
			handler.edge.sw = 3
		"score":
			handler.force_scoreboard = true
		"pause":
			pause_pressed.emit()


func _release_button(id: String) -> void:
	match id:
		"fire":
			handler.input.fire = false
		"ads":
			handler.input.ads = false
		"use":
			handler.input.u = false
		"score":
			handler.force_scoreboard = false


func _release_all() -> void:
	_joy_id = -1
	_look_id = -1
	_pressed.clear()
	_toggle_state.clear()
	if handler != null:
		handler.input.mv = [0, 0, 0, 0]
		handler.input.fire = false
		handler.input.ads = false
		handler.input.u = false
		handler.input.c = false
		handler.input.s = false
		handler.force_scoreboard = false


# ---------------- 绘制 ----------------

func _draw() -> void:
	if not enabled:
		return
	var a: float = clampf(opacity, 0.1, 1.0)
	# 摇杆
	var jr: float = _joy_r()
	draw_circle(_joy_origin, jr, Color(1, 1, 1, 0.06 * a))
	draw_arc(_joy_origin, jr, 0, TAU, 48, Color(1, 1, 1, 0.28 * a), 2.0, true)
	var knob: Vector2 = _joy_pos
	if knob.distance_to(_joy_origin) > jr:
		knob = _joy_origin + (knob - _joy_origin).normalized() * jr
	draw_circle(knob, jr * 0.42, Color(1, 1, 1, 0.20 * a))
	draw_arc(knob, jr * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.45 * a), 2.0, true)
	# 按钮
	var font: Font = ThemeDB.fallback_font
	for b in _buttons:
		var col: Color = Color(1, 1, 1, 0.10 * a)
		var edge: Color = Color(1, 1, 1, 0.30 * a)
		if b.id == "fire":
			col = Color(1.0, 0.35, 0.28, 0.22 * a)
			edge = Color(1.0, 0.45, 0.35, 0.55 * a)
		elif b.id == "ads":
			col = Color(0.35, 0.7, 1.0, 0.18 * a)
			edge = Color(0.45, 0.75, 1.0, 0.5 * a)
		elif b.kind == "toggle" and bool(_toggle_state.get("crouch", false)):
			col = Color(1.0, 0.85, 0.3, 0.25 * a)
			edge = Color(1.0, 0.9, 0.4, 0.6 * a)
		var pressed: bool = false
		for k in _pressed:
			if str(_pressed[k]) == b.id:
				pressed = true
				break
		if pressed:
			col = Color(col.r, col.g, col.b, minf(1.0, col.a * 2.0))
		draw_circle(b.pos, b.r, col)
		draw_arc(b.pos, b.r, 0, TAU, 32, edge, 2.0, true)
		var fs: int = int(clampf(b.r * 0.62, 10.0, 22.0))
		var tw: float = font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, b.pos + Vector2(-tw * 0.5, fs * 0.36), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85 * a))
