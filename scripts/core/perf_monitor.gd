# 性能监控 + 自适应画质。
# - 采集帧时间分布（avg/p95/max）、绘制调用、内存、网络 RTT
# - 依据目标帧率动态调整 3D 分辨率（带迟滞，避免来回抖动）
# - 可在 HUD 上叠加实时曲线（F3）
extends Node

signal spike(frame_ms: float)
signal rescaled(scale: float, fps: float)

const WINDOW: int = 120           # 采样窗口（帧）
const SPIKE_MS: float = 32.0      # 超过即视为一次尖峰
const HYSTERESIS: float = 3.0     # 目标帧率的容差

var enabled: bool = true
var auto_scale: bool = true
var target_fps: int = 60
var show_overlay: bool = false

var frame_times: PackedFloat32Array = PackedFloat32Array()
var avg_ms: float = 16.6
var p95_ms: float = 16.6
var max_ms: float = 16.6
var fps: float = 60.0

var _acc: float = 0.0
var _frames: int = 0
var _scale_timer: float = 0.0
var _scale_cooldown: float = 0.0
var _last_scale: float = 1.0
var _spikes: int = 0
var _overlay: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	frame_times.resize(WINDOW)
	for i in WINDOW:
		frame_times[i] = 16.6
	if Platform.is_mobile or Platform.is_web:
		target_fps = 60 if Platform.is_mobile else 45
	else:
		target_fps = int(clampf(Platform.refresh_hz, 30.0, 165.0))


func _process(delta: float) -> void:
	if not enabled:
		return
	var ms: float = delta * 1000.0
	frame_times[_frames % WINDOW] = ms
	_frames += 1
	_acc += ms
	if ms > SPIKE_MS:
		_spikes += 1
		spike.emit(ms)
	if _frames % 10 != 0:
		return
	# 每 10 帧刷新一次统计（避免每帧排序）
	var arr: Array = []
	for i in WINDOW:
		arr.append(frame_times[i])
	arr.sort()
	avg_ms = _acc / float(maxi(1, mini(_frames, WINDOW)))
	_acc = 0.0
	p95_ms = float(arr[int(WINDOW * 0.95)])
	max_ms = float(arr[WINDOW - 1])
	fps = 1000.0 / maxf(0.001, avg_ms)
	if auto_scale and Settings.get_bool("graphics", "auto_scale"):
		_adapt(delta)


func _adapt(delta: float) -> void:
	_scale_cooldown = maxf(0.0, _scale_cooldown - delta)
	_scale_timer += delta
	if _scale_timer < 1.0 or _scale_cooldown > 0.0:
		return
	_scale_timer = 0.0
	var cur: float = Platform.render_scale
	var lo: float = 0.55 if (Platform.is_mobile or Platform.is_web) else 0.6
	var hi: float = 1.0
	var target: float = float(target_fps)
	if fps < target - HYSTERESIS * 2.5 and cur > lo:
		cur = maxf(lo, cur - 0.08)
	elif fps > target - HYSTERESIS and p95_ms < (1000.0 / target) * 1.15 and cur < hi:
		cur = minf(hi, cur + 0.04)
	if absf(cur - _last_scale) < 0.001:
		return
	_last_scale = cur
	Platform.set_render_scale(cur)
	_scale_cooldown = 1.5
	rescaled.emit(cur, fps)


## 网络 RTT 变化时由 NetManager 调用，必要时降低特效等级
func on_network_rtt(ms: int) -> void:
	if ms > 220 and Platform.tier > Platform.Tier.LOW:
		pass  # 预留：高延迟时关闭非必要特效


func stats() -> Dictionary:
	return {
		"fps": snappedf(fps, 0.1),
		"avg_ms": snappedf(avg_ms, 0.01),
		"p95_ms": snappedf(p95_ms, 0.01),
		"max_ms": snappedf(max_ms, 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"mem_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)),
		"scale": snappedf(Platform.render_scale, 0.01),
		"spikes": _spikes,
	}

# ---------------- 调试叠加层 ----------------

func toggle_overlay() -> void:
	show_overlay = not show_overlay
	if show_overlay and _overlay == null:
		_build_overlay()
	if _overlay != null:
		_overlay.visible = show_overlay


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "PerfOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_overlay.position = Vector2(12, 10)
	var lbl := Label.new()
	lbl.name = "Text"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.text = ""
	_overlay.add_child(lbl)
	var g: Graph = Graph.new()
	g.name = "Graph"
	g.position = Vector2(0, 96)
	g.custom_minimum_size = Vector2(240, 48)
	g.size = Vector2(240, 48)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(g)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PerfLayer"
	layer.layer = 128
	layer.add_child(_overlay)
	add_child(layer)
	_overlay.visible = show_overlay


func _notification(what: int) -> void:
	if what == NOTIFICATION_PROCESS and show_overlay and _overlay != null:
		var s: Dictionary = stats()
		var lbl: Label = _overlay.get_node_or_null("Text")
		if lbl != null:
			lbl.text = "%.0f FPS  avg %.1fms  p95 %.1fms  max %.1fms\nDC %d  OBJ %d  MEM %dMB  SCALE %.2f" % [
				s.fps, s.avg_ms, s.p95_ms, s.max_ms, s.draw_calls, s.objects, s.mem_mb, s.scale,
			]
		var g: Graph = _overlay.get_node_or_null("Graph")
		if g != null:
			g.frame_times = frame_times
			g.queue_redraw()


class Graph extends Control:
	var frame_times: PackedFloat32Array = PackedFloat32Array()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))
		# 16.6ms 基准线
		var y60: float = h - (16.6 / 40.0) * h
		draw_line(Vector2(0, y60), Vector2(w, y60), Color(0.3, 0.9, 0.5, 0.5), 1.0)
		var n: int = frame_times.size()
		if n < 2:
			return
		var prev := Vector2(0, h)
		for i in n:
			var v: float = clampf(frame_times[i] / 40.0, 0.0, 1.0)
			var p := Vector2(w * float(i) / float(n - 1), h - v * h)
			var col: Color = Color(0.4, 1.0, 0.5) if frame_times[i] < 20.0 else (Color(1.0, 0.85, 0.3) if frame_times[i] < 30.0 else Color(1.0, 0.35, 0.3))
			draw_line(prev, p, col, 1.5)
			prev = p
