class_name InputHandler
extends Node

# 输入处理：键盘 / 鼠标 → 玩家 input/edge 字典。指针锁定。

const PITCH_LIMIT: float = deg_to_rad(89.0)

var mouse_sensitivity: float = 0.004   # 弧度/像素
var invert_y: bool = false
var mouse_smoothing: float = 0.3       # 0 = 关闭平滑

var input: Dictionary = {
	"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
	"yaw": 0.0, "pitch": 0.0, "fire": false, "ads": false,
	"r": false, "sw": -1, "swd": 0, "u": false,
}
var edge: Dictionary = {"sw": -1, "swd": 0, "r": false, "j": false, "u": false, "skill": false}

var _yaw: float = 0.0
var _pitch: float = 0.0
var _enabled: bool = false
var _locked: bool = false
var _sdx: float = 0.0
var _sdy: float = 0.0


func _ready() -> void:
	set_process_unhandled_input(true)


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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_locked = true


func unlock_pointer() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_locked = false


func set_yaw_pitch(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	input.yaw = _yaw
	input.pitch = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseMotion and _locked:
		var raw_dx: float = event.relative.x * mouse_sensitivity
		var raw_dy: float = event.relative.y * mouse_sensitivity
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
			input.fire = event.pressed and _locked
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			input.ads = event.pressed and _locked
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
	var fwd: int = 1 if Input.is_action_pressed("move_forward") else 0
	var back: int = 1 if Input.is_action_pressed("move_back") else 0
	var left: int = 1 if Input.is_action_pressed("move_left") else 0
	var right: int = 1 if Input.is_action_pressed("move_right") else 0
	input.mv = [fwd, back, left, right]
	input.c = Input.is_action_pressed("crouch")
	input.s = Input.is_action_pressed("sprint")
	input.j = Input.is_action_pressed("jump")
	input.u = Input.is_action_pressed("use")
	input.r = Input.is_action_pressed("reload")
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


# 拷贝当前输入到玩家的 input 字典（每 tick 调用）
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
