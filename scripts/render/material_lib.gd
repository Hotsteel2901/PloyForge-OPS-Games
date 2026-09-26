# MaterialLib: procedural PBR material library. Zero external assets.
# All textures generated at runtime (FastNoiseLite + Image), cached statically.
class_name MaterialLib
extends RefCounted

# 256² 纹理：GDScript 逐像素构建开销降 4 倍（Web 单线程敏感），
# 配合 mipmap 后远景质量与 512² 几乎无差（256² 覆盖 2m 网格表面足够）。
const SIZE: int = 256

# Per-id material config
const MAT_DEFS: Dictionary = {
	"concrete":      {"base": Color("706f68"), "metal": 0.0, "rough": 0.92, "bump": 0.8, "freq": 7.0, "noise": 0.16, "kind": "mottle"},
	"concrete_dark": {"base": Color("4e4d48"), "metal": 0.0, "rough": 0.94, "bump": 0.9, "freq": 7.0, "noise": 0.2, "kind": "mottle"},
	"concrete_panel":{"base": Color("7a7970"), "metal": 0.0, "rough": 0.9, "bump": 0.5, "freq": 8.0, "noise": 0.14, "kind": "panel"},
	"plaster":       {"base": Color("b3a98c"), "metal": 0.0, "rough": 0.93, "bump": 0.6, "freq": 9.0, "noise": 0.07, "kind": "mottle"},
	"sand":          {"base": Color("cda866"), "metal": 0.0, "rough": 0.96, "bump": 0.6, "freq": 6.0, "noise": 0.18, "kind": "sand"},
	"asphalt":       {"base": Color("403f3a"), "metal": 0.0, "rough": 0.95, "bump": 1.0, "freq": 5.0, "noise": 0.25, "kind": "asphalt"},
	"tile":          {"base": Color("8f928a"), "metal": 0.0, "rough": 0.85, "bump": 0.3, "freq": 10.0, "noise": 0.08, "kind": "tile"},
	"brick":         {"base": Color("7d5a4a"), "metal": 0.0, "rough": 0.94, "bump": 0.9, "freq": 8.0, "noise": 0.12, "kind": "brick"},
	"metal_dark":    {"base": Color("3b4046"), "metal": 0.95, "rough": 0.38, "bump": 0.35, "freq": 14.0, "noise": 0.08, "kind": "brushed"},
	"metal_light":   {"base": Color("a6abb1"), "metal": 0.95, "rough": 0.32, "bump": 0.3, "freq": 14.0, "noise": 0.07, "kind": "brushed"},
	"metal_rust":    {"base": Color("5a4a3e"), "metal": 0.8, "rough": 0.55, "bump": 0.6, "freq": 6.0, "noise": 0.22, "kind": "rust"},
	"metal_blue":    {"base": Color("27508f"), "metal": 0.9, "rough": 0.35, "bump": 0.3, "freq": 12.0, "noise": 0.06, "kind": "brushed"},
	"metal_brass":   {"base": Color("a9853a"), "metal": 0.95, "rough": 0.4, "bump": 0.3, "freq": 12.0, "noise": 0.08, "kind": "brushed"},
	"wood":          {"base": Color("9c743d"), "metal": 0.0, "rough": 0.82, "bump": 0.65, "freq": 5.0, "noise": 0.14, "kind": "planks"},
	"wood_crate":    {"base": Color("8a6134"), "metal": 0.0, "rough": 0.85, "bump": 0.6, "freq": 7.0, "noise": 0.16, "kind": "planks"},
	"wood_dark":     {"base": Color("4c3a26"), "metal": 0.0, "rough": 0.85, "bump": 0.55, "freq": 5.0, "noise": 0.12, "kind": "planks"},
	"glass":         {"base": Color("9fd8cf"), "metal": 0.1, "rough": 0.06, "bump": 0.1, "freq": 20.0, "noise": 0.02, "kind": "glass"},
	"cloth_ct":      {"base": Color("2a6ef5"), "metal": 0.0, "rough": 0.95, "bump": 0.3, "freq": 24.0, "noise": 0.1, "kind": "weave"},
	"cloth_t":       {"base": Color("d84a28"), "metal": 0.0, "rough": 0.95, "bump": 0.3, "freq": 24.0, "noise": 0.1, "kind": "weave"},
	"cloth_grey":    {"base": Color("6d7075"), "metal": 0.0, "rough": 0.95, "bump": 0.3, "freq": 24.0, "noise": 0.1, "kind": "weave"},
	"cloth_torn":    {"base": Color("4a5a3a"), "metal": 0.0, "rough": 0.97, "bump": 0.4, "freq": 10.0, "noise": 0.2, "kind": "torn"},
	"rubber":        {"base": Color("2a2d31"), "metal": 0.0, "rough": 0.85, "bump": 0.35, "freq": 16.0, "noise": 0.1, "kind": "mottle"},
	"plastic":       {"base": Color("4d5157"), "metal": 0.0, "rough": 0.45, "bump": 0.2, "freq": 18.0, "noise": 0.05, "kind": "mottle"},
	"paint_white":   {"base": Color("cfd2d2"), "metal": 0.0, "rough": 0.7, "bump": 0.25, "freq": 12.0, "noise": 0.06, "kind": "mottle"},
	"paint_black":   {"base": Color("222427"), "metal": 0.0, "rough": 0.72, "bump": 0.3, "freq": 12.0, "noise": 0.07, "kind": "mottle"},
	"paint_red":     {"base": Color("a03c32"), "metal": 0.0, "rough": 0.68, "bump": 0.25, "freq": 12.0, "noise": 0.07, "kind": "mottle"},
	"paint_yellow":  {"base": Color("c9a63c"), "metal": 0.0, "rough": 0.68, "bump": 0.25, "freq": 12.0, "noise": 0.07, "kind": "mottle"},
	"paint_olive":   {"base": Color("6b7050"), "metal": 0.0, "rough": 0.7, "bump": 0.25, "freq": 12.0, "noise": 0.07, "kind": "mottle"},
	"gravel":        {"base": Color("6e6a5e"), "metal": 0.0, "rough": 0.96, "bump": 0.9, "freq": 4.0, "noise": 0.3, "kind": "mottle"},
	"graffiti_wall": {"base": Color("6b6e6b"), "metal": 0.0, "rough": 0.93, "bump": 0.5, "freq": 6.0, "noise": 0.16, "kind": "graffiti"},
	"bone":          {"base": Color("d8cdb8"), "metal": 0.0, "rough": 0.6, "bump": 0.35, "freq": 10.0, "noise": 0.08, "kind": "mottle"},
}

