# GameEnvironment: builds WorldEnvironment (sky, atmosphere, post-FX) + sun/fill lights.
# The theme dictionary comes from map data (map.sky) with sensible defaults.
class_name GameEnvironment
extends Node3D

const DEFAULT_THEME: Dictionary = {
	"zenith": Color("2e4f85"),
	"horizon": Color("c9d2db"),
	"ground": Color("4a443c"),
	"fog": Color("b9c3cc"),
	"fog_density": 0.006,
	"sun_dir": Vector3(0.45, 0.28, -0.85),
	"sun_color": Color("ffe9c4"),
	"sun_energy": 2.4,
	"sun_softness": 0.55,
	"sky_brightness": 1.15,
	"ambient_energy": 0.65,
	"fill_energy": 0.15,
	"fill_color": Color("8fb8ff"),
	"glow_intensity": 0.9,
	"glow_strength": 0.12,
	"exposure": 1.0,
	"saturation": 1.06,
	"contrast": 1.04,
	"cloud_coverage": 0.30,
	"cloud_density": 0.55,
	"haze": 0.30,
	"stars": 0.0,
	"volumetric": 0.05,
	"shadow_color": Color(0.1, 0.14, 0.22, 0.7),
}

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var we: WorldEnvironment
var theme: Dictionary = {}
var sky_shader: ShaderMaterial


static func create(t: Dictionary = {}) -> GameEnvironment:
	var inst := GameEnvironment.new()
	inst.theme = DEFAULT_THEME.duplicate(true)
	for k in t:
		inst.theme[k] = t[k]
	return inst


