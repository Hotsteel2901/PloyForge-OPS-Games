# 移动端虚拟手柄：左摇杆移动 + 右侧拖拽视角 + 全套功能键。
#
# 层级约定（非常重要）：
#   世界 3D  →  HUD(layer 10, 纯展示/IGNORE)  →  TouchControls(layer 20, 全屏接收)
#   →  菜单类 UI(layer 30+)：主菜单 / 暂停 / 购买 / 设置 / 联机 / 计分板
# 菜单在更高层，可见时优先吃掉触摸；不可见时触摸落到这里。
# 旧版把 TouchControls 挂在 layer 0 且用 z_index 排序（z_index 不跨 CanvasLayer），
# 同时 InputHandler 每帧覆盖触屏写入 → 按钮有反馈但人物不动、UI 也点不了。
class_name TouchControls
extends Control

signal pause_pressed()

const DEADZONE: float = 0.16
const PULSE_TIME: float = 0.11

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
var _pressed: Dictionary = {}      # touch_index -> button id
var _toggle_state: Dictionary = {}
var _pulse: Dictionary = {}        # action -> remaining seconds
var _buttons: Array = []           # {id,pos,r,label,kind}
var _layout_dirty: bool = true
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(true)
	resized.connect(func() -> void: _layout_dirty = true)


func setup(h: InputHandler) -> void:
	handler = h


func refresh_from_settings() -> void:
	scale_factor = Settings.get_float("controls", "touch_scale")
	opacity = Settings.get_float("controls", "touch_opacity")
	left_handed = Settings.get_bool("controls", "touch_left_handed")
	auto_fire = Settings.get_bool("controls", "auto_reload")
	_layout_dirty = true
	queue_redraw()


func set_active(on: bool) -> void:
	enabled = on
	visible = on
	if handler != null:
		handler.touch_active = on
	if not on:
		_release_all()
	_layout_dirty = true
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _layout_dirty:
		_layout()
		_layout_dirty = false
	# 脉冲动作（跳/换弹/技能/切枪）在若干帧后自动释放
	for k in _pulse.keys():
		_pulse[k] = maxf(0.0, float(_pulse[k]) - delta)
	_sync_to_handler()
	queue_redraw()


func _sync_to_handler() -> void:
	if handler == null:
		return
	if not enabled:
		handler.touch_active = false
		return
	handler.touch_active = true
	handler.touch.j = float(_pulse.get("j", 0.0)) > 0.0
	handler.touch.r = float(_pulse.get("r", 0.0)) > 0.0
	handler.touch.u = float(_pulse.get("u", 0.0)) > 0.0 or _is_held("use")


func _is_held(id: String) -> bool:
	for k in _pressed:
		if str(_pressed[k]) == id:
			return true
	return false


# ---------------- 布局 ----------------

