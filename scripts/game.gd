# Game: main orchestrator. Fixed-step sim (30Hz) + render at display rate.
# Owns: WorldRenderer, Camera, viewmodel, InputHandler, Sfx, UI (HUD/BuyMenu/Scoreboard/MainMenu).
extends Node

const TICK_DT: float = Constants.TICK_MS / 1000.0
const EYE_STAND: float = Constants.PHYS.EYE_STAND
const EYE_CROUCH: float = Constants.PHYS.EYE_CROUCH
const DEFAULT_FOV: float = 74.0

var _world: WorldRenderer
var _camera: Camera3D
var _viewmodel_root: Node3D
var _viewmodel: Node3D = null
var _viewmodel_muzzle: Node3D = null
var _input_handler: InputHandler
var _sfx: Sfx
var _bgm: Bgm
var _hud: HUD
var _buy_menu: BuyMenu
var _scoreboard: Scoreboard
var _main_menu: MainMenu
var _pause_menu: PauseMenu
var _debug_overlay: DebugOverlay

var _room: Room = null
var _local_id: String = ""
var _running: bool = false
var _paused: bool = false
var _tick_accum: float = 0.0
var _footstep_dist: float = 0.0
var _camera_kick: float = 0.0
var _vm_punch: float = 0.0
var _vm_sway: Vector3 = Vector3.ZERO
var _reload_anim: float = 0.0
var _reload_t: float = -1.0        # 换弹开始时刻（-1 = 未在换弹）
var _reload_dur: float = 1.0       # 换弹总时长（来自武器 def.reloadTime）
var _reload_stage: int = -1        # 已播放音效的阶段（0拆夹/1扔夹/2装夹/3上膛）
var _mag_rest: Dictionary = {}     # 当前弹夹节点的初始 pose（pos/rot），换弹动画以此为基准
var _melee_swing_t: float = -1.0   # 近战挥砍/抓挠开始时刻（-1 = 未在挥动）
var _melee_kind: String = ""       # fang=匕首挥砍 / zclaw=尸爪抓挠
var _eye_h: float = EYE_STAND      # 当前视角高度（蹲/站平滑过渡，参考专业 FPS 的 lerp 过渡）
var _bob_phase: float = 0.0        # headbob 相位（按移动速度累积，比直接用时间更可控）
var _bob_amt: Vector2 = Vector2.ZERO  # 当前 headbob 幅度（走路/冲刺间平滑过渡）
var _land_impact: float = 0.0      # 落地冲击（落地瞬间相机下压回弹）
var _was_grounded: bool = true     # 上一帧是否接地（落地冲击检测）
var _fov_sprint: float = 0.0       # 冲刺 FOV 扩展量（速度感）
var _dead_cam: Vector3 = Vector3.ZERO
var _beep_accum: float = 0.0
var _menu_cam: Camera3D = null
var _menu_time: float = 0.0
var _give_weapon: String = ""
var _cam_override: Array = []
var _yaw_override: float = NAN
var _debug_pos: bool = false
var _auto_reload_at: int = -1
var _audio_unlocked: bool = false
# Web 自适应 3D 分辨率：低配设备自动降分辨率保帧率，富余时再抬回去（UI 始终原生清晰）
const WEB_SCALE_MIN: float = 0.5
const WEB_SCALE_MAX: float = 0.85
const WEB_SCALE_STEP_DOWN: float = 0.07
const WEB_SCALE_STEP_UP: float = 0.05
var _web_scale: float = 0.7
var _web_scale_timer: float = 0.0
var _web_scale_frames: int = 0


# 首次输入解锁音频（Web autoplay 策略：浏览器要求用户手势后才能播放）
func _input(event: InputEvent) -> void:
	if _audio_unlocked:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		_audio_unlocked = true
		if _bgm != null:
			_bgm.start()
var _hide_ui_for_shot: bool = false
var _no_taa: bool = false
var _menu_chars: Array = []
var _buy_menu_delay: float = -1.0
var _base_fov: float = DEFAULT_FOV
var _settings_volume: float = 1.0


func _ready() -> void:
	# Web 特化性能优化：Compatibility/WebGL2 对填充率敏感，
	# 3D 渲染分辨率缩放到 70%（像素量减半），UI（2D）保持原生清晰。
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = _web_scale
		Engine.max_fps = 60
	set_process_input(true)
	_world = WorldRenderer.new()
	_world.name = "World"
	add_child(_world)
	get_viewport().use_taa = (not _no_taa) and not OS.has_feature("web")
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = _base_fov
	_camera.near = 0.05
	# far=400：远雾密度 0.006 下 400m 已完全雾化，900m 浪费深度精度
	_camera.far = 400.0
	add_child(_camera)
	_viewmodel_root = Node3D.new()
	_viewmodel_root.name = "Viewmodel"
	_viewmodel_root.position = Vector3(0.18, -0.18, -0.35)
	_camera.add_child(_viewmodel_root)
	_input_handler = InputHandler.new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)
	_sfx = Sfx.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	_bgm = Bgm.new()
	_bgm.name = "Bgm"
	add_child(_bgm)
	_hud = HUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	_buy_menu = BuyMenu.new()
	_buy_menu.name = "BuyMenu"
	add_child(_buy_menu)
	_scoreboard = Scoreboard.new()
	_scoreboard.name = "Scoreboard"
	add_child(_scoreboard)
	_main_menu = MainMenu.new()
	_main_menu.name = "MainMenu"
	add_child(_main_menu)
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	_debug_overlay = DebugOverlay.new()
	_debug_overlay.name = "DebugOverlay"
	_debug_overlay.setup(self)
	add_child(_debug_overlay)
	_pause_menu.resume_requested.connect(func(): _toggle_pause(false))
	_pause_menu.menu_requested.connect(_on_menu_requested)
	_pause_menu.quit_requested.connect(func(): get_tree().quit())
	_main_menu.start_requested.connect(_on_start_game)
	_main_menu.quit_requested.connect(func(): get_tree().quit())
	_main_menu.settings_changed.connect(_on_settings_changed)
	_apply_settings(_main_menu.get_settings())
	_buy_menu.buy.connect(_on_buy)
	_buy_menu.refund.connect(_on_refund)
	_buy_menu.close_requested.connect(_on_buy_menu_closed)
	_main_menu.show_menu()
	_input_handler.set_enabled(false)
	_build_menu_backdrop()
	# CLI autostart for automated testing / screenshots:
	# --autostart[=map_id]  --mode=defusal|zombie  --bots=N  --team=ct|t|random  --name=X
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var has_autostart: bool = false
	for a in args:
		if a == "--autostart" or a.begins_with("--autostart="):
			has_autostart = true
			break
	if has_autostart:
		var map_id: String = "cinder"
		var mode: String = "defusal"
		var bots: int = 8
		var team: String = "random"
		var pname: String = "Player1"
		for a in args:
			if a.begins_with("--autostart="):
				map_id = a.get_slice("=", 1)
			elif a.begins_with("--map="):
				map_id = a.get_slice("=", 1)
			elif a.begins_with("--mode="):
				mode = a.get_slice("=", 1)
			elif a.begins_with("--bots="):
				bots = int(a.get_slice("=", 1))
			elif a.begins_with("--team="):
				team = a.get_slice("=", 1)
			elif a.begins_with("--name="):
				pname = a.get_slice("=", 1)
		if mode == "defusal" and map_id == "containment":
			map_id = "cinder"
		if mode == "zombie" and map_id != "containment" and map_id != "obsidian":
			map_id = "containment"
		call_deferred("_autostart_match", {"mode": mode, "mapId": map_id, "botCount": bots, "playerName": pname, "teamPref": team})
	for a in args:
		if a.begins_with("--shot="):
			_shot_at = int(a.get_slice("=", 1))
		elif a.begins_with("--give="):
			_give_weapon = a.get_slice("=", 1)
		elif a.begins_with("--cam="):
			_cam_override = a.get_slice("=", 1).split(",")
		elif a.begins_with("--yaw="):
			_yaw_override = float(a.get_slice("=", 1))
		elif a == "--debug-pos":
			_debug_pos = true
		elif a.begins_with("--autoreload="):
			_auto_reload_at = int(a.get_slice("=", 1))
		elif a == "--notaa":
			_no_taa = true
		elif a == "--nohud":
			_hide_ui_for_shot = true


