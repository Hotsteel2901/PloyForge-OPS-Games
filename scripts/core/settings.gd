# 统一设置中心（v2）。替代散落在 main_menu / game.gd 里的零散存取。
# 特点：schema 驱动、类型安全、改动即广播、自动迁移旧 settings.cfg、可导出/导入配置。
extends Node

signal changed(section: String, key: String, value: Variant)
signal applied(section: String)

const PATH_V2: String = "user://settings_v2.cfg"
const PATH_V1: String = "user://settings.cfg"
const PATH_PROFILE: String = "user://profile.cfg"

# schema: section -> key -> {v: default, min, max, step, label, kind}
# kind: "bool" | "int" | "float" | "enum" | "color" | "string"
const SCHEMA: Dictionary = {
	"graphics": {
		"quality": {"v": 3, "min": 0, "max": 4, "kind": "enum", "label": "画质档位"},
		"render_scale": {"v": 1.0, "min": 0.4, "max": 1.5, "step": 0.05, "kind": "float", "label": "3D 分辨率"},
		"auto_scale": {"v": true, "kind": "bool", "label": "自适应分辨率"},
		"fov": {"v": 74.0, "min": 60.0, "max": 120.0, "step": 1.0, "kind": "float", "label": "视野 FOV"},
		"weapon_fov_scale": {"v": true, "kind": "bool", "label": "武器独立 FOV"},
		"motion_blur": {"v": 0.0, "min": 0.0, "max": 1.0, "step": 0.05, "kind": "float", "label": "动态模糊"},
		"film_grain": {"v": 0.0, "min": 0.0, "max": 0.5, "step": 0.01, "kind": "float", "label": "胶片颗粒"},
		"chromatic": {"v": 0.0, "min": 0.0, "max": 1.0, "step": 0.05, "kind": "float", "label": "色散"},
		"bloom": {"v": 1.0, "min": 0.0, "max": 2.0, "step": 0.05, "kind": "float", "label": "泛光"},
		"ssao": {"v": true, "kind": "bool", "label": "环境光遮蔽"},
		"ssr": {"v": true, "kind": "bool", "label": "屏幕空间反射"},
		"volumetric_fog": {"v": true, "kind": "bool", "label": "体积雾"},
		"blood": {"v": true, "kind": "bool", "label": "血液特效"},
		"shells": {"v": true, "kind": "bool", "label": "弹壳抛射"},
		"decals": {"v": true, "kind": "bool", "label": "弹孔贴花"},
		"vsync": {"v": true, "kind": "bool", "label": "垂直同步"},
		"fps_limit": {"v": 0, "min": 0, "max": 360, "step": 15, "kind": "int", "label": "帧率上限"},
		"gamma": {"v": 1.0, "min": 0.6, "max": 1.6, "step": 0.02, "kind": "float", "label": "亮度"},
		"hud_scale": {"v": 1.0, "min": 0.7, "max": 1.6, "step": 0.05, "kind": "float", "label": "HUD 缩放"},
	},
	"audio": {
		"master": {"v": 0.9, "min": 0.0, "max": 1.0, "step": 0.01, "kind": "float", "label": "主音量"},
		"music": {"v": 0.55, "min": 0.0, "max": 1.0, "step": 0.01, "kind": "float", "label": "音乐"},
		"sfx": {"v": 0.9, "min": 0.0, "max": 1.0, "step": 0.01, "kind": "float", "label": "音效"},
		"voice": {"v": 0.9, "min": 0.0, "max": 1.0, "step": 0.01, "kind": "float", "label": "语音"},
		"mute_unfocused": {"v": true, "kind": "bool", "label": "失焦静音"},
		"music_dynamic": {"v": true, "kind": "bool", "label": "动态音乐"},
		"hrtf": {"v": true, "kind": "bool", "label": "3D 音效定位"},
	},
	"controls": {
		"sensitivity": {"v": 1.0, "min": 0.1, "max": 6.0, "step": 0.05, "kind": "float", "label": "鼠标灵敏度"},
		"ads_sens_mult": {"v": 0.75, "min": 0.2, "max": 1.5, "step": 0.05, "kind": "float", "label": "开镜灵敏度倍率"},
		"invert_y": {"v": false, "kind": "bool", "label": "反转 Y 轴"},
		"smoothing": {"v": 0.25, "min": 0.0, "max": 1.0, "step": 0.05, "kind": "float", "label": "鼠标平滑"},
		"toggle_ads": {"v": false, "kind": "bool", "label": "开镜切换模式"},
		"toggle_sprint": {"v": false, "kind": "bool", "label": "冲刺切换模式"},
		"auto_reload": {"v": true, "kind": "bool", "label": "自动换弹"},
		"gyro": {"v": false, "kind": "bool", "label": "陀螺仪辅助瞄准"},
		"gyro_sens": {"v": 1.0, "min": 0.1, "max": 4.0, "step": 0.05, "kind": "float", "label": "陀螺仪灵敏度"},
		"touch_scale": {"v": 1.0, "min": 0.6, "max": 1.8, "step": 0.05, "kind": "float", "label": "触摸按键大小"},
		"touch_opacity": {"v": 0.55, "min": 0.15, "max": 1.0, "step": 0.05, "kind": "float", "label": "触摸按键透明度"},
		"touch_left_handed": {"v": false, "kind": "bool", "label": "左手布局"},
		"aim_assist": {"v": 0.35, "min": 0.0, "max": 1.0, "step": 0.05, "kind": "float", "label": "辅助瞄准（手柄/触屏）"},
	},
	"gameplay": {
		"player_name": {"v": "Operator", "kind": "string", "label": "玩家名"},
		"crosshair_style": {"v": 0, "min": 0, "max": 3, "kind": "enum", "label": "准星样式"},
		"crosshair_color": {"v": 0, "min": 0, "max": 5, "kind": "enum", "label": "准星颜色"},
		"hitmarker_sound": {"v": true, "kind": "bool", "label": "命中音效"},
		"damage_numbers": {"v": true, "kind": "bool", "label": "伤害数字"},
		"killcam": {"v": true, "kind": "bool", "label": "死亡回放"},
		"view_bob": {"v": 1.0, "min": 0.0, "max": 2.0, "step": 0.1, "kind": "float", "label": "视角晃动"},
		"subtitles": {"v": true, "kind": "bool", "label": "播报字幕"},
	},
	"network": {
		"relay_url": {"v": "", "kind": "string", "label": "中继服务器"},
		"prefer_p2p": {"v": true, "kind": "bool", "label": "优先 P2P 直连"},
		"max_ping": {"v": 200, "min": 40, "max": 600, "step": 10, "kind": "int", "label": "延迟上限"},
		"lan_discovery": {"v": true, "kind": "bool", "label": "局域网发现"},
		"interp_ms": {"v": 60, "min": 0, "max": 200, "step": 5, "kind": "int", "label": "插值延迟"},
	},
	"accessibility": {
		"colorblind": {"v": 0, "min": 0, "max": 3, "kind": "enum", "label": "色盲模式"},
		"reduce_motion": {"v": false, "kind": "bool", "label": "减少动效"},
		"large_text": {"v": false, "kind": "bool", "label": "大字号"},
		"screen_shake": {"v": 1.0, "min": 0.0, "max": 1.5, "step": 0.1, "kind": "float", "label": "屏幕震动"},
	},
}

