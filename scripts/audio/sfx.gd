class_name Sfx
extends Node

# 程序化音效引擎：全部音效在运行时用 PCM 合成，无外部资源。

const SAMPLE_RATE_DESKTOP: int = 44100
const SAMPLE_RATE_WEB: int = 22050
var SAMPLE_RATE: int = 44100
const PLAYER_COUNT: int = 8
const PEAK: float = 0.8

var _players: Array = []
var _next: int = 0
var _cache: Dictionary = {}
var _ext_shot: Dictionary = {}
var _footstep_paths: Array = []
var plays_total: int = 0  # 累计播放次数（诊断用）


func _ready() -> void:
	AudioServer.set_bus_volume_db(0, 0.0)
	# Web 端降采样：音效合成量减半，配合 BGM 降采样减少卡顿
	if OS.has_feature("web"):
		SAMPLE_RATE = SAMPLE_RATE_WEB
	for i in range(PLAYER_COUNT):
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i
		# 音效显式走 Master 总线，与 BGM 总线完全隔离：关闭背景音乐绝不影响音效
		p.bus = "Master"
		# Web：音效强制走 Sample —— 整段 PCM 注册给浏览器 Web Audio 直接播放，
		# 不参与引擎逐帧混音，掉帧/卡顿不会吞掉音效（Web 上默认也是 Sample，这里写死避免被项目设置改坏）
		if OS.has_feature("web"):
			p.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		add_child(p)
		_players.append(p)
	_scan_footsteps()
	_prewarm()


# 预合成全部程序化音效 + 预加载脚步 wav。
# 开枪/脚步等高发音效若在运行时才首次合成，会与主线程渲染/混音争抢时间，
# 导致首次开枪、首次脚步明显卡顿（Web 为单线程，尤其明显）。
func _prewarm() -> void:
	for name in [
		"shot_rifle", "shot_pistol", "shot_smg", "shot_lmg", "shot_shotgun",
		"shot_sniper", "shot_claw", "shot_melee", "shot_throw", "shot_grenade",
		"reload", "reload_mag_out", "reload_mag_in", "reload_bolt", "footstep",
		"hit", "hit_headshot", "kill", "damage", "explosion", "plant", "defuse",
		"buy", "click", "empty", "throw", "tick", "defuse_beep", "pickup",
		"round_start", "round_end_win", "round_end_lose", "match_end_win",
		"match_end_lose", "zombie", "boost",
	]:
		_get_stream(name)
	for p in _footstep_paths:
		load(p)
	# Web：把预合成好的音效提前注册成 sample（Web Audio 缓冲），
	# 否则每种音效第一次播放时才注册/解码，会造成首枪、首次脚步的卡顿。
	if OS.has_feature("web"):
		for key in _cache:
			_register_sample(_cache[key])
		for p in _footstep_paths:
			_register_sample(load(p))


func _register_sample(stream: AudioStream) -> void:
	if stream == null or not stream.can_be_sampled():
		return
	if AudioServer.is_stream_registered_as_sample(stream):
		return
	AudioServer.register_stream_as_sample(stream)


# ---------- 公开 API ----------
func play_shot(kind: String) -> void:
	var name: String = "shot_" + kind
	var stream: AudioStreamWAV = _get_stream(name)
	if stream == null:
		stream = _get_stream("shot_rifle")
	if stream != null:
		var pitch: float = randf_range(0.95, 1.05) if _ext_shot.has(name) else randf_range(0.96, 1.05)
		_play(stream, 0.0, pitch)


func reload() -> void:
	_play(_get_stream("reload"))


# 精细换弹三步音效：拆弹夹 / 装弹夹 / 上膛
func reload_mag_out() -> void:
	_play(_get_stream("reload_mag_out"))


func reload_mag_in() -> void:
	_play(_get_stream("reload_mag_in"))


func reload_bolt() -> void:
	_play(_get_stream("reload_bolt"))


func footstep() -> void:
	if not _footstep_paths.is_empty():
		var wav := load(_footstep_paths[randi() % _footstep_paths.size()])
		if wav is AudioStreamWAV:
			_play(wav, 0.0, randf_range(0.9, 1.1))
			return
	_play(_get_stream("footstep"), 0.0, randf_range(0.9, 1.1))


func hit(headshot: bool) -> void:
	_play(_get_stream("hit_headshot" if headshot else "hit"))


func kill() -> void:
	_play(_get_stream("kill"))


func damage() -> void:
	_play(_get_stream("damage"))


func explosion() -> void:
	_play(_get_stream("explosion"), 0.0, randf_range(0.95, 1.05))


