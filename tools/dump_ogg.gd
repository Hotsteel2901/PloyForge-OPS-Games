extends SceneTree
func _init() -> void:
	var s: AudioStream = load("res://assets/bgm/ObsidianCircuit.ogg")
	if s == null:
		print("LOAD NULL")
		quit(1)
		return
	print("class: ", s.get_class())
	print("stream len: ", s.get_length())
	for p in s.get_property_list():
		print("prop: ", p.name, " = ", s.get(p.name))
	var player := AudioStreamPlayer.new()
	player.stream = s
	print("player stream ok")
	quit(0)
