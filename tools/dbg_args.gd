extends SceneTree

func _init() -> void:
	print("user args: ", OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			var ov: Array = a.get_slice("=", 1).split(",")
			print("cam override parsed: ", ov, " size=", ov.size())
	quit()
