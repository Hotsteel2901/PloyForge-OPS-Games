# Crosshair: guaranteed-visible cross built from plain ColorRect children
# (no custom _draw — avoids dynamic-draw issues). Spread gap animates with weapon spread.
class_name Crosshair
extends Control

var base_gap: float = 8.0
var max_spread_gap: float = 30.0
var spread01: float = 0.0
var ads: bool = false
var flash_t: float = 0.0
var gap: float = 8.0

var _segs: Array = []   # [{bg: ColorRect, fg: ColorRect}]
var _dot_bg: ColorRect
var _dot: ColorRect

const SEG_LEN: float = 9.0
const SEG_W: float = 3.0
const COL: Color = Color(0.0, 0.9, 1.0, 1.0)
const OUT: Color = Color(0.0, 0.0, 0.0, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 4 segments (right, left, bottom, top) each with a dark outline layer behind
	for i in 4:
		var bg := ColorRect.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = OUT
		add_child(bg)
		var fg := ColorRect.new()
		fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fg.color = COL
		add_child(fg)
		_segs.append({"bg": bg, "fg": fg})
	_dot_bg = ColorRect.new()
	_dot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot_bg.color = OUT
	add_child(_dot_bg)
	_dot = ColorRect.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.color = COL
	add_child(_dot)


func set_spread(s: float, a: bool) -> void:
	spread01 = clampf(s, 0.0, 1.0)
	ads = a


func flash() -> void:
	flash_t = 0.12


func _process(delta: float) -> void:
	var target: float = base_gap * (0.45 if ads else 1.0) + spread01 * max_spread_gap
	gap = lerpf(gap, target, 0.25)
	if flash_t > 0.0:
		flash_t -= delta
	_update_positions()


func _update_positions() -> void:
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var c: Color = Color(1.0, 0.3, 0.2, 1.0) if flash_t > 0.0 else COL
	var g: float = gap
	# ADS: hide the 4-line cross, keep only a smaller center dot
	for seg in _segs:
		seg.bg.visible = not ads
		seg.fg.visible = not ads
	if ads:
		_dot_bg.position = Vector2(cx - 2.0, cy - 2.0)
		_dot_bg.size = Vector2(4, 4)
		_dot.position = Vector2(cx - 1.0, cy - 1.0)
		_dot.size = Vector2(2, 2)
		_dot.color = Color(1.0, 0.95, 0.85, 0.95)
	else:
		# right
		_place_seg(_segs[0], cx + g, cy, SEG_LEN, SEG_W, c)
		# left
		_place_seg(_segs[1], cx - g - SEG_LEN, cy, SEG_LEN, SEG_W, c)
		# bottom
		_place_seg(_segs[2], cx, cy + g, SEG_W, SEG_LEN, c)
		# top
		_place_seg(_segs[3], cx, cy - g - SEG_LEN, SEG_W, SEG_LEN, c)
		_dot_bg.position = Vector2(cx - 2.5, cy - 2.5)
		_dot_bg.size = Vector2(5, 5)
		_dot.position = Vector2(cx - 1.5, cy - 1.5)
		_dot.size = Vector2(3, 3)
		_dot.color = c


func _place_seg(seg: Dictionary, x: float, y: float, w: float, h: float, c: Color) -> void:
	var fg: ColorRect = seg.fg
	var bg: ColorRect = seg.bg
	fg.position = Vector2(x, y)
	fg.size = Vector2(w, h)
	fg.color = c
	bg.position = Vector2(x - 1.0, y - 1.0)
	bg.size = Vector2(w + 2.0, h + 2.0)
