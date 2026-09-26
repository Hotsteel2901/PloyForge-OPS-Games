class_name Bgm
extends Node

# BGM 引擎：播放预渲染的 OGG 音乐（用 GeneralUser GS 音色库离线渲染，替代实时 MIDI 合成）。
# 优点：零 CPU 开销（Web 不再卡顿）、音质统一、无音色库依赖。
# 播放列表第一首为 ObsidianCircuit.ogg，其余三首轮流循环。

const VOLUME: float = 0.30
const BUS_NAME: String = "BGM"

var _playlist: Array = [
	"res://assets/bgm/ObsidianCircuit.ogg",
	"res://assets/bgm/ChromeDistrict.ogg",
	"res://assets/bgm/NeonVault.ogg",
	"res://assets/bgm/ShatterCore.ogg",
]
var _song_index: int = 0
var _enabled: bool = true
var _playing: bool = false

var _player: AudioStreamPlayer
var _bus_index: int = -1
var _fade_gain: float = 1.0
var _fade_target: float = 1.0
var _fade_step: float = 0.0
var _song_title: String = ""


func _ready() -> void:
	_setup_bus()
	_setup_player()
	# 不自动播放：Web 浏览器 autoplay 策略要求用户手势后才能出声，
	# 由 game.gd 在第一次输入事件时调用 start() 解锁（桌面同样适用）


# 用户首次输入后调用：解锁音频上下文并开始播放
func start() -> void:
	if _enabled and not _playing and _player != null:
		_start_playback()


func _setup_bus() -> void:
	for i in range(AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == BUS_NAME:
			_bus_index = i
			AudioServer.set_bus_volume_db(i, linear_to_db(VOLUME))
			return
	AudioServer.add_bus()
	_bus_index = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(_bus_index, BUS_NAME)
	AudioServer.set_bus_send(_bus_index, "Master")
	AudioServer.set_bus_volume_db(_bus_index, linear_to_db(VOLUME))


func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = BUS_NAME
	# Web：BGM 强制走 Stream（引擎混音）而不是默认的 Sample。
	# Sample 模式会把整首歌一次性解码成 PCM 交给 Web Audio：174 秒立体声约 66MB/首，
	# 且首次播放会同步阻塞主线程（低配机可达数秒），多首之后内存持续累积。
	# Stream 模式按需解码，内存恒定，配合 150ms 输出缓冲足够抗主线程抖动。
	if OS.has_feature("web"):
		_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_player.finished.connect(_on_song_finished)


# ---------- 公开 API ----------
func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if enabled:
		_start_playback()
	else:
		_stop_playback()


func set_volume_linear(vol: float) -> void:
	# vol 是主音量的 0~1 比例；以 VOLUME 为最大基准缩放，避免把 BGM 总线音量
	# 覆盖成 0dB（那样音乐会比预期响 3 倍多、盖过音效）。
	if _bus_index >= 0:
		AudioServer.set_bus_volume_db(_bus_index, linear_to_db(clampf(vol, 0.0, 1.0) * VOLUME))


func is_enabled() -> bool:
	return _enabled


func is_playing() -> bool:
	return _playing


func current_song_path() -> String:
	if _song_index < 0 or _song_index >= _playlist.size():
		return ""
	return _playlist[_song_index]


func current_song_name() -> String:
	return _song_title


# ---------- 播放控制 ----------
func _start_playback() -> void:
	# 可能被 call_deferred 延迟到帧末执行，需再次检查开关：启动时音乐可能已被
	# 设置面板/M键关闭（_enabled=false），否则会在"关闭"状态下依然开播。
	if not _enabled or _playing or _player == null:
		return
	var t0: int = Time.get_ticks_msec()
	_load_song(_playlist[_song_index])
	_player.play()
	_playing = true
	_fade_gain = 0.0
	_fade_target = 1.0
	_fade_step = 1.0 / (0.5 * 60.0)  # 0.5s 淡入（按帧推进）
	# 诊断：Web 上若走 Sample 模式，play() 内部会把整首歌解码成 PCM，可能卡住主线程
	var st: AudioStream = _player.stream
	var dt: int = Time.get_ticks_msec() - t0
	if st != null and AudioServer.is_stream_registered_as_sample(st):
		print("[Bgm] sample 模式启动（整曲解码）耗时 %d ms，时长 %.0fs" % [dt, st.get_length()])
	else:
		print("[Bgm] stream 模式启动耗时 %d ms" % dt)


func _stop_playback() -> void:
	if not _playing:
		return
	# 关闭音乐立即真正停止（Web 上依赖淡出缓冲推进可能关不掉）
	_player.stop()
	_playing = false
	_fade_gain = 0.0
	_fade_target = 0.0


func _on_song_finished() -> void:
	if not _enabled:
		_playing = false
		return
	# 下一首循环
	_song_index = (_song_index + 1) % _playlist.size()
	_load_song(_playlist[_song_index])
	_player.play()


func _process(delta: float) -> void:
	if not _playing or _player == null:
		return
	# 淡入/淡出
	if _fade_gain < _fade_target:
		_fade_gain = minf(_fade_target, _fade_gain + _fade_step * delta * 60.0)
	elif _fade_gain > _fade_target:
		_fade_gain = maxf(_fade_target, _fade_gain - _fade_step * delta * 60.0)
	_player.volume_db = linear_to_db(_fade_gain * VOLUME)
	if _fade_gain <= 0.0 and _fade_target <= 0.0:
		_player.stop()
		_playing = false


func _load_song(path: String) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		push_error("BGM: 无法加载 %s" % path)
		_playing = false
		return
	_player.stream = stream
	_song_title = path.get_file().get_basename()
