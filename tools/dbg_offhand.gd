extends SceneTree

func _init() -> void:
	var root: Node3D = ViewmodelFactory.build("k9")
	var off: Node3D = root.get_node_or_null("OffHand")
	print("OffHand node: ", off)
	if off == null:
		print("OFFHAND MISSING!")
		quit()
		return
	print("off pos=", off.position, " rot=", off.rotation, " visible=", off.visible, " children=", off.get_children().size())
	var vm_root: Node3D = Node3D.new()
	vm_root.position = Vector3(0.18, -0.18, -0.35)
	vm_root.add_child(root)
	print("off global: ", off.global_position, " (x=", off.global_position.x, " y=", off.global_position.y, " z=", off.global_position.z, ")")
	print("arm end global: ", vm_root.to_global(root.position + Vector3(-0.26, 0, 0)))
	root.queue_free()
	quit()
