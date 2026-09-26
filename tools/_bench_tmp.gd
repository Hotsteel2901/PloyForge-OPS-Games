extends SceneTree

func _initialize() -> void:
	var log := FileAccess.open("res://tools/_bench_tmp.txt", FileAccess.WRITE)
	if log == null:
		quit(1)
		return
	log.store_line("BENCH START")
	var t0 := Time.get_ticks_msec()
	var n := FastNoiseLite.new()
	n.seed = 42
	n.frequency = 0.02
	n.fractal_octaves = 4
	var img := n.get_image(1024, 1024, true)
	log.store_line("get_image 1024 seamless: " + str(Time.get_ticks_msec() - t0) + " ms")
	var data: PackedByteArray = img.get_data()
	log.store_line("data size: " + str(data.size()))
	t0 = Time.get_ticks_msec()
	var pb := PackedByteArray()
	pb.resize(1024 * 1024 * 3)
	for i in 1024 * 1024:
		var v: int = data[i]
		var g: int = 255 - v
		var r: float = float(v) * 0.5 + float(g) * 0.3
		pb[i * 3] = int(r)
		pb[i * 3 + 1] = v >> 1
		pb[i * 3 + 2] = g
	log.store_line("packed loop 1M x3 stores: " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var img2 := Image.create_from_data(1024, 1024, false, Image.FORMAT_RGB8, pb)
	log.store_line("create_from_data: " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var img3: Image = img2.duplicate()
	img3.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	log.store_line("resize in-place 1024->512: " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var tex := ImageTexture.create_from_image(img3)
	log.store_line("ImageTexture create: " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = tex
	sm.normal_texture = tex
	sm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	sm.transmission_enabled = true
	sm.transmission = 1.0
	log.store_line("material wiring: " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var img5 := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512:
			var c: Color = img3.get_pixel(x, y)
			img5.set_pixel(x, y, c)
	log.store_line("get+set 512 loop (262K): " + str(Time.get_ticks_msec() - t0) + " ms")
	t0 = Time.get_ticks_msec()
	var pbs := PackedByteArray()
	pbs.resize(512 * 512 * 4)
	var pby: PackedByteArray = img3.get_data()
	for y in 512:
		var o: int = y * 512
		for x in 512:
			var v: int = pby[o * 3 + x * 3]
			var off: int = (o + x) * 4
			pbs[off] = v
			pbs[off + 1] = v >> 1
			pbs[off + 2] = 255 - v
			pbs[off + 3] = 255
	log.store_line("packed byte loop 512 (262K x4): " + str(Time.get_ticks_msec() - t0) + " ms")
	log.store_line("DONE")
	log.close()
	quit()
