class_name InputHandler
extends Node

# 输入处理：键盘 / 鼠标 / 触屏 → 玩家 input/edge 字典。指针锁定。
# 关键设计：键盘与触屏各写一份状态，_process 里做 OR 合并。
# 旧版每帧用 Input.is_action_pressed 直接覆盖 input.*，把虚拟手柄写入的
# 摇杆/蹲/跳/用 全部清零，导致手机上"按钮有反馈但人物不动"。

const PITCH_LIMIT: float = deg_to_rad(89.0)

var mouse_sensitivity: float = 0.004   # 弧度/像素（基准值）
var invert_y: bool = false
var mouse_smoothing: float = 0.3       # 0 = 关闭平滑

var input: Dictionary = {
	"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
	"yaw": 0.0, "pitch": 0.0, "fire": false, "ads": false,
	"r": false, "sw": -1, "swd": 0, "u": false,
}
var edge: Dictionary = {"sw": -1, "swd": 0, "r": false, "j": false, "u": false, "skill": false}

## 触屏层（TouchControls 写入），与键盘层合并
var touch: Dictionary = {
	"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
	"fire": false, "ads": false, "u": false, "r": false,
}
var touch_active: bool = false

## 开关类操作（设置里决定是按住还是切换）
var toggle_ads: bool = false
var toggle_sprint: bool = false
var _ads_latched: bool = false
var _sprint_latched: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _enabled: bool = false
var _locked: bool = false
var _sdx: float = 0.0
var _sdy: float = 0.0
var _kbd_fire: bool = false
var _kbd_ads: bool = false
var _touch_device: bool = false
## 陀螺仪（移动端）
var gyro_enabled: bool = false
var gyro_sens: float = 1.0
## 触屏/手柄：按住即显示记分板
var force_scoreboard: bool = false
## 辅助瞄准强度（0..1），触屏与手柄生效
var aim_assist: float = 0.0


## 外部（触屏摇杆 / 陀螺仪 / 手柄右摇杆）注入视角增量，单位：弧度
func aim_delta(dyaw: float, dpitch: float) -> void:
	if not _enabled:
		return
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, -PITCH_LIMIT, PITCH_LIMIT)
	input.yaw = _yaw
	input.pitch = _pitch


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	_touch_device = Platform.is_touch_device() if Platform != null else false
	refresh_settings()


## 设置变更后立即生效（controls 段全部在这里落地）
func refresh_settings() -> void:
	if Settings == null:
		return
	var sens: float = Settings.get_float("controls", "sensitivity")
	mouse_sensitivity = 0.004 * clampf(sens, 0.1, 6.0)
	invert_y = Settings.get_bool("controls", "invert_y")
	mouse_smoothing = Settings.get_float("controls", "smoothing")
	toggle_ads = Settings.get_bool("controls", "toggle_ads")
	toggle_sprint = Settings.get_bool("controls", "toggle_sprint")
	gyro_enabled = Settings.get_bool("controls", "gyro") and Platform.has_gyro
	gyro_sens = Settings.get_float("controls", "gyro_sens")
	aim_assist = Settings.get_float("controls", "aim_assist") if Platform.wants_touch_ui() else 0.0


func set_enabled(v: bool) -> void:
	_enabled = v
	if not v:
		_release_all()


func is_enabled() -> bool:
	return _enabled


func is_locked() -> bool:
	return _locked


func lock_pointer() -> void:
	if not _enabled:
		return
	# 触屏设备锁指针会导致没有鼠标可点 UI，直接跳过
	if _touch_device:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_locked = true


func unlock_pointer() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_locked = false


## 后坐力反冲：直接叠加到视角（视觉与瞄准同步，符合 FPS 惯例）
func recoil(dyaw: float, dpitch: float) -> void:
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, -PITCH_LIMIT, PITCH_LIMIT)
	input.yaw = _yaw
	input.pitch = _pitch