func _autostart_match(opts: Dictionary) -> void:
	_main_menu.hide_menu()
	_on_start_game(opts)


# ---------- match lifecycle ----------
func _build_menu_backdrop() -> void:
	var map: Dictionary = MapData.get_map("cinder")
	_world.build_map(map, "cinder")
	_menu_cam = Camera3D.new()
	_menu_cam.name = "MenuCam"
	_menu_cam.fov = 60.0
	_menu_cam.near = 0.05
	_menu_cam.far = 400.0
	_world.add_child(_menu_cam)
	_menu_cam.current = true
	# stage a few characters in the backdrop
	var spots: Array = [
		{"pos": Vector3(-19, 0, 2), "yaw": 0.4, "team": 1, "zombie": false},
		{"pos": Vector3(16, 0, 12), "yaw": -2.6, "team": 2, "zombie": false},
		{"pos": Vector3(-2, 0, 25), "yaw": 0.2, "team": 2, "zombie": false},
	]
	var root := Node3D.new()
	root.name = "MenuStage"
	for s in spots:
		var ch: Node3D = CharacterFactory.build(s.team, s.zombie)
		ch.position = s.pos
		ch.rotation.y = s.yaw
		root.add_child(ch)
	_world.add_child(root)


func _process_menu(delta: float) -> void:
	if _menu_cam == null:
		return
	_menu_time += delta
	var a: float = _menu_time * 0.08
	var r: float = 26.0
	var cam_pos := Vector3(cos(a) * r, 7.0 + sin(_menu_time * 0.15) * 1.5, sin(a) * r)
	_menu_cam.position = cam_pos
	_menu_cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	_menu_cam.current = true
	# 缓存 MenuStage 角色（避免每帧 find_children 全树递归遍历）
	if _menu_chars.is_empty():
		for ch in _world.find_children("*", "Node3D", true, false):
			if ch.get_parent() != null and ch.get_parent().name == "MenuStage":
				_menu_chars.append(ch)
	for ch in _menu_chars:
		CharacterFactory.animate(ch, delta, 0.0, false, true, _menu_time)


func _on_start_game(opts: Dictionary) -> void:
	_main_menu.hide_menu()
	# 无声保护：主音量为 0 时全部音频静音，玩家容易误判成"音乐/音效坏了"，给一次明确提示
	if _settings_volume <= 0.001:
		_hud.show_message("主音量为 0%：请在「设置 → 主音量」调高后即可听到音乐与音效", 6.0)
	if _menu_cam != null:
		_menu_cam.queue_free()
		_menu_cam = null
	var stage: Node = _world.get_node_or_null("MenuStage")
	if stage != null:
		stage.queue_free()
	_menu_chars.clear()
	_world.clear_map()
	_room = Room.new({
		"id": "local",
		"mode": opts.mode,
		"mapId": opts.mapId,
		"botCount": int(opts.get("botCount", 8)),
		"maxPlayers": Constants.MAX_PLAYERS,
		"localOnly": true,
	})
	_room.events["player_damage"] = _on_player_damage
	_room.events["player_death"] = _on_player_death
	# 爆炸特效统一走 "explosion" 广播消息（room 不再双发 events.explosion）
	_room.events["tick"] = func(_args: Dictionary) -> void: pass
	var local_p: Dictionary = _room.add_local_player(str(opts.get("playerName", "Player1")), str(opts.get("teamPref", "random")))
	_local_id = str(local_p.id)
	_world.local_player_id = _local_id
	_room.start()
	_room.spawn_joiner(local_p)
	if _give_weapon != "" and WeaponData.BUILTIN_WEAPONS.has(_give_weapon):
		var gdef: Dictionary = WeaponData.BUILTIN_WEAPONS[_give_weapon]
		local_p.weapons[int(gdef.get("slot", 2))] = WeaponData.WeaponRuntime.new(gdef)
		local_p.activeSlot = int(gdef.get("slot", 2))
	_input_handler.set_yaw_pitch(float(local_p.yaw), float(local_p.pitch))
	if is_finite(_yaw_override):
		# 调试/截图：覆盖玩家初始朝向（--yaw=弧度）
		_input_handler.set_yaw_pitch(_yaw_override, 0.0)
	_camera.current = true
	_input_handler.set_enabled(true)
	_input_handler.lock_pointer()
	_running = true
	_paused = false
	_tick_accum = 0.0
	_world.build_map(_room.state.map, _room.state.mapId)
	_hud.show_message("比赛开始", 2.0)
	_sfx.round_start()


func _exit_tree() -> void:
	if _input_handler != null:
		_input_handler.unlock_pointer()


func _process(delta: float) -> void:
	_adapt_web_scale(delta)
	if _auto_reload_at > 0 and Engine.get_frames_drawn() >= _auto_reload_at:
		_auto_reload_at = 0
		# 调试：强制触发换弹视觉动画（不经过模拟层弹药逻辑）
		if _viewmodel != null:
			_handle_message({"type": "reloading"})
	if _shot_at > 0 and Engine.get_frames_drawn() >= _shot_at:
		_capture_shot()
		_shot_at = 0
	if not _running:
		if _menu_cam != null:
			_process_menu(delta)
		return
	if _paused:
		return
	# 购买菜单延迟弹出（先展示回合结束横幅）
	if _buy_menu_delay > 0.0:
		_buy_menu_delay -= delta
		if _buy_menu_delay <= 0.0 and _running and _local_id != "" and _room != null:
			_open_buy_menu()
	_tick_accum += delta
	var max_steps: int = 4
	while _tick_accum >= TICK_DT and max_steps > 0:
		_step_sim()
		_tick_accum -= TICK_DT
		max_steps -= 1
	var alpha: float = clampf(_tick_accum / TICK_DT, 0.0, 1.0)
	_render_frame(delta, alpha)