func plant() -> void:
	_play(_get_stream("plant"))


func defuse() -> void:
	_play(_get_stream("defuse"))


func buy() -> void:
	_play(_get_stream("buy"))


func click() -> void:
	_play(_get_stream("click"))


func empty() -> void:
	_play(_get_stream("empty"))


func throw_sfx() -> void:
	_play(_get_stream("throw"), 0.0, randf_range(0.92, 1.08))


func tick_sfx() -> void:
	_play(_get_stream("tick"))


# CS 风格拆弹滴滴：两声急促的哔（T 侧听到提示）
func defuse_beep(world_pos: Vector3, cam_pos: Vector3) -> void:
	var stream: AudioStreamWAV = _get_stream("defuse_beep")
	if stream != null:
		play_at(stream, world_pos, cam_pos, 45.0)


func pickup() -> void:
	_play(_get_stream("pickup"))


func round_start() -> void:
	_play(_get_stream("round_start"))


func round_end(win: bool) -> void:
	_play(_get_stream("round_end_win" if win else "round_end_lose"))


func match_end(win: bool) -> void:
	_play(_get_stream("match_end_win" if win else "match_end_lose"))


func zombie() -> void:
	_play(_get_stream("zombie"))


func boost() -> void:
	_play(_get_stream("boost"))


# 简易 2D 定位：按距离衰减音量
func play_at(stream: AudioStreamWAV, global_pos: Vector3, cam_pos: Vector3, max_dist: float = 30.0) -> void:
	if stream == null:
		return
	var d: float = global_pos.distance_to(cam_pos)
	if d >= max_dist:
		return
	var v: float = 1.0 - d / max_dist
	_play(stream, linear_to_db(v * v), 1.0)


# ---------- 内部 ----------
func _get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var ext: AudioStreamWAV = _external_stream(name)
	if ext != null:
		_ext_shot[name] = true
		_cache[name] = ext
		return ext
	var samples: PackedFloat32Array = _build(name)
	if samples.is_empty():
		return null
	var stream := _to_stream(samples)
	_cache[name] = stream
	return stream


func _external_stream(name: String) -> AudioStreamWAV:
	var path: String = ""
	match name:
		"shot_rifle":
			path = "res://assets/sfx/gunshots/gunshot.wav"
		"shot_sniper":
			path = "res://assets/sfx/gunshots/sniper.wav"
	if path != "" and ResourceLoader.exists(path):
		var wav := load(path)
		if wav is AudioStreamWAV:
			return wav
	return null