# External (ambientCG) texture overrides: external id -> texture folder name.
const EXT_MAP: Dictionary = {
	"concrete": "Concrete034",
	"concrete_dark": "Concrete047A",
	"plaster": "Plaster001",
	"brick": "Bricks097",
	"wood": "Wood092",
	"wood_dark": "Wood094",
	"metal_dark": "Metal049A",
	"metal_rust": "Metal055A",
	"ground": "Ground037",
	"sand": "Ground037",
	"asphalt": "Asphalt023S",
	"rock": "Rock058",
}

static var _tex_cache: Dictionary = {}   # id -> {albedo, normal, rough, ao}
static var _mat_cache: Dictionary = {}   # "id|scale" -> StandardMaterial3D
static var _plain_cache: Dictionary = {} # "color|metal|rough" -> StandardMaterial3D
static var _decal_cache: Dictionary = {} # id -> {tex, mat}
static var _built: bool = false


static func _ensure() -> void:
	if _built:
		return
	_built = true
	# 懒构建：仅地图实际用到的材质在 get_mat 时单独构建，避免开局全量卡顿。
	# 预构建一个最快的大色块材质（concrete），确保首帧有可用材质。

static func _to_texture(img: Image) -> ImageTexture:
	# 运行时兜底（无 mipmap：4.7.1 的 ImageTexture 无法上传 mipmap 链，
	# 正式路径用烘焙 PNG（assets/gen/mat），由导入器生成 mipmap + VRAM 压缩）
	return ImageTexture.create_from_image(img)