# Web 自适应分辨率：每 2 秒看一次平均帧率，低于 50 降档、高于 58 升档（带迟滞避免抖动）
func _adapt_web_scale(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_web_scale_timer += delta
	_web_scale_frames += 1
	if _web_scale_timer < 2.0:
		return
	var avg_fps: float = float(_web_scale_frames) / maxf(_web_scale_timer, 0.001)
	_web_scale_timer = 0.0
	_web_scale_frames = 0
	var old_scale: float = _web_scale
	if avg_fps < 50.0:
		_web_scale = maxf(WEB_SCALE_MIN, _web_scale - WEB_SCALE_STEP_DOWN)
	elif avg_fps > 58.0:
		_web_scale = minf(WEB_SCALE_MAX, _web_scale + WEB_SCALE_STEP_UP)
	if not is_equal_approx(old_scale, _web_scale):
		get_viewport().scaling_3d_scale = _web_scale
		print("[WebPerf] 平均 %.1f FPS → 3D 分辨率 %.2f" % [avg_fps, _web_scale])
	if _shot_at > 0 and Engine.get_frames_drawn() >= _shot_at:
		_capture_shot()
		_shot_at = 0


var _shot_at: int = 0


func _capture_shot() -> void:
	if _hide_ui_for_shot:
		_hud.hide_ui()
		if _viewmodel != null:
			_viewmodel.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if _hide_ui_for_shot:
		_hud.show_ui()
		if _viewmodel != null:
			_viewmodel.visible = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var path: String = "res://shots/game_%06d.png" % Engine.get_frames_drawn()
	img.save_png(path)
	var dbg: Dictionary = {}
	if _room != null and _local_id != "":
		var pl: Dictionary = _room.state.players
		var lp: Dictionary = pl.get(_local_id, {})
		if not lp.is_empty():
			dbg["pos"] = lp.pos
			dbg["alive"] = lp.alive
			dbg["team"] = lp.team
			dbg["yaw"] = lp.yaw
			dbg["pitch"] = lp.pitch
			dbg["phase"] = _room.state.phase
			dbg["round"] = _room.state.roundNum
	dbg["cam"] = _camera.global_position
	dbg["fov"] = _camera.fov
	dbg["fps"] = Engine.get_frames_per_second()
	if _hud != null:
		var cr: Variant = _hud.get_crosshair_info()
		dbg["crosshair"] = cr
	print("[GAME] saved " + path + " " + str(dbg))


func _step_sim() -> void:
	if _room == null:
		return
	var players_dict: Dictionary = _room.state.players
	var local: Dictionary = players_dict.get(_local_id, {})
	if not local.is_empty():
		_input_handler.snapshot_to(local.input)
		local.edge.sw = _input_handler.edge.sw
		local.edge.swd = _input_handler.edge.swd
		local.edge.r = _input_handler.edge.r
		local.edge.j = _input_handler.edge.j
		local.edge.u = _input_handler.edge.u
		local.edge.skill = _input_handler.edge.skill
	_room.tick()
	_input_handler.clear_edges()
	if not local.is_empty() and local.has("pendingMessages"):
		for msg in local.pendingMessages:
			_handle_message(msg)
		local.pendingMessages.clear()


# ---------- messages ----------
# 武器定义查询：zclaw 是运行时生成的（zombie_claw_def），不在 BUILTIN_WEAPONS 里，
# 若直接 get 会得到空字典，导致 melee 判不到（产生火光、抓挠动画不触发）。
static func _weapon_def(wid: String) -> Dictionary:
	if WeaponData.BUILTIN_WEAPONS.has(wid):
		return WeaponData.BUILTIN_WEAPONS[wid]
	if wid == "zclaw":
		return WeaponData.zombie_claw_def()
	return {}


func _handle_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("type", ""))
	match t:
		"shot":
			var wid: String = str(msg.get("weapon", "vx9"))
			var def: Dictionary = _weapon_def(wid)
			_sfx.play_shot(str(def.get("sound", "rifle")))
			_vm_punch = 1.0
			_camera_kick = min(_camera_kick + float(def.get("recoil", 0.02)) * 3.0, 0.09)
			# 近战触发挥砍/抓挠动画（fang 挥砍、zclaw 抓挠）
			if def.get("melee", false):
				_melee_swing_t = Time.get_ticks_msec() / 1000.0
				_melee_kind = wid
			# 近战（匕首挥砍/尸爪抓挠）不产生枪口火光、弹壳与曳光
			if not def.get("melee", false) and _viewmodel_muzzle != null:
				var dir := -_camera.global_transform.basis.z
				_world.on_muzzle_flash(_viewmodel_muzzle.global_position, dir)
				_world.on_shell(_viewmodel_muzzle.global_position + Vector3(0.05, -0.02, 0), _camera.global_transform.basis.x)
				# tracer follows the camera center so it visually aligns with the crosshair
				_world.on_shot(_viewmodel_muzzle.global_position, dir, 80.0, wid, null)
		"shot_visual":
			if str(msg.get("id", "")) != _local_id:
				var def2: Dictionary = _weapon_def(str(msg.get("weapon", "")))
				_sfx.play_shot(str(def2.get("sound", "rifle")))
				# 近战不产生曳光/火光（避免匕首尸爪攻击时冒火光）
				if def2.get("melee", false):
					return
				var eye: Vector3 = Vector3(msg.pos.x, msg.pos.y + EYE_STAND, msg.pos.z)
				var dir2 := MathUtil.direction_from_angles(float(msg.yaw), float(msg.pitch))
				_world.on_shot(eye, dir2, 40.0, str(msg.get("weapon", "")))
		"throw_visual":
			if str(msg.get("id", "")) != _local_id:
				_sfx.throw_sfx()
		"throw_ack":
			_sfx.throw_sfx()
		"reloading":
			# 精细换弹：记录开始时刻与时长，由 _update_viewmodel 按进度驱动弹夹动画/分步音效
			var wdef: Dictionary = {}
			if _room != null:
				var lp: Dictionary = _room.state.players.get(_local_id, {})
				if not lp.is_empty() and lp.weapons.has(int(lp.activeSlot)) and lp.weapons[int(lp.activeSlot)] != null:
					wdef = lp.weapons[int(lp.activeSlot)].def
			_reload_t = Time.get_ticks_msec() / 1000.0
			_reload_dur = maxf(0.5, float(wdef.get("reloadTime", 2.0)))
			_reload_stage = -1
			_reload_anim = 1.0
			# 换弹期间显示副手（平时隐藏）
			if _viewmodel != null:
				var hand: Node3D = _viewmodel.get_meta("hand", null)
				if hand != null:
					hand.visible = true
		"reloaded":
			_reload_t = -1.0
			_reload_anim = 0.0
			# 换弹结束：隐藏副手（平时枪悬空，只有换弹时左手出现）
			if _viewmodel != null:
				var hand: Node3D = _viewmodel.get_meta("hand", null)
				if hand != null:
					hand.visible = false
		"use_progress":
			_hud.update_use_progress(str(msg.get("action", "")), float(msg.get("progress", 0.0)))
			if float(msg.get("progress", 0.0)) > 0.0:
				_sfx.tick_sfx()
		"defuse_beep":
			# CS 风格：T 侧听到拆弹的"滴滴"提示（按距离衰减）
			if str(msg.get("id", "")) != _local_id:
				_sfx.defuse_beep(Vector3(msg.pos.x, msg.pos.y, msg.pos.z), _camera.global_position)
		"buy_ok":
			_sfx.buy()
		"refund_ok":
			_sfx.click()
		"ammo_refill":
			_sfx.pickup()
		"health_refill":
			_sfx.pickup()
		"ammo_box":
			_sfx.pickup()
		"health_box":
			_sfx.pickup()
		"kill":
			var killer: String = str(msg.get("killerName", ""))
			var victim: String = str(msg.get("victimName", ""))
			var wpn: String = str(msg.get("weapon", ""))
			var hs: bool = bool(msg.get("headshot", false))
			_hud.add_kill_feed(killer, victim, _weapon_label(wpn), hs)
			_sfx.kill()
			if str(msg.get("victim", "")) == _local_id:
				_hud.show_message("你被击杀了", 2.0)
		"infected":
			if str(msg.get("id", "")) == _local_id:
				_hud.show_message("你被感染了!", 2.0)
			_sfx.zombie()
		"bomb_pickup":
			_hud.show_message("你拾取了炸弹", 1.5)
		"bomb_dropped":
			_hud.show_message("炸弹掉落!", 1.5)
		"bomb_planted":
			_sfx.plant()
			_hud.show_message("炸弹已安放!", 2.0)
		"bomb_defused":
			_sfx.defuse()
			_hud.show_message("炸弹已拆除!", 2.0)
		"bomb_exploded":
			_sfx.explosion()
		"explosion":
			_world.on_explosion(Vector3(msg.pos.x, msg.pos.y, msg.pos.z))
			_sfx.explosion()
		"round_start":
			_sfx.round_start()
			_hud.show_message("回合开始", 1.5)
			if _buy_menu.is_open():
				_buy_menu.hide_menu()
				_input_handler.lock_pointer()
		"round_end":
			# 比赛已定胜负时只播 match_end，避免同帧两条消息互相覆盖。
			# 注意：matchWinner 用 != null 判断（str(null) 在 GDScript 里是 "<null>" 而非空串，
			# 用 str()!="" 会把普通回合结束误判成决胜局，导致拆弹模式每回合横幅都被吞掉）
			if msg.get("matchWinner", null) != null:
				return
			var win: bool = _round_win(str(msg.get("winner", "")))
			_sfx.round_end(win)
			var scores: Dictionary = msg.get("scores", {})
			_hud.show_banner(_banner_text(win, str(msg.get("winner", "")), str(msg.get("reason", "")), scores, true), win)
		"match_end":
			var mwin: bool = _round_win(str(msg.get("winner", "")))
			_sfx.match_end(mwin)
			var mscores: Dictionary = msg.get("scores", {})
			_hud.show_banner(_banner_text(mwin, str(msg.get("winner", "")), str(msg.get("reason", "")), mscores, false), mwin)
		"buy_phase":
			_hud.show_message("购买阶段开始", 1.5)
			# 延迟弹出购买菜单：回合结束的横幅会与购买菜单同帧触发，
			# 全屏菜单会立刻把横幅盖住（拆弹模式看不到胜负横幅的根因）。
			# 先让横幅展示，再自动弹出菜单；玩家也可按 B 提前打开。
			# 自动截图（--shot）时不弹菜单，避免菜单遮挡画面
			if not _buy_menu.is_open():
				_buy_menu_delay = 2.2 if _shot_at <= 0 else -1.0
		"map_change":
			_world.build_map(_room.state.map, _room.state.mapId)
			_world.clear_effects()
			var map_data: Dictionary = _room.state.map
			_hud.show_message("换图: %s" % str(map_data.get("name", "")), 2.5)
		"finale_start":
			_hud.show_message("琉璃决战开始!", 5.0)
		"zombie_boost_visual":
			if str(msg.get("id", "")) == _local_id:
				_sfx.boost()
		"state":
			pass
		"switch":
			_sfx.click()
		"zselect_ok":
			_sfx.buy()