func _layout() -> void:
	_buttons.clear()
	var vs: Vector2 = size
	if vs.x < 8.0 or vs.y < 8.0:
		vs = get_viewport_rect().size
	var s: float = clampf(minf(vs.x, vs.y) / 760.0, 0.72, 1.6) * scale_factor
	var safe_top: float = Platform.safe_top()
	var safe_bot: float = Platform.safe_bottom()
	# 沉浸式全屏下安全区可能返回 0，这里垫一个最小内边距，避免按钮贴边
	var pad: float = maxf(20.0 * s, 12.0)
	var r: float = 42.0 * s
	var side: float = -1.0 if left_handed else 1.0

	# --- 右手主操作区（开火为锚点）---
	var fire_r: float = r * 1.22
	var fx: float = vs.x - pad - fire_r if not left_handed else pad + fire_r
	var fy: float = vs.y - safe_bot - pad - fire_r
	_btn("fire", Vector2(fx, fy), fire_r, "开火", "hold")
	_btn("ads", Vector2(fx - side * r * 2.05, fy - r * 0.95), r * 0.86, "瞄准", "hold")
	_btn("jump", Vector2(fx - side * r * 1.05, fy - r * 2.35), r * 0.8, "跳", "pulse")
	_btn("crouch", Vector2(fx - side * r * 3.15, fy - r * 1.75), r * 0.74, "蹲", "toggle")
	_btn("reload", Vector2(fx - side * r * 3.05, fy + r * 0.15), r * 0.72, "换弹", "pulse")
	_btn("use", Vector2(fx - side * r * 1.55, fy + r * 1.35), r * 0.7, "使用", "hold")
	_btn("skill", Vector2(fx - side * r * 3.55, fy + r * 1.55), r * 0.64, "技能", "pulse")

	# --- 顶部：计分板 / 暂停 ---
	var top: float = maxf(safe_top, 0.0) + pad * 0.9
	_btn("score", Vector2(pad + r * 0.75, top + r * 0.75), r * 0.62, "TAB", "toggle")
	_btn("pause", Vector2(vs.x - pad - r * 0.65, top + r * 0.65), r * 0.58, "II", "tap")

	# --- 底部中央：武器槽 ---
	var slot_y: float = vs.y - safe_bot - pad * 0.9 - r * 0.5
	for i in 4:
		_btn("slot%d" % (i + 1), Vector2(vs.x * 0.5 + (i - 1.5) * r * 1.35, slot_y), r * 0.48, str(i + 1), "tap")

	# --- 左下（或左下反向）：摇杆 ---
	var joy_r: float = 78.0 * s
	_joy_origin = Vector2(pad + joy_r, vs.y - safe_bot - pad - joy_r)
	_joy_pos = _joy_origin
	set_meta("joy_r", joy_r)


func _btn(id: String, pos: Vector2, r: float, label: String, kind: String) -> void:
	_buttons.append({"id": id, "pos": pos, "r": r, "label": label, "kind": kind})


func _joy_r() -> float:
	return float(get_meta("joy_r", 76.0))


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
			if handler != null:
				handler.touch.mv = [0, 0, 0, 0]
				handler.touch.s = false
		if idx == _look_id:
			_look_id = -1
		if _pressed.has(idx):
			_release_button(str(_pressed[idx]))
			_pressed.erase(idx)
		return
	# 摇杆优先（左下角圆形区）
	if _joy_id < 0 and pos.distance_to(_joy_origin) < _joy_r() * 1.5:
		_joy_id = idx
		_joy_pos = pos
		return
	# 按钮
	for b in _buttons:
		if pos.distance_to(b.pos) <= b.r * 1.08:
			_pressed[idx] = b.id
			_press_button(str(b.id), str(b.kind))
			return
	# 右侧空白 → 视角拖拽
	if _look_id < 0:
		_look_id = idx


func _handle_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if handler == null:
		return
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
		handler.touch.mv = mv
		handler.touch.s = d.length() > r * 0.86
		return
	if idx == _look_id:
		# content_scale_factor 让 UI 放大后，同样物理滑动对应的逻辑像素更少，
		# 这里按缩放因子补偿，保证不同 DPI 下手感一致
		var csf: float = 1.0
		if is_inside_tree():
			csf = get_window().content_scale_factor
		var sens: float = 0.0030 * float(Settings.get_float("controls", "sensitivity")) * csf
		handler.aim_delta(-rel.x * sens, -rel.y * sens)


func _press_button(id: String, kind: String) -> void:
	if handler == null:
		return
	match id:
		"fire":
			handler.touch.fire = true
		"ads":
			handler.touch.ads = true
		"use":
			handler.touch.u = true
			_pulse["u"] = PULSE_TIME
		"jump":
			_pulse["j"] = PULSE_TIME
		"reload":
			_pulse["r"] = PULSE_TIME
		"skill":
			_pulse["skill"] = PULSE_TIME
		"crouch":
			var on: bool = not bool(_toggle_state.get("crouch", false))
			_toggle_state["crouch"] = on
			handler.touch.c = on
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
	if kind == "pulse" and not _pulse.has(id):
		_pulse[id] = PULSE_TIME