static func _noise_bytes(seed: int, freq: float, gain: float = 0.5, lacunarity: float = 2.0) -> PackedByteArray:
	var fnl := FastNoiseLite.new()
	fnl.seed = seed
	fnl.noise_type = FastNoiseLite.TYPE_VALUE
	fnl.frequency = freq
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = 4
	fnl.fractal_gain = gain
	fnl.fractal_lacunarity = lacunarity
	var img := fnl.get_image(SIZE, SIZE)
	if img.get_format() != Image.FORMAT_R8:
		img.convert(Image.FORMAT_R8)
	return img.get_data()


static func _build_material_tex(id: String) -> void:
	var imgs: Dictionary = _gen_material_images(id)
	_tex_cache[id] = {
		"albedo": _to_texture(imgs.albedo),
		"normal": _to_texture(imgs.normal),
		"rough": _to_texture(imgs.rough),
		"ao": _to_texture(imgs.ao),
	}


# 烘焙导出：把程序化材质保存为 PNG（由 Godot 导入器生成 mipmap + VRAM 压缩），
# 运行时零生成开销（Web 单线程启动不再卡顿）。返回 id -> 保存的路径列表。
static func bake_materials(out_dir: String) -> Dictionary:
	var saved: Dictionary = {}
	for id in MAT_DEFS:
		if uses_external(id):
			continue
		var imgs: Dictionary = _gen_material_images(id)
		var paths: Array = []
		for ch in ["albedo", "normal", "rough", "ao"]:
			var p: String = out_dir + "/" + id + "_" + ch + ".png"
			imgs[ch].save_png(p)
			paths.append(p)
		saved[id] = paths
	return saved


# 运行时的烘焙纹理路径（存在则直接 load，导入器已生成 mipmap + 压缩）
static func _baked_tex_path(id: String, ch: String) -> String:
	return "res://assets/gen/mat/" + id + "_" + ch + ".png"


static func _baked(id: String, ch: String) -> Texture2D:
	var p: String = _baked_tex_path(id, ch)
	if ResourceLoader.exists(p):
		return load(p)
	return null