func _weapon_label(wid: String) -> String:
	var def: Dictionary = WeaponData.BUILTIN_WEAPONS.get(wid, {})
	if def.is_empty():
		return wid
	return str(def.get("name", wid))


func _round_win(winner: String) -> bool:
	if _room == null:
		return false
	var players_dict: Dictionary = _room.state.players
	var local: Dictionary = players_dict.get(_local_id, {})
	if local.is_empty():
		return false
	if _room.state.mode == Constants.MODE_DEFUSAL:
		return (local.team == Constants.TEAM_CT) == (winner == "CT")
	if winner == "DRAW":
		return true
	return (local.isZombie) == (winner == "ZOMBIE")


# 胜负播报文案：胜/败 + 阵营 + 原因 + 比分
func _banner_text(win: bool, winner: String, reason: String, scores: Dictionary, is_round: bool) -> String:
	var head: String = "胜利" if win else "失败"
	var team: String = _winner_label(winner)
	var why: String = _reason_label(reason)
	var score_str: String = ""
	if not scores.is_empty():
		var ct: int = int(scores.get("CT", 0))
		var t: int = int(scores.get("T", 0))
		var h: int = int(scores.get("HUMAN", 0))
		var z: int = int(scores.get("ZOMBIE", 0))
		if _room != null and _room.state.mode == Constants.MODE_DEFUSAL:
			score_str = "\n比分 %d : %d" % [ct, t]
		else:
			score_str = "\n比分 人类 %d : %d 丧尸" % [h, z]
	var prefix: String = "本回合" if is_round else "比赛"
	if winner == "DRAW":
		return "%s平局\n双方同归于尽%s" % [prefix, score_str]
	var first: String = "%s：%s %s" % [prefix, team, head]
	if why != "":
		first += "（%s）" % why
	return first + score_str


func _winner_label(winner: String) -> String:
	match winner:
		"CT":
			return "CT 反恐精英"
		"T":
			return "T 恐怖分子"
		"HUMAN":
			return "人类"
		"ZOMBIE":
			return "丧尸"
	return winner


func _reason_label(reason: String) -> String:
	match reason:
		"bomb_exploded":
			return "炸弹爆炸"
		"bomb_defused":
			return "炸弹被拆除"
		"t_eliminated":
			return "T 全灭"
		"ct_eliminated":
			return "CT 全灭"
		"timeout":
			return "时间耗尽"
		"zombies_eliminated":
			return "丧尸全灭"
		"infected_all":
			return "人类全灭"
		"mutual_annihilation":
			return "同归于尽"
		"survived":
			return "幸存到结束"
	return reason


# ---------- events ----------
func _on_player_damage(args: Dictionary) -> void:
	var result: Dictionary = args.result
	var attacker: Variant = args.attacker
	var victim_dict: Dictionary = result.get("victim", {})
	var victim_id: String = str(victim_dict.get("id", ""))
	if victim_id == _local_id:
		_hud.on_damage()
		_sfx.damage()
	elif attacker != null and str(attacker.get("id", "")) == _local_id:
		_hud.on_hit_marker()
		_sfx.hit(bool(result.get("headshot", false)))
		var vp: Dictionary = result.get("victim", {})
		var vpos: Variant = vp.get("pos", null) if vp is Dictionary else null
		if vpos != null and vpos is Vector3:
			var v3: Vector3 = vpos
			_world.on_hit(Vector3(v3.x, v3.y + 1.4, v3.z), bool(result.get("headshot", false)))


