extends Node

func _ready() -> void:
	var fnl := FastNoiseLite.new()
	fnl.seed = 5
	fnl.noise_type = FastNoiseLite.TYPE_VALUE
	fnl.frequency = 2.0
	var img := fnl.get_image(64, 64)
	print("FNL format: ", img.get_format(), " size: ", img.get_data().size())
	img.convert(Image.FORMAT_RF)
	print("after convert: ", img.get_format(), " size: ", img.get_data().size())
	var m := MaterialLib.get_mat("concrete", 1.0)
	print("mat ok: ", m != null)
	print("albedo: ", MaterialLib.get_albedo("concrete"))
	var t0 := Time.get_ticks_msec()
	for id in ["concrete", "sand", "metal_dark", "wood", "cloth_ct", "glass", "graffiti_wall", "brick"]:
		MaterialLib.get_mat(id, 2.0)
	print("8 mats built in ", Time.get_ticks_msec() - t0, " ms")
	var fnl2 := FastNoiseLite.new()
	fnl2.seed = 3
	fnl2.noise_type = FastNoiseLite.TYPE_VALUE
	fnl2.frequency = 0.012
	fnl2.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl2.fractal_octaves = 4
	var di := fnl2.get_image(256, 256)
	print("decal img format: ", di.get_format(), " size: ", di.get_data().size())
	var sc: Dictionary = {"CT": 0, "T": 1}
	print("str test: " + String(sc.get("CT", 0)))
	var d := MaterialLib.get_decal("stain_dirt")
	print("decal: ", d, " mat: ", MaterialLib.decal_mat("graffiti") != null)
	get_tree().quit()

var fnl2 := FastNoiseLite.new()
