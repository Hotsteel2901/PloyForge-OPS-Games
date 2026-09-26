extends SceneTree

# 诊断探针：打印音频相关项目设置的真实注册信息（提示字符串/默认值/当前值），
# 以及当前平台的播放模式。仅用于调试，不属于游戏运行路径。
func _initialize() -> void:
	print("[probe] godot=", Engine.get_version_info().string, " web=", OS.has_feature("web"))
	for prop in ProjectSettings.get_property_list():
		var n: String = str(prop.get("name", ""))
		if n.contains("playback_type") or n.begins_with("audio/"):
			print("[setting] %s | hint=%s | hint_string=%s | default=%s | current=%s" % [
				n, prop.get("hint", -1), prop.get("hint_string", ""),
				ProjectSettings.property_get_revert(n), ProjectSettings.get_setting(n)])
	for m in ["get_playback_type", "get_default_playback_type"]:
		if AudioServer.has_method(m):
			print("[runtime] %s=" % m, AudioServer.call(m))
	print("[runtime] mix_rate=", AudioServer.get_mix_rate(), " buses=", AudioServer.get_bus_count())
	for path in [
		"res://assets/bgm/ObsidianCircuit.ogg",
		"res://assets/sfx/footsteps/Fantozzi-StoneL1.wav",
	]:
		var s: AudioStream = load(path)
		print("[stream] %s class=%s len=%.2fs can_be_sampled=%s meta=%s" % [
			path.get_file(), s.get_class(), s.get_length(), s.can_be_sampled(), s.is_meta_stream()])
	# 运行时合成的 AudioStreamWAV 是否可被 sample 化（Web Sample 模式的关键判定）
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(2205 * 2)
	wav.data = bytes
	print("[stream] runtime_wav can_be_sampled=", wav.can_be_sampled(), " len=%.3fs" % wav.get_length())

	# 渲染相关设置的真实名称/默认值
	print("--- 渲染设置（名称 | hint_string | default | current） ---")
	for prop in ProjectSettings.get_property_list():
		var n: String = str(prop.get("name", ""))
		if n.begins_with("rendering/") or n.contains("shadow") or n.contains("msaa") \
				or n.contains("anisotropic") or n.contains("scaling") or n.contains("driver"):
			print("  %s | %s | %s | %s" % [n, prop.get("hint_string", ""),
				ProjectSettings.property_get_revert(n), ProjectSettings.get_setting(n)])

	# project.godot 中引擎不认识的键（历史遗留的“注释式”垃圾键）
	print("--- project.godot 中的未知键 ---")
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	var section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if line == "" or line.begins_with(";") or not line.contains("="):
			continue
		var key := line.split("=")[0].strip_edges()
		var full := (section + "/" + key) if section != "" else key
		if not ProjectSettings.has_setting(full) and not ProjectSettings.has_setting(key):
			print("  UNKNOWN: %s" % full)

	quit(0)