func _on_player_death(_args: Dictionary) -> void:
	pass


# ---------- rendering ----------
func _render_frame(delta: float, alpha: float) -> void:
	if _debug_pos and Engine.get_frames_drawn() == 300:
		for pid2 in _room.state.players:
			var pl: Dictionary = _room.state.players[pid2]
			print("[DBG] player ", pid2, " team=", pl.team, " pos=", pl.pos, " alive=", pl.alive, " bot=", pl.isBot)
		print("[DBG] local=", _local_id, " phase=", _room.state.phase)
	var st: Dictionary = _room.state
	_world.render_state(st, alpha)
	var players_st: Dictionary = st.players
	var local: Dictionary = players_st.get(_local_id, {})
	if local.is_empty():
		return
	# enrich HUD snapshot with ammo info
	var ammo: int = 0
	var reserve: int = 0
	if local.weapons.has(int(local.activeSlot)):
		var w: Variant = local.weapons[int(local.activeSlot)]
		if w != null:
			ammo = int(w.ammo)
			reserve = int(w.reserve)
	local["ammo"] = ammo
	local["reserve"] = reserve
	local["w"] = local.weapons[int(local.activeSlot)].def.id if local.weapons.has(int(local.activeSlot)) and local.weapons[int(local.activeSlot)] != null else ""
	_hud.update_local_player(local)
	var core: Variant = st.get("core", null)
	if core != null and st.mode == Constants.MODE_DEFUSAL:
		# 炸弹已安放时主计时器显示炸弹倒计时（CS 风格）
		var time_left: float = float(core.bomb_time_left) if bool(core.bomb_planted) else float(core.time_left)
		_hud.update_round_info(int(st.get("roundNum", 0)), time_left, st.get("matchScore", {}), str(st.get("phase", "live")), float(st.get("buyUntil", 0.0)) - float(st.time))
	elif core != null:
		_hud.update_round_info(int(st.get("roundNum", 0)), float(core.time_left), st.get("matchScore", {}), str(st.get("phase", "live")), 0.0)
	else:
		_hud.update_round_info(0, 0.0, {}, "live", 0.0)
	var bomb: Dictionary = st.get("bomb", {})
	var bomb_state: int = 0
	var bomb_text: String = ""
	var bomb_color: Color = Color(1.0, 1.0, 1.0)
	var bomb_timer: float = 0.0
	if not bomb.is_empty():
		if bomb.get("planted", false):
			bomb_state = 2
			bomb_timer = float(bomb.get("timeLeft", 0.0))
			if int(local.get("team", 0)) == Constants.TEAM_CT:
				bomb_text = "炸弹已安放，按住 E 拆除"
				bomb_color = Color(1.0, 0.45, 0.35)
			else:
				bomb_text = "炸弹已安放"
				bomb_color = Color(1.0, 0.85, 0.4)
			_beep_accum += delta
			if _beep_accum > 0.8:
				_beep_accum = 0.0
				_sfx.tick_sfx()
		elif bomb.get("carried", false):
			bomb_state = 1
			var local_team: int = int(local.get("team", 0))
			var carrier_team: int = -1
			var carrier_id: String = str(bomb.get("carrierId", ""))
			if carrier_id != "" and st.players.has(carrier_id):
				carrier_team = int(st.players[carrier_id].get("team", -1))
			if bool(local.get("bombCarrier", false)):
				bomb_text = "你携带炸弹，前往 A/B 点按 E 安装"
				bomb_color = Color(1.0, 0.85, 0.4)
			elif carrier_team == local_team:
				bomb_text = "炸弹已被队友携带"
				bomb_color = Color(0.8, 0.82, 0.9)
			else:
				bomb_text = "敌人携带炸弹"
				bomb_color = Color(1.0, 0.5, 0.3)
		elif bomb.get("pos", null) != null:
			bomb_state = 3
			bomb_text = "炸弹已掉落"
			bomb_color = Color(0.75, 0.78, 0.84)
	_hud.update_bomb(bomb_state, bomb_text, bomb_color, bomb_timer)
	if float(local.get("useProgress", 0.0)) > 0.0:
		# CT 拆弹 / T 安弹：按队伍判定动作，避免 useTarget 字符串匹配误判
		var act: String = "defuse" if int(local.get("team", 0)) == Constants.TEAM_CT else "plant"
		var max_t: float = 5.0 if act == "defuse" else 3.0
		_hud.update_use_progress(act, clampf(float(local.useProgress) / max_t, 0.0, 1.0))
	else:
		_hud.update_use_progress("", 0.0)
	_hud.update_respawn(max(0.0, float(local.get("respawnAt", 0.0)) - float(st.time)))
	var players_arr: Array = []
	for p in st.players.values():
		players_arr.append(p)
	_scoreboard.update(players_arr, st.get("matchScore", {}), st.mode)
	_update_camera(local, delta)
	_update_viewmodel(local, delta, ammo, reserve)
	_update_footsteps(local, delta)
	var active_def: Dictionary = {}
	if local.weapons.has(int(local.activeSlot)):
		var w2: Variant = local.weapons[int(local.activeSlot)]
		if w2 != null:
			active_def = w2.def
	var spread01: float = 0.0
	var ads: bool = bool(local.input.ads) and not bool(local.isZombie)
	if not active_def.is_empty() and (active_def.get("melee", false) or active_def.has("projectile")):
		ads = false
	if not active_def.is_empty():
		var base: float = float(active_def.get("spread", 0.02))
		var spread: float = WeaponData.apply_spread(active_def, ads)
		spread01 = clampf(spread / max(0.02, base * 2.5), 0.0, 1.0)
	_hud.set_crosshair(spread01, ads)
	if Input.is_action_pressed("scoreboard") and not _buy_menu.is_open():
		_scoreboard.show_scoreboard()
	else:
		if _scoreboard.is_panel_visible():
			_scoreboard.hide_scoreboard()
	_camera_kick = max(0.0, _camera_kick - delta * 0.18)
	_vm_punch = max(0.0, _vm_punch - delta * 4.0)
	_reload_anim = max(0.0, _reload_anim - delta / 1.2)


