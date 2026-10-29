# 平台抽象层：设备能力探测、画质档位、安全区、输入形态。
# 目标：同一套代码在 Windows / Linux / macOS / Web / Android / iOS 上自动选择最优参数。
extends Node

# 画质档位（数值越大越好）
enum Tier { POTATO = 0, LOW = 1, MEDIUM = 2, HIGH = 3, ULTRA = 4 }

const TIER_NAMES: Array = ["土豆", "低", "中", "高", "极致"]

var tier: int = Tier.HIGH
var tier_locked: bool = false
var is_mobile: bool = false
var is_web: bool = false
var is_desktop: bool = false
var is_touch_primary: bool = false
var has_gyro: bool = false
var core_count: int = 1
var screen_dpi: float = 96.0
var refresh_hz: float = 60.0
var gpu_name: String = "unknown"
var gpu_vendor: String = "unknown"
var total_ram_mb: int = 0

## 运行时可变的分辨率缩放（自适应帧率会调用 set_render_scale）
var render_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web = OS.has_feature("web")
	is_mobile = OS.has_feature("mobile")
	is_desktop = not is_web and not is_mobile
	is_touch_primary = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	core_count = maxi(1, OS.get_processor_count())
	if not is_web:
		gpu_name = str(RenderingServer.get_video_adapter_name())
		gpu_vendor = str(RenderingServer.get_video_adapter_vendor())
		total_ram_mb = int(OS.get_memory_info().get("physical", 0) / (1024 * 1024))
		screen_dpi = DisplayServer.screen_get_dpi()
		refresh_hz = float(DisplayServer.screen_get_refresh_rate())
		if refresh_hz <= 0.0:
			refresh_hz = 60.0
	else:
		gpu_name = "webgl"
	# 陀螺仪：移动端与支持传感器的手持设备
	has_gyro = is_mobile or Input.get_connected_joypads().size() > 0
	tier = _detect_tier()
	_log_banner()


func _detect_tier() -> int:
	# Web：单线程 WASM + WebGL2，填充率是最大瓶颈
	if is_web:
		if core_count >= 8:
			return Tier.MEDIUM
		return Tier.LOW
	# 移动端：按核心数 / 内存 / DPI 粗分
	if is_mobile:
		if total_ram_mb >= 7000 and core_count >= 8:
			return Tier.HIGH
		if total_ram_mb >= 4000 and core_count >= 6:
			return Tier.MEDIUM
		return Tier.LOW
	# 桌面：核显低配 → MEDIUM，独显 → HIGH，强力独显 → ULTRA
	var g: String = gpu_name.to_lower()
	var weak: bool = g.contains("intel") or g.contains("uhd") or g.contains("hd graphics") \
		or g.contains("radeon graphics") or g.contains("vega 8") or g.contains("apple m1")
	if weak and core_count < 8:
		return Tier.MEDIUM
	if core_count >= 12 and total_ram_mb >= 16000 and not weak:
		return Tier.ULTRA
	if weak:
		return Tier.MEDIUM
	return Tier.HIGH


func _log_banner() -> void:
	print("[Platform] tier=%s mobile=%s web=%s cores=%d gpu=%s ram=%dMB dpi=%.0f hz=%.0f" % [
		TIER_NAMES[tier], str(is_mobile), str(is_web), core_count, gpu_name, total_ram_mb, screen_dpi, refresh_hz,
	])


# ---------------- 画质应用 ----------------

## 界面缩放系数（DPI 自适应）：高分屏 UI 不至于太小，低分屏不至于挤爆
func ui_scale() -> float:
	if is_web:
		return 1.0
	var dpi: float = maxf(72.0, screen_dpi)
	var s: float = dpi / 96.0
	# 手机 DPI 常 400+，直接按 DPI 会过大，压缩到 1.0~1.6
	if is_mobile:
		return clampf(0.95 + (s - 1.0) * 0.22, 0.95, 1.5)
	return clampf(s, 1.0, 2.0)


## 依据档位套用全局渲染设置。viewport 传入当前视口（可为 null）。
func apply_quality(t: int, viewport: Viewport = null) -> void:
	tier = clampi(t, 0, 4)
	var vp: Viewport = viewport
	if vp == null and is_inside_tree():
		vp = get_viewport()

	# --- 3D 分辨率缩放 ---
	render_scale = _default_render_scale(tier)
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
		vp.use_taa = tier >= Tier.HIGH and not is_web and not is_mobile
		vp.msaa_3d = Viewport.MSAA_4X if tier >= Tier.ULTRA else (Viewport.MSAA_2X if tier == Tier.HIGH else Viewport.MSAA_DISABLED)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if tier <= Tier.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED

	# --- 阴影 ---
	_ps("rendering/lights_and_shadows/directional_shadow/size", _dir_shadow_size(tier))
	_ps("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", clampi(tier - 1, 0, 4))
	_ps("rendering/lights_and_shadows/positional_shadow/atlas_size", _pos_shadow_atlas(tier))
	_ps("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", clampi(tier - 2, 0, 4))

	# --- 纹理过滤 ---
	_ps("rendering/textures/default_filters/anisotropic_filtering_level", clampi(tier - 1, 0, 4))
	_ps("rendering/textures/default_filters/use_nearest_mipmap_filter", false)

	# --- 后处理 ---
	_ps("rendering/environment/glow/upscale_mode", 1 if tier >= Tier.HIGH else 0)
	_ps("rendering/anti_aliasing/quality/msaa_2d", 1 if tier >= Tier.HIGH and not is_web else 0)
	_ps("rendering/scaling_3d/fsr_sharpness", 0.2 if tier >= Tier.HIGH else 0.0)

	# --- 帧率 ---
	match tier:
		Tier.POTATO:
			Engine.max_fps = 30
		Tier.LOW:
			Engine.max_fps = 45 if is_mobile else 60
		_:
			Engine.max_fps = 0 if is_desktop else 60

	# --- 物理/线程 ---
	_ps("physics/3d/physics_engine", "Jolt Physics")
	print("[Platform] quality -> %s (render_scale=%.2f)" % [TIER_NAMES[tier], render_scale])


