# 全屏后处理：色散 / 胶片颗粒 / 速度模糊 / 亮度 gamma。
# 用 CanvasLayer + BackBufferCopy 采样当前画面，位于 HUD 之下（layer 6），不影响 UI 清晰度。
# 默认整层隐藏：三项强度都为 0 时不产生任何采样开销。
class_name PostFX
extends CanvasLayer

const SHADER_CODE: String = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain_amount : hint_range(0.0, 0.5) = 0.0;
uniform float chroma_amount : hint_range(0.0, 1.0) = 0.0;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float gamma_value : hint_range(0.5, 2.0) = 1.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float r2 = dot(dir, dir);

	// 色散：中心无偏移，边缘最大
	float ca = chroma_amount * 0.0035 * r2;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ca).b;

	// 速度模糊：径向拖影，中心保持清晰
	if (blur_amount > 0.001) {
		vec3 acc = col;
		for (int i = 1; i <= 5; i++) {
			float t = float(i) / 5.0;
			vec2 suv = uv - dir * blur_amount * 0.05 * t * t;
			acc += texture(screen_tex, suv).rgb;
		}
		col = acc / 6.0;
	}

	// 胶片颗粒（随时间抖动）
	float n = hash21(uv * vec2(1920.0, 1080.0) + vec2(TIME * 41.0, TIME * 17.0));
	col += (n - 0.5) * grain_amount * 0.4;

	// 亮度
	if (abs(gamma_value - 1.0) > 0.001) {
		col = pow(max(col, vec3(0.0)), vec3(1.0 / max(gamma_value, 0.4)));
	}

	COLOR = vec4(col, 1.0);
}
"""

var _copy: BackBufferCopy
var _rect: ColorRect
var _mat: ShaderMaterial
var _speed01: float = 0.0
var _active: bool = false


func _ready() -> void:
	layer = 6
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_copy)
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = false
	refresh_from_settings()


func refresh_from_settings() -> void:
	if _mat == null:
		return
	var grain: float = Settings.get_float("graphics", "film_grain")
	var chroma: float = Settings.get_float("graphics", "chromatic")
	var blur: float = Settings.get_float("graphics", "motion_blur")
	var gamma_v: float = Settings.get_float("graphics", "gamma")
	if Settings.get_bool("accessibility", "reduce_motion"):
		blur = 0.0
	_active = grain > 0.001 or chroma > 0.001 or blur > 0.001 or absf(gamma_v - 1.0) > 0.001
	_mat.set_shader_parameter("grain_amount", grain)
	_mat.set_shader_parameter("chroma_amount", chroma)
	_mat.set_shader_parameter("gamma_value", gamma_v)
	_mat.set_shader_parameter("blur_amount", blur * _speed01)
	_rect.visible = _active


## 每帧由 game 传入移动速度归一化值（0=静止，1=冲刺）
func set_speed(speed01: float) -> void:
	_speed01 = clampf(speed01, 0.0, 1.0)
	if not _active or _mat == null:
		return
	var blur: float = Settings.get_float("graphics", "motion_blur")
	if Settings.get_bool("accessibility", "reduce_motion"):
		blur = 0.0
	_mat.set_shader_parameter("blur_amount", blur * _speed01)
