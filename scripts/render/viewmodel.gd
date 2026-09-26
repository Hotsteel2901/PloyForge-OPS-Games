# ViewmodelFactory: procedural first-person weapon viewmodels.
# Primitive meshes only, materials cached via MaterialLib. Aim -Z, y-up, meters.
class_name ViewmodelFactory
extends RefCounted

static var _cache: Dictionary = {}
static var _built_cache: Dictionary = {}  # weapon_id -> 模板节点树

# 外部 CC0 GLB 模型：id -> 资源路径
const EXTERNAL_MODELS: Dictionary = {
	"pc": "res://assets/weapons/Pistol_Compact_East.glb",
	"pf": "res://assets/weapons/Pistol_Full_East.glb",
	"ra": "res://assets/weapons/Rifle_Assault_East.glb",
	"rb": "res://assets/weapons/Rifle_Battle_East.glb",
	"sc": "res://assets/weapons/SMG_Compact_East.glb",
	"sf": "res://assets/weapons/SMG_Full_East.glb",
	"sa": "res://assets/weapons/Shotgun_Auto_East.glb",
	"sp": "res://assets/weapons/Shotgun_Pump_East.glb",
	"sm": "res://assets/weapons/Sniper_Material_East.glb",
	"sr": "res://assets/weapons/Sniper_Rifle_East.glb",
}

static var _scene_cache: Dictionary = {}

# 外部 GLB 模型已按 Godot 惯例朝 -Z（枪口向前），无需翻转；
# 个别模型若朝 +Z，在此置 true 以应用 rotation.y = PI。
static var EXT_FLIP := {
	"pc": false, "pf": false, "ra": false, "rb": false, "sc": false,
	"sf": false, "sa": false, "sp": false, "sm": false, "sr": false,
}


static func is_external(weapon_id: String) -> bool:
	return EXTERNAL_MODELS.has(weapon_id)


