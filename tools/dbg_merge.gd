extends SceneTree

const MapDataScript = preload("res://scripts/data/maps.gd")

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	# 直接构造合并桶验证 _flush_merge：3 个盒子 2 种材质 → 应产出 2 个 ArrayMesh
	var mat_a: Material = MaterialLib.solid(Color("aa5533"), 0.0, 0.8)
	var mat_b: Material = MaterialLib.solid(Color("3355aa"), 0.0, 0.8)
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	MapBuilder._merge_buckets = {
		mat_a.get_instance_id(): {"mat": mat_a, "items": [
			{"mesh": box, "xform": Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))},
			{"mesh": box, "xform": Transform3D(Basis.IDENTITY, Vector3(2, 0, 0))},
		]},
		mat_b.get_instance_id(): {"mat": mat_b, "items": [
			{"mesh": box, "xform": Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))},
		]},
	}
	MapBuilder._web_merge = true
	MapBuilder._flush_merge(root)
	var count: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			count += 1
			print("[MERGE] mi mesh=", (n as MeshInstance3D).mesh, " verts=", (n as MeshInstance3D).mesh.get_aabb())
		for c in n.get_children():
			stack.append(c)
	print("[MERGE] merged MeshInstance3D count = ", count)
	root.queue_free()
	quit()