func set_yaw_pitch(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	input.yaw = _yaw
	input.pitch = _pitch


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	# 触屏设备忽略鼠标：模拟鼠标事件会把触屏写入的 fire/ads 打回 false
	if _touch_device and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseMotion and _locked:
		var sens_mult: float = 1.0
		if input.ads and Settings != null:
			sens_mult = Settings.get_float("controls", "ads_sens_mult")
		var raw_dx: float = event.relative.x * mouse_sensitivity * sens_mult
		var raw_dy: float = event.relative.y * mouse_sensitivity * sens_mult
		if mouse_smoothing > 0.0:
			_sdx = lerpf(_sdx, raw_dx, mouse_smoothing)
			_sdy = lerpf(_sdy, raw_dy, mouse_smoothing)
		else:
			_sdx = raw_dx
			_sdy = raw_dy
		_yaw -= _sdx
		_pitch -= _sdy * (-1.0 if invert_y else 1.0)
		_pitch = clampf(_pitch, -PITCH_LIMIT, PITCH_LIMIT)
		input.yaw = _yaw
		input.pitch = _pitch
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_kbd_fire = event.pressed and _locked
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if toggle_ads:
				# 切换式开镜：按下翻转，不依赖按住状态
				if event.pressed:
					_ads_latched = not _ads_latched
			else:
				_kbd_ads = event.pressed and _locked
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			edge.swd = 1
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			edge.swd = -1
		return
	if event.is_action_pressed("pause_toggle") or event.is_action_pressed("buy_menu") \
			or event.is_action_pressed("scoreboard"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			# CS 惯例键位：1=主武器(slot2)、2=手枪(slot1)、3=刀(slot0)、4=投掷(slot3)
			KEY_1: edge.sw = 2
			KEY_2: edge.sw = 1
			KEY_3: edge.sw = 0
			KEY_4: edge.sw = 3
			KEY_R: edge.r = true
			KEY_F: edge.skill = true
			KEY_E: edge.u = true
		return


func _process(_delta: float) -> void:
	if not _enabled:
		return
	# ---- 键盘/手柄层 ----
	var fwd: int = 1 if Input.is_action_pressed("move_forward") else 0
	var back: int = 1 if Input.is_action_pressed("move_back") else 0
	var left: int = 1 if Input.is_action_pressed("move_left") else 0
	var right: int = 1 if Input.is_action_pressed("move_right") else 0
	var kb_sprint: bool = Input.is_action_pressed("sprint")
	if toggle_sprint and Input.is_action_just_pressed("sprint"):
		_sprint_latched = not _sprint_latched
	var sprint_on: bool = _sprint_latched if toggle_sprint else kb_sprint
	var kb_ads: bool = Input.is_action_pressed("ads") or _kbd_ads or _ads_latched
	var kb_fire: bool = _kbd_fire or Input.is_action_pressed("fire")

	# ---- 合并触屏层（OR，绝不覆盖）----
	var mv: Array = [fwd, back, left, right]
	if touch_active:
		var tmv: Array = touch.mv
		for i in 4:
			mv[i] = maxi(int(mv[i]), int(tmv[i]))
	input.mv = mv
	input.c = Input.is_action_pressed("crouch") or (touch_active and bool(touch.c))
	input.s = sprint_on or (touch_active and bool(touch.s))
	input.j = Input.is_action_pressed("jump") or (touch_active and bool(touch.j))
	input.u = Input.is_action_pressed("use") or (touch_active and bool(touch.u))
	input.r = Input.is_action_pressed("reload") or (touch_active and bool(touch.r))
	input.fire = kb_fire or (touch_active and bool(touch.fire))
	input.ads = kb_ads or (touch_active and bool(touch.ads))

	if Input.is_action_just_pressed("slot1"):
		edge.sw = 2
	elif Input.is_action_just_pressed("slot2"):
		edge.sw = 1
	elif Input.is_action_just_pressed("slot3"):
		edge.sw = 0
	elif Input.is_action_just_pressed("slot4"):
		edge.sw = 3
	if Input.is_action_just_pressed("jump"):
		edge.j = true
	if Input.is_action_just_pressed("reload"):
		edge.r = true
	if Input.is_action_just_pressed("use"):
		edge.u = true
	if Input.is_action_just_pressed("skill"):
		edge.skill = true

	# 陀螺仪：按帧增量叠加到视角（开镜时减半，符合主流手游手感）
	if gyro_enabled and _touch_device:
		var g: Vector3 = Input.get_gyroscope()
		if g.length_squared() > 0.000001:
			var k: float = 0.016 * gyro_sens * (0.6 if input.ads else 1.0)
			aim_delta(-g.y * k, -g.z * k)


## 拷贝当前输入到玩家的 input 字典（每 tick 调用）
func snapshot_to(out: Dictionary) -> void:
	out.mv = input.mv.duplicate()
	out.fwd = float(input.mv[0] - input.mv[1])
	out.strafe = float(input.mv[3] - input.mv[2])
	out.yaw = input.yaw
	out.pitch = input.pitch
	out.fire = input.fire
	out.ads = input.ads
	out.j = input.j
	out.c = input.c
	out.s = input.s
	out.reload = input.r
	out.crouch = input.c
	out.jump = input.j
	out.use = input.u
	out.r = input.r
	out.u = input.u
	out.sw = edge.sw
	out.swd = edge.swd


# tick 完成后清空 edge
func clear_edges() -> void:
	edge.sw = -1
	edge.swd = 0
	edge.r = false
	edge.j = false
	edge.u = false
	edge.skill = false


func _release_all() -> void:
	_kbd_fire = false
	_kbd_ads = false
	_ads_latched = false
	_sprint_latched = false
	input.fire = false
	input.ads = false
	input.mv = [0, 0, 0, 0]
	input.j = false
	input.c = false
	input.s = false
	input.r = false
	input.u = false
	edge.sw = -1
	edge.swd = 0
	edge.r = false
	edge.j = false
	edge.u = false
	edge.skill = false
