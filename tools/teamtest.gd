extends Node

func _ready() -> void:
	add_child(GameEnvironment.create({"zenith": Color("6a85a8"), "horizon": Color("c9d2db"), "ground": Color("6a6a6a"), "fog": Color("b9c3cc"), "fog_density": 0.002, "sun_dir": Vector3(0.3, 0.5, -0.8), "sun_color": Color(1, 1, 1), "sun_energy": 1.5, "ambient_energy": 1.0, "use_hdri": false, "volumetric": 0.0, "cloud_coverage": 0.0}))
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 1.6, 6)
	cam.fov = 50
	add_child(cam)
	var spots := [
		{"team": 1, "zombie": false, "x": -1.4, "name": "CT"},
		{"team": 2, "zombie": false, "x": 0.0, "name": "T"},
		{"team": 2, "zombie": true, "x": 1.4, "name": "ZOMBIE"},
	]
	for s in spots:
		var ch := CharacterFactory.build(s.team, s.zombie)
		ch.position = Vector3(s.x, 0, 0)
		ch.rotation.y = 0.0
		ch.set_meta("name", s.name)
		add_child(ch)
	await get_tree().create_timer(0.6).timeout
	var m_ct: StandardMaterial3D = MaterialLib.get_mat("cloth_ct")
	var m_t: StandardMaterial3D = MaterialLib.get_mat("cloth_t")
	print("[MAT] cloth_ct albedo=", m_ct.albedo_texture.get_image().get_pixel(256, 256).to_html(), " default=", m_ct.albedo_color.to_html())
	print("[MAT] cloth_t albedo=", m_t.albedo_texture.get_image().get_pixel(256, 256).to_html(), " default=", m_t.albedo_color.to_html())
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/teamtest.png")
	for s in spots:
		var x: int = 1280 + int(s.x / 4.98 * 1280.0)
		print("[TEAM] ", s.name, " cx=", x)
		for y in [700, 760, 820]:
			var c: Color = img.get_pixel(x, y)
			print("[TEAM] ", s.name, " y=", y, " = ", c.to_html())
	get_tree().quit()