func _ready() -> void:
	# Compatibility 渲染器（Web 专用）不支持 SDFGI/SSIL/SSR/体积雾等间接光，
	# 且从天空采样辐照度的环境光极弱，导致无点光源区域几乎无光、天空偏暗。
	# 按当前渲染方法判定：Compatibility 下改用直接环境光并提高天空/光源/曝光。
	var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# ---------- Sky ----------
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var hdri_path := "res://assets/hdri/sky_2k.hdr"
	var use_hdri: bool = bool(theme.get("use_hdri", true)) and ResourceLoader.exists(hdri_path)
	var th := theme
	if use_hdri:
		var pan := PanoramaSkyMaterial.new()
		pan.panorama = load(hdri_path)
		pan.filter = true
		pan.energy_multiplier = 1.05 if compat else 1.0
		sky.sky_material = pan
		sky.radiance_size = Sky.RADIANCE_SIZE_256
	else:
		var sky_mat := ShaderMaterial.new()
		sky_mat.shader = load("res://assets/shaders/sky.gdshader")
		sky_mat.set_shader_parameter("zenith_color", Color(th.zenith).lightened(0.12))
		sky_mat.set_shader_parameter("horizon_color", Color(th.horizon))
		sky_mat.set_shader_parameter("ground_color", Color(th.ground))
		sky_mat.set_shader_parameter("sun_dir", Vector3(th.sun_dir).normalized())
		sky_mat.set_shader_parameter("sun_color", Color(th.sun_color))
		sky_mat.set_shader_parameter("sun_intensity", 0.9 + 1.4 * float(th.sky_brightness))
		sky_mat.set_shader_parameter("cloud_coverage", th.cloud_coverage)
		sky_mat.set_shader_parameter("cloud_density", th.cloud_density)
		sky_mat.set_shader_parameter("cloud_albedo", Color(th.horizon).lightened(0.35))
		sky_mat.set_shader_parameter("haze_strength", th.haze)
		sky_mat.set_shader_parameter("stars_amount", th.stars)
		sky_shader = sky_mat
		sky.sky_material = sky_mat
	# HDRI exposure scaling: panoramas are very bright; pull exposure/sun/ambient down.
	var hdri_exp: float = float(th.get("hdri_exposure", 1.0)) if use_hdri else 1.0

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Compatibility 下天空辐照度几乎不起作用，改用直接环境光颜色保证无点光源区域也有亮度。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if compat else Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(th.ambient_energy) * (0.55 if compat else 1.0)
	env.ambient_light_color = Color(th.horizon).lightened(0.15) if compat else Color(th.horizon)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(th.exposure) * hdri_exp * (1.0 if compat else 1.0)
	env.adjustment_enabled = true
	env.adjustment_saturation = float(th.saturation)
	env.adjustment_contrast = float(th.contrast)

	# Distance fog (atmospheric depth)——降低雾强度：用户反馈雾效过重把远景全糊
	env.fog_enabled = true
	env.fog_light_color = Color(th.fog)
	env.fog_light_energy = 0.5
	env.fog_density = float(th.fog_density)
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.2

	# Volumetric fog (light shafts / dust)
	env.volumetric_fog_enabled = float(th.volumetric) > 0.0
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = float(th.volumetric)
		env.volumetric_fog_albedo = Color(th.fog)
		env.volumetric_fog_emission = Color(th.sun_color) * 0.03
		env.volumetric_fog_emission_energy = 0.35
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_length = 64.0
		env.volumetric_fog_detail_spread = 2.5
		env.volumetric_fog_ambient_inject = 0.35
		env.volumetric_fog_sky_affect = 0.6

	# SDFGI (voxel GI for interiors + outdoor bounce)
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.35
	env.sdfgi_max_distance = 96.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.35
	env.sdfgi_energy = 1.0
	env.sdfgi_normal_bias = 0.9
	env.sdfgi_probe_bias = 1.0

	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.3
	env.ssao_power = 1.2

	# SSIL 与 SDFGI 功能重叠（都做间接光照）：SDFGI 4 级联已覆盖，
	# 关闭 SSIL 省掉一次全屏间接光采样（Web 单线程 + 桌面 GPU 都受益）
	env.ssil_enabled = false

	# SSR (screen-space reflections)
	env.ssr_enabled = true
	env.ssr_max_steps = 16
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.05

	# Glow / bloom
	# Web（Compatibility）下 glow 多级 blur 是显著开销：降级为单级弱强度
	env.glow_enabled = true
	env.glow_intensity = float(th.glow_intensity) * (0.55 if compat else 1.0)
	env.glow_strength = float(th.glow_strength) * (0.5 if compat else 1.0)
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 1.6
	if compat:
		# 只用单级 glow，跳过 7 级金字塔 blur
		for i in 7:
			env.set_glow_level(i, 1.0 if i == 1 else 0.0)
	else:
		for i in 7:
			env.set_glow_level(i, 0.55 if i in [1, 2, 3] else (0.18 if i in [4, 5] else 0.0))
	env.glow_normalized = true

	# Vignette is handled by a custom screen shader in post_fx.gd (removed from env in 4.7)

	we = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# ---------- Sun ----------
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var sd := Vector3(th.sun_dir).normalized()
	sun.rotation = Vector3(asin(sd.y), atan2(sd.x, sd.z), 0.0)
	sun.light_color = Color(th.sun_color)
	sun.light_energy = float(th.sun_energy) * (0.55 if hdri_exp < 1.0 else 1.0) * (1.25 if compat else 1.0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	# Web（Compatibility）下阴影渲染开销最大：降为 2 split + 缩短投影距离
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if compat else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0 if compat else 160.0
	sun.directional_shadow_pancake_size = 8.0
	sun.directional_shadow_fade_start = 0.8 if compat else 0.7
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	# Shadow tint (slight blue bounce)
	var sb := DirectionalLight3D.new()
	sb.name = "ShadowTint"
	sb.rotation = sun.rotation + Vector3(PI * 0.18, PI * 0.55, 0.0)
	sb.light_color = Color(th.shadow_color)
	sb.light_energy = 0.12 * (1.5 if compat else 1.0)
	sb.shadow_enabled = false
	add_child(sb)

	# ---------- Fill ----------
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = sun.rotation + Vector3(PI * 0.24, PI * 0.85, 0.0)
	fill.light_color = Color(th.fill_color)
	fill.light_energy = float(th.fill_energy) * (1.2 if compat else 1.0)
	fill.shadow_enabled = false
	add_child(fill)
