# Crosshair: 4 种样式 / 6 种颜色，随散布动态张开。
# 用 _draw 直接画（比一堆 ColorRect 更省节点，也方便加圆环/三角样式）。
class_name Crosshair
extends Control

const COLORS: Array = [
	Color(0.0, 0.9, 1.0, 1.0),
	Color(0.35, 1.0, 0.45, 1.0),
	Color(1.0, 0.28, 0.22, 1.0),
	Color(1.0, 0.88, 0.25, 1.0),
	Color(1.0, 1.0, 1.0, 1.0),
	Color(1.0, 0.35, 1.0, 1.0),
]
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.85)

var base_gap: float = 8.0
var max_spread_gap: float = 30.0
var spread01: float = 0.0
var ads: bool = false
var flash_t: float = 0.0
var gap: float = 8.0
var style: int = 0
var color: Color = Color(0.0, 0.9, 1.0, 1.0)

const SEG_LEN: float = 9.0
const SEG_W: float = 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	apply_settings()
	set_process(true)


func apply_settings() -> void:
	style = Settings.get_int("gameplay", "crosshair_style") if Settings != null else 0
	var idx: int = Settings.get_int("gameplay", "crosshair_color") if Settings != null else 0
	color = COLORS[clampi(idx, 0, COLORS.size() - 1)]
	# 色盲模式：红/绿色盲用高对比的黄色
	if Settings != null and Settings.get_int("accessibility", "colorblind") > 0:
		color = Color(1.0, 0.95, 0.2, 1.0)
	queue_redraw()


func set_spread(s: float, a: bool) -> void:
	spread01 = clampf(s, 0.0, 1.0)
	ads = a


func flash() -> void:
	flash_t = 0.12


func _process(delta: float) -> void:
	var target: float = base_gap * (0.45 if ads else 1.0) + spread01 * max_spread_gap
	gap = lerpf(gap, target, 0.25)
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
	queue_redraw()


func _draw() -> void:
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var c: Color = Color(1.0, 0.35, 0.25, 1.0) if flash_t > 0.0 else color
	var g: float = gap

	if ads:
		# 开镜：只留 2px 中心点
		draw_circle(Vector2(cx, cy), 2.4, OUTLINE)
		draw_circle(Vector2(cx, cy), 1.3, Color(1.0, 0.95, 0.85, 0.95))
		return

	match style:
		1:  # 点
			draw_circle(Vector2(cx, cy), 2.6, OUTLINE)
			draw_circle(Vector2(cx, cy), 1.5, c)
		2:  # 圆环 + 点
			draw_arc(Vector2(cx, cy), g + SEG_LEN * 0.45, 0.0, TAU, 48, OUTLINE, SEG_W + 2.0, true)
			draw_arc(Vector2(cx, cy), g + SEG_LEN * 0.45, 0.0, TAU, 48, c, SEG_W, true)
			draw_circle(Vector2(cx, cy), 1.8, c)
		3:  # 三角
			var r: float = g + SEG_LEN
			var pts := PackedVector2Array([
				Vector2(cx, cy - r),
				Vector2(cx + r * 0.866, cy + r * 0.5),
				Vector2(cx - r * 0.866, cy + r * 0.5),
				Vector2(cx, cy - r),
			])
			draw_polyline(pts, OUTLINE, SEG_W + 2.0, true)
			draw_polyline(pts, c, SEG_W, true)
			draw_circle(Vector2(cx, cy), 1.8, c)
		_:  # 十字
			_seg(cx + g, cy, SEG_LEN, SEG_W, c)
			_seg(cx - g - SEG_LEN, cy, SEG_LEN, SEG_W, c)
			_seg(cx, cy + g, SEG_W, SEG_LEN, c)
			_seg(cx, cy - g - SEG_LEN, SEG_W, SEG_LEN, c)
			draw_circle(Vector2(cx, cy), 1.6, c)


func _seg(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x - 1.0, y - 1.0, w + 2.0, h + 2.0), OUTLINE, true)
	draw_rect(Rect2(x, y, w, h), c, true)
