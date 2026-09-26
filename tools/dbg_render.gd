extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := get_root()
	var cam := Camera3D.new()
	cam.fov = 74.0
	cam.near = 0.05
	cam.far = 100.0
	cam.position = Vector3.ZERO
	root.add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 2.5
	root.add_child(sun)
	var env_node := GameEnvironment.create({
		"use_hdri": false,
		"sun_dir": Vector3(0.4, 0.5, -0.7),
		"sun_energy": 2.5,
		"fog_density": 0.0,
		"ambient_energy": 1.0,
		"volumetric": 0.0,
	})
	root.add_child(env_node)
	var vm: Node3D = ViewmodelFactory.build("k9")
	var holder := Node3D.new()
	holder.position = Vector3(0.10, -0.20, -0.38)
	holder.add_child(vm)
	root.add_child(holder)
	# 调试：隐藏枪身，只渲染双手，确认手的位置与形态
	for c in vm.get_children():
		if c.name == "OffHand" or c.name == "Hand":
			continue
		c.visible = false
	await process_frame
	await process_frame
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png("res://shots/hand_test.png")
	print("saved")
	quit()