func _release_button(id: String) -> void:
	if handler == null:
		return
	match id:
		"fire":
			handler.touch.fire = false
		"ads":
			handler.touch.ads = false
		"use":
			handler.touch.u = false
		"score":
			handler.force_scoreboard = false


func _release_all() -> void:
	_joy_id = -1
	_look_id = -1
	_pressed.clear()
	_toggle_state.clear()
	_pulse.clear()
	_joy_pos = _joy_origin
	if handler != null:
		handler.touch.mv = [0, 0, 0, 0]
		handler.touch.fire = false
		handler.touch.ads = false
		handler.touch.u = false
		handler.touch.c = false
		handler.touch.s = false
		handler.touch.j = false
		handler.touch.r = false
		handler.force_scoreboard = false


# ---------------- 绘制 ----------------

func _draw() -> void:
	if not enabled:
		return
	var a: float = clampf(opacity, 0.12, 1.0)
	Draw.joy(self, _joy_origin, _joy_pos, _joy_r(), a)
	for b in _buttons:
		var pressed: bool = _is_held(b.id)
		var on: bool = b.kind == "toggle" and bool(_toggle_state.get("crouch", false))
		Draw.button(self, b.pos, b.r, b.label, b.id, a, pressed, on)


# 绘制工具拆成内部类，_draw 里少写重复代码
class Draw:
	static func joy(ci: CanvasItem, origin: Vector2, knob_pos: Vector2, jr: float, a: float) -> void:
		ci.draw_circle(origin, jr, Color(0.02, 0.03, 0.05, 0.30 * a))
		ci.draw_arc(origin, jr, 0.0, TAU, 48, Color(1, 1, 1, 0.34 * a), 2.0, true)
		var knob: Vector2 = knob_pos
		var d: Vector2 = knob - origin
		if d.length() > jr:
			knob = origin + d.normalized() * jr
		ci.draw_circle(knob, jr * 0.44, Color(0.85, 0.9, 1.0, 0.22 * a))
		ci.draw_arc(knob, jr * 0.44, 0.0, TAU, 32, Color(1, 1, 1, 0.55 * a), 2.0, true)

	static func button(ci: CanvasItem, pos: Vector2, r: float, label: String, id: String, a: float, pressed: bool, on: bool) -> void:
		var fill: Color = Color(0.06, 0.07, 0.10, 0.42 * a)
		var edge: Color = Color(1, 1, 1, 0.34 * a)
		var text: Color = Color(1, 1, 1, 0.9 * a)
		match id:
			"fire":
				fill = Color(0.85, 0.22, 0.18, 0.42 * a)
				edge = Color(1.0, 0.42, 0.32, 0.85 * a)
			"ads":
				fill = Color(0.16, 0.42, 0.72, 0.38 * a)
				edge = Color(0.45, 0.75, 1.0, 0.8 * a)
			"pause":
				fill = Color(0.06, 0.07, 0.10, 0.55 * a)
		if on:
			fill = Color(1.0, 0.75, 0.25, 0.45 * a)
			edge = Color(1.0, 0.85, 0.4, 0.9 * a)
		if pressed:
			fill = Color(minf(1.0, fill.r + 0.18), minf(1.0, fill.g + 0.18), minf(1.0, fill.b + 0.18), minf(1.0, fill.a + 0.25))
			edge = Color(1, 1, 1, 0.95)
		ci.draw_circle(pos, r, fill)
		ci.draw_arc(pos, r, 0.0, TAU, 36, edge, 2.0, true)
		var font: Font = ThemeDB.fallback_font
		var fs: int = int(clampf(r * 0.62, 10.0, 22.0))
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, pos + Vector2(-tw * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text)
