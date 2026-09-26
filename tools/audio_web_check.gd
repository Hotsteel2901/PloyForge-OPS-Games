# Web 音频静音诊断：检查 OGG 流式标记、BGM/SFX 播放状态。
# 运行: godot --headless --audio-driver Dummy --path . res://tools/audio_web_check.tscn
extends Node

func _ready() -> void:
	print("[cfg] web=%s" % OS.has_feature("web"))
	# 1. OGG stream 属性
	for path in [
		"res://assets/bgm/ObsidianCircuit.ogg",
		"res://assets/bgm/ChromeDistrict.ogg",
		"res://assets/bgm/NeonVault.ogg",
		"res://assets/bgm/ShatterCore.ogg",
	]:
		var s: AudioStream = load(path)
		if s == null:
			print("[ogg] FAIL load:", path)
			continue
		var streaming: bool = false
		if s is AudioStreamOggVorbis:
			streaming = (s as AudioStreamOggVorbis).stream
		print("[ogg] %s type=%s streaming=%s len=%.1fs" % [path.get_file(), s.get_class(), streaming, s.get_length()])
	# 2. 加载 main，检查 BGM/SFX
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var bgm: Node = main.get_node_or_null("Bgm")
	var sfx: Node = main.get_node_or_null("Sfx")
	print("[bgm] enabled=", bgm.call("is_enabled"), " playing=", bgm.call("is_playing"), " song=", bgm.call("current_song_name"))
	# 3. 手动触发 BGM 播放并检查
	bgm.call("_start_playback")
	await get_tree().process_frame
	print("[bgm] after start playing=", bgm.call("is_playing"))
	var bgm_player: AudioStreamPlayer = bgm.get_node_or_null(".")
	for c in bgm.get_children():
		if c is AudioStreamPlayer:
			var p := c as AudioStreamPlayer
			print("[bgm-player] stream=", p.stream.get_class() if p.stream else "null", " playing=", p.playing)
	# 4. 触发 SFX
	sfx.call("explosion")
	sfx.call("play_shot", "rifle")
	await get_tree().process_frame
	var playing_count: int = 0
	for i in sfx.get_child_count():
		var c: Node = sfx.get_child(i)
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
			playing_count += 1
	print("[sfx] players playing=%d/%d" % [playing_count, sfx.get_child_count()])
	get_tree().quit(0)
