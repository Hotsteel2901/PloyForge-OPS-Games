extends SceneTree

func _init() -> void:
	var root: Node3D = CharacterFactory.build(1, false)
	root.add_child(Node3D.new())
	CharacterFactory.animate(root, 1.0 / 30.0, 0.0, false, true, 1.0)
	var sk: Skeleton3D = root.get_meta("skeleton", null)
	var body: Node3D = root.get_meta("body", null)
	var parts: Array = root.get_meta("parts", [])
	print("body transform: ", body.transform)
	for part in parts:
		var mi: MeshInstance3D = part.mi
		if part.pidx >= 0:
			var gp: Transform3D = sk.get_bone_global_pose(part.pidx)
			print("  ", mi.name, " global_pose.origin=", gp.origin, " world=", (body.transform * gp).origin)
	print("skeleton global transform: ", sk.global_transform)
	var ap: AnimationPlayer = root.get_meta("animplayer", null)
	print("animplayer anims: ", ap.get_animation_list())
	root.queue_free()
	quit()
