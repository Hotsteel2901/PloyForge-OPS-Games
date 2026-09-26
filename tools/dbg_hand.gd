extends SceneTree

func _init() -> void:
	var root: Node3D = ViewmodelFactory.build("k9")
	print("root children: ", root.get_children().size())
	var hand: Node3D = root.get_meta("hand", null)
	print("hand meta: ", hand)
	if hand != null:
		print("hand pos=", hand.position, " rot=", hand.rotation, " visible=", hand.visible, " children=", hand.get_children().size())
		for c in hand.get_children():
			print("  ", c.name, " pos=", (c as Node3D).position)
	# 模拟换弹动画结束后手的位置
	var mag: Node3D = root.get_meta("mag", null)
	print("mag: ", mag, " magpos=", mag.position if mag != null else "?")
	root.queue_free()
	quit()