func _update_camera(p: Dictionary, delta: float) -> void:
	if not _cam_override.is_empty():
		_camera.global_position = Vector3(float(_cam_override[0]), float(_cam_override[1]), float(_cam_override[2]))
		_camera.look_at(Vector3(float(_cam_override[3]), float(_cam_override[4]), float(_cam_override[5])), Vector3.UP)
		return
	# 视角高度：蹲/站之间平滑过渡（参考专业 FPS 的 lerp，避免瞬间跳变）
	var eye_target: float = EYE_CROUCH if bool(p.crouch) else EYE_STAND
	_eye_h = lerpf(_eye_h, eye_target, minf(1.0, delta * 10.0))
	var pos: Vector3
	if bool(p.alive):
		pos = Vector3(p.pos.x, p.pos.y + _eye_h, p.pos.z)
		_dead_cam = pos
	else:
		pos = _dead_cam
	var base_basis := Basis(Vector3(0, 1, 0), float(p.yaw)) * Basis(Vector3(1, 0, 0), float(p.pitch))
	var basis := base_basis * Basis(Vector3(1, 0, 0), _camera_kick)
	_camera.global_position = pos
	_camera.global_transform.basis = basis
	var speed: float = Vector2(p.vel.x, p.vel.z).length() if p.has("vel") else 0.0
	# 冲刺判定（与物理一致：冲刺键 + 前向移动 + 接地 + 非蹲）
	var sprinting: bool = bool(p.input.s) and not bool(p.crouch) and not bool(p.isZombie) and bool(p.grounded) and speed > 3.0
	# headbob：相位按移动速度累积，X/Y 双轴不同频率（参考 Cogito 的 wiggle 实现）
	if bool(p.alive) and bool(p.grounded) and speed > 0.5:
		var freq: float = 12.0 if sprinting else 9.0
		_bob_phase += delta * freq
		var target_amt: float = 0.022 if sprinting else 0.012
		_bob_amt.x = lerpf(_bob_amt.x, target_amt, minf(1.0, delta * 6.0))
		_bob_amt.y = lerpf(_bob_amt.y, target_amt, minf(1.0, delta * 6.0))
		var bob_x: float = sin(_bob_phase * 0.5) * _bob_amt.x * 0.6
		var bob_y: float = absf(sin(_bob_phase)) * _bob_amt.y
		_camera.global_position.y += bob_y
		_camera.global_position.x += bob_x * cos(float(p.yaw))
		_camera.global_position.z += bob_x * -sin(float(p.yaw))
	else:
		_bob_amt = _bob_amt.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	# 落地冲击：从下落转为落地时相机下压再回弹
	if bool(p.alive):
		if bool(p.grounded) and not _was_grounded and float(p.vel.y) < -5.0:
			_land_impact = clampf(-float(p.vel.y) * 0.012, 0.02, 0.14)
		_was_grounded = bool(p.grounded)
	if _land_impact > 0.0:
		_camera.global_position.y -= _land_impact
		_land_impact = maxf(0.0, _land_impact - delta * 0.5)
	var active_def: Dictionary = {}
	if p.weapons.has(int(p.activeSlot)):
		var w: Variant = p.weapons[int(p.activeSlot)]
		if w != null:
			active_def = w.def
	var ads_fov: float = _base_fov
	var ads_active: bool = false
	# 只有枪械能开镜：近战（匕首/尸爪）与投掷物（手雷）禁止 ADS
	if not active_def.is_empty() and not active_def.get("melee", false) and not active_def.has("projectile") and bool(p.input.ads) and not bool(p.isZombie):
		var ads_mult: float = ViewmodelFactory.get_ads_fov(str(active_def.get("id", "vx9"))) / DEFAULT_FOV
		ads_fov = _base_fov * ads_mult
		ads_active = true
	# 冲刺 FOV 扩展（速度感）：非 ADS 时冲刺平滑把 FOV 放大，回正同理
	if sprinting and not ads_active:
		_fov_sprint = lerpf(_fov_sprint, 6.0, minf(1.0, delta * 5.0))
	else:
		_fov_sprint = lerpf(_fov_sprint, 0.0, minf(1.0, delta * 5.0))
	_camera.fov = lerpf(_camera.fov, ads_fov + _fov_sprint, min(1.0, delta * 8.0))
	# ADS focus vignette (screen edges darken while aiming)
	_hud.set_ads_vignette(1.0 if ads_active else 0.0)
	# ADS scope overlay
	_hud.set_scope(str(active_def.get("id", "vx9")) if not active_def.is_empty() else "", ads_active)


func _update_viewmodel(p: Dictionary, delta: float, ammo: int = 0, reserve: int = 0) -> void:
	var w: Variant = p.weapons.get(int(p.activeSlot), null)
	if w == null or not bool(p.alive):
		if _viewmodel != null:
			_viewmodel.queue_free()
			_viewmodel = null
			_viewmodel_muzzle = null
		return
	var wid: String = str(w.def.get("id", "vx9"))
	if _viewmodel == null or str(_viewmodel.get_meta("weapon_id", "")) != wid:
		if _viewmodel != null:
			_viewmodel.queue_free()
		_viewmodel = ViewmodelFactory.build(wid)
		_viewmodel.set_meta("weapon_id", wid)
		_viewmodel_root.add_child(_viewmodel)
		_viewmodel_muzzle = _viewmodel.get_meta("muzzle", null)
		# 缓存弹夹初始 pose（换弹动画基准）；切枪中断旧换弹
		_mag_rest = {}
		var mag: Node3D = _viewmodel.get_meta("mag", null)
		if mag != null:
			_mag_rest = {"pos": mag.position, "rot": mag.rotation}
		_reload_t = -1.0
		_reload_anim = 0.0
	var ads: bool = bool(p.input.ads) and not bool(p.isZombie)
	var wdef_cur: Dictionary = w.def
	# 近战/投掷物不开镜（viewmodel 不贴脸）
	if wdef_cur.get("melee", false) or wdef_cur.has("projectile"):
		ads = false
	var target_pos := Vector3(0.18, -0.18, -0.35)
	if ads:
		target_pos = Vector3(0.0, -0.12, -0.3) + ViewmodelFactory.get_ads_offset(wid)
	var speed: float = Vector2(p.vel.x, p.vel.z).length() if p.has("vel") else 0.0
	# 武器摆动（参考专业 FPS）：相位随移动累积，双轴不同频率；走路/冲刺幅度不同
	var sprinting: bool = bool(p.input.s) and not bool(p.crouch) and not bool(p.isZombie) and bool(p.grounded) and speed > 3.0
	if speed > 0.5 and bool(p.grounded):
		var bob_freq: float = 11.0 if sprinting else 9.0
		_bob_phase += delta * bob_freq
		var amp: float = (0.011 if sprinting else 0.006) * (0.25 if ads else 1.0)
		_bob_amt.x = lerpf(_bob_amt.x, amp, minf(1.0, delta * 6.0))
		_bob_amt.y = lerpf(_bob_amt.y, amp, minf(1.0, delta * 6.0))
		var b_x: float = sin(_bob_phase * 0.5) * _bob_amt.x * 0.8
		var b_y: float = absf(cos(_bob_phase)) * -_bob_amt.y * 1.2
		target_pos.x += b_x
		target_pos.y += b_y
	else:
		_bob_amt = _bob_amt.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	# 移动惯性 sway：速度变化时武器轻微滞后摆动（受控范围，避免飘）
	var sway_x: float = clampf(-p.vel.x * 0.002, -0.012, 0.012) if p.has("vel") else 0.0
	var sway_y: float = clampf(p.vel.y * 0.001, -0.006, 0.006) if p.has("vel") else 0.0
	target_pos.x += sway_x * (0.3 if ads else 1.0)
	target_pos.y += sway_y
	target_pos += Vector3(0.0, -_vm_punch * 0.05, _vm_punch * 0.06)
	target_pos += Vector3(0.0, -_reload_anim * 0.06, _reload_anim * 0.04)
	# 精细换弹：按进度驱动弹夹滑出/甩出/装入 + 上膛脉冲
	if _reload_t >= 0.0:
		var now: float = Time.get_ticks_msec() / 1000.0
		var rp: float = clampf((now - _reload_t) / _reload_dur, 0.0, 1.0)
		_apply_reload_anim(rp)
	# 近战挥砍/抓挠动画：匕首横扫（绕 Y 大角度挥）；尸爪向下挖一下（绕 X 下压 + 下沉回弹）
	var melee_ry: float = 0.0
	var melee_rx: float = 0.0
	var melee_dip: float = 0.0
	if _melee_swing_t >= 0.0:
		var mnow: float = Time.get_ticks_msec() / 1000.0
		var mt: float = mnow - _melee_swing_t
		var mdur: float = 0.3
		if mt < mdur:
			var ph: float = mt / mdur
			if _melee_kind == "fang":
				# 匕首挥砍：从一侧横扫到另一侧（绕 Y）
				melee_ry = sin(ph * PI) * 1.15
			else:
				# 尸爪抓挠：向下挖一下——绕 X 快速下压(向下戳)再回弹，手部同步下沉
				melee_rx = sin(ph * PI) * 0.65
				melee_dip = sin(ph * PI) * -0.04
		else:
			_melee_swing_t = -1.0
	if _viewmodel != null:
		_viewmodel.rotation.y = melee_ry
		_viewmodel.rotation.x = melee_rx
	target_pos.y += melee_dip
	var ads_speed: float = 24.0 if ads else 18.0
	_viewmodel_root.position = _viewmodel_root.position.lerp(target_pos, min(1.0, delta * ads_speed))
	var sway_max: float = 0.003 if ads else 0.012
	var sway := Vector3(clampf(_vm_sway.x, -sway_max, sway_max), clampf(_vm_sway.y, -sway_max, sway_max), 0.0)
	_viewmodel_root.rotation = sway
	_vm_sway *= (1.0 - min(1.0, delta * 6.0))


