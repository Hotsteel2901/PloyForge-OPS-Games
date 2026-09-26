extends Node

# 截图验证：k9/pc/pf 在精确校准 offset 下的 ADS 构图是否合理。
# 用法: godot --path . res://tools/_sight_shot.tscn

var _cam: Camera3D
var _vm_root: Node3D

func _ready() -> void:
	var ws := SubViewport.new()
	ws.size = Vector2i(1280, 720)
	ws.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ws)
	_cam = Camera3D.new()
	_cam.current = true
	ws.add_child(_cam)
	_vm_root = Node3D.new()
	_cam.add_child(_vm_root)
	var cfg := {"k9": 0.07, "pc": 0.0955, "pf": 0.0874}
	for wid in cfg:
		_cam.fov = ViewmodelFactory.get_ads_fov(wid)
		var vm: Node3D = ViewmodelFactory.build(wid)
		_vm_root.add_child(vm)
		_vm_root.position = Vector3(0.0, -0.12, -0.3) + Vector3(0, cfg[wid], -0.019)
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = ws.get_texture().get_image()
		var full: String = ProjectSettings.globalize_path("res://shots/ads_" + wid + ".png")
		img.save_png(full)
		print("[SHOT] saved ", full)
		vm.queue_free()
		await get_tree().process_frame
	get_tree().quit()