static func _gen_material_images(id: String) -> Dictionary:
	var cfg: Dictionary = MAT_DEFS[id]
	var base: Color = cfg.base
	var kind: String = cfg.kind
	var freq: float = cfg.freq
	var noise_a: float = cfg.noise
	var seed: int = 1000 + id.hash()

	var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rgh := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ao := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	var n1 := _noise_bytes(seed, freq)
	var n2 := _noise_bytes(seed + 11, freq * 2.2, 0.55)
	var n3 := _noise_bytes(seed + 37, freq * 0.28, 0.5)   # large scale
	var n4 := _noise_bytes(seed + 53, freq * 2.2, 0.5)    # fine detail

	var nd: PackedByteArray = n1
	var n2d: PackedByteArray = n2
	var n3d: PackedByteArray = n3
	var n4d: PackedByteArray = n4
	var abd: PackedByteArray = alb.get_data()
	var nrd: PackedByteArray = nrm.get_data()
	var rhd: PackedByteArray = rgh.get_data()
	var aod: PackedByteArray = ao.get_data()
	abd.resize(SIZE * SIZE * 4)
	nrd.resize(SIZE * SIZE * 4)
	rhd.resize(SIZE * SIZE * 4)
	aod.resize(SIZE * SIZE * 4)

	var bump: float = cfg.bump
	var rough_base: float = cfg.rough
	var metal: float = cfg.metal

	for y in range(SIZE):
		var row: int = y * SIZE
		for x in range(SIZE):
			var i: int = (row + x)
			var a: float = float(nd[i]) / 255.0
			var b: float = float(n2d[i]) / 255.0
			var c: float = float(n3d[i]) / 255.0
			var d: float = float(n4d[i]) / 255.0
			var lum: float = 1.0
			var r_var: float = 0.0
			var ao_v: float = 0.0

			match kind:
				"mottle":
					lum = 1.0 + (a - 0.5) * 2.0 * noise_a + (c - 0.5) * 1.6 * noise_a
					r_var = (b - 0.5) * 0.35
					ao_v = 0.6 * smoothstep(0.55, 0.78, c)
				"sand":
					lum = 1.0 + (a - 0.5) * 1.8 * noise_a + (c - 0.5) * 1.2 * noise_a * 0.6
					var ripple: float = sin(float(y) * 0.055 + a * 2.0 + c * 9.0) * 0.05
					lum += ripple
					r_var = (b - 0.5) * 0.4
					ao_v = 0.35 * smoothstep(0.5, 0.8, c)
				"asphalt":
					lum = 1.0 + (a - 0.5) * 2.0 * noise_a + (c - 0.5) * 2.2 * noise_a
					var crack: float = smoothstep(0.86, 0.95, a) + smoothstep(0.9, 0.98, b)
					lum -= crack * 0.5
					ao_v = crack * 0.8
					r_var = (b - 0.5) * 0.3
				"panel":
					lum = 1.0 + (a - 0.5) * 1.8 * noise_a
					var gx: int = int(x / 64) * 64
					var gy: int = int(y / 64) * 64
					var edge: float = max(float(abs(x - gx) < 3), float(abs(y - gy) < 3))
					lum -= edge * 0.32
					ao_v += edge * 0.7
					# corner bolts
					if (x == gx + 4 or x == gx + 60) and (y == gy + 4 or y == gy + 60):
						lum += 0.25
				"planks":
					var plank_w: float = 128.0
					var px: int = int(x / plank_w)
					var pxo: float = float(x - px * int(plank_w)) / plank_w
					var grain: float = sin(float(y) * 0.06 + float(px) * 3.1) * 0.5 + 0.5
					lum = 1.0 + (a - 0.5) * 0.7 * noise_a + (grain - 0.5) * 0.55 * noise_a
					var seam: float = float(pxo < 0.012 or pxo > 0.988)
					lum -= seam * 0.45
					ao_v += seam * 0.85
					if float(abs(y - 128 * int(y / 128))) < 2.0:
						lum -= 0.12
				"brick":
					var bw: int = 64
					var bh: int = 26
					var bx: int = int(x / bw)
					var by: int = int(y / bh)
					var off: float = 32.0 if by % 2 == 0 else 0.0
					var rx: float = abs(float(x) - (bx * bw + off))
					var ry: float = abs(float(y) - by * bh)
					var mortar: float = float(rx < 2.5 or ry < 2.5)
					lum = 1.0 + (a - 0.5) * 1.6 * noise_a + (c - 0.5) * 0.6 * noise_a
					lum -= mortar * 0.55
					ao_v += mortar * 0.9
				"brushed":
					var streak: float = sin(float(x) * 0.9 + (a - 0.5) * 3.0 + c * 12.0) * 0.5 + 0.5
					lum = 1.0 + (streak - 0.5) * 0.6 * noise_a + (b - 0.5) * 0.35 * noise_a
					var scratch: float = smoothstep(0.93, 0.99, d) * 0.8
					lum += scratch * 0.25
					r_var = (streak - 0.5) * 0.3
					ao_v = scratch * 0.4
				"rust":
					var rust: float = smoothstep(0.42, 0.75, c)
					lum = 1.0 + (a - 0.5) * 0.9 * noise_a
					# rust patches push toward brown
					base = base.lerp(Color("8a5a30"), rust * 0.55)
					r_var = rust * 0.45
					ao_v = rust * 0.5
				"weave":
					var wv: float = sin(float(x) * 1.4) * sin(float(y) * 1.4) * 0.5 + 0.5
					lum = 1.0 + (wv - 0.5) * 0.5 * noise_a + (a - 0.5) * 0.5 * noise_a
					r_var = (a - 0.5) * 0.25
				"torn":
					var tear: float = smoothstep(0.4, 0.85, a)
					lum = 1.0 + (a - 0.5) * 1.4 * noise_a
					lum = lerp(lum, 0.55, tear * 0.5)
					r_var = tear * 0.5
					ao_v = tear * 0.6
				"glass":
					lum = 1.0 + (a - 0.5) * 0.3 * noise_a
				"graffiti":
					lum = 1.0 + (a - 0.5) * 1.6 * noise_a + (c - 0.5) * 1.2 * noise_a
					var blob: float = smoothstep(0.62, 0.8, c) * 0.8
					if blob > 0.01:
						base = base.lerp(Color(0.62, 0.3, 0.22).lerp(Color(0.15, 0.45, 0.7), b), blob * 0.85)
					ao_v = 0.3 * smoothstep(0.55, 0.75, c)

			var rr: float = clamp(rough_base + r_var, 0.02, 1.0)
			var r8: int = int(clamp(rr * 255.0, 0.0, 255.0))
			var cr: int = int(clamp(base.r * lum * 255.0, 0.0, 255.0))
			var cg: int = int(clamp(base.g * lum * 255.0, 0.0, 255.0))
			var cb: int = int(clamp(base.b * lum * 255.0, 0.0, 255.0))
			var ao8: int = int(clamp((1.0 - ao_v) * 255.0, 0.0, 255.0))
			var o: int = i * 4
			abd[o] = cr
			abd[o + 1] = cg
			abd[o + 2] = cb
			abd[o + 3] = 255
			rhd[o] = r8
			rhd[o + 1] = r8
			rhd[o + 2] = r8
			rhd[o + 3] = 255
			aod[o] = ao8
			aod[o + 1] = ao8
			aod[o + 2] = ao8
			aod[o + 3] = 255
			nrd[o + 3] = 255

	# normal map from high-frequency noise height (independent micro-bump) + albedo gradient blend
	var abd_n: PackedByteArray = alb.get_data()
	var n4d2: PackedByteArray = n4
	for y in range(SIZE):
		for x in range(SIZE):
			var xp: int = (x + 1) % SIZE
			var yp: int = (y + 1) % SIZE
			var i: int = (y * SIZE + x) * 4
			var alb_dx: float = (float(abd_n[(y * SIZE + xp) * 4]) - float(abd_n[i])) / 255.0
			var alb_dy: float = (float(abd_n[(yp * SIZE + x) * 4]) - float(abd_n[i])) / 255.0
			# micro-bump from raw high-freq noise (visible under direct sun)
			var h0: float = float(n4d2[i / 4]) / 255.0
			var hdx: float = float(n4d2[(y * SIZE + xp) / 4]) / 255.0 - h0
			var hdy: float = float(n4d2[(yp * SIZE + x) / 4]) / 255.0 - h0
			var dx: float = alb_dx * 0.35 + hdx * bump * 1.2
			var dy: float = alb_dy * 0.35 + hdy * bump * 1.2
			var nz: float = 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			var nx: float = -dx * nz * 1.5
			var ny: float = -dy * nz * 1.5
			nrd[i] = int(clamp(nx * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			nrd[i + 1] = int(clamp(ny * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			nrd[i + 2] = int(clamp(nz * 0.5 + 0.5, 0.0, 1.0) * 255.0)

	alb.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, abd)
	nrm.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, nrd)
	rgh.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, rhd)
	ao.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, aod)
	return {"albedo": alb, "normal": nrm, "rough": rgh, "ao": ao}