var _data: Dictionary = {}
var _dirty: bool = false
var _save_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_reset_to_defaults()
	_load()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_timer += delta
	if _save_timer >= 0.8:
		_save_timer = 0.0
		flush()


func _reset_to_defaults() -> void:
	_data.clear()
	for section in SCHEMA:
		_data[section] = {}
		for key in SCHEMA[section]:
			_data[section][key] = SCHEMA[section][key].v


# ---------------- 读写 ----------------

func get_value(section: String, key: String) -> Variant:
	if _data.has(section) and _data[section].has(key):
		return _data[section][key]
	if SCHEMA.has(section) and SCHEMA[section].has(key):
		return SCHEMA[section][key].v
	return null


func get_int(section: String, key: String) -> int:
	return int(get_value(section, key))


func get_float(section: String, key: String) -> float:
	return float(get_value(section, key))


func get_bool(section: String, key: String) -> bool:
	return bool(get_value(section, key))


func get_str(section: String, key: String) -> String:
	return str(get_value(section, key))


func set_value(section: String, key: String, value: Variant) -> void:
	if not SCHEMA.has(section) or not SCHEMA[section].has(key):
		push_warning("[Settings] 未知配置项 %s.%s" % [section, key])
		return
	var spec: Dictionary = SCHEMA[section][key]
	var clamped: Variant = _coerce(spec, value)
	if _data.has(section) and _data[section].get(key) == clamped:
		return
	_data[section][key] = clamped
	_dirty = true
	changed.emit(section, key, clamped)


