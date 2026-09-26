class_name DebugOverlay
extends CanvasLayer

# 诊断叠层（F8 开关，默认隐藏，仅用于排查 Web/音频/性能问题）。
# 显示：帧率、内存、音频播放模式（Sample/Stream）、总线路由、实际输出的 RMS 电平。

const REFRESH: float = 0.25

var _game: Node = null
var _panel: PanelContainer
var _label: Label
var _capture: AudioEffectCapture = null
var _acc: float = 0.0
var _peak: float = 0.0
var _frames: int = 0
var _timer: float = 0.0
var _lines: PackedStringArray = PackedStringArray()
var _bgm_pos: float = 0.0
var _bgm_pos_rate: float = 0.0


func setup(game: Node) -> void:
	_game = game


func _ready() -> void:
	layer = 128
	visible = false
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.modulate = Color(1, 1, 1, 0.92)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.82)
	style.border_color = Color(1.0, 0.55, 0.15, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_panel.add_child(_label)
	add_child(_panel)


func _set_capture(enable: bool) -> void:
	# 只在叠层可见时挂 AudioEffectCapture，避免正式游玩时多一份总线拷贝开销
	if enable:
		if _capture == null:
			_capture = AudioEffectCapture.new()
			_capture.buffer_length = 2.0
			AudioServer.add_bus_effect(0, _capture)
	elif _capture != null:
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
		_capture = null


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_set_capture(visible)
	_drain_capture()
	print("[DebugOverlay] ", "ON" if visible else "OFF")


# 取走 Master 总线上的采样，算出 RMS/峰值（用于确认音频真的在出声）
func _drain_capture() -> void:
	if _capture == null:
		return
	var available: int = _capture.get_frames_available()
	if available <= 0:
		return
	var buf: PackedVector2Array = _capture.get_buffer(available)
	for f in buf:
		var v: float = maxf(absf(f.x), absf(f.y))
		_acc += v * v
		_peak = maxf(_peak, v)
	_frames += buf.size()


func _process(delta: float) -> void:
	_drain_capture()
	if not visible:
		return
	_timer += delta
	if _timer < REFRESH:
		return
	var elapsed: float = _timer
	_timer = 0.0
	var rms: float = sqrt(_acc / float(maxi(_frames, 1)))
	_lines = _build_lines(rms, elapsed)
	_acc = 0.0
	_frames = 0
	_peak = 0.0
	_label.text = "\n".join(_lines)


func _fmt_db(v: float) -> String:
	return "%.1f dB" % linear_to_db(maxf(v, 0.000001))


func _build_lines(rms: float, elapsed: float) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var mem: float = float(OS.get_static_memory_usage()) / 1048576.0
	out.append("POLYFORGE DEBUG  (F8 关闭)")
	out.append("FPS %.0f  帧 %.1f ms  静态内存 %.0f MB  Web=%s" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		mem, str(OS.has_feature("web"))])
	out.append("3D 渲染分辨率缩放 %.2f  视口 %dx%d" % [
		get_viewport().scaling_3d_scale,
		int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)])
	out.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	out.append("总线数 %d  Master 音量 %s  BGM 音量 %s" % [
		AudioServer.get_bus_count(),
		_fmt_db(db_to_linear(AudioServer.get_bus_volume_db(0))),
		_fmt_db(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM")))) if AudioServer.get_bus_index("BGM") >= 0 else "无 BGM 总线"])
	out.append("输出电平 RMS %s  峰值 %s" % [_fmt_db(rms), _fmt_db(_peak)])
	out.append("音频驱动延迟 %.0f ms  混音率 %d Hz" % [
		AudioServer.get_output_latency() * 1000.0, int(AudioServer.get_mix_rate())])

	var bgm: Node = _game.get("_bgm") if _game != null else null
	if bgm != null:
		var player: AudioStreamPlayer = bgm.get("_player")
		var song: String = str(bgm.call("current_song_path"))
		var stream: AudioStream = player.stream if player != null else null
		var registered: bool = false
		if stream != null:
			registered = AudioServer.is_stream_registered_as_sample(stream)
		out.append("BGM %s  开关=%s  播放中=%s  时长 %.0fs" % [
			song.get_file(), str(bgm.call("is_enabled")), str(bgm.call("is_playing")),
			stream.get_length() if stream != null else 0.0])
		out.append("    播放器模式=%s  sample 已注册=%s  音量 %s" % [
			["默认", "Stream", "Sample"][player.playback_type] if player != null else "?",
			str(registered), _fmt_db(db_to_linear(player.volume_db)) if player != null else "-"])
		# Sample 模式下，播放位置由浏览器的 Web Audio 节点推进：
		# 位置在往前走 == 浏览器真的在播放这段音频（上下文未挂起、缓冲在走）
		if player != null and bgm.call("is_playing"):
			var pos: float = player.get_playback_position()
			_bgm_pos_rate = (pos - _bgm_pos) / maxf(elapsed, 0.001)
			_bgm_pos = pos
		out.append("    播放位置 %.2fs  推进速度 %.2fx 实时" % [_bgm_pos, _bgm_pos_rate])

	var sfx: Node = _game.get("_sfx") if _game != null else null
	if sfx != null:
		var cache: Dictionary = sfx.get("_cache")
		var samples_registered: int = 0
		var probe_stream: AudioStream = null
		for key in cache:
			var st: AudioStream = cache[key]
			if st == null:
				continue
			if probe_stream == null:
				probe_stream = st
			if AudioServer.is_stream_registered_as_sample(st):
				samples_registered += 1
		var players: Array = sfx.get("_players")
		var playing: int = 0
		var sfx_pos: String = ""
		for p in players:
			var ap := p as AudioStreamPlayer
			if ap.playing:
				playing += 1
				if sfx_pos == "":
					sfx_pos = "%.2fs" % ap.get_playback_position()
		out.append("SFX 缓存 %d 个  sample 已注册 %d 个  播放中 %d/%d  累计播放 %d 次" % [
			cache.size(), samples_registered, playing, players.size(), int(sfx.get("plays_total"))])
		if playing > 0:
			out.append("    最近一个音效播放位置 %s" % sfx_pos)
		if probe_stream != null:
			out.append("    sample 模式生效=%s  缓冲 %.2fs" % [
				str(AudioServer.is_stream_registered_as_sample(probe_stream)), probe_stream.get_length()])
	return out