static func get_albedo(id: String) -> Texture2D:
	_ensure()
	if not _tex_cache.has(id):
		_build_material_tex(id)
	return _tex_cache[id].albedo


static func get_normal(id: String) -> Texture2D:
	_ensure()
	if not _tex_cache.has(id):
		_build_material_tex(id)
	return _tex_cache[id].normal


static func get_roughness(id: String) -> Texture2D:
	_ensure()
	if not _tex_cache.has(id):
		_build_material_tex(id)
	return _tex_cache[id].rough


static func get_ao(id: String) -> Texture2D:
	_ensure()
	if not _tex_cache.has(id):
		_build_material_tex(id)
	return _tex_cache[id].ao


static func get_mat(id: String, scale: float = 1.0) -> StandardMaterial3D:
	_ensure()
	var ext_key: String = "ext|" + id + "|" + str(scale)
	if _mat_cache.has(ext_key):
		return _mat_cache[ext_key]
	if uses_external(id):
		var em := _build_external_mat(id, scale)
		_mat_cache[ext_key] = em
		return em
	var key: String = id + "|" + str(scale)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	# 优先烘焙纹理（mipmap + VRAM 压缩，启动零生成开销）；缺失时回退运行时生成
	var albedo_t: Texture2D = _baked(id, "albedo")
	var normal_t: Texture2D = _baked(id, "normal")
	var rough_t: Texture2D = _baked(id, "rough")
	var ao_t: Texture2D = _baked(id, "ao")
	if albedo_t == null:
		if not _tex_cache.has(id):
			_build_material_tex(id)
		albedo_t = _tex_cache[id].albedo
		normal_t = _tex_cache[id].normal
		rough_t = _tex_cache[id].rough
		ao_t = _tex_cache[id].ao
	m.albedo_texture = albedo_t
	if normal_t != null:
		m.normal_enabled = true
		m.normal_texture = normal_t
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness_texture = rough_t
	m.ao_enabled = true
	m.ao_texture = ao_t
	var cfg: Dictionary = MAT_DEFS[id]
	m.metallic = float(cfg.metal)
	m.roughness = float(cfg.rough)
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.anisotropy = 0.5
	if id == "glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.18)
		m.transmission_enabled = true
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		# keep metal-ish tint for reflections
		m.refraction_enabled = false
	if id.begins_with("cloth"):
		m.rim_enabled = true
		m.rim_tint = 0.7
		m.rim = 0.6
	_mat_cache[key] = m
	return m