func _coerce(spec: Dictionary, value: Variant) -> Variant:
	var kind: String = str(spec.get("kind", "float"))
	match kind:
		"bool":
			return bool(value)
		"int":
			return clampi(int(value), int(spec.get("min", -2147483648)), int(spec.get("max", 2147483647)))
		"enum":
			return clampi(int(value), int(spec.get("min", 0)), int(spec.get("max", 255)))
		"float":
			return clampf(float(value), float(spec.get("min", -1e9)), float(spec.get("max", 1e9)))
		"color":
			return value
		"string":
			return str(value)
	return value


func section(name: String) -> Dictionary:
	return _data.get(name, {}).duplicate()


func schema(section_name: String) -> Dictionary:
	return SCHEMA.get(section_name, {})


# ---------------- 持久化 ----------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(PATH_V2):
		if cfg.load(PATH_V2) == OK:
			_apply_cfg(cfg)
	else:
		_migrate_v1()
	apply()


func _apply_cfg(cfg: ConfigFile) -> void:
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if SCHEMA.has(section) and SCHEMA[section].has(key):
				_data[section][key] = _coerce(SCHEMA[section][key], cfg.get_value(section, key))


func _migrate_v1() -> void:
	# 旧版只有 game/fov, game/volume, game/bgm 三项
	var cfg := ConfigFile.new()
	if cfg.load(PATH_V1) != OK:
		return
	var fov: float = float(cfg.get_value("game", "fov", 74.0))
	var vol: float = float(cfg.get_value("game", "volume", 1.0))
	var bgm: bool = bool(cfg.get_value("game", "bgm", true))
	set_value("graphics", "fov", fov)
	set_value("audio", "master", vol)
	set_value("audio", "music", 0.55 if bgm else 0.0)
	print("[Settings] 已从 v1 配置迁移")


func flush() -> void:
	if not _dirty:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 2)
	for section in _data:
		for key in _data[section]:
			cfg.set_value(section, key, _data[section][key])
	var err: int = cfg.save(PATH_V2)
	if err != OK:
		push_warning("[Settings] 保存失败: %d" % err)
	_dirty = false


## 立即把设置作用到引擎（音量总线、帧率、FOV 等）
func apply() -> void:
	_apply_audio()
	_apply_video()
	applied.emit("all")


func _apply_audio() -> void:
	_set_bus("Master", get_float("audio", "master"))
	_set_bus("Music", get_float("audio", "music"))
	_set_bus("SFX", get_float("audio", "sfx"))
	_set_bus("Voice", get_float("audio", "voice"))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, linear)))


func _apply_video() -> void:
	# headless / 服务端没有真实交换链，设置 VSYNC 会让主循环永久阻塞
	var ds_name: String = DisplayServer.get_name()
	if ds_name != "headless":
		var want_vsync: bool = get_bool("graphics", "vsync")
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if want_vsync else DisplayServer.VSYNC_DISABLED
		)
	var cap: int = get_int("graphics", "fps_limit")
	if cap > 0:
		Engine.max_fps = cap


func export_json() -> String:
	return JSON.stringify(_data, "\t")


func import_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return false
	for section in parsed:
		if not SCHEMA.has(section):
			continue
		for key in parsed[section]:
			if SCHEMA[section].has(key):
				set_value(section, key, parsed[section][key])
	flush()
	apply()
	return true


func reset_all() -> void:
	_reset_to_defaults()
	_dirty = true
	flush()
	apply()
