extends SceneTree

func _init() -> void:
	var root: Node3D = ViewmodelFactory.build("k9")
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var line: String = n.name
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			var sz: String = "?"
			if mi.mesh is BoxMesh:
				sz = str((mi.mesh as BoxMesh).size)
			line += "  MI pos=" + str(n.position) + " scale=" + str(n.scale) + " size=" + sz
		elif n is Node3D:
			line += "  N pos=" + str((n as Node3D).position) + " visible=" + str((n as Node3D).visible)
		print(line)
		for c in n.get_children():
			stack.append(c)
	root.queue_free()
	quit()