static func _scene_for(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene: PackedScene = load(path)
	_scene_cache[path] = scene
	return scene


static func _m(id: String) -> Material:
	if _cache.has(id):
		return _cache[id]
	var mat: Material = MaterialLib.get_mat(id, 1.0)
	_cache[id] = mat
	return mat


static func _solid(c: Color, metal: float, rough: float) -> Material:
	var key := "solid|%s|%.2f|%.2f" % [c.to_html(), metal, rough]
	if _cache.has(key):
		return _cache[key]
	var mat: Material = MaterialLib.solid(c, metal, rough)
	_cache[key] = mat
	return mat


static func _emit(c: Color, e: float) -> Material:
	var key := "emit|%s|%.2f" % [c.to_html(), e]
	if _cache.has(key):
		return _cache[key]
	var mat: Material = MaterialLib.emissive(c, e)
	_cache[key] = mat
	return mat


static func _mi(m: Mesh, mat: Material, pos: Vector3, rot: Vector3, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if n != "":
		mi.name = n
	return mi


static func _box(mat: Material, s: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO, n: String = "") -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = s
	return _mi(m, mat, pos, rot, n)


static func _cyl(mat: Material, r1: float, r2: float, h: float, pos: Vector3, rot: Vector3 = Vector3.ZERO, seg: int = 14, n: String = "") -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r2
	m.height = h
	m.radial_segments = seg
	return _mi(m, mat, pos, rot, n)


static func _sph(mat: Material, r: float, pos: Vector3, n: String = "") -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return _mi(m, mat, pos, Vector3.ZERO, n)


static func _torus(mat: Material, inner: float, outer: float, pos: Vector3, rot: Vector3 = Vector3.ZERO, n: String = "") -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	return _mi(m, mat, pos, rot, n)


static func _screw(mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _cyl(mat, 0.0022, 0.0022, 0.0018, pos, rot, 8)


static func _zl(mat: Material, r: float, h: float, pos: Vector3, n: String = "") -> MeshInstance3D:
	return _cyl(mat, r, r, h, pos, Vector3(PI * 0.5, 0, 0), 14, n)


static func _rz(mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, n: String = "") -> MeshInstance3D:
	return _box(mat, Vector3(0.0035, 0.004, 0.024), pos, rot, n)


static func _dark() -> Material:
	return _solid(Color("0b0c0e"), 0.0, 0.9)


static func build(weapon_id: String) -> Node3D:
	# 场景级缓存：首次构建模板树，后续 duplicate 复用（网格/材质资源共享）。
	# 每次返回深拷贝，外部对 transform/meta 的修改不会污染模板。
	if not _built_cache.has(weapon_id):
		_built_cache[weapon_id] = _build_new(weapon_id)
	var root := (_built_cache[weapon_id] as Node3D).duplicate(true) as Node3D
	# duplicate 不复制 meta：重建引用（节点名固定）
	root.set_meta("weapon_id", weapon_id)
	root.set_meta("muzzle", root.get_node("Muzzle"))
	root.set_meta("mag", _find_mag(root, weapon_id))
	root.set_meta("hand", root.get_node_or_null("Hand"))
	return root


static func _build_new(weapon_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Viewmodel_" + weapon_id
	root.set_meta("weapon_id", weapon_id)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	root.add_child(muzzle)
	match weapon_id:
		"fang": _build_fang(root, muzzle)
		"k9": _build_k9(root, muzzle)
		"vx9": _build_vx9(root, muzzle)
		"arc17": _build_arc17(root, muzzle)
		"warden": _build_warden(root, muzzle)
		"longshot": _build_longshot(root, muzzle)
		"bruiser": _build_bruiser(root, muzzle)
		"thunder": _build_thunder(root, muzzle)
		"zclaw": _build_zclaw(root, muzzle)
		_:
			if EXTERNAL_MODELS.has(weapon_id):
				_build_external(root, muzzle, weapon_id)
			else:
				_build_fang(root, muzzle)
	root.set_meta("muzzle", muzzle)
	_store_mag(root, weapon_id)
	_build_hand(root, weapon_id)
	_disable_shadows(root)
	return root


# 第一人称 viewmodel 与第三人称角色武器一律关闭阴影：
# 近相机的枪不需要自阴影（还有伪影），20 人局的武器阴影 pass 是纯开销。
static func _disable_shadows(root: Node3D) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for c in n.get_children():
			stack.append(c)


# 每把枪的副手持握位置（左手从画面左侧 -x 侧伸入握护木/前握把，相对枪局部坐标）。
# 换弹动画以此为基准，不同枪手的位置不同。
static func _hand_hold(weapon_id: String) -> Vector3:
	if weapon_id == "thunder" or weapon_id == "zclaw":
		return Vector3(0, -99, 0)  # 手雷/尸爪不显示副手
	match weapon_id:
		"fang":
			return Vector3(-0.03, -0.015, 0.04)
		"k9":
			return Vector3(-0.024, -0.02, -0.30)
		"vx9":
			return Vector3(-0.024, -0.018, -0.27)
		"arc17":
			return Vector3(-0.024, -0.018, -0.22)
		"warden":
			return Vector3(-0.024, -0.02, -0.27)
		"longshot":
			return Vector3(-0.024, -0.018, -0.09)
		"bruiser":
			return Vector3(-0.026, -0.02, -0.12)
		"pc":
			return Vector3(-0.022, -0.026, -0.07)
		"pf":
			return Vector3(-0.022, -0.028, -0.08)
		"ra", "rb", "sc", "sf", "sa", "sp":
			return Vector3(-0.024, -0.03, -0.24)
		"sm", "sr":
			return Vector3(-0.024, -0.028, -0.2)
	return Vector3(-0.024, -0.02, -0.2)


# 程序化第一人称副手（战术手套左手）：手掌 + 4 指 + 拇指 + 手腕。
# 左手在枪身 -x 侧，绕 Y 转 90° 让手指朝 +x 勾住枪身、手臂残段朝 -x 伸向画面外。
# 默认隐藏，仅换弹期间由 game.gd 显示并驱动拆/装弹夹动作。
static func _build_hand(root: Node3D, weapon_id: String) -> void:
	var hold: Vector3 = _hand_hold(weapon_id)
	if hold.y < -50:
		return  # thunder/zclaw 等不放副手
	var glove := _solid(Color("181c20"), 0.05, 0.75)
	var back := _solid(Color("1c2024"), 0.05, 0.8)
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.set_meta("hold", hold)
	hand.position = hold
	hand.rotation.y = PI * 0.5
	hand.visible = false
	root.add_child(hand)
	# 手腕 + 手臂残段
	hand.add_child(_box(glove, Vector3(0.052, 0.038, 0.055), Vector3(0, 0, -0.045)))
	hand.add_child(_box(glove, Vector3(0.05, 0.04, 0.07), Vector3(0, -0.002, -0.09)))
	# 手掌
	hand.add_child(_box(glove, Vector3(0.058, 0.034, 0.09), Vector3(0, 0.0, 0.02)))
	hand.add_child(_box(back, Vector3(0.058, 0.014, 0.08), Vector3(0, 0.021, 0.02), Vector3(-0.12, 0, 0)))
	# 四指（微弯曲）
	for i in 4:
		var fx: float = -0.021 + i * 0.014
		hand.add_child(_box(glove, Vector3(0.011, 0.026, 0.034), Vector3(fx, 0.01, 0.078), Vector3(-0.3, 0, 0)))
		hand.add_child(_box(back, Vector3(0.011, 0.013, 0.024), Vector3(fx, 0.024, 0.085), Vector3(-0.3, 0, 0)))
	# 拇指
	hand.add_child(_box(glove, Vector3(0.016, 0.024, 0.038), Vector3(-0.038, -0.004, 0.045), Vector3(-0.25, 0.25, 0.45)))
	root.set_meta("hand", hand)








# 存储弹夹节点引用（换弹动画用）：内部武器弹夹名为 Mag/BoxMag；
# 外部 GLB 没有独立弹夹，用整枪根节点作为动画载体（整枪下沉模拟拆装）。
static func _store_mag(root: Node3D, weapon_id: String) -> void:
	root.set_meta("mag", _find_mag(root, weapon_id))


static func _find_mag(root: Node3D, weapon_id: String) -> Node3D:
	var stack: Array = [root]
	var mag: Node3D = null
	var glb: Node3D = null
	while not stack.is_empty() and (mag == null or glb == null):
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n.name == "Mag" or n.name == "BoxMag"):
			mag = n
		elif n.name == "GLB_%s" % weapon_id:
			glb = n as Node3D
		for c in n.get_children():
			stack.append(c)
	return mag if mag != null else glb


static func _build_external(root: Node3D, muzzle: Node3D, weapon_id: String) -> void:
	var path: String = str(EXTERNAL_MODELS.get(weapon_id, ""))
	if path == "":
		return
	var scene: PackedScene = _scene_for(path)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "GLB_%s" % weapon_id
	root.add_child(inst)
	inst.rotation.y = PI if bool(EXT_FLIP.get(weapon_id, false)) else 0.0
	inst.scale = Vector3(0.9, 0.9, 0.9)
	var box: Dictionary = _collect_aabb(inst, Transform3D.IDENTITY)
	if bool(box.has):
		inst.position = -box.aabb.get_center()
		# 枪口朝 -Z，取最小角（min-z 面）作为枪口位置
		muzzle.position = Vector3(0, 0.02, box.aabb.position.z)
	else:
		muzzle.position = Vector3(0, 0.02, -0.55)
	# 程序化弹夹：GLB 模型没有独立弹夹网格，换弹动画需要一个可滑出/甩出的弹夹模型。
	# 命名 "Mag" 会被 _store_mag 找到，从而走独立弹夹换弹动画。
	var mag_spec: Dictionary = _glb_mag_spec(weapon_id)
	if not mag_spec.is_empty():
		var mag_mat: Material = _solid(Color("24292f"), 0.3, 0.55)
		var mag_box: Vector3 = mag_spec.size
		var mag_pos: Vector3 = mag_spec.pos
		var mag_rot: Vector3 = mag_spec.rot
		var mag := _box(mag_mat, mag_box, mag_pos, mag_rot, "Mag")
		# 弹夹底部加个底板，更像真弹夹
		mag.add_child(_box(_solid(Color("1a1e22"), 0.35, 0.6), Vector3(mag_box.x * 1.08, 0.01, mag_box.z * 1.1), Vector3(0, -mag_box.y * 0.5 + 0.002, 0), Vector3.ZERO, "MagBase"))
		root.add_child(mag)


# 外部 GLB 枪的程序化弹夹规格（位置/尺寸相对居中后的枪局部坐标，y 向下为弹匣井）
static func _glb_mag_spec(weapon_id: String) -> Dictionary:
	match weapon_id:
		"pc":
			return {"size": Vector3(0.021, 0.05, 0.027), "pos": Vector3(0, -0.05, 0.008), "rot": Vector3(0.08, 0, 0)}
		"pf":
			return {"size": Vector3(0.024, 0.06, 0.031), "pos": Vector3(0, -0.057, 0.008), "rot": Vector3(0.08, 0, 0)}
		"ra":
			return {"size": Vector3(0.027, 0.088, 0.082), "pos": Vector3(0, -0.06, -0.012), "rot": Vector3(0.1, 0, 0)}
		"rb":
			return {"size": Vector3(0.026, 0.078, 0.078), "pos": Vector3(0, -0.055, -0.006), "rot": Vector3(0.08, 0, 0)}
		"sc":
			return {"size": Vector3(0.026, 0.082, 0.058), "pos": Vector3(0, -0.058, -0.002), "rot": Vector3(0.06, 0, 0)}
		"sf":
			return {"size": Vector3(0.028, 0.096, 0.068), "pos": Vector3(0, -0.064, -0.002), "rot": Vector3(0.06, 0, 0)}
		"sa":
			return {"size": Vector3(0.04, 0.058, 0.078), "pos": Vector3(0, -0.05, 0.01), "rot": Vector3.ZERO}
		"sp":
			return {"size": Vector3(0.042, 0.052, 0.068), "pos": Vector3(0, -0.046, 0.0), "rot": Vector3.ZERO}
		"sm":
			return {"size": Vector3(0.024, 0.042, 0.06), "pos": Vector3(0, -0.038, 0.012), "rot": Vector3.ZERO}
		"sr":
			return {"size": Vector3(0.024, 0.05, 0.07), "pos": Vector3(0, -0.042, 0.0), "rot": Vector3.ZERO}
	return {}


# 递归收集网格世界 AABB（含旋转缩放），返回 {"has": bool, "aabb": AABB}
static func _collect_aabb(node: Node, xf: Transform3D) -> Dictionary:
	var out: Dictionary = {"has": false, "aabb": AABB()}
	var next: Transform3D = xf * node.transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.has = true
			out.aabb = next * mi.mesh.get_aabb()
	for c in node.get_children():
		var sub: Dictionary = _collect_aabb(c, next)
		if bool(sub.has):
			if bool(out.has):
				out.aabb = out.aabb.merge(sub.aabb)
			else:
				out.has = true
				out.aabb = sub.aabb
	return out


static func build_mag(weapon_id: String) -> MeshInstance3D:
	match weapon_id:
		"k9": return _mag_k9()
		"vx9": return _mag_vx9()
		"arc17": return _mag_arc17()
		"warden": return _mag_warden()
		"longshot": return _mag_longshot()
		"bruiser": return _mag_bruiser()
	return null


static func build_casing() -> MeshInstance3D:
	var brass := _m("metal_brass")
	var body := _cyl(brass, 0.0026, 0.0026, 0.014, Vector3.ZERO, Vector3.ZERO, 10, "Casing")
	body.add_child(_cyl(brass, 0.0026, 0.0014, 0.005, Vector3(0, 0.0092, 0), Vector3.ZERO, 10, "Neck"))
	body.add_child(_cyl(brass, 0.0031, 0.0026, 0.0015, Vector3(0, -0.0075, 0), Vector3.ZERO, 10, "Rim"))
	return body


static func get_ads_offset(weapon_id: String) -> Vector3:
	match weapon_id:
		"fang": return Vector3(0, -0.0105, -0.017)
		# 手枪机瞄对齐：实测 ADS 时准星线（机瞄顶）偏在屏幕中心下方
		# （k9 下 54px / pc 下 72px / pf 下 66px @720p ≈ 5900px/m），上移 viewmodel 使其与
		# 屏幕中心（实际弹着点）重合。
		"k9": return Vector3(0, 0.013, -0.019)
		"pc": return Vector3(0, 0.036, -0.019)
		"pf": return Vector3(0, 0.029, -0.019)
		"vx9": return Vector3(0, -0.0125, -0.022)
		"arc17": return Vector3(0, -0.013, -0.020)
		"warden": return Vector3(0, -0.012, -0.024)
		"longshot": return Vector3(0, -0.0135, -0.028)
		"bruiser": return Vector3(0, -0.012, -0.021)
		"thunder": return Vector3(0, 0.0, -0.008)
		"zclaw": return Vector3(0, -0.005, -0.012)
		"ra": return Vector3(0, -0.013, -0.02)
		"rb": return Vector3(0, -0.0135, -0.021)
		"sc": return Vector3(0, -0.0125, -0.022)
		"sf": return Vector3(0, -0.0125, -0.022)
		"sa": return Vector3(0, -0.012, -0.024)
		"sp": return Vector3(0, -0.012, -0.024)
		"sm": return Vector3(0, -0.014, -0.028)
		"sr": return Vector3(0, -0.0135, -0.026)
	return Vector3(0, -0.012, -0.02)


static func get_ads_fov(weapon_id: String) -> float:
	match weapon_id:
		"fang": return 56.0
		"k9": return 50.0
		"vx9": return 46.0
		"arc17": return 48.0
		"warden": return 40.0
		"longshot": return 22.0
		"bruiser": return 50.0
		"thunder": return 60.0
		"zclaw": return 60.0
		"pc": return 56.0
		"pf": return 52.0
		"ra": return 46.0
		"rb": return 40.0
		"sc": return 50.0
		"sf": return 52.0
		"sa": return 48.0
		"sp": return 45.0
		"sm": return 22.0
		"sr": return 28.0
	return 50.0


# ---------------- fang: 战术匕首（近战） ----------------
static func _build_fang(root: Node3D, muzzle: Node3D) -> void:
	var steel := _m("metal_light")
	var steel_dark := _m("metal_dark")
	var dark := _dark()
	var rubber := _m("rubber")

	root.add_child(_box(steel, Vector3(0.026, 0.005, 0.18), Vector3(0, 0.004, -0.11), Vector3.ZERO, "Blade"))
	root.add_child(_box(steel, Vector3(0.014, 0.005, 0.1), Vector3(0, 0.004, -0.25), Vector3.ZERO, "BladeTip"))
	root.add_child(_box(steel_dark, Vector3(0.004, 0.008, 0.15), Vector3(0, 0.01, -0.11), Vector3.ZERO, "Spine"))
	root.add_child(_box(steel_dark, Vector3(0.003, 0.002, 0.26), Vector3(0, -0.0005, -0.155), Vector3.ZERO, "Edge"))
	root.add_child(_box(dark, Vector3(0.05, 0.013, 0.013), Vector3(0, 0.0, -0.005), Vector3.ZERO, "Crossguard"))
	root.add_child(_box(rubber, Vector3(0.022, 0.024, 0.09), Vector3(0, -0.011, 0.045), Vector3.ZERO, "Handle"))
	root.add_child(_box(steel_dark, Vector3(0.024, 0.024, 0.012), Vector3(0, -0.011, 0.096), Vector3.ZERO, "Pommel"))
	root.add_child(_box(dark, Vector3(0.004, 0.014, 0.02), Vector3(0.009, -0.011, 0.045)))
	root.add_child(_box(dark, Vector3(0.004, 0.014, 0.02), Vector3(-0.009, -0.011, 0.045)))
	muzzle.position = Vector3(0, 0.004, -0.3)


# ---------------- k9: compact SMG (MP9) ----------------
static func _build_k9(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var poly := _m("plastic")
	var rubber := _m("rubber")
	var dark := _dark()

	root.add_child(_box(md, Vector3(0.046, 0.046, 0.32), Vector3(0, 0.01, -0.2), Vector3.ZERO, "Receiver"))
	root.add_child(_box(md, Vector3(0.034, 0.01, 0.3), Vector3(0, 0.043, -0.19), Vector3.ZERO, "TopCover"))
	root.add_child(_zl(md, 0.007, 0.13, Vector3(0, 0.006, -0.445), "Barrel"))
	root.add_child(_zl(md, 0.011, 0.018, Vector3(0, 0.006, -0.52), "MuzzleNut"))
	root.add_child(_box(poly, Vector3(0.04, 0.034, 0.12), Vector3(0, 0.004, -0.32), Vector3.ZERO, "Handguard"))
	root.add_child(_box(md, Vector3(0.012, 0.012, 0.09), Vector3(0, -0.023, -0.32), Vector3.ZERO, "Rail"))
	for i in 3:
		root.add_child(_box(dark, Vector3(0.012, 0.003, 0.006), Vector3(0, -0.019 - i * 0.006, -0.32)))
	for i in 5:
		root.add_child(_box(md, Vector3(0.008, 0.006, 0.012), Vector3(0, 0.05, -0.31 + i * 0.03), Vector3.ZERO, "Teeth"))
	root.add_child(_box(md, Vector3(0.02, 0.018, 0.018), Vector3(0, 0.04, 0.05), Vector3.ZERO, "Hinge"))
	# 枪托与枪体之间的金属连接杆（StrutR/L 改为单根中置杆，避免"两根平行杆"观感）
	root.add_child(_zl(md, 0.005, 0.15, Vector3(0, 0.042, 0.125), "StockStrut"))
	root.add_child(_box(rubber, Vector3(0.048, 0.058, 0.024), Vector3(0, 0.042, 0.2), Vector3(0.06, 0, 0), "Pad"))
	root.add_child(_box(poly, Vector3(0.034, 0.055, 0.042), Vector3(0, -0.032, -0.02), Vector3(-0.22, 0, 0), "Grip"))
	root.add_child(_box(dark, Vector3(0.035, 0.004, 0.034), Vector3(0, -0.05, -0.043), Vector3(-0.22, 0, 0)))
	root.add_child(_box(poly, Vector3(0.038, 0.032, 0.014), Vector3(0, -0.02, -0.065), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.022, 0.014, 0.01), Vector3(0, -0.022, -0.065)))
	root.add_child(_box(ml, Vector3(0.008, 0.016, 0.005), Vector3(0, -0.026, -0.06), Vector3.ZERO, "Trigger"))
	var mag := _mag_k9()
	mag.position = Vector3(0, -0.1, -0.1)
	mag.rotation = Vector3(-0.06, 0, 0)
	root.add_child(mag)
	root.add_child(_box(md, Vector3(0.004, 0.012, 0.004), Vector3(0, 0.056, -0.47), Vector3.ZERO, "FrontSight"))
	root.add_child(_zl(md, 0.009, 0.012, Vector3(0, 0.052, -0.47), "Hood"))
	root.add_child(_box(md, Vector3(0.01, 0.012, 0.028), Vector3(0, 0.05, 0.015), Vector3.ZERO, "RearSight"))
	root.add_child(_box(dark, Vector3(0.004, 0.008, 0.02), Vector3(0, 0.054, 0.02)))
	root.add_child(_box(dark, Vector3(0.002, 0.014, 0.05), Vector3(0.024, 0.032, -0.24), Vector3.ZERO, "EjectPort"))
	root.add_child(_cyl(md, 0.006, 0.006, 0.006, Vector3(0.027, 0.034, -0.26), Vector3(0, 0, PI * 0.5), 12, "EjectCover"))
	root.add_child(_cyl(md, 0.004, 0.004, 0.01, Vector3(0.028, 0.016, 0.005), Vector3(0, 0, PI * 0.5), 8, "Charge"))
	root.add_child(_box(md, Vector3(0.003, 0.008, 0.006), Vector3(0.024, -0.006, -0.045), Vector3.ZERO, "Selector"))
	root.add_child(_box(dark, Vector3(0.012, 0.002, 0.08), Vector3(0, 0.057, -0.05)))
	root.add_child(_box(ml, Vector3(0.004, 0.01, 0.008), Vector3(-0.022, -0.045, -0.08), Vector3.ZERO, "MagRelease"))
	muzzle.position = Vector3(0, 0.006, -0.53)


static func _mag_k9() -> MeshInstance3D:
	var ml := _m("metal_light")
	var md := _m("metal_dark")
	var dark := _dark()
	var body := _box(ml, Vector3(0.028, 0.115, 0.055), Vector3(0, -0.058, 0), Vector3.ZERO, "Mag")
	body.add_child(_box(md, Vector3(0.028, 0.1, 0.007), Vector3(0, -0.058, 0.025)))
	body.add_child(_box(md, Vector3(0.028, 0.1, 0.007), Vector3(0, -0.058, -0.025)))
	body.add_child(_box(dark, Vector3(0.024, 0.01, 0.045), Vector3(0, -0.085, 0)))
	body.add_child(_box(md, Vector3(0.03, 0.012, 0.058), Vector3(0, -0.12, 0), Vector3.ZERO, "Base"))
	return body


# ---------------- vx9: AK-style rifle ----------------
static func _build_vx9(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var wood := _m("wood_dark")
	var rubber := _m("rubber")
	var dark := _dark()

	root.add_child(_zl(md, 0.0075, 0.4, Vector3(0, 0.002, -0.42), "Barrel"))
	root.add_child(_zl(md, 0.013, 0.055, Vector3(0, 0.002, -0.648), "Brake"))
	root.add_child(_box(dark, Vector3(0.005, 0.011, 0.05), Vector3(0.0125, 0.002, -0.648)))
	root.add_child(_box(dark, Vector3(0.005, 0.011, 0.05), Vector3(-0.0125, 0.002, -0.648)))
	root.add_child(_box(md, Vector3(0.022, 0.026, 0.028), Vector3(0, 0.004, -0.56), Vector3.ZERO, "SightBlock"))
	root.add_child(_box(md, Vector3(0.003, 0.016, 0.004), Vector3(0, 0.024, -0.56), Vector3.ZERO, "Post"))
	root.add_child(_box(md, Vector3(0.004, 0.008, 0.008), Vector3(0.0095, 0.027, -0.56)))
	root.add_child(_box(md, Vector3(0.004, 0.008, 0.008), Vector3(-0.0095, 0.027, -0.56)))
	root.add_child(_box(md, Vector3(0.022, 0.03, 0.026), Vector3(0, 0.006, -0.5), Vector3.ZERO, "GasBlock"))
	root.add_child(_zl(md, 0.01, 0.24, Vector3(0, 0.035, -0.3), "GasTube"))
	root.add_child(_box(wood, Vector3(0.026, 0.034, 0.22), Vector3(0, 0.034, -0.3), Vector3.ZERO, "TopHand"))
	for i in 3:
		root.add_child(_box(dark, Vector3(0.022, 0.005, 0.008), Vector3(0, 0.03 + i * 0.008, -0.3)))
	root.add_child(_box(wood, Vector3(0.028, 0.026, 0.22), Vector3(0, -0.014, -0.3), Vector3.ZERO, "LowHand"))
	root.add_child(_box(dark, Vector3(0.028, 0.006, 0.02), Vector3(0, -0.027, -0.3)))
	root.add_child(_zl(ml, 0.0025, 0.46, Vector3(0, -0.032, -0.4), "CleanRod"))
	root.add_child(_box(md, Vector3(0.042, 0.048, 0.32), Vector3(0, 0.005, -0.02), Vector3.ZERO, "Receiver"))
	root.add_child(_box(md, Vector3(0.036, 0.005, 0.22), Vector3(0, 0.034, -0.05), Vector3.ZERO, "DustCover"))
	root.add_child(_box(md, Vector3(0.012, 0.022, 0.026), Vector3(0, 0.043, -0.15), Vector3.ZERO, "RearSight"))
	root.add_child(_box(dark, Vector3(0.004, 0.014, 0.016), Vector3(0, 0.048, -0.15)))
	root.add_child(_cyl(ml, 0.004, 0.004, 0.02, Vector3(0.028, 0.034, 0.02), Vector3(0, 0, PI * 0.5), 10, "BoltHandle"))
	root.add_child(_cyl(ml, 0.006, 0.006, 0.012, Vector3(0.037, 0.034, 0.02), Vector3(0, 0, PI * 0.5), 12, "BoltKnob"))
	root.add_child(_box(dark, Vector3(0.002, 0.016, 0.055), Vector3(0.023, 0.02, -0.02), Vector3.ZERO, "EjectPort"))
	root.add_child(_box(ml, Vector3(0.003, 0.012, 0.009), Vector3(0.023, 0.0, 0.06), Vector3.ZERO, "Selector"))
	root.add_child(_box(ml, Vector3(0.004, 0.007, 0.005), Vector3(0.023, 0.047, -0.3), Vector3.ZERO, "GasLever"))
	root.add_child(_box(_m("plastic"), Vector3(0.038, 0.034, 0.014), Vector3(0, -0.02, -0.015), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.022, 0.014, 0.01), Vector3(0, -0.022, -0.015)))
	root.add_child(_box(ml, Vector3(0.008, 0.015, 0.005), Vector3(0, -0.024, -0.018), Vector3.ZERO, "Trigger"))
	root.add_child(_box(wood, Vector3(0.028, 0.06, 0.042), Vector3(0, -0.045, 0.095), Vector3(0.22, 0, 0), "Grip"))
	root.add_child(_box(dark, Vector3(0.028, 0.005, 0.036), Vector3(0, -0.06, 0.127), Vector3(0.22, 0, 0)))
	root.add_child(_box(dark, Vector3(0.028, 0.005, 0.036), Vector3(0, -0.047, 0.134), Vector3(0.22, 0, 0)))
	root.add_child(_box(wood, Vector3(0.028, 0.058, 0.028), Vector3(0, -0.082, 0.128), Vector3(0.22, 0, 0), "GripBase"))
	var mag := _mag_vx9()
	mag.position = Vector3(0, -0.055, -0.16)
	mag.rotation = Vector3(-0.14, 0, 0)
	root.add_child(mag)
	root.add_child(_box(wood, Vector3(0.026, 0.046, 0.21), Vector3(0, 0.02, 0.2), Vector3(0.03, 0, 0), "Stock"))
	root.add_child(_box(wood, Vector3(0.022, 0.028, 0.06), Vector3(0, 0.038, 0.13), Vector3(0.03, 0, 0), "StockTaper"))
	root.add_child(_box(rubber, Vector3(0.028, 0.052, 0.012), Vector3(0, 0.02, 0.308), Vector3(0.03, 0, 0), "Butt"))
	root.add_child(_screw(ml, Vector3(0, 0.0, 0.31), Vector3.ZERO))
	root.add_child(_torus(md, 0.004, 0.0075, Vector3(-0.025, 0.0, 0.14), Vector3.ZERO, "Sling"))
	muzzle.position = Vector3(0, 0.002, -0.675)


static func _mag_vx9() -> MeshInstance3D:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var body := _box(md, Vector3(0.03, 0.08, 0.095), Vector3(0, -0.045, -0.005), Vector3(-0.14, 0, 0), "Mag")
	body.add_child(_box(md, Vector3(0.028, 0.07, 0.085), Vector3(0, -0.125, 0.008), Vector3(-0.28, 0, 0)))
	body.add_child(_box(md, Vector3(0.026, 0.06, 0.075), Vector3(0, -0.195, 0.028), Vector3(-0.42, 0, 0)))
	body.add_child(_box(_m("plastic"), Vector3(0.03, 0.018, 0.082), Vector3(0, -0.245, 0.052), Vector3(-0.5, 0, 0), "Base"))
	body.add_child(_box(ml, Vector3(0.007, 0.055, 0.08), Vector3(-0.014, -0.07, -0.012), Vector3(-0.14, 0, 0), "Spine"))
	body.add_child(_box(ml, Vector3(0.007, 0.05, 0.07), Vector3(-0.013, -0.145, 0.002), Vector3(-0.28, 0, 0)))
	return body


# ---------------- arc17: M4-style rifle ----------------
static func _build_arc17(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var poly := _m("plastic")
	var rubber := _m("rubber")
	var dark := _dark()

	root.add_child(_zl(md, 0.0065, 0.36, Vector3(0, 0.004, -0.43), "Barrel"))
	root.add_child(_zl(md, 0.0105, 0.06, Vector3(0, 0.004, -0.64), "FlashHider"))
	for i in 3:
		var a := i * PI / 3.0
		root.add_child(_box(dark, Vector3(0.006, 0.008, 0.052), Vector3(sin(a) * 0.0095, 0.004, -0.64), Vector3(0, a, 0)))
	root.add_child(_box(md, Vector3(0.004, 0.012, 0.004), Vector3(0, 0.032, -0.56), Vector3.ZERO, "FrontSight"))
	root.add_child(_box(md, Vector3(0.004, 0.007, 0.008), Vector3(0.0095, 0.033, -0.56)))
	root.add_child(_box(md, Vector3(0.004, 0.007, 0.008), Vector3(-0.0095, 0.033, -0.56)))
	root.add_child(_box(md, Vector3(0.022, 0.026, 0.024), Vector3(0, 0.005, -0.52), Vector3.ZERO, "GasBlock"))
	root.add_child(_zl(md, 0.014, 0.012, Vector3(0, 0.004, -0.235), "Delta"))
	root.add_child(_box(poly, Vector3(0.038, 0.038, 0.18), Vector3(0, 0.004, -0.235), Vector3.ZERO, "Handguard"))
	root.add_child(_box(md, Vector3(0.012, 0.01, 0.16), Vector3(0, 0.032, -0.235), Vector3.ZERO, "TopRail"))
	root.add_child(_box(md, Vector3(0.012, 0.01, 0.16), Vector3(0, -0.024, -0.235), Vector3.ZERO, "BotRail"))
	root.add_child(_box(md, Vector3(0.01, 0.012, 0.16), Vector3(-0.026, 0.004, -0.235), Vector3(0, PI * 0.5, 0), "LRail"))
	root.add_child(_box(md, Vector3(0.01, 0.012, 0.16), Vector3(0.026, 0.004, -0.235), Vector3(0, PI * 0.5, 0), "RRail"))
	for i in 3:
		root.add_child(_box(dark, Vector3(0.012, 0.002, 0.005), Vector3(0, 0.038 + i * 0.006, -0.235)))
	root.add_child(_box(md, Vector3(0.04, 0.042, 0.22), Vector3(0, 0.004, -0.03), Vector3.ZERO, "UpperRecv"))
	root.add_child(_box(md, Vector3(0.022, 0.007, 0.26), Vector3(0, 0.035, -0.03), Vector3.ZERO, "FlatTop"))
	for i in 6:
		root.add_child(_box(md, Vector3(0.006, 0.006, 0.014), Vector3(0, 0.042, -0.11 + i * 0.028)))
	root.add_child(_box(md, Vector3(0.02, 0.022, 0.09), Vector3(0, 0.058, -0.035), Vector3.ZERO, "CarryHandle"))
	root.add_child(_zl(md, 0.008, 0.012, Vector3(0, 0.062, 0.005), "Aperture"))
	root.add_child(_cyl(ml, 0.004, 0.004, 0.008, Vector3(0, 0.07, -0.075), Vector3.ZERO, 8, "Windage"))
	root.add_child(_cyl(ml, 0.0035, 0.0035, 0.02, Vector3(0.024, 0.04, 0.065), Vector3(0, 0, PI * 0.5), 8, "ChargeHandle"))
	root.add_child(_cyl(ml, 0.0055, 0.0055, 0.013, Vector3(0.033, 0.04, 0.065), Vector3(0, 0, PI * 0.5), 10, "ChargeKnob"))
	root.add_child(_box(md, Vector3(0.037, 0.038, 0.19), Vector3(0, -0.012, -0.02), Vector3.ZERO, "LowerRecv"))
	root.add_child(_box(md, Vector3(0.045, 0.026, 0.04), Vector3(0, -0.04, -0.06), Vector3(0, 0, -0.08), "Magwell"))
	root.add_child(_box(dark, Vector3(0.036, 0.012, 0.028), Vector3(0, -0.05, -0.062), Vector3(0, 0, -0.08)))
	root.add_child(_box(poly, Vector3(0.03, 0.062, 0.042), Vector3(0, -0.05, 0.075), Vector3(-0.12, 0, 0), "Grip"))
	root.add_child(_box(dark, Vector3(0.03, 0.004, 0.034), Vector3(0, -0.066, 0.102), Vector3(-0.12, 0, 0)))
	root.add_child(_box(dark, Vector3(0.03, 0.004, 0.034), Vector3(0, -0.048, 0.11), Vector3(-0.12, 0, 0)))
	root.add_child(_zl(md, 0.004, 0.17, Vector3(0.011, 0.028, 0.14), "StockRail"))
	root.add_child(_zl(md, 0.004, 0.17, Vector3(-0.011, 0.028, 0.14), "StockRailL"))
	root.add_child(_box(poly, Vector3(0.048, 0.058, 0.028), Vector3(0, 0.03, 0.225), Vector3.ZERO, "Butt"))
	root.add_child(_box(poly, Vector3(0.036, 0.014, 0.09), Vector3(0, 0.066, 0.17), Vector3.ZERO, "Cheek"))
	root.add_child(_cyl(dark, 0.003, 0.003, 0.006, Vector3(0.011, 0.012, 0.15), Vector3.ZERO, 8, "Hole1"))
	root.add_child(_cyl(dark, 0.003, 0.003, 0.006, Vector3(0.011, 0.012, 0.185), Vector3.ZERO, 8, "Hole2"))
	var mag := _mag_arc17()
	mag.position = Vector3(0, -0.08, -0.085)
	mag.rotation = Vector3(-0.03, 0, 0)
	root.add_child(mag)
	root.add_child(_box(dark, Vector3(0.002, 0.014, 0.05), Vector3(0.021, 0.012, -0.06), Vector3.ZERO, "EjectPort"))
	root.add_child(_box(md, Vector3(0.006, 0.012, 0.014), Vector3(0.024, 0.004, -0.035), Vector3(-0.15, 0, 0), "Deflector"))
	root.add_child(_box(md, Vector3(0.004, 0.008, 0.01), Vector3(-0.02, -0.02, -0.05), Vector3.ZERO, "BoltCatch"))
	root.add_child(_cyl(md, 0.0045, 0.0045, 0.007, Vector3(0.024, 0.02, -0.02), Vector3(0, 0, PI * 0.5), 8, "FwdAssist"))
	root.add_child(_box(ml, Vector3(0.003, 0.01, 0.007), Vector3(0.02, -0.015, 0.02), Vector3.ZERO, "Selector"))
	root.add_child(_cyl(ml, 0.0035, 0.0035, 0.008, Vector3(0.021, -0.02, -0.1), Vector3(0, 0, PI * 0.5), 8, "PinR"))
	root.add_child(_cyl(ml, 0.0035, 0.0035, 0.008, Vector3(-0.021, -0.02, -0.1), Vector3(0, 0, PI * 0.5), 8, "PinL"))
	root.add_child(_box(poly, Vector3(0.036, 0.03, 0.014), Vector3(0, -0.02, -0.035), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.02, 0.013, 0.01), Vector3(0, -0.022, -0.035)))
	root.add_child(_box(ml, Vector3(0.008, 0.014, 0.005), Vector3(0, -0.024, -0.04), Vector3.ZERO, "Trigger"))
	muzzle.position = Vector3(0, 0.004, -0.67)


static func _mag_arc17() -> MeshInstance3D:
	var poly := _m("plastic")
	var md := _m("metal_dark")
	var dark := _dark()
	var body := _box(poly, Vector3(0.026, 0.062, 0.085), Vector3(0, -0.031, 0), Vector3.ZERO, "Mag")
	body.add_child(_box(poly, Vector3(0.024, 0.028, 0.075), Vector3(0, -0.082, -0.004), Vector3(-0.22, 0, 0)))
	body.add_child(_box(md, Vector3(0.028, 0.058, 0.016), Vector3(0, -0.045, 0.038), Vector3.ZERO, "Spine"))
	body.add_child(_box(md, Vector3(0.028, 0.008, 0.09), Vector3(0, -0.102, 0.002), Vector3.ZERO, "Floor"))
	body.add_child(_box(dark, Vector3(0.003, 0.044, 0.06), Vector3(-0.0135, -0.044, 0)))
	body.add_child(_box(dark, Vector3(0.003, 0.044, 0.06), Vector3(0.0135, -0.044, 0)))
	return body


# ---------------- warden: AUG-style bullpup ----------------
static func _build_warden(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var olive := _m("paint_olive")
	var poly := _m("plastic")
	var rubber := _m("rubber")
	var dark := _dark()
	var lens := _emit(Color(0.3, 0.6, 1.0), 2.4)

	root.add_child(_zl(md, 0.008, 0.52, Vector3(0, 0.003, -0.46), "Barrel"))
	root.add_child(_zl(md, 0.014, 0.05, Vector3(0, 0.003, -0.745), "Brake"))
	root.add_child(_box(dark, Vector3(0.005, 0.012, 0.045), Vector3(0.0135, 0.003, -0.745)))
	root.add_child(_box(dark, Vector3(0.005, 0.012, 0.045), Vector3(-0.0135, 0.003, -0.745)))
	root.add_child(_box(md, Vector3(0.024, 0.028, 0.03), Vector3(0, 0.006, -0.6), Vector3.ZERO, "GasBlock"))
	root.add_child(_box(md, Vector3(0.004, 0.014, 0.004), Vector3(0, 0.034, -0.63), Vector3.ZERO, "Post"))
	root.add_child(_box(olive, Vector3(0.052, 0.055, 0.42), Vector3(0, 0.005, -0.05), Vector3.ZERO, "Receiver"))
	root.add_child(_box(md, Vector3(0.03, 0.008, 0.44), Vector3(0, 0.042, -0.05), Vector3.ZERO, "TopRail"))
	for i in 5:
		root.add_child(_box(md, Vector3(0.006, 0.006, 0.014), Vector3(0, 0.05, -0.14 + i * 0.05)))
	root.add_child(_box(olive, Vector3(0.046, 0.03, 0.26), Vector3(0, -0.016, -0.3), Vector3.ZERO, "Handguard"))
	root.add_child(_box(poly, Vector3(0.032, 0.1, 0.032), Vector3(0, -0.058, -0.28), Vector3(0.12, 0, 0), "Foregrip"))
	root.add_child(_box(dark, Vector3(0.034, 0.012, 0.034), Vector3(0, -0.11, -0.27), Vector3(0.12, 0, 0)))
	root.add_child(_box(poly, Vector3(0.034, 0.058, 0.044), Vector3(0, -0.048, 0.1), Vector3(-0.18, 0, 0), "Grip"))
	root.add_child(_box(poly, Vector3(0.04, 0.036, 0.016), Vector3(0, -0.024, -0.02), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.023, 0.016, 0.012), Vector3(0, -0.026, -0.02)))
	root.add_child(_box(ml, Vector3(0.008, 0.016, 0.005), Vector3(0, -0.03, -0.025), Vector3.ZERO, "Trigger"))
	root.add_child(_box(olive, Vector3(0.05, 0.052, 0.2), Vector3(0, 0.02, 0.19), Vector3.ZERO, "Stock"))
	root.add_child(_box(olive, Vector3(0.036, 0.012, 0.12), Vector3(0, 0.058, 0.16), Vector3.ZERO, "Cheek"))
	root.add_child(_box(rubber, Vector3(0.052, 0.058, 0.016), Vector3(0, 0.02, 0.29), Vector3.ZERO, "Butt"))
	root.add_child(_box(ml, Vector3(0.004, 0.012, 0.008), Vector3(0.028, -0.018, 0.08), Vector3.ZERO, "Selector"))
	root.add_child(_zl(md, 0.0165, 0.17, Vector3(0, 0.062, -0.02), "Scope"))
	root.add_child(_zl(md, 0.021, 0.014, Vector3(0, 0.062, -0.105), "Objective"))
	root.add_child(_cyl(lens, 0.018, 0.018, 0.004, Vector3(0, 0.062, -0.112), Vector3.ZERO, 16, "Lens"))
	root.add_child(_zl(md, 0.0135, 0.012, Vector3(0, 0.062, 0.068), "Eyepiece"))
	root.add_child(_cyl(md, 0.006, 0.006, 0.014, Vector3(0, 0.088, -0.03), Vector3.ZERO, 10, "Turret"))
	root.add_child(_cyl(md, 0.005, 0.005, 0.01, Vector3(0.023, 0.062, -0.02), Vector3(0, 0, PI * 0.5), 8, "Windage"))
	root.add_child(_box(md, Vector3(0.024, 0.012, 0.012), Vector3(0, 0.048, -0.08), Vector3.ZERO, "MountA"))
	root.add_child(_box(md, Vector3(0.024, 0.012, 0.012), Vector3(0, 0.048, 0.03), Vector3.ZERO, "MountB"))
	root.add_child(_box(dark, Vector3(0.024, 0.004, 0.06), Vector3(0, 0.052, -0.16), Vector3.ZERO, "EjectTop"))
	root.add_child(_cyl(ml, 0.005, 0.005, 0.012, Vector3(-0.03, 0.03, -0.12), Vector3(0, 0, PI * 0.5), 8, "ChargeHandle"))
	var mag := _mag_warden()
	mag.position = Vector3(0, -0.052, 0.055)
	mag.rotation = Vector3(-0.16, 0, 0)
	root.add_child(mag)
	root.add_child(_torus(md, 0.004, 0.0075, Vector3(-0.026, -0.01, -0.15), Vector3.ZERO, "Sling"))
	muzzle.position = Vector3(0, 0.003, -0.77)


static func _mag_warden() -> MeshInstance3D:
	var poly := _m("plastic")
	var md := _m("metal_dark")
	var body := _box(poly, Vector3(0.03, 0.075, 0.075), Vector3(0, -0.038, 0), Vector3.ZERO, "Mag")
	body.add_child(_box(md, Vector3(0.032, 0.01, 0.08), Vector3(0, -0.08, 0), Vector3.ZERO, "Floor"))
	return body


# ---------------- longshot: AWP-style sniper ----------------
static func _build_longshot(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var steel := _m("metal_blue")
	var wood := _m("wood")
	var poly := _m("plastic")
	var rubber := _m("rubber")
	var dark := _dark()
	var lens := _emit(Color(0.25, 0.55, 1.0), 2.6)

	root.add_child(_zl(md, 0.011, 0.62, Vector3(0, 0.0, -0.42), "Barrel"))
	root.add_child(_zl(md, 0.0135, 0.14, Vector3(0, 0.0, -0.18), "BarrelTaper"))
	root.add_child(_zl(md, 0.016, 0.06, Vector3(0, 0.0, -0.76), "Brake"))
	for i in 4:
		var a := i * PI / 2.0
		root.add_child(_box(dark, Vector3(0.005, 0.012, 0.052), Vector3(sin(a) * 0.015, 0.0, -0.76), Vector3(0, a, 0)))
	root.add_child(_box(md, Vector3(0.003, 0.008, 0.003), Vector3(0, 0.024, -0.62), Vector3.ZERO, "FrontSight"))
	root.add_child(_box(steel, Vector3(0.048, 0.062, 0.4), Vector3(0, 0.005, 0.04), Vector3.ZERO, "Receiver"))
	root.add_child(_box(dark, Vector3(0.002, 0.02, 0.07), Vector3(0.025, 0.02, 0.02), Vector3.ZERO, "EjectPort"))
	root.add_child(_box(steel, Vector3(0.022, 0.03, 0.045), Vector3(0, 0.0, -0.1), Vector3.ZERO, "Chassis"))
	root.add_child(_cyl(ml, 0.0045, 0.0045, 0.035, Vector3(-0.028, 0.03, 0.14), Vector3(0, 0, PI * 0.5), 10, "BoltHandle"))
	root.add_child(_sph(ml, 0.0085, Vector3(-0.052, 0.03, 0.14), "BoltKnob"))
	root.add_child(_zl(ml, 0.02, 0.05, Vector3(0, 0.005, 0.25), "Bolt"))
	root.add_child(_zl(md, 0.017, 0.34, Vector3(0, 0.075, -0.04), "Scope"))
	root.add_child(_zl(md, 0.024, 0.03, Vector3(0, 0.075, -0.22), "Hood"))
	root.add_child(_cyl(lens, 0.019, 0.019, 0.005, Vector3(0, 0.075, -0.236), Vector3.ZERO, 18, "Lens"))
	root.add_child(_zl(md, 0.015, 0.02, Vector3(0, 0.075, 0.135), "Eyepiece"))
	for i in 3:
		root.add_child(_cyl(md, 0.0065, 0.0065, 0.016, Vector3(0, 0.102, -0.06 + i * 0.06), Vector3.ZERO, 10, "Turret"))
	root.add_child(_cyl(md, 0.005, 0.005, 0.012, Vector3(-0.026, 0.075, -0.02), Vector3(0, 0, PI * 0.5), 8, "Windage"))
	root.add_child(_box(md, Vector3(0.026, 0.014, 0.016), Vector3(0, 0.056, -0.13), Vector3.ZERO, "MountA"))
	root.add_child(_box(md, Vector3(0.026, 0.014, 0.016), Vector3(0, 0.056, 0.03), Vector3.ZERO, "MountB"))
	root.add_child(_box(wood, Vector3(0.05, 0.062, 0.26), Vector3(0, 0.012, 0.27), Vector3.ZERO, "Stock"))
	root.add_child(_box(wood, Vector3(0.038, 0.02, 0.13), Vector3(0, 0.056, 0.22), Vector3.ZERO, "Cheek"))
	root.add_child(_box(rubber, Vector3(0.052, 0.068, 0.015), Vector3(0, 0.012, 0.4), Vector3.ZERO, "Butt"))
	root.add_child(_screw(ml, Vector3(0, 0.05, 0.33), Vector3.ZERO))
	root.add_child(_box(poly, Vector3(0.044, 0.04, 0.016), Vector3(0, -0.024, 0.05), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.026, 0.018, 0.012), Vector3(0, -0.026, 0.05)))
	root.add_child(_box(ml, Vector3(0.009, 0.017, 0.005), Vector3(0, -0.028, 0.045), Vector3.ZERO, "Trigger"))
	var mag := _mag_longshot()
	mag.position = Vector3(0, -0.045, -0.05)
	root.add_child(mag)
	root.add_child(_zl(md, 0.004, 0.2, Vector3(0.012, -0.035, -0.15), "BipodR"))
	root.add_child(_zl(md, 0.004, 0.2, Vector3(-0.012, -0.035, -0.15), "BipodL"))
	root.add_child(_box(md, Vector3(0.008, 0.008, 0.012), Vector3(0.012, -0.035, -0.255), Vector3.ZERO, "FootR"))
	root.add_child(_box(md, Vector3(0.008, 0.008, 0.012), Vector3(-0.012, -0.035, -0.255), Vector3.ZERO, "FootL"))
	root.add_child(_torus(md, 0.004, 0.007, Vector3(0.026, 0.0, 0.2), Vector3.ZERO, "SlingR"))
	root.add_child(_torus(md, 0.004, 0.007, Vector3(-0.026, 0.0, 0.2), Vector3.ZERO, "SlingL"))
	muzzle.position = Vector3(0, 0.0, -0.79)


static func _mag_longshot() -> MeshInstance3D:
	var md := _m("metal_dark")
	var dark := _dark()
	var body := _box(md, Vector3(0.021, 0.032, 0.06), Vector3(0, -0.016, 0), Vector3.ZERO, "Mag")
	body.add_child(_box(dark, Vector3(0.017, 0.018, 0.05), Vector3(0, -0.02, 0)))
	body.add_child(_box(md, Vector3(0.023, 0.006, 0.062), Vector3(0, -0.034, 0), Vector3.ZERO, "Floor"))
	return body


# ---------------- bruiser: M249-style LMG ----------------
static func _build_bruiser(root: Node3D, muzzle: Node3D) -> void:
	var md := _m("metal_dark")
	var ml := _m("metal_light")
	var poly := _m("plastic")
	var rubber := _m("rubber")
	var dark := _dark()

	root.add_child(_zl(md, 0.009, 0.55, Vector3(0, 0.008, -0.33), "Barrel"))
	root.add_child(_zl(md, 0.0135, 0.05, Vector3(0, 0.008, -0.63), "Booster"))
	root.add_child(_box(ml, Vector3(0.03, 0.032, 0.38), Vector3(0, 0.008, -0.31), Vector3.ZERO, "HeatShield"))
	for i in 4:
		root.add_child(_box(dark, Vector3(0.004, 0.014, 0.006), Vector3(0.015, 0.008, -0.4 + i * 0.055)))
		root.add_child(_box(dark, Vector3(0.004, 0.014, 0.006), Vector3(-0.015, 0.008, -0.4 + i * 0.055)))
	root.add_child(_zl(md, 0.005, 0.45, Vector3(0, -0.008, -0.33), "GasTube"))
	root.add_child(_box(md, Vector3(0.004, 0.014, 0.004), Vector3(0, 0.042, -0.55), Vector3.ZERO, "FrontSight"))
	root.add_child(_box(md, Vector3(0.004, 0.008, 0.008), Vector3(0.0095, 0.043, -0.55)))
	root.add_child(_box(md, Vector3(0.004, 0.008, 0.008), Vector3(-0.0095, 0.043, -0.55)))
	root.add_child(_box(md, Vector3(0.014, 0.02, 0.03), Vector3(0, 0.048, -0.02), Vector3.ZERO, "RearSight"))
	root.add_child(_zl(md, 0.005, 0.006, Vector3(0, 0.05, -0.005), "Aperture"))
	root.add_child(_box(md, Vector3(0.052, 0.058, 0.4), Vector3(0, 0.012, 0.06), Vector3.ZERO, "Receiver"))
	root.add_child(_box(md, Vector3(0.046, 0.006, 0.3), Vector3(0, 0.047, 0.02), Vector3.ZERO, "TopCover"))
	for i in 3:
		root.add_child(_box(md, Vector3(0.006, 0.005, 0.012), Vector3(0, 0.054, -0.03 + i * 0.03)))
	root.add_child(_box(md, Vector3(0.02, 0.012, 0.13), Vector3(0, 0.066, 0.04), Vector3.ZERO, "CarryHandle"))
	root.add_child(_box(poly, Vector3(0.058, 0.095, 0.11), Vector3(0, -0.05, -0.045), Vector3.ZERO, "BoxMag"))
	root.add_child(_box(dark, Vector3(0.05, 0.03, 0.004), Vector3(0, -0.05, 0.003), Vector3.ZERO, "MagWindow"))
	root.add_child(_box(poly, Vector3(0.06, 0.012, 0.115), Vector3(0, -0.103, -0.045), Vector3.ZERO, "MagBase"))
	root.add_child(_box(dark, Vector3(0.012, 0.008, 0.02), Vector3(-0.034, -0.02, -0.055), Vector3(0.5, 0, 0), "Belt1"))
	root.add_child(_box(dark, Vector3(0.012, 0.008, 0.02), Vector3(-0.052, -0.025, -0.06), Vector3(0.9, 0, 0), "Belt2"))
	root.add_child(_box(poly, Vector3(0.034, 0.06, 0.046), Vector3(0, -0.05, 0.16), Vector3(-0.18, 0, 0), "Grip"))
	root.add_child(_box(dark, Vector3(0.034, 0.004, 0.04), Vector3(0, -0.066, 0.188), Vector3(-0.18, 0, 0)))
	root.add_child(_box(poly, Vector3(0.046, 0.04, 0.016), Vector3(0, -0.028, 0.07), Vector3.ZERO, "Guard"))
	root.add_child(_box(dark, Vector3(0.026, 0.018, 0.012), Vector3(0, -0.03, 0.07)))
	root.add_child(_box(ml, Vector3(0.009, 0.017, 0.005), Vector3(0, -0.034, 0.065), Vector3.ZERO, "Trigger"))
	root.add_child(_box(poly, Vector3(0.05, 0.058, 0.17), Vector3(0, 0.02, 0.24), Vector3.ZERO, "Stock"))
	root.add_child(_box(rubber, Vector3(0.052, 0.062, 0.016), Vector3(0, 0.02, 0.325), Vector3.ZERO, "Butt"))
	root.add_child(_box(poly, Vector3(0.03, 0.09, 0.03), Vector3(0, -0.055, -0.1), Vector3(0.1, 0, 0), "FrontGrip"))
	root.add_child(_zl(md, 0.004, 0.16, Vector3(0.012, -0.025, -0.26), "BipodR"))
	root.add_child(_zl(md, 0.004, 0.16, Vector3(-0.012, -0.025, -0.26), "BipodL"))
	root.add_child(_box(md, Vector3(0.008, 0.008, 0.01), Vector3(0.012, -0.025, -0.345), Vector3.ZERO, "FootR"))
	root.add_child(_box(md, Vector3(0.008, 0.008, 0.01), Vector3(-0.012, -0.025, -0.345), Vector3.ZERO, "FootL"))
	root.add_child(_box(dark, Vector3(0.002, 0.02, 0.08), Vector3(0.027, 0.02, 0.02), Vector3.ZERO, "EjectPort"))
	root.add_child(_box(md, Vector3(0.016, 0.02, 0.08), Vector3(-0.035, 0.01, 0.02), Vector3.ZERO, "FeedTray"))
	root.add_child(_cyl(md, 0.005, 0.005, 0.01, Vector3(0.03, 0.035, 0.1), Vector3(0, 0, PI * 0.5), 8, "ChargeHandle"))
	root.add_child(_box(ml, Vector3(0.003, 0.01, 0.007), Vector3(0.027, -0.008, 0.12), Vector3.ZERO, "Selector"))
	muzzle.position = Vector3(0, 0.008, -0.655)


static func _mag_bruiser() -> MeshInstance3D:
	var poly := _m("plastic")
	var md := _m("metal_dark")
	var body := _box(poly, Vector3(0.058, 0.095, 0.11), Vector3(0, -0.048, 0), Vector3.ZERO, "BoxMag")
	body.add_child(_box(_dark(), Vector3(0.05, 0.03, 0.004), Vector3(0, -0.05, 0.055), Vector3.ZERO, "Window"))
	body.add_child(_box(poly, Vector3(0.06, 0.012, 0.115), Vector3(0, -0.1, 0), Vector3.ZERO, "Base"))
	body.add_child(_box(md, Vector3(0.014, 0.085, 0.008), Vector3(-0.031, -0.048, 0), Vector3.ZERO, "Spine"))
	return body


# ---------------- thunder: M67 frag grenade ----------------
static func _build_thunder(root: Node3D, muzzle: Node3D) -> void:
	var olive := _m("paint_olive")
	var darkolive := _solid(Color("3b3f26"), 0.1, 0.8)
	var steel := _m("metal_light")
	var dark := _dark()

	var body := _cyl(olive, 0.042, 0.042, 0.084, Vector3(0, 0, 0), Vector3.ZERO, 12, "Body")
	root.add_child(body)
	root.add_child(_sph(olive, 0.03, Vector3(0, 0.046, 0), "Cap"))
	root.add_child(_sph(olive, 0.03, Vector3(0, -0.046, 0), "Base"))
	for i in 12:
		var a := i * PI / 6.0
		var p := Vector3(sin(a) * 0.0405, 0, cos(a) * 0.0405)
		root.add_child(_box(darkolive, Vector3(0.004, 0.07, 0.008), p, Vector3(0, -a + PI * 0.5, 0), "Ridge"))
	for i in 3:
		root.add_child(_zl(darkolive, 0.0432, 0.004, Vector3(0, -0.028 + i * 0.028, 0), "Ring"))
	root.add_child(_cyl(steel, 0.014, 0.014, 0.022, Vector3(0, 0.064, 0), Vector3.ZERO, 12, "Fuse"))
	root.add_child(_cyl(steel, 0.006, 0.006, 0.008, Vector3(0, 0.08, 0), Vector3.ZERO, 8, "FuseTop"))
	root.add_child(_box(steel, Vector3(0.018, 0.004, 0.052), Vector3(0, 0.052, -0.002), Vector3(0.1, 0, 0), "Spoon"))
	root.add_child(_box(steel, Vector3(0.018, 0.02, 0.007), Vector3(0, 0.042, -0.023), Vector3(0.35, 0, 0), "SpoonBend"))
	root.add_child(_torus(steel, 0.005, 0.0085, Vector3(0, 0.062, -0.02), Vector3(PI * 0.5, 0, 0), "PinRing"))
	root.add_child(_cyl(steel, 0.0018, 0.0018, 0.032, Vector3(0.011, 0.062, -0.02), Vector3(0, 0, PI * 0.5), 6, "Pin"))
	root.add_child(_box(dark, Vector3(0.03, 0.002, 0.02), Vector3(0, 0.044, 0.018), Vector3.ZERO, "Stencil"))
	muzzle.position = Vector3(0, 0.062, 0)


# ---------------- zclaw: zombie claws ----------------
static func _build_zclaw(root: Node3D, muzzle: Node3D) -> void:
	var flesh := _m("paint_olive")
	var bone := _m("bone")
	var bone_dark := _solid(Color("a8a08c"), 0.0, 0.55)
	var vein := _emit(Color(0.35, 0.9, 0.35), 1.4)
	var dark := _dark()

	root.add_child(_sph(flesh, 0.055, Vector3(0, -0.01, 0.02), "Wrist"))
	root.add_child(_zl(flesh, 0.045, 0.1, Vector3(0, -0.01, 0.1), "Arm"))
	root.add_child(_box(flesh, Vector3(0.05, 0.035, 0.05), Vector3(0, 0.015, -0.01), Vector3.ZERO, "Palm"))
	root.add_child(_box(dark, Vector3(0.054, 0.007, 0.02), Vector3(0, -0.032, 0.06), Vector3.ZERO, "Strap"))
	root.add_child(_sph(bone, 0.012, Vector3(-0.015, 0.028, -0.025), "KnuckleL"))
	root.add_child(_sph(bone, 0.012, Vector3(0.015, 0.028, -0.025), "KnuckleR"))
	root.add_child(_sph(bone, 0.011, Vector3(0, 0.031, -0.028), "KnuckleM"))
	for i in 3:
		var fx := float(i) - 1.0
		var fan := Vector3(0, 0, fx * 0.45)
		var base := _cyl(bone, 0.006, 0.005, 0.055, Vector3(fx * 0.017, 0.04, 0.0), fan + Vector3(-0.3, 0, 0), 10, "ClawBase%d" % i)
		root.add_child(base)
		root.add_child(_cyl(bone, 0.0045, 0.0038, 0.05, Vector3(fx * 0.017, 0.082, -0.02), fan + Vector3(-0.55, 0, 0), 10, "ClawMid%d" % i))
		root.add_child(_cyl(bone_dark, 0.0036, 0.0022, 0.045, Vector3(fx * 0.017, 0.122, -0.05), fan + Vector3(-0.75, 0, 0), 10, "ClawTip%d" % i))
	root.add_child(_cyl(vein, 0.0025, 0.0025, 0.06, Vector3(0, -0.005, 0.03), Vector3(0.5, 0, 0), 6, "Vein1"))
	root.add_child(_cyl(vein, 0.0025, 0.0025, 0.055, Vector3(-0.015, -0.012, 0.05), Vector3(0.4, 0.3, 0), 6, "Vein2"))
	root.add_child(_cyl(vein, 0.0025, 0.0025, 0.05, Vector3(0.015, -0.012, 0.05), Vector3(0.4, -0.3, 0), 6, "Vein3"))
	root.add_child(_sph(bone, 0.008, Vector3(0.024, 0.02, -0.012), "Wart"))
	muzzle.position = Vector3(0, 0.164, -0.085)