# 换弹动画（p: 0→1 进度）。阶段：0 拆弹夹 → 1 甩弹夹 → 2 装弹夹 → 3 上膛。
# 内部武器：独立弹夹节点按各枪初始位置做不同路径；
# 外部 GLB：无独立弹夹，整枪做小幅度下沉/上抬（手枪=拉滑套，长枪=下沉）。
func _apply_reload_anim(p: float) -> void:
	if _viewmodel == null:
		return
	var stage: int = 0 if p < 0.30 else (1 if p < 0.45 else (2 if p < 0.75 else 3))
	if stage != _reload_stage:
		_reload_stage = stage
		match stage:
			0:
				_sfx.reload_mag_out()
			2:
				_sfx.reload_mag_in()
			3:
				_sfx.reload_bolt()
	var mag: Node3D = _viewmodel.get_meta("mag", null)
	var is_glb: bool = mag != null and str(mag.name).begins_with("GLB_")
	var is_pistol: bool = str(_viewmodel.get_meta("weapon_id", "")) in ["k9", "pc", "pf"]
	var tilt: float = 0.0
	if mag != null and not _mag_rest.is_empty():
		var rest: Vector3 = _mag_rest["pos"]
		var rrest: Vector3 = _mag_rest["rot"]
		var mpos: Vector3 = rest
		var mrot: Vector3 = rrest
		if is_glb:
			# 外部模型整枪动画：幅度按枪型（手枪拉滑套=下沉+后拉，长枪=下沉）
			var amp: float = 0.02 if is_pistol else 0.035
			var slide: float = 0.01 if is_pistol else 0.0
			if stage == 0:
				var e: float = clampf(p / 0.30, 0.0, 1.0)
				e = e * e
				mpos = rest + Vector3(0, -amp * e, -slide * e)
				tilt = 0.05 * e
			elif stage == 1:
				var e: float = clampf((p - 0.30) / 0.15, 0.0, 1.0)
				mpos = rest + Vector3(0.02 * e, -amp, -slide)
				mrot = rrest + Vector3(0, 0, 0.9 * e)
				tilt = 0.05
			elif stage == 2:
				var e: float = clampf((p - 0.45) / 0.30, 0.0, 1.0)
				e = 1.0 - (1.0 - e) * (1.0 - e)
				mpos = rest + Vector3(0, -amp * (1.0 - e), -slide * (1.0 - e))
				mrot = Vector3(rrest.x, rrest.y, lerpf(rrest.z + 0.9, rrest.z, e))
				tilt = 0.05 * (1.0 - e)
			elif stage == 3:
				mpos = rest
				mrot = rrest
				var e: float = clampf((p - 0.75) / 0.25, 0.0, 1.0)
				tilt = sin(e * PI) * 0.03
		else:
			# 内部武器独立弹夹：沿弹夹方向滑出 → 侧甩 → 插回 → 上膛脉冲
			if stage == 0:
				var e: float = clampf(p / 0.30, 0.0, 1.0)
				e = e * e
				mpos = rest + Vector3(0, -0.05 * e, 0)
				tilt = 0.07 * e
			elif stage == 1:
				var e: float = clampf((p - 0.30) / 0.15, 0.0, 1.0)
				mpos = rest + Vector3(0.055 * e, -0.05 - 0.09 * e, 0)
				mrot = rrest + Vector3(0, 0, 1.4 * e)
				tilt = 0.07
			elif stage == 2:
				var e: float = clampf((p - 0.45) / 0.30, 0.0, 1.0)
				e = 1.0 - (1.0 - e) * (1.0 - e)
				mpos = rest + Vector3(0, -0.06 * (1.0 - e), 0)
				mrot = Vector3(rrest.x, rrest.y, lerpf(rrest.z + 1.4, rrest.z, e))
				tilt = 0.07 * (1.0 - e)
			elif stage == 3:
				mpos = rest
				mrot = rrest
				var e: float = clampf((p - 0.75) / 0.25, 0.0, 1.0)
				tilt = sin(e * PI) * 0.035
		mag.position = mpos
		mag.rotation = mrot
		# 副手跟随弹夹：伸向抓取位 → 带夹甩出 → 插回 → 回持握位
		var hand: Node3D = _viewmodel.get_meta("hand", null)
		if hand != null:
			var hold: Vector3 = hand.get_meta("hold", Vector3.ZERO)
			var grab: Vector3 = rest + Vector3(-0.005, 0.006, 0.008)
			var htarget: Vector3 = hold
			if is_glb:
				# GLB 整枪：手在持握位小幅下沉/侧甩模拟
				var amp2: float = 0.02 if is_pistol else 0.03
				if stage == 0:
					var e: float = clampf(p / 0.30, 0.0, 1.0)
					htarget = hold + Vector3(0, -amp2 * e, 0.005 * e)
				elif stage == 1:
					var e: float = clampf((p - 0.30) / 0.15, 0.0, 1.0)
					htarget = hold + Vector3(-0.03 * e, -amp2, 0.008)
				elif stage == 2:
					var e: float = clampf((p - 0.45) / 0.30, 0.0, 1.0)
					e = 1.0 - (1.0 - e) * (1.0 - e)
					htarget = hold + Vector3(-0.03 * (1.0 - e), -amp2 * (1.0 - e), 0.008 * (1.0 - e))
				else:
					htarget = hold
			else:
				# 独立弹夹：手抓弹夹做完整拆/装动作
				if stage == 0:
					var e: float = clampf(p / 0.30, 0.0, 1.0)
					htarget = grab
				elif stage == 1:
					var e: float = clampf((p - 0.30) / 0.15, 0.0, 1.0)
					htarget = grab + Vector3(-0.055 * e, -0.05 - 0.09 * e, 0)
				elif stage == 2:
					var e: float = clampf((p - 0.45) / 0.30, 0.0, 1.0)
					e = 1.0 - (1.0 - e) * (1.0 - e)
					htarget = grab + Vector3(-0.055 * (1.0 - e), (-0.05 - 0.09) * (1.0 - e), 0)
				else:
					htarget = hold
			hand.position = hand.position.lerp(htarget, minf(1.0, 0.35))
	else:
		# 无弹夹节点：整体下倾模拟
		if stage == 0:
			tilt = 0.07 * clampf(p / 0.30, 0.0, 1.0)
		elif stage == 1:
			tilt = 0.07
		elif stage == 2:
			tilt = 0.07 * (1.0 - clampf((p - 0.45) / 0.30, 0.0, 1.0))
		elif stage == 3:
			var e: float = clampf((p - 0.75) / 0.25, 0.0, 1.0)
			tilt = sin(e * PI) * 0.035
	_viewmodel.rotation.x = tilt