func _scan_footsteps() -> void:
	var dir := DirAccess.open("res://assets/sfx/footsteps")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.to_lower().ends_with(".wav"):
			_footstep_paths.append("res://assets/sfx/footsteps/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	_footstep_paths.sort()


func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak: float = 0.0
	for i in samples.size():
		var a: float = absf(samples[i])
		if a > peak:
			peak = a
	if peak > 0.0 and peak != PEAK:
		var k: float = PEAK / peak
		for i in samples.size():
			samples[i] *= k
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	stream.data = bytes
	return stream


func _play(stream: AudioStreamWAV, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	plays_total += 1
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


# ---------- 合成原语 ----------
func _noise(dur: float, amp: float, decay: float, lp_hz: float = 0.0, hp_hz: float = 0.0) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var lp_alpha: float = 1.0 - exp(-TAU * lp_hz / SAMPLE_RATE) if lp_hz > 0.0 else 0.0
	var hp_alpha: float = 1.0 - exp(-TAU * hp_hz / SAMPLE_RATE) if hp_hz > 0.0 else 0.0
	var lp_state: float = 0.0
	var hp_state: float = 0.0
	var prev_in: float = 0.0
	for i in n:
		var x: float = randf_range(-1.0, 1.0)
		var y: float = x
		if lp_alpha > 0.0:
			lp_state += lp_alpha * (y - lp_state)
			y = lp_state
		if hp_alpha > 0.0:
			hp_state = hp_alpha * (hp_state + y - prev_in)
			y = hp_state
		prev_in = x
		out[i] = y * amp * exp(-decay * float(i) / SAMPLE_RATE)
	return out


func _tone(dur: float, f_start: float, f_end: float, amp: float, shape: String = "sine", decay: float = 4.0) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i in n:
		var f: float = lerpf(f_start, f_end, float(i) / float(n))
		phase += TAU * f / SAMPLE_RATE
		var s: float = 0.0
		match shape:
			"sine":
				s = sin(phase)
			"saw":
				s = 2.0 * (phase / TAU - floor(phase / TAU + 0.5))
			"triangle":
				s = 4.0 * abs(phase / TAU - floor(phase / TAU + 0.5)) - 1.0
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
		out[i] = s * amp * exp(-decay * float(i) / SAMPLE_RATE)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain_a: float = 1.0, gain_b: float = 1.0) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var va: float = a[i] * gain_a if i < a.size() else 0.0
		var vb: float = b[i] * gain_b if i < b.size() else 0.0
		out[i] = va + vb
	return out


func _concat_parts(parts: Array) -> PackedFloat32Array:
	var total: int = 0
	for p in parts:
		total += p.size()
	var out := PackedFloat32Array()
	out.resize(total)
	var off: int = 0
	for p in parts:
		for i in p.size():
			out[off + i] = p[i]
		off += p.size()
	return out


func _silence(dur: float) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	return out


# ---------- 音色设计 ----------
func _build(name: String) -> PackedFloat32Array:
	match name:
		"shot_rifle":
			var crack := _noise(0.012, 0.6, 70.0)
			var body := _noise(0.09, 0.5, 26.0, 850.0)
			var thump := _tone(0.16, 120.0, 55.0, 0.5, "sine", 14.0)
			return _mix(_mix(crack, body), thump)
		"shot_pistol":
			var crack := _noise(0.06, 0.55, 38.0, 1400.0, 300.0)
			var thump := _tone(0.1, 140.0, 70.0, 0.4, "sine", 18.0)
			return _mix(crack, thump)
		"shot_smg":
			var body := _noise(0.055, 0.42, 30.0, 1600.0)
			var thump := _tone(0.09, 130.0, 70.0, 0.32, "sine", 22.0)
			return _mix(body, thump)
		"shot_sniper":
			var crack := _noise(0.1, 0.7, 30.0, 3000.0, 150.0)
			var tail := _tone(0.45, 75.0, 40.0, 0.6, "sine", 6.0)
			return _mix(crack, tail)
		"shot_lmg":
			var crack := _noise(0.014, 0.6, 60.0)
			var body := _noise(0.11, 0.5, 22.0, 750.0)
			var thump := _tone(0.2, 110.0, 50.0, 0.55, "sine", 12.0)
			return _mix(_mix(crack, body), thump)
		"shot_shotgun":
			var boom := _noise(0.14, 0.7, 16.0, 700.0)
			var thump := _tone(0.24, 80.0, 40.0, 0.65, "sine", 10.0)
			return _mix(boom, thump)
		"shot_claw", "shot_melee":
			var swish := _noise(0.18, 0.3, 16.0, 900.0, 300.0)
			var thump := _tone(0.08, 150.0, 90.0, 0.3, "sine", 22.0)
			return _mix(swish, thump)
		"shot_throw", "shot_grenade":
			return _noise(0.24, 0.35, 15.0, 1000.0, 200.0)
		"reload":
			var c1 := _noise(0.022, 0.4, 55.0, 1800.0)
			var c2 := _noise(0.03, 0.5, 45.0, 1200.0)
			var met := _tone(0.035, 900.0, 600.0, 0.28, "square", 70.0)
			return _concat_parts([c1, _silence(0.14), _mix(c2, met)])
		"reload_mag_out":
			# 拆弹夹：咔哒 + 金属滑出
			var click := _noise(0.018, 0.42, 60.0, 1600.0)
			var slide := _noise(0.08, 0.3, 22.0, 900.0)
			return _concat_parts([click, _silence(0.02), slide])
		"reload_mag_in":
			# 装弹夹：短促金属撞击
			var thunk := _noise(0.03, 0.5, 45.0, 700.0)
			var ring := _tone(0.05, 620.0, 480.0, 0.24, "square", 40.0)
			return _mix(thunk, ring)
		"reload_bolt":
			# 上膛：清脆咔嚓
			var rack := _noise(0.03, 0.5, 50.0, 2200.0, 400.0)
			var snap := _noise(0.02, 0.45, 70.0, 1800.0)
			return _concat_parts([rack, _silence(0.03), snap])
		"footstep":
			var thud := _noise(0.06, 0.2, 28.0, 350.0)
			var low := _tone(0.07, 110.0, 60.0, 0.26, "sine", 20.0)
			return _mix(thud, low)
		"hit":
			var tic := _noise(0.035, 0.5, 45.0, 1100.0)
			var pn := _tone(0.03, 500.0, 400.0, 0.22, "triangle", 55.0)
			return _mix(tic, pn)
		"hit_headshot":
			var crack := _noise(0.05, 0.6, 38.0, 2000.0, 400.0)
			var ping := _tone(0.05, 1500.0, 1300.0, 0.3, "triangle", 40.0)
			return _mix(crack, ping)
		"kill":
			var a := _tone(0.09, 660.0, 660.0, 0.35, "square", 6.0)
			var b := _tone(0.14, 440.0, 420.0, 0.38, "square", 7.0)
			return _concat_parts([a, b])
		"damage":
			var thud := _noise(0.05, 0.5, 30.0, 500.0)
			var low := _tone(0.12, 90.0, 50.0, 0.5, "sine", 12.0)
			return _mix(thud, low)
		"explosion":
			var boom := _noise(0.6, 0.75, 5.0, 400.0)
			var crack := _noise(0.25, 0.5, 12.0, 900.0)
			var low := _tone(0.6, 55.0, 30.0, 0.55, "sine", 4.0)
			return _mix(_mix(boom, crack), low)
		"plant":
			var a := _tone(0.09, 880.0, 880.0, 0.38, "sine", 6.0)
			var b := _tone(0.12, 660.0, 620.0, 0.38, "sine", 6.0)
			return _concat_parts([a, _silence(0.05), b])
		"defuse":
			var parts: Array = []
			for f in [660.0, 550.0, 440.0]:
				parts.append(_tone(0.08, f, f, 0.38, "sine", 6.0))
				parts.append(_silence(0.03))
			return _concat_parts(parts)
		"buy":
			var a := _tone(0.08, 660.0, 660.0, 0.35, "sine", 6.0)
			var b := _tone(0.1, 880.0, 880.0, 0.35, "sine", 6.0)
			return _concat_parts([a, b])
		"click":
			return _noise(0.012, 0.5, 60.0)
		"empty":
			var clack := _noise(0.025, 0.45, 50.0, 900.0)
			var tick := _tone(0.04, 700.0, 500.0, 0.28, "square", 70.0)
			return _mix(clack, tick)
		"throw":
			return _noise(0.24, 0.35, 15.0, 1000.0, 200.0)
		"tick":
			return _tone(0.02, 1000.0, 900.0, 0.3, "sine", 40.0)
		"defuse_beep":
			var a := _tone(0.055, 1150.0, 1080.0, 0.32, "sine", 12.0)
			var b := _tone(0.055, 1150.0, 1080.0, 0.32, "sine", 12.0)
			return _concat_parts([a, _silence(0.06), b])
		"pickup":
			var pop := _tone(0.09, 520.0, 760.0, 0.34, "sine", 8.0)
			var blip := _noise(0.03, 0.2, 30.0, 1400.0)
			return _mix(pop, blip)
		"round_start":
			var parts: Array = []
			for f in [523.0, 659.0, 784.0]:
				parts.append(_tone(0.11, f, f, 0.38, "sine", 5.0))
				parts.append(_silence(0.02))
			return _concat_parts(parts)
		"round_end_win":
			var parts: Array = []
			for f in [523.0, 659.0, 784.0, 1047.0]:
				parts.append(_tone(0.12, f, f, 0.4, "sine", 5.0))
				parts.append(_silence(0.03))
			return _concat_parts(parts)
		"round_end_lose":
			var parts: Array = []
			for f in [392.0, 330.0, 262.0]:
				parts.append(_tone(0.16, f, f * 0.98, 0.4, "sine", 5.0))
				parts.append(_silence(0.03))
			return _concat_parts(parts)
		"match_end_win":
			var parts: Array = []
			for f in [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0]:
				parts.append(_tone(0.16, f, f, 0.42, "sine", 5.0))
				parts.append(_silence(0.04))
			return _concat_parts(parts)
		"match_end_lose":
			var parts: Array = []
			for f in [330.0, 294.0, 262.0, 196.0]:
				parts.append(_tone(0.18, f, f * 0.97, 0.42, "sine", 5.0))
				parts.append(_silence(0.04))
			return _concat_parts(parts)
		"zombie":
			var growl := _tone(0.5, 65.0, 42.0, 0.5, "saw", 3.0)
			var nz := _noise(0.4, 0.4, 4.0, 500.0)
			var hz := _tone(0.3, 130.0, 90.0, 0.22, "square", 8.0)
			return _mix(_mix(growl, nz), hz)
		"boost":
			var whoosh := _noise(0.35, 0.4, 8.0, 2000.0, 200.0)
			var rise := _tone(0.35, 200.0, 600.0, 0.28, "sine", 5.0)
			return _mix(whoosh, rise)
	return PackedFloat32Array()