func _default_render_scale(t: int) -> float:
	if is_web:
		return [0.5, 0.62, 0.75, 0.85, 0.9][t]
	if is_mobile:
		return [0.55, 0.68, 0.8, 0.9, 1.0][t]
	return [0.7, 0.85, 1.0, 1.0, 1.0][t]


func _dir_shadow_size(t: int) -> int:
	return [512, 1024, 2048, 4096, 4096][t]


func _pos_shadow_atlas(t: int) -> int:
	return [512, 1024, 2048, 2048, 4096][t]


func set_render_scale(s: float) -> void:
	render_scale = clampf(s, 0.4, 1.5)
	if is_inside_tree():
		get_viewport().scaling_3d_scale = render_scale


## 当前档位下的推荐特性开关，供 Environment / 渲染器查询
func fx_enabled(feature: String) -> bool:
	match feature:
		"sdfgi":
			return tier >= Tier.HIGH and not is_web
		"ssr":
			return tier >= Tier.MEDIUM and not is_web
		"ssao":
			return tier >= Tier.MEDIUM
		"ssil":
			return tier >= Tier.ULTRA
		"glow":
			return tier >= Tier.LOW
		"volumetric_fog":
			return tier >= Tier.HIGH
		"motion_blur":
			return tier >= Tier.ULTRA and not is_mobile
		"decals":
			return tier >= Tier.MEDIUM
		"particle_high":
			return tier >= Tier.HIGH
		"dynamic_lights":
			return tier >= Tier.MEDIUM
		"viewmodel_shadows":
			return tier >= Tier.HIGH
	return false


## 安全区（刘海/挖孔/圆角）：返回 UI 可用的矩形像素
func safe_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	var win_size: Vector2 = get_viewport().get_visible_rect().size
	if not is_mobile:
		return Rect2(Vector2.ZERO, win_size)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var scr: Vector2i = DisplayServer.screen_get_size()
	if scr.x <= 0 or scr.y <= 0:
		return Rect2(Vector2.ZERO, win_size)
	var sx: float = win_size.x / float(scr.x)
	var sy: float = win_size.y / float(scr.y)
	return Rect2(Vector2(safe.position.x * sx, safe.position.y * sy), Vector2(safe.size.x * sx, safe.size.y * sy))


## 刘海/水滴屏顶部内缩（像素）
func safe_top() -> float:
	var r: Rect2 = safe_rect()
	return r.position.y


func safe_bottom() -> float:
	if not is_inside_tree():
		return 0.0
	var r: Rect2 = safe_rect()
	return maxf(0.0, get_viewport().get_visible_rect().size.y - (r.position.y + r.size.y))


func is_landscape() -> bool:
	if not is_inside_tree():
		return true
	return get_viewport().get_visible_rect().size.x >= get_viewport().get_visible_rect().size.y


## 是否应该显示触摸虚拟按键
func wants_touch_ui() -> bool:
	if is_mobile:
		return true
	if is_web and OS.has_feature("web_android"):
		return true
	return false


## UI 基准缩放：canvas_items + expand 已经按 1080p 等比缩放，
## 但手机屏幕物理尺寸小、握持距离近，仍需要再放大一档才看得清。
## mult 来自用户设置 graphics/hud_scale（0.7~1.6）。
func apply_ui_scale(mult: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var base: float = 1.0
	if is_mobile:
		# 6.7" 2400x1080 上 1.35 倍后逻辑分辨率约 1778x800，UI 元素接近桌面观感
		base = 1.35
	elif is_web and OS.has_feature("web_android"):
		base = 1.25
	var f: float = clampf(base * mult, 0.7, 2.2)
	get_window().content_scale_factor = f


## 触摸输入是否为主输入（决定是否忽略鼠标事件、是否启用虚拟手柄）
func is_touch_device() -> bool:
	if is_touch_primary:
		return true
	return DisplayServer.is_touchscreen_available()


func _ps(key: String, value: Variant) -> void:
	# 直接改 ProjectSettings 对已初始化的渲染后端无效，这里仅记录；
	# 真正的运行时切换由各系统（Environment / 光影）读取 Platform.tier 完成。
	if ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, value)