func _update_footsteps(p: Dictionary, delta: float) -> void:
	if not bool(p.alive):
		return
	var speed: float = Vector2(p.vel.x, p.vel.z).length()
	if not bool(p.grounded) or speed < 1.5:
		return
	_footstep_dist += speed * delta
	if _footstep_dist > 2.6:
		_footstep_dist = 0.0
		_sfx.footstep()


# ---------- buy menu ----------
func _open_buy_menu() -> void:
	if _local_id == "" or _room == null:
		return
	var players_dict: Dictionary = _room.state.players
	var local: Dictionary = players_dict.get(_local_id, {})
	if local.is_empty():
		return
	# CS 规则：购买阶段（phase=="buy"）允许死亡玩家打开菜单——回合结束刚阵亡、
	# 队伍全灭时还没重生，此时必须能先为下一回合买枪。非购买阶段死亡则不允许。
	if _room.state.phase != "buy" and not bool(local.alive):
		return
	if _room.state.mode != Constants.MODE_DEFUSAL and _room.state.mode != Constants.MODE_ZOMBIE:
		return
	var bought: Array = _bought_list(local, _room.state.mode)
	_buy_menu.open(_room.state.mode, int(local.money), int(local.armor), bought)
	_input_handler.unlock_pointer()


func _bought_list(local: Dictionary, mode: String) -> Array:
	var bought: Array = []
	if mode == Constants.MODE_ZOMBIE:
		var sp: Variant = local.get("selectedPrimary", null)
		if sp != null and str(sp) != "":
			bought.append(str(sp))
	else:
		for rec in local.get("boughtItems", []):
			bought.append(str(rec.item))
	return bought


func _on_buy(item: String) -> void:
	if _room == null or _local_id == "":
		return
	var players_dict: Dictionary = _room.state.players
	var local: Dictionary = players_dict.get(_local_id, {})
	if local.is_empty():
		return
	var r: Dictionary
	if _room.state.mode == Constants.MODE_DEFUSAL:
		r = _room.handle_buy(local, item)
	else:
		r = _room.handle_zombie_select(local, item)
	if not bool(r.get("ok", false)):
		_sfx.empty()
	_buy_menu.update_money(int(local.money), _bought_list(local, _room.state.mode))


func _on_refund(item: String) -> void:
	if _room == null or _local_id == "":
		return
	var players_dict: Dictionary = _room.state.players
	var local: Dictionary = players_dict.get(_local_id, {})
	if local.is_empty():
		return
	_room.handle_refund(local, item)
	_buy_menu.update_money(int(local.money), _bought_list(local, _room.state.mode))


func _on_buy_menu_closed() -> void:
	if _running:
		_input_handler.lock_pointer()


# ---------- pause / menu keys ----------
func _toggle_pause(paused: bool) -> void:
	_paused = paused
	if _paused:
		_input_handler.unlock_pointer()
		_pause_menu.show_menu()
	else:
		_pause_menu.hide_menu()
		_input_handler.lock_pointer()


func _on_menu_requested() -> void:
	_toggle_pause(false)
	_running = false
	_room = null
	_local_id = ""
	_world.clear_map()
	_input_handler.set_enabled(false)
	_input_handler.unlock_pointer()
	_main_menu.show_menu()


func _on_settings_changed(settings: Dictionary) -> void:
	_apply_settings(settings)
	_save_settings(settings)


func _apply_settings(settings: Dictionary) -> void:
	_base_fov = clampf(float(settings.get("fov", DEFAULT_FOV)), 70.0, 110.0)
	_settings_volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_settings_volume))
	if _bgm != null:
		_bgm.set_volume_linear(_settings_volume)
		_bgm.set_enabled(bool(settings.get("bgm", true)))


func _save_settings(settings: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "fov", clampf(float(settings.get("fov", DEFAULT_FOV)), 70.0, 110.0))
	cfg.set_value("game", "volume", clampf(float(settings.get("volume", 1.0)), 0.0, 1.0))
	cfg.set_value("game", "bgm", bool(settings.get("bgm", true)))
	cfg.save("user://settings.cfg")


func _unhandled_input(event: InputEvent) -> void:
	# F11 全屏切换（主菜单和游戏中都可用）
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_bgm"):
		_on_toggle_bgm()
		get_viewport().set_input_as_handled()
		return
	if not _running:
		return
	if event.is_action_pressed("pause_toggle") and not _buy_menu.is_open():
		_toggle_pause(not _paused)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("buy_menu") and not _paused:
		if _buy_menu.is_open():
			_buy_menu.hide_menu()
			_input_handler.lock_pointer()
		else:
			_open_buy_menu()
		get_viewport().set_input_as_handled()


func _on_toggle_bgm() -> void:
	if _bgm == null:
		return
	_bgm.set_enabled(not _bgm.is_enabled())
	if _hud != null:
		_hud.show_message("BGM: %s" % ("开" if _bgm.is_enabled() else "关"), 1.5)


# F11 全屏切换：全屏 <-> 最大化窗口（项目启动默认为最大化窗口）
func _toggle_fullscreen() -> void:
	var win: Window = get_window()
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		win.mode = Window.MODE_MAXIMIZED
	else:
		win.mode = Window.MODE_FULLSCREEN
	if _hud != null:
		_hud.show_message("全屏: %s" % ("开" if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else "关"), 1.2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _running and not _paused:
		_paused = true
		_input_handler.unlock_pointer()
		_hud.show_message("已暂停 - 按 Esc 继续", 99999.0)
