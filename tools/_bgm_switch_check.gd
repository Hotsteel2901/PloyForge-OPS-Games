extends SceneTree

# 诊断：验证 BGM 切歌路径（播放 → 结束 → 下一首 → 播放）不报错
func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var bgm: Node = main.get_node("Bgm")
	bgm.call("_start_playback")
	await process_frame
	print("[bgm] 首曲=", bgm.call("current_song_name"), " playing=", bgm.call("is_playing"))
	for i in 3:
		bgm.call("_on_song_finished")
		await process_frame
		print("[bgm] 切歌 %d → %s playing=%s" % [
			i + 1, bgm.call("current_song_name"), str(bgm.call("is_playing"))])
	bgm.call("set_enabled", false)
	await process_frame
	print("[bgm] 关闭后 playing=", bgm.call("is_playing"))
	bgm.call("set_enabled", true)
	await process_frame
	print("[bgm] 重新开启 playing=", bgm.call("is_playing"), " song=", bgm.call("current_song_name"))
	quit(0)
