# MapBuilder: turns map data into a detailed 3D scene. Walls get beveled caps, baseboards,
# corner pillars; props get PBR materials from MaterialLib; lighting from data.
class_name MapBuilder
extends RefCounted

static var _map_theme: Dictionary = {}
static var _compat: int = -1
# Web（Compatibility 渲染器）网格合并：850+ 独立 MeshInstance3D → 每材质一个 ArrayMesh，
# draw call 从 ~900 降到 ~40（WebGL 单线程+低端 GPU 的帧率关键）。桌面保持独立节点。
static var _web_merge: bool = false
static var _merge_buckets: Dictionary = {}  # mat_instance_id -> {mat, items: [{mesh, xform}]}

# Compatibility 渲染器（Web 专用）缺少间接光，点光源需要更强能量才能达到桌面观感。
static func _light_boost() -> float:
	if _compat < 0:
		_compat = 1 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	return 1.5 if _compat == 1 else 1.0


static func build(root: Node3D, map: Dictionary) -> void:
	_map_theme = _theme_for(map)
	_web_merge = OS.has_feature("web")
	_build_ground(root, map)
	for c in map.get("colliders", []):
		_build_collider(root, c)
	for site in map.get("sites", []):
		_build_site(root, site)
	for prop in map.get("props", []):
		if prop.type == "light":
			_build_light(root, prop)
	for d in map.get("deco", []):
		_build_deco(root, d)
	if not OS.has_feature("web"):
		# Web 性能：跳过远处地平线装饰（岩石/塔楼 20+ 网格），减少 draw call
		_build_distant_scenery(root, map)
	_flush_merge(root)


static func _theme_for(map: Dictionary) -> Dictionary:
	var id: String = map.get("id", "cinder")
	match id:
		"cinder":
			return {
				"floor": "sand", "floor_scale": 6.0, "wall": "plaster", "wall_scale": 2.0,
				"wall_dark": "concrete", "crate": "wood_crate", "metal": "metal_rust",
				"accent": "paint_yellow", "trim": "concrete_dark", "roof_light": false,
			}
		"containment":
			return {
				"floor": "tile", "floor_scale": 3.0, "wall": "concrete_panel", "wall_scale": 1.5,
				"wall_dark": "metal_dark", "crate": "metal_blue", "metal": "metal_dark",
				"accent": "paint_yellow", "trim": "metal_dark",
			}
		"obsidian":
			return {
				"floor": "asphalt", "floor_scale": 4.0, "wall": "concrete", "wall_scale": 2.0,
				"wall_dark": "concrete_dark", "crate": "wood_crate", "metal": "metal_dark",
				"accent": "paint_red", "trim": "concrete_dark",
			}
	return {"floor": "concrete", "floor_scale": 4.0, "wall": "plaster", "wall_scale": 2.0,
		"wall_dark": "concrete", "crate": "wood_crate", "metal": "metal_rust",
		"accent": "paint_yellow", "trim": "concrete_dark"}


static func _mat(id: String, scale: float = 1.0) -> Material:
	return MaterialLib.get_mat(id, scale)


