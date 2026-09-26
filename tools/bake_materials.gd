# 烘焙程序化材质为 PNG（tools）：生成后需重新导入（Godot --import），
# 运行时 MaterialLib 会优先加载烘焙纹理（mipmap + VRAM 压缩，零生成开销）。
extends SceneTree

func _init() -> void:
	var out_dir := "res://assets/gen/mat"
	var err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	print("mkdir err=", err)
	var saved: Dictionary = MaterialLib.bake_materials(out_dir)
	print("baked materials: ", saved.size())
	var total_bytes: int = 0
	for id in saved:
		var paths: Array = saved[id]
		var sum: int = 0
		for p in paths:
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				sum += f.get_length()
		total_bytes += sum
		print("  ", id, " files=", paths.size(), " bytes=", sum)
	print("total bytes=", total_bytes)
	quit()