static func uses_external(id: String) -> bool:
	if not EXT_MAP.has(id):
		return false
	return ResourceLoader.exists(_ext_path(id, "Color.jpg"))


static func has_hdri() -> bool:
	return ResourceLoader.exists("res://assets/hdri/sky_2k.hdr")


static func _ext_path(id: String, suffix: String) -> String:
	var folder: String = EXT_MAP[id]
	return "res://assets/textures/" + folder + "/" + folder + "_2K-JPG_" + suffix


static func _build_external_mat(id: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(_ext_path(id, "Color.jpg")):
		m.albedo_texture = load(_ext_path(id, "Color.jpg"))
	if ResourceLoader.exists(_ext_path(id, "NormalGL.jpg")):
		m.normal_enabled = true
		m.normal_texture = load(_ext_path(id, "NormalGL.jpg"))
	if ResourceLoader.exists(_ext_path(id, "Roughness.jpg")):
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = load(_ext_path(id, "Roughness.jpg"))
	var cfg: Dictionary = MAT_DEFS.get(id, {})
	m.metallic = float(cfg.get("metal", 0.0))
	m.roughness = float(cfg.get("rough", 0.9))
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.anisotropy = 0.5
	return m


static func solid(color: Color, metalness: float = 0.0, roughness: float = 0.8) -> StandardMaterial3D:
	var key: String = "s|" + color.to_html() + "|" + str(metalness) + "|" + str(roughness)
	if _plain_cache.has(key):
		return _plain_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metalness
	m.roughness = roughness
	_plain_cache[key] = m
	return m


static func emissive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key: String = "e|" + color.to_html() + "|" + str(energy)
	if _plain_cache.has(key):
		return _plain_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_plain_cache[key] = m
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var key: String = "u|" + color.to_html()
	if _plain_cache.has(key):
		return _plain_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plain_cache[key] = m
	return m


# ---------------- Decals ----------------
static func get_decal(id: String) -> Texture2D:
	_ensure()
	if not _decal_cache.has(id):
		_build_decal(id)
	return _decal_cache[id].tex


static func decal_mat(id: String) -> StandardMaterial3D:
	_ensure()
	if not _decal_cache.has(id):
		_build_decal(id)
	return _decal_cache[id].mat


static func _build_decal(id: String) -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var seed: int = 7000 + id.hash()
	var fnl := FastNoiseLite.new()
	fnl.seed = seed
	fnl.noise_type = FastNoiseLite.TYPE_VALUE
	fnl.frequency = 0.012
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = 4
	var n_img := fnl.get_image(256, 256)
	if n_img.get_format() != Image.FORMAT_RF:
		n_img.convert(Image.FORMAT_RF)
	var nd: PackedByteArray = n_img.get_data()
	var data: PackedByteArray = img.get_data()
	data.resize(256 * 256 * 4)
	var col: Color
	match id:
		"stain_dirt": col = Color("3a3228")
		"stain_blood": col = Color("6e1d16")
		"stain_oil": col = Color("1c1d1e")
		"stain_water": col = Color("2c3a44")
		"crack": col = Color("0c0c0c")
		"scorch": col = Color("141414")
		"graffiti": col = Color("c95b3a")
		"paint_stripe": col = Color("e0c84a")
		_: col = Color("333333")
	var center := Vector2(128, 128)
	for y in range(256):
		for x in range(256):
			var i: int = (y * 256 + x) * 4
			var n: float = float(nd[y * 256 + x]) / 255.0
			var dpos: float = Vector2(x, y).distance_to(center)
			var edge: float = smoothstep(128.0, 60.0, dpos)
			var alpha: float = 0.0
			match id:
				"stain_dirt", "stain_blood", "stain_oil", "stain_water", "scorch":
					alpha = smoothstep(0.45, 0.8, n) * edge * 0.85
					if id == "stain_blood":
						alpha *= 0.7 + 0.3 * smoothstep(0.5, 0.9, abs(n - 0.7))
					elif id == "scorch":
						alpha = smoothstep(0.4, 0.75, n) * edge * 0.8
						# darker center
						alpha *= 0.5 + 0.5 * smoothstep(90.0, 10.0, dpos)
				"crack":
					var c: float = smoothstep(0.52, 0.6, n)
					alpha = c * edge * 0.9
					if abs(float(y - 128)) < 4 and abs(float(x - 128)) > 40:
						alpha = 0.0
				"graffiti":
					var blob: float = smoothstep(0.55, 0.85, n)
					alpha = blob * edge * 0.8
				"paint_stripe":
					alpha = smoothstep(0.3, 0.8, n) * smoothstep(128.0, 60.0, abs(float(y - 128))) * 0.85
				_:
					alpha = smoothstep(0.5, 0.8, n) * edge
			var t: float = 1.0 - (n - 0.5) * 0.8
			data[i] = int(clamp(col.r * t * 255.0, 0, 255))
			data[i + 1] = int(clamp(col.g * t * 255.0, 0, 255))
			data[i + 2] = int(clamp(col.b * t * 255.0, 0, 255))
			data[i + 3] = int(clamp(alpha * 255.0, 0, 255))
	img.set_data(256, 256, false, Image.FORMAT_RGBA8, data)
	var tex := _to_texture(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_decal_cache[id] = {"tex": tex, "mat": m}