static func _add(root: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, cast_shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> MeshInstance3D:
	if _web_merge:
		# Web：收集到合并桶（按材质实例分桶，UV 缩放已烘焙进材质 key）
		var mid: int = material.get_instance_id()
		if not _merge_buckets.has(mid):
			_merge_buckets[mid] = {"mat": material, "items": []}
		_merge_buckets[mid].items.append({"mesh": mesh, "xform": Transform3D(Basis.from_euler(rot), pos)})
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = cast_shadow
	root.add_child(mi)
	return mi


# 提交合并桶：每材质一个 ArrayMesh（顶点烘焙实例变换）。
# Web（Compatibility）关闭阴影：省掉阴影 pass 的全部 draw call，是 Web 帧率关键。
static func _flush_merge(root: Node3D) -> void:
	if not _web_merge or _merge_buckets.is_empty():
		_merge_buckets.clear()
		return
	for mid in _merge_buckets:
		var bucket: Dictionary = _merge_buckets[mid]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for item in bucket.items:
			st.append_from(item.mesh, 0, item.xform)
		st.set_material(bucket.mat)
		var arr_mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = arr_mesh
		mi.material_override = bucket.mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_merge_buckets.clear()


static func _box(root: Node3D, size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(root, b, material, pos, rot)


static func _cyl(root: Node3D, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return _add(root, m, material, pos, rot)


static func _sphere(root: Node3D, r: float, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, radial: int = 16, rings: int = 8) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = radial
	m.rings = rings
	return _add(root, m, material, pos, rot)


static func _build_ground(root: Node3D, map: Dictionary) -> void:
	var t: Dictionary = _map_theme
	var sz: Vector2 = map.size
	var ground := BoxMesh.new()
	ground.size = Vector3(sz.x * 2.2, 0.4, sz.y * 2.2)
	_add(root, ground, _mat(t.floor, t.floor_scale), Vector3(0, -0.2, 0))
	# outer apron (dark, prevents sky bleed at map edge)
	var apron := BoxMesh.new()
	apron.size = Vector3(sz.x * 2.6, 0.5, sz.y * 2.6)
	_add(root, apron, _mat("gravel", 10.0), Vector3(0, -0.55, 0))
	# inner trim ring right at the playable border
	var trim := BoxMesh.new()
	trim.size = Vector3(sz.x * 2.2, 0.06, sz.y * 2.2)
	_add(root, trim, _mat(t.trim, 8.0), Vector3(0, 0.03, 0))


static func _build_collider(root: Node3D, c: Dictionary) -> void:
	var t: Dictionary = _map_theme
	var mn: Vector3 = c.min
	var mx: Vector3 = c.max
	var size: Vector3 = mx - mn
	var center: Vector3 = (mn + mx) * 0.5
	var type: String = c.get("type", "wall")

	# derived prop colliders render as their deco mesh instead
	if type.begins_with("deco_"):
		return

	match type:
		"wall":
			# main slab
			_box(root, size, _mat(t.wall, t.wall_scale), center)
			# top cap
			var cap := BoxMesh.new()
			cap.size = Vector3(size.x + 0.12, 0.18, size.z + 0.12)
			_add(root, cap, _mat(t.trim, 3.0), center + Vector3(0, size.y * 0.5 + 0.06, 0))
			# baseboard
			if size.y > 1.0:
				var base := BoxMesh.new()
				base.size = Vector3(size.x + 0.1, 0.16, size.z + 0.1)
				_add(root, base, _mat(t.wall_dark, 4.0), center + Vector3(0, -size.y * 0.5 + 0.08, 0))
			# corner pillars for long walls
			if size.x >= 4.0 or size.z >= 4.0:
				var ph: float = min(size.y, 4.0)
				var pw: float = 0.3
				var px: float = max(size.x, 0.4)
				var pz: float = max(size.z, 0.4)
				_box(root, Vector3(pw, ph, pw), _mat(t.wall_dark, 2.0), center + Vector3(-px * 0.5 + pw * 0.5, -size.y * 0.5 + ph * 0.5, -pz * 0.5 + pw * 0.5))
				_box(root, Vector3(pw, ph, pw), _mat(t.wall_dark, 2.0), center + Vector3(px * 0.5 - pw * 0.5, -size.y * 0.5 + ph * 0.5, -pz * 0.5 + pw * 0.5))
				_box(root, Vector3(pw, ph, pw), _mat(t.wall_dark, 2.0), center + Vector3(-px * 0.5 + pw * 0.5, -size.y * 0.5 + ph * 0.5, pz * 0.5 - pw * 0.5))
				_box(root, Vector3(pw, ph, pw), _mat(t.wall_dark, 2.0), center + Vector3(px * 0.5 - pw * 0.5, -size.y * 0.5 + ph * 0.5, pz * 0.5 - pw * 0.5))
		"crate":
			var m: Material = _mat(t.crate, 1.0)
			_box(root, size, m, center)
			var corner: Material = MaterialLib.solid(Color("3a3f45"), 0.6, 0.5)
			var cw: float = max(size.x, 0.4)
			var cd: float = max(size.z, 0.4)
			var cs := 0.07
			for sx2 in [-1.0, 1.0]:
				for sz2 in [-1.0, 1.0]:
					_box(root, Vector3(cs, size.y, cs), corner,
						center + Vector3(sx2 * cw * 0.5, 0, sz2 * cd * 0.5))
			# top rim
			var rim := BoxMesh.new()
			rim.size = Vector3(cw + 0.04, 0.06, cd + 0.04)
			_add(root, rim, MaterialLib.solid(Color("5a4a32"), 0.0, 0.8), center + Vector3(0, size.y * 0.5 + 0.03, 0))
		"barrel":
			var r: float = max(0.4, min(size.x, size.z) * 0.5)
			var h: float = max(0.6, size.y)
			var body: Material = _mat("metal_blue" if int(center.x * 7 + center.z * 13) % 3 != 0 else "metal_rust", 1.0)
			_cyl(root, r, h, body, center + Vector3(0, h * 0.5, 0))
			var band: Material = MaterialLib.solid(Color("2a2d31"), 0.7, 0.45)
			_cyl(root, r + 0.012, 0.07, band, center + Vector3(0, h * 0.25, 0))
			_cyl(root, r + 0.012, 0.07, band, center + Vector3(0, h * 0.6, 0))
			_cyl(root, r + 0.02, 0.05, band, center + Vector3(0, h, 0))
		"pillar":
			var r: float = max(0.4, min(size.x, size.z) * 0.5)
			var h: float = max(0.8, size.y)
			_cyl(root, r, h, _mat(t.wall_dark, 1.5), center + Vector3(0, h * 0.5, 0))
			_cyl(root, r + 0.08, 0.22, _mat(t.trim, 2.0), center + Vector3(0, h + 0.11, 0))
			_cyl(root, r + 0.05, 0.12, _mat(t.trim, 2.0), center + Vector3(0, -0.06, 0))
		"step":
			_box(root, size, _mat(t.wall, t.wall_scale), center)
			var lip := BoxMesh.new()
			lip.size = Vector3(size.x + 0.02, 0.05, 0.12)
			_add(root, lip, _mat(t.wall_dark, 2.0), center + Vector3(0, -size.y * 0.5 + 0.03, size.z * 0.5 - 0.06))
		"floor":
			# elevated walkway: slab + skirt + supports
			var slab := BoxMesh.new()
			slab.size = Vector3(size.x, size.y, size.z)
			_add(root, slab, _mat(t.floor, t.floor_scale), center)
			# emissive strip light on the underside (office-light look)
			var strip := BoxMesh.new()
			strip.size = Vector3(min(size.x - 0.4, 3.0), 0.05, min(size.z - 0.4, 0.5))
			var strip_mat: Material = MaterialLib.emissive(Color("e8f4ff"), 2.8)
			if t.floor == "tile":
				strip_mat = MaterialLib.emissive(Color("e0ffee"), 3.2)
			_add(root, strip, strip_mat, center + Vector3(0, -size.y * 0.5 - 0.03, 0), Vector3.ZERO, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var skirt := BoxMesh.new()
			skirt.size = Vector3(size.x + 0.1, 0.25, size.z + 0.1)
			_add(root, skirt, _mat(t.wall_dark, 3.0), center + Vector3(0, -size.y * 0.5 - 0.12, 0))
			# edge beam on long sides
			var beam := BoxMesh.new()
			beam.size = Vector3(size.x, 0.14, 0.16)
			_add(root, beam, _mat(t.metal, 2.0), center + Vector3(0, -size.y * 0.5 - 0.06, size.z * 0.5 - 0.08))
			beam.size = Vector3(size.x, 0.14, 0.16)
			_add(root, beam, _mat(t.metal, 2.0), center + Vector3(0, -size.y * 0.5 - 0.06, -size.z * 0.5 + 0.08))
			# supports
			for i in range(int(max(size.x, size.z) / 4.0) + 1):
				var sx3: float = -size.x * 0.5 + 2.0 + i * 4.0
				_box(root, Vector3(0.3, size.y + 0.5, 0.3), _mat(t.wall_dark, 1.0), center + Vector3(clamp(sx3, -size.x * 0.5 + 0.3, size.x * 0.5 - 0.3), -0.25, 0))
		"ceiling":
			var slab2 := BoxMesh.new()
			slab2.size = Vector3(size.x, size.y, size.z)
			_add(root, slab2, _mat(t.wall_dark, 3.0), center)
			# strip lights on the underside (skipped for outdoor town roofs)
			if _map_theme.get("roof_light", true):
				var light_mat: Material = MaterialLib.emissive(Color("fff3d0"), 3.5)
				var strips: int = max(2, int(size.x / 6.0))
				for i in range(strips):
					var sx4: float = -size.x * 0.5 + (i + 0.5) * size.x / strips
					var strip := BoxMesh.new()
					strip.size = Vector3(0.3, 0.04, size.z - 1.0)
					_add(root, strip, light_mat, center + Vector3(sx4, -size.y * 0.5 - 0.02, 0))
		_:
			_box(root, size, _mat(t.wall, t.wall_scale), center)


static func _build_site(root: Node3D, site: Dictionary) -> void:
	var pos: Vector3 = site.pos
	var radius: float = float(site.get("radius", 2.6))
	var color: Color = site.color
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color.a = 0.85
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 2.0
	var ring := CylinderMesh.new()
	ring.top_radius = radius
	ring.bottom_radius = radius - 0.28
	ring.height = 0.05
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = ring_mat
	ring_mi.position = pos + Vector3(0, 0.06, 0)
	root.add_child(ring_mi)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = color
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color.a = 0.12
	var glow := CylinderMesh.new()
	glow.top_radius = radius
	glow.bottom_radius = radius
	glow.height = 0.03
	var glow_mi := MeshInstance3D.new()
	glow_mi.mesh = glow
	glow_mi.material_override = glow_mat
	glow_mi.position = pos + Vector3(0, 0.05, 0)
	root.add_child(glow_mi)
	# 竖直光柱：从地面到 4m 高的半透明发光柱，隔墙/屋顶也能看到安放点标记。
	# 原来只有贴地 5cm 的环，室内安放点（如 Cinder B 点）被墙和屋顶挡住根本看不到。
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = color
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color.a = 0.16
	beam_mat.emission_enabled = true
	beam_mat.emission = color
	beam_mat.emission_energy_multiplier = 1.6
	beam_mat.no_depth_test = false
	var beam := CylinderMesh.new()
	beam.top_radius = 0.14
	beam.bottom_radius = 0.14
	beam.height = 4.0
	var beam_mi := MeshInstance3D.new()
	beam_mi.mesh = beam
	beam_mi.material_override = beam_mat
	beam_mi.position = pos + Vector3(0, 2.0, 0)
	beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam_mi)
	# corner beacons
	for i in 4:
		var a: float = i * PI / 2.0 + PI / 4.0
		var bp := pos + Vector3(cos(a) * radius * 0.55, 0, sin(a) * radius * 0.55)
		var beacon := BoxMesh.new()
		beacon.size = Vector3(0.5, 0.07, 0.5)
		_add(root, beacon, MaterialLib.emissive(color, 4.0), bp + Vector3(0, 0.09, 0))
	# beacon light
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6 * _light_boost()
	light.omni_range = 9.0
	light.position = pos + Vector3(0, 3.2, 0)
	root.add_child(light)
	# floating beacon orb
	var orb := SphereMesh.new()
	orb.radius = 0.09
	orb.height = 0.18
	_add(root, orb, MaterialLib.emissive(color, 5.0), pos + Vector3(0, 3.2, 0))


static func _build_light(root: Node3D, prop: Dictionary) -> void:
	var pos: Vector3 = prop.pos
	var color: Color = prop.color
	var energy: float = float(prop.get("energy", 1.6))
	var range: float = float(prop.get("range", 10.0))
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy * _light_boost()
	light.omni_range = range
	light.omni_attenuation = 1.4
	light.shadow_enabled = range > 9.0
	light.position = pos
	root.add_child(light)
	# emissive housing
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	_add(root, sphere, MaterialLib.emissive(color, 3.0), pos)
	# lamp housing box for covered areas
	if range < 10.0:
		var housing := BoxMesh.new()
		housing.size = Vector3(0.5, 0.16, 0.5)
		_add(root, housing, MaterialLib.solid(Color("3a3f45"), 0.5, 0.5), pos + Vector3(0, 0.14, 0))


static func _build_deco(root: Node3D, d: Dictionary) -> void:
	var type: String = d.type
	var pos: Vector3 = d.pos
	var rot: float = d.get("rot", 0.0)
	var s: Vector3 = d.get("scale", Vector3.ONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 73856093) ^ int(pos.z * 19349663)
	var yrot := Vector3(0, rot, 0)
	var maxf: float = max(s.x, s.z)

	match type:
		"crate":
			var m := _mat("wood_crate", 1.0)
			_box(root, Vector3(0.9 * s.x, 0.9 * s.y, 0.9 * s.z), m, pos + Vector3(0, 0.45 * s.y, 0), yrot)
			var corner := MaterialLib.solid(Color("3a3f45"), 0.6, 0.5)
			for sx2 in [-1.0, 1.0]:
				for sz2 in [-1.0, 1.0]:
					_box(root, Vector3(0.06, 0.9 * s.y, 0.06), corner, pos + Vector3(sx2 * 0.44 * s.x, 0.45 * s.y, sz2 * 0.44 * s.z), yrot)
		"barrel":
			var r: float = 0.42 * s.x
			var h: float = 0.9 * s.y
			var body: Material = _mat(["metal_blue", "metal_rust", "metal_dark"][rng.randi_range(0, 2)], 1.0)
			_cyl(root, r, h, body, pos + Vector3(0, h * 0.5, 0))
			var band: Material = MaterialLib.solid(Color("2a2d31"), 0.7, 0.45)
			_cyl(root, r + 0.01, 0.06, band, pos + Vector3(0, h * 0.3, 0))
			_cyl(root, r + 0.01, 0.06, band, pos + Vector3(0, h * 0.65, 0))
		"tire":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.26 * s.x
			torus.outer_radius = 0.36 * s.x
			torus.rings = 24
			torus.ring_segments = 10
			var rubber := MaterialLib.solid(Color("1d1f22"), 0.0, 0.9)
			for i in int(max(1, s.y * 3)):
				_add(root, torus, rubber, pos + Vector3(0, (0.32 + i * 0.6) * s.x, 0), Vector3(PI / 2, rot, 0))
		"pipe":
			var r: float = 0.16 * s.x
			var m: Material = _mat("metal_blue" if rng.randi() % 2 == 0 else "metal_rust", 1.0)
			var rot2 := Vector3(0, 0, PI / 2) if d.get("variant", 0) == 0 else Vector3.ZERO
			_cyl(root, r, 3.2 * s.z, m, pos + Vector3(0, 0, 0), rot2 + yrot)
			# flange
			var flange := CylinderMesh.new()
			flange.top_radius = r + 0.03
			flange.bottom_radius = r + 0.03
			flange.height = 0.08
			_add(root, flange, MaterialLib.solid(Color("2a2d31"), 0.6, 0.5), pos + Vector3(0, 0.05, 0), rot2 + yrot)
		"ac_unit":
			_box(root, Vector3(1.1 * s.x, 0.7 * s.y, 0.7 * s.z), MaterialLib.solid(Color("c9ccd0"), 0.2, 0.6), pos + Vector3(0, 0.35 * s.y, 0), yrot)
			var grill := BoxMesh.new()
			grill.size = Vector3(0.05, 0.5, 0.5)
			_add(root, grill, MaterialLib.solid(Color("2a2d31"), 0.6, 0.5), pos + Vector3(0.55 * s.x, 0.35 * s.y, 0), yrot)
			_box(root, Vector3(1.14 * s.x, 0.1, 0.74 * s.z), MaterialLib.solid(Color("8a8d92"), 0.4, 0.5), pos + Vector3(0, 0.74 * s.y, 0), yrot)
		"pallet":
			var wood := _mat("wood", 2.0)
			_box(root, Vector3(1.0 * s.x, 0.12, 1.0 * s.z), wood, pos + Vector3(0, 0.18, 0), yrot)
			_box(root, Vector3(1.0 * s.x, 0.12, 1.0 * s.z), wood, pos + Vector3(0, 0.06, 0), yrot)
			for i in 3:
				_box(root, Vector3(0.14, 0.06, 0.9 * s.z), wood, pos + Vector3(-0.35 + i * 0.35, 0.03, 0), yrot)
		"sandbag":
			var m: Material = MaterialLib.solid(Color("8a7a58"), 0.0, 0.95)
			for i in 3:
				_box(root, Vector3(0.55 * s.x, 0.3, 0.55 * s.z), m, pos + Vector3((i - 1) * 0.3 * s.x, 0.15, (i % 2) * 0.22 - 0.11), Vector3(rng.randf_range(-0.08, 0.08), rot, rng.randf_range(-0.08, 0.08)))
			_box(root, Vector3(1.2 * s.x, 0.3, 0.55 * s.z), m, pos + Vector3(0, 0.45, 0), Vector3(0.05, rot, -0.05))
		"fence":
			var m: Material = MaterialLib.solid(Color("2c2e31"), 0.7, 0.5)
			_box(root, Vector3(0.08, 1.2 * s.y, 0.08), m, pos + Vector3(-0.55 * s.x, 0.6 * s.y, 0), yrot)
			_box(root, Vector3(0.08, 1.2 * s.y, 0.08), m, pos + Vector3(0.55 * s.x, 0.6 * s.y, 0), yrot)
			_box(root, Vector3(1.2 * s.x, 0.08, 0.06), m, pos + Vector3(0, 1.16 * s.y, 0), yrot)
			_box(root, Vector3(1.2 * s.x, 0.06, 0.06), m, pos + Vector3(0, 0.3 * s.y, 0), yrot)
			var mesh_mat := StandardMaterial3D.new()
			mesh_mat.albedo_color = Color(0.25, 0.28, 0.31, 0.35)
			mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_mat.roughness = 0.9
			mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var panel := PlaneMesh.new()
			panel.size = Vector2(1.2 * s.x, 1.15 * s.y)
			panel.orientation = PlaneMesh.FACE_Z
			_add(root, panel, mesh_mat, pos + Vector3(0, 0.6 * s.y, 0.01), yrot, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		"cable":
			var m := MaterialLib.solid(Color("1c1e21"), 0.8, 0.5)
			var n: int = 5
			for i in range(n):
				var t: float = float(i) / (n - 1)
				var yy: float = -sin(t * PI) * 0.5 * s.x
				var seg := CylinderMesh.new()
				seg.top_radius = 0.02
				seg.bottom_radius = 0.02
				seg.height = 0.9
				var dir := Vector3(1, yy, 0).normalized()
				var p := pos + Vector3(-1.2 * s.x + t * 2.4 * s.x, yy * 0.9 + 0.1, 0)
				_add(root, seg, m, p, Vector3(0, 0, -atan2(dir.y, dir.x)) + yrot)
		"lamp":
			_box(root, Vector3(0.3, 0.5, 0.2), MaterialLib.solid(Color("3a3f45"), 0.5, 0.5), pos + Vector3(0, 0.25, 0), yrot)
			_box(root, Vector3(0.34, 0.12, 0.24), MaterialLib.emissive(Color("fff3d0"), 2.5), pos + Vector3(0, 0.06, 0), yrot)
			var l := OmniLight3D.new()
			l.light_color = Color("ffe9c0")
			l.light_energy = 0.7 * _light_boost()
			l.omni_range = 5.0
			l.position = pos + Vector3(0, 0.05, 0)
			root.add_child(l)
		"sign":
			_box(root, Vector3(0.1, 0.8 * s.y, 1.6 * s.z), MaterialLib.solid(Color("2a2d31"), 0.6, 0.5), pos + Vector3(0, 0.4 * s.y, 0), yrot)
			var panel := BoxMesh.new()
			panel.size = Vector3(0.12, 0.6 * s.y, 1.4 * s.z)
			var pc: Color = [Color("ffcf4a"), Color("5fd0ff"), Color("ff7a4a")][rng.randi_range(0, 2)]
			_add(root, panel, MaterialLib.emissive(pc, 1.8), pos + Vector3(0.06, 0.45 * s.y, 0), yrot)
		"banner":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.55, 0.35, 0.2, 0.95)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			var plane := PlaneMesh.new()
			plane.size = Vector2(1.6 * s.x, 0.9 * s.y)
			_add(root, plane, m, pos + Vector3(0, 0.5 * s.y, 0), yrot, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		"vent":
			_box(root, Vector3(0.9 * s.x, 0.5 * s.y, 0.16 * s.z), MaterialLib.solid(Color("4a4e54"), 0.5, 0.6), pos, yrot)
			for i in 4:
				_box(root, Vector3(0.06, 0.05, 0.18), MaterialLib.solid(Color("1c1e21"), 0.7, 0.5), pos + Vector3(-0.3 + i * 0.2, 0, 0), yrot)
		"duct":
			_box(root, Vector3(0.9 * s.x, 0.35 * s.y, 2.2 * s.z), MaterialLib.solid(Color("7c8086"), 0.4, 0.55), pos, yrot)
			_box(root, Vector3(0.94, 0.06, 2.24), MaterialLib.solid(Color("5a5e64"), 0.4, 0.6), pos + Vector3(0, 0.2, 0), yrot)
		"plant":
			_box(root, Vector3(0.4, 0.4, 0.4), MaterialLib.solid(Color("7a4a2e"), 0.0, 0.8), pos + Vector3(0, 0.2, 0), yrot)
			for i in 3:
				var bush := SphereMesh.new()
				bush.radius = 0.22
				bush.height = 0.4
				_add(root, bush, MaterialLib.solid(Color("4d6b33"), 0.0, 0.9),
					pos + Vector3((i - 1) * 0.14, 0.55, rng.randf_range(-0.1, 0.1)), yrot)
		"debris":
			for i in 3:
				var b := BoxMesh.new()
				b.size = Vector3(rng.randf_range(0.25, 0.5) * s.x, rng.randf_range(0.15, 0.3) * s.y, rng.randf_range(0.25, 0.5) * s.z)
				_add(root, b, _mat("concrete", 2.0), pos + Vector3(rng.randf_range(-0.4, 0.4), 0.15 * s.y, rng.randf_range(-0.4, 0.4)),
					Vector3(rng.randf_range(-0.3, 0.3), rot, rng.randf_range(-0.3, 0.3)))
		"pylon":
			_cyl(root, 0.09, 3.4, MaterialLib.solid(Color("6a6e74"), 0.5, 0.5), pos + Vector3(0, 1.7, 0))
			_box(root, Vector3(1.4, 0.08, 0.08), MaterialLib.solid(Color("6a6e74"), 0.5, 0.5), pos + Vector3(0, 3.3, 0))
			var cable_m := MaterialLib.solid(Color("1c1e21"), 0.8, 0.5)
			_cyl(root, 0.015, 2.2, cable_m, pos + Vector3(-0.6, 2.9, 0), Vector3(0.25, 0, 0))
			_cyl(root, 0.015, 2.2, cable_m, pos + Vector3(0.6, 2.9, 0), Vector3(-0.25, 0, 0))
		"hydrant":
			_cyl(root, 0.12, 0.5, MaterialLib.solid(Color("b03a2e"), 0.3, 0.6), pos + Vector3(0, 0.25, 0))
			_box(root, Vector3(0.32, 0.1, 0.1), MaterialLib.solid(Color("b03a2e"), 0.3, 0.6), pos + Vector3(0, 0.45, 0.15))
			_box(root, Vector3(0.32, 0.1, 0.1), MaterialLib.solid(Color("b03a2e"), 0.3, 0.6), pos + Vector3(0, 0.45, -0.15))
		"rock":
			var rock := SphereMesh.new()
			rock.radius = 0.5 * s.x
			rock.height = 1.0 * s.x
			rock.radial_segments = 14
			rock.rings = 7
			_add(root, rock, _mat("gravel", 3.0), pos + Vector3(0, 0.4 * s.x, 0), Vector3(rng.randf_range(-0.3, 0.3), rot, rng.randf_range(-0.3, 0.3)))
		"stain", "scorch_mark":
			var quad := QuadMesh.new()
			quad.size = Vector2(1.3 * s.x, 1.3 * s.z)
			_add(root, quad, MaterialLib.decal_mat("stain_dirt" if type == "stain" else "scorch"),
				pos + Vector3(0, 0.02, 0), Vector3(-PI / 2, rot, 0), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		"graffiti":
			var quad2 := QuadMesh.new()
			quad2.size = Vector2(1.5 * s.x, 1.0 * s.z)
			var face := Vector3(0, rot, 0)
			_add(root, quad2, MaterialLib.decal_mat("graffiti"), pos + Vector3(0, 0.5 * s.z, 0), face, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		"paint_stripe":
			var stripe := QuadMesh.new()
			stripe.size = Vector2(2.6 * s.x, 0.9 * s.z)
			_add(root, stripe, MaterialLib.decal_mat("paint_stripe"),
				pos + Vector3(0, 0.02, 0), Vector3(-PI / 2, rot, 0), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		"bush":
			var g1 := MaterialLib.solid(Color("4d6b33"), 0.0, 0.9)
			var g2 := MaterialLib.solid(Color("5a7a3a"), 0.0, 0.9)
			_sphere(root, 0.34 * maxf, g1, pos + Vector3(-0.2 * maxf, 0.34 * maxf, -0.1 * maxf))
			_sphere(root, 0.42 * maxf, g2, pos + Vector3(0.15 * maxf, 0.42 * maxf, 0.12 * maxf), Vector3.ZERO, 12, 6)
			_sphere(root, 0.26 * maxf, g1, pos + Vector3(0.05 * maxf, 0.26 * maxf, -0.24 * maxf), Vector3.ZERO, 12, 6)
		"vehicle":
			_build_vehicle(root, pos, yrot, s, rng, d.get("variant", 0))
		"ruin":
			_build_ruin(root, pos, yrot, s, rng, d.get("variant", 0))
		"tower_shell":
			_build_tower_shell(root, pos, yrot, s, rng, d.get("variant", 0))
		"billboard":
			_build_billboard(root, pos, yrot, s, rng, d.get("variant", 0))
		_:
			pass


# Rusted truck / jeep: cab + cargo box + wheels (collider footprint 2*maxf x 1.8m)
static func _build_vehicle(root: Node3D, pos: Vector3, yrot: Vector3, s: Vector3, rng: RandomNumberGenerator, variant: int) -> void:
	var w: float = 2.0 * max(s.x, s.z)
	var wd: float = 1.0 * max(s.x, s.z)
	var rust := _mat("metal_rust", 1.5)
	var dark := _mat("metal_dark", 1.5)
	var paint_col: Color = [Color("5a6b52"), Color("8a6a4a"), Color("4a4e5a")][variant % 3]
	var paint := MaterialLib.solid(paint_col, 0.5, 0.5)
	var glass := MaterialLib.solid(Color("2a3a44"), 0.2, 0.3)
	var wheel := MaterialLib.solid(Color("15171a"), 0.0, 0.9)
	var hw: float = w * 0.5
	var hwd: float = wd * 0.5
	var axle := Vector3(hw - w * 0.22, 0, hwd - 0.12)
	var wheels: Array = [axle, Vector3(-axle.x, 0, axle.z), Vector3(axle.x, 0, -axle.z), Vector3(-axle.x, 0, -axle.z)]
	for wp in wheels:
		_cyl(root, w * 0.085, 0.3, wheel, pos + wp + Vector3(0, 0.36, 0), Vector3(PI / 2, 0, 0) + yrot)
	if variant == 2:
		# jeep: low open body + rollbar
		_box(root, Vector3(w * 0.85, 0.7, wd * 0.85), paint, pos + Vector3(0, 0.55, 0), yrot)
		_box(root, Vector3(w * 0.35, 0.5, wd * 0.8), rust, pos + Vector3(-w * 0.2, 0.85, 0), yrot)
		_box(root, Vector3(0.08, 1.0, wd * 0.7), dark, pos + Vector3(w * 0.3, 1.1, 0), yrot)
	else:
		var cab_h: float = 1.35 if variant == 0 else 1.15
		_box(root, Vector3(w * 0.3, cab_h, wd * 0.9), paint, pos + Vector3(-w * 0.34, cab_h * 0.55, 0), yrot)
		_box(root, Vector3(w * 0.3, 0.35, wd * 0.92), glass, pos + Vector3(-w * 0.34, cab_h + 0.17, 0), yrot)
		if variant == 0:
			# pickup bed with open top
			_box(root, Vector3(w * 0.52, 0.55, wd * 0.9), rust, pos + Vector3(w * 0.18, 0.55, 0), yrot)
			_box(root, Vector3(w * 0.5, 0.08, wd * 0.86), dark, pos + Vector3(w * 0.18, 0.82, 0), yrot)
		else:
			# box truck cargo
			_box(root, Vector3(w * 0.52, 1.4, wd * 0.94), rust, pos + Vector3(w * 0.17, 0.75, 0), yrot)
			_box(root, Vector3(w * 0.06, 0.9, wd * 0.9), dark, pos + Vector3(w * 0.03, 0.9, 0), yrot)


# Broken wall segment with jagged top (collider 2*maxf footprint, 2.0m tall)
static func _build_ruin(root: Node3D, pos: Vector3, yrot: Vector3, s: Vector3, rng: RandomNumberGenerator, _variant: int) -> void:
	var w: float = 1.4 * max(s.x, s.z)
	var d: float = 0.8 * max(s.x, s.z)
	var m := _mat("concrete", 2.0)
	var m2 := _mat("brick", 2.0)
	_box(root, Vector3(w, 1.7, d), m, pos + Vector3(0, 0.85, 0), yrot)
	_box(root, Vector3(w * 0.55, 0.45, d * 0.9), m2, pos + Vector3(-w * 0.18, 1.7 + 0.22, 0), yrot + Vector3(0, 0, rng.randf_range(-0.06, 0.06)))
	_box(root, Vector3(w * 0.4, 0.35, d * 0.8), m, pos + Vector3(w * 0.2, 1.7 + 0.17, 0), yrot + Vector3(0, 0, rng.randf_range(-0.08, 0.08)))
	_box(root, Vector3(w * 0.3, 0.25, d * 0.7), m2, pos + Vector3(w * 0.05, 1.7 + 0.12, 0), yrot + Vector3(0, 0, rng.randf_range(-0.1, 0.1)))
	_box(root, Vector3(w * 0.2, 0.18, d * 0.6), m, pos + Vector3(-w * 0.3, 1.7 + 0.08, 0), yrot + Vector3(0, 0, rng.randf_range(-0.12, 0.12)))


# Hollow ruined tower shell: 4 corner pillars + 3 walls with window gaps, no roof
# (deco variant is solid for collision; enterable ruins are built from wall colliders)
static func _build_tower_shell(root: Node3D, pos: Vector3, yrot: Vector3, s: Vector3, rng: RandomNumberGenerator, _variant: int) -> void:
	var w: float = 2.0 * max(s.x, s.z)
	var h: float = 4.0
	var m := _mat("concrete", 2.0)
	var m2 := _mat("brick", 2.0)
	var hw := w * 0.5
	var pillar := Vector3(0.6, h, 0.6)
	for px in [-1.0, 1.0]:
		for pz in [-1.0, 1.0]:
			_box(root, pillar, m2, pos + Vector3(px * (hw - 0.3), h * 0.5, pz * (hw - 0.3)), yrot)
	# north wall with window gap (base + top, gap at 1.4-2.8)
	_box(root, Vector3(w, 1.35, 0.5), m, pos + Vector3(0, 0.67, -hw + 0.25), yrot)
	_box(root, Vector3(w, 1.0, 0.5), m2, pos + Vector3(0, 3.1, -hw + 0.25), yrot)
	# east wall with window gap
	_box(root, Vector3(0.5, 1.35, w), m, pos + Vector3(hw - 0.25, 0.67, 0), yrot)
	_box(root, Vector3(0.5, 1.0, w), m2, pos + Vector3(hw - 0.25, 3.1, 0), yrot)
	# west wall with door gap (1.8m opening)
	var dw: float = 1.8
	var seg: float = (w - dw) * 0.5
	_box(root, Vector3(0.5, 1.35, seg), m, pos + Vector3(-hw + 0.25, 0.67, -w * 0.5 + seg * 0.5), yrot)
	_box(root, Vector3(0.5, 1.35, seg), m, pos + Vector3(-hw + 0.25, 0.67, w * 0.5 - seg * 0.5), yrot)
	_box(root, Vector3(0.5, 1.0, seg), m2, pos + Vector3(-hw + 0.25, 3.1, -w * 0.5 + seg * 0.5), yrot)
	_box(root, Vector3(0.5, 1.0, seg), m2, pos + Vector3(-hw + 0.25, 3.1, w * 0.5 - seg * 0.5), yrot)
	# scattered rubble inside
	for i in 3:
		var rr: float = rng.randf_range(0.25, 0.5)
		_box(root, Vector3(rr, rr * 0.6, rr), m, pos + Vector3(rng.randf_range(-hw * 0.4, hw * 0.4), rr * 0.3, rng.randf_range(-hw * 0.4, hw * 0.4)), yrot + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))


# Roadside billboard: two legs + large emissive panel with colored text blocks
static func _build_billboard(root: Node3D, pos: Vector3, yrot: Vector3, s: Vector3, rng: RandomNumberGenerator, _variant: int) -> void:
	var leg := MaterialLib.solid(Color("3a3f45"), 0.6, 0.5)
	var bw: float = 5.2
	var bh: float = 2.4
	var xoff: float = bw * 0.5 - 0.25
	for lx in [-1.0, 1.0]:
		_box(root, Vector3(0.28, 4.4, 0.28), leg, pos + Vector3(lx * xoff, 2.2, 0), yrot)
	_box(root, Vector3(bw, 0.16, 0.24), leg, pos + Vector3(0, 4.36, 0), yrot)
	var panel_mat := MaterialLib.emissive(Color("e8e0c8"), 1.4)
	_box(root, Vector3(bw, bh, 0.12), panel_mat, pos + Vector3(0, 2.4 + bh * 0.5, 0.06), yrot)
	var rows: Array = [
		[Color("c9302e"), 0.62], [Color("2e6fb0"), 0.35], [Color("e0a02e"), 0.62],
	]
	for i in range(rows.size()):
		var col: Color = rows[i][0]
		var wf: float = rows[i][1]
		var tb := BoxMesh.new()
		tb.size = Vector3(bw * wf, 0.3, 0.02)
		_add(root, tb, MaterialLib.emissive(col, 2.2), pos + Vector3(0, 2.4 + bh - 0.55 - i * 0.7, 0.13), yrot, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# small support struts
	_box(root, Vector3(0.16, 0.5, 0.16), leg, pos + Vector3(-bw * 0.28, 1.95, 0), yrot)
	_box(root, Vector3(0.16, 0.5, 0.16), leg, pos + Vector3(bw * 0.28, 1.95, 0), yrot)


# Distant desert scenery: big rock meshes + ruined towers on the horizon (fog-tinted, no collision)
static func _build_distant_scenery(root: Node3D, map: Dictionary) -> void:
	if not map.get("open_world", false):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273 + int(map.get("id", "map").hash())
	var half: float = map.size.x / 2.0
	var rock_m := _mat("gravel", 8.0)
	var rock_dark := _mat("concrete_dark", 8.0)
	var tower_m := _mat("concrete", 6.0)
	var tower_dark := _mat("brick", 6.0)
	for i in 20:
		var ang: float = rng.randf() * TAU
		var dist: float = half + 14.0 + rng.randf() * (half - 18.0)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var rs: float = rng.randf_range(5.0, 13.0)
		var m: Material = rock_m if rng.randf() < 0.65 else rock_dark
		_sphere(root, rs, m, p + Vector3(rng.randf_range(-2.5, 2.5), rs * 0.3, rng.randf_range(-2.5, 2.5)), Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)), 10, 5)
		var rs2: float = rs * rng.randf_range(0.45, 0.7)
		_sphere(root, rs2, m, p + Vector3(rng.randf_range(-3.5, 3.5), rs2 * 0.3, rng.randf_range(-3.5, 3.5)), Vector3.ZERO, 8, 4)
	for i in 3:
		var ang: float = rng.randf() * TAU
		var dist: float = half + 16.0 + rng.randf() * (half - 20.0)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var tz: float = rng.randf_range(-0.5, 0.5)
		_box(root, Vector3(7.0, 3.2, 7.0), tower_m, p + Vector3(0, 1.6, 0), Vector3(0, tz, 0))
		_box(root, Vector3(5.4, 2.6, 5.4), tower_dark, p + Vector3(rng.randf_range(-0.8, 0.8), 3.8, 0), Vector3(0, tz, 0))
		_box(root, Vector3(4.0, 2.2, 4.0), tower_m, p + Vector3(rng.randf_range(-0.8, 0.8), 5.6, rng.randf_range(-0.6, 0.6)), Vector3(rng.randf_range(-0.06, 0.06), tz, rng.randf_range(-0.06, 0.06)))
		_box(root, Vector3(2.6, 1.6, 2.6), tower_dark, p + Vector3(rng.randf_range(-0.8, 0.8), 7.2, 0), Vector3(0.12, tz, -0.1))
