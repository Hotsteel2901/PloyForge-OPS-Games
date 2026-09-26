# Effects: tracers, muzzle flashes, impacts, blood, explosions, casings. All procedural.
class_name Effects
extends Node3D

# Web（Compatibility 渲染器）不支持 GPUParticles3D：所有粒子特效直接跳过，
# 避免每帧提交无效粒子（Web 端卡顿的显著来源之一）
static var IS_WEB: bool = OS.has_feature("web")

var _flash_lights: Array = []
var _explosion_lights: Array = []
var _trail_nodes: Array = []
var _decal_nodes: Array = []
var _casings: Array = []
var _next_light: int = 0
# 枪口闪光节点池：每发 3 节点（2 quad + 1 core），复用避免场景树 churn
# Web 单线程/低端设备用更小池，缓解透明排序与节点分配压力
var _flash_groups: int = 8 if not IS_WEB else 4
var _flash_pool: Array = []
var _flash_pool_life: Array = []
var _next_flash: int = 0
# 弹壳数量上限（交火时丢弃最老弹壳，防止 draw call 无限增长）
const MAX_CASINGS: int = 24

# ---- Static caches: materials & meshes reused across all effect calls ----
# Material caches keyed by color HTML string
static var _tracer_mat_cache: Dictionary = {}
static var _flash_mat_cache: Dictionary = {}
static var _spark_mat_cache: Dictionary = {}
# Single-instance materials (fixed color)
static var _core_mat: StandardMaterial3D = null
static var _decal_mat: StandardMaterial3D = null
static var _casing_mat: StandardMaterial3D = null
static var _blood_mat: ParticleProcessMaterial = null
static var _fireball_mat: ParticleProcessMaterial = null
static var _exp_smoke_mat: ParticleProcessMaterial = null
# Cached fixed-size meshes
static var _flash_quad: QuadMesh = null
static var _core_sphere: SphereMesh = null
static var _decal_quad: QuadMesh = null
static var _casing_cyl: CylinderMesh = null


static func _get_tracer_mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _tracer_mat_cache.has(key):
		return _tracer_mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat_cache[key] = mat
	return mat


static func _get_flash_mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _flash_mat_cache.has(key):
		return _flash_mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _flash_tex()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 10.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_flash_mat_cache[key] = mat
	return mat


static func _get_core_mat() -> StandardMaterial3D:
	if _core_mat != null:
		return _core_mat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.95, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.5)
	mat.emission_energy_multiplier = 14.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat = mat
	return mat


static func _get_decal_mat() -> StandardMaterial3D:
	if _decal_mat != null:
		return _decal_mat
	# 程序化污渍贴花（MaterialLib 生成）：命中弹孔从纯色方块升级为不规则污渍，
	# 视觉效果接近真实弹痕（焦黑中心 + 边缘过渡）
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = MaterialLib.get_decal("scorch")
	mat.albedo_color = Color(0.55, 0.48, 0.42, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_decal_mat = mat
	return mat


static func _get_casing_mat() -> StandardMaterial3D:
	if _casing_mat != null:
		return _casing_mat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.6, 0.25)
	mat.metallic = 0.9
	mat.roughness = 0.35
	_casing_mat = mat
	return mat


static func _get_blood_mat() -> ParticleProcessMaterial:
	if _blood_mat != null:
		return _blood_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 55.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -9.0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.scale_min = 0.02
	mat.scale_max = 0.05
	mat.color = Color(0.55, 0.08, 0.06)
	_blood_mat = mat
	return mat


static func _get_fireball_mat() -> ParticleProcessMaterial:
	if _fireball_mat != null:
		return _fireball_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, 3.0, 0)
	mat.damping_min = 2.0
	mat.damping_max = 6.0
	mat.scale_min = 0.3
	mat.scale_max = 1.4
	mat.color = Color(1.0, 0.75, 0.3)
	_fireball_mat = mat
	return mat


static func _get_exp_smoke_mat() -> ParticleProcessMaterial:
	if _exp_smoke_mat != null:
		return _exp_smoke_mat
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 50.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, 2.0, 0)
	mat.scale_min = 0.8
	mat.scale_max = 3.2
	mat.color = Color(0.28, 0.26, 0.24, 0.7)
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	_exp_smoke_mat = mat
	return mat


static func _get_flash_quad() -> QuadMesh:
	if _flash_quad != null:
		return _flash_quad
	_flash_quad = QuadMesh.new()
	_flash_quad.size = Vector2(0.3, 0.3)
	_flash_quad.orientation = PlaneMesh.FACE_Y
	return _flash_quad


static func _get_core_sphere() -> SphereMesh:
	if _core_sphere != null:
		return _core_sphere
	_core_sphere = SphereMesh.new()
	_core_sphere.radius = 0.035
	_core_sphere.height = 0.07
	return _core_sphere


static func _get_decal_quad() -> QuadMesh:
	if _decal_quad != null:
		return _decal_quad
	_decal_quad = QuadMesh.new()
	_decal_quad.size = Vector2(0.22, 0.22)
	return _decal_quad


static func _get_casing_cyl() -> CylinderMesh:
	if _casing_cyl != null:
		return _casing_cyl
	_casing_cyl = CylinderMesh.new()
	_casing_cyl.top_radius = 0.006
	_casing_cyl.bottom_radius = 0.007
	_casing_cyl.height = 0.02
	return _casing_cyl


static var _tracer_mesh: BoxMesh = null


static func _get_tracer_mesh() -> BoxMesh:
	if _tracer_mesh != null:
		return _tracer_mesh
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
	return _tracer_mesh


static var _ring_mesh: TorusMesh = null


static func _get_ring_mesh() -> TorusMesh:
	if _ring_mesh != null:
		return _ring_mesh
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.5
	_ring_mesh.outer_radius = 0.9
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 8
	return _ring_mesh


static var _scorch_quad: QuadMesh = null


static func _get_scorch_quad() -> QuadMesh:
	if _scorch_quad != null:
		return _scorch_quad
	_scorch_quad = QuadMesh.new()
	_scorch_quad.size = Vector2(4.0, 4.0)
	return _scorch_quad


static var _smoke_mat_cache: Dictionary = {}


static func _get_smoke_mat(color: Color) -> ParticleProcessMaterial:
	var key: String = color.to_html()
	if _smoke_mat_cache.has(key):
		return _smoke_mat_cache[key]
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3.UP
	sm.spread = 70.0
	sm.initial_velocity_min = 0.5
	sm.initial_velocity_max = 2.5
	sm.gravity = Vector3(0, 1.2, 0)
	sm.scale_min = 0.4
	sm.scale_max = 2.0
	sm.color = Color(color.r, color.g, color.b, 0.55)
	_smoke_mat_cache[key] = sm
	return sm


func tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.5)) -> void:
	var dir := (to - from)
	var len: float = dir.length()
	if len < 0.1:
		return
	# 共享单位网格 + 实例缩放：避免每发子弹向 RenderingServer 上传新 BoxMesh（交火时可到每秒数十次）
	var mi := MeshInstance3D.new()
	mi.mesh = _get_tracer_mesh()
	mi.material_override = _get_tracer_mat(color)
	mi.scale = Vector3(1.0, 1.0, len)
	mi.position = (from + to) * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("life", 0.09)
	add_child(mi)
	mi.look_at(to, Vector3.UP)
	_trail_nodes.append(mi)


func muzzle_flash(pos: Vector3, dir: Vector3 = Vector3.FORWARD, color: Color = Color(1.0, 0.8, 0.4)) -> void:
	var light: OmniLight3D = null
	if _flash_lights.size() < 4:
		light = OmniLight3D.new()
		light.light_color = color
		light.omni_range = 7.0
		light.omni_attenuation = 1.2
		add_child(light)
		_flash_lights.append(light)
	else:
		light = _flash_lights[_next_light]
		_next_light = (_next_light + 1) % _flash_lights.size()
	light.global_position = pos
	light.light_energy = 9.0
	light.shadow_enabled = false
	light.set_meta("life", 0.055)
	light.set_meta("active", true)
	# 复用枪口闪光节点池（避免每发 3 个节点创建/销毁）
	_ensure_flash_pool()
	var group := _next_flash
	_next_flash = (_next_flash + 1) % _flash_groups
	var base: int = group * 3
	var mat: StandardMaterial3D = _get_flash_mat(color)
	for k in 2:
		var mi: MeshInstance3D = _flash_pool[base + k]
		mi.mesh = _get_flash_quad()
		mi.material_override = mat
		mi.position = pos + dir * 0.06
		mi.rotation = Vector3(randf_range(0, 6.28), randf_range(0, 6.28), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = true
	var core: MeshInstance3D = _flash_pool[base + 2]
	core.mesh = _get_core_sphere()
	core.material_override = _get_core_mat()
	core.position = pos + dir * 0.06
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3.ONE * (1.0 + randf() * 0.5)
	core.visible = true
	_flash_pool_life[group] = 0.045


static var _flash_img: ImageTexture = null


# 软圆粒子贴图：血/烟/火粒子从"方块粒子"升级为软边圆粒（32²，全粒子共享）
static var _soft_particle_img: ImageTexture = null


static func _soft_particle_tex() -> ImageTexture:
	if _soft_particle_img != null:
		return _soft_particle_img
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var data: PackedByteArray = img.get_data()
	data.resize(32 * 32 * 4)
	for y in range(32):
		for x in range(32):
			var dx: float = (x - 16.0) / 16.0
			var dy: float = (y - 16.0) / 16.0
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = smoothstep(1.15, 0.25, d)
			var i: int = (y * 32 + x) * 4
			data[i] = 255
			data[i + 1] = 255
			data[i + 2] = 255
			data[i + 3] = int(a * 255.0)
	img.set_data(32, 32, false, Image.FORMAT_RGBA8, data)
	_soft_particle_img = ImageTexture.create_from_image(img)
	return _soft_particle_img


func _setup_particles(parts: GPUParticles3D) -> GPUParticles3D:
	parts.texture = _soft_particle_tex()
	return parts


func _ensure_flash_pool() -> void:
	if _flash_pool.size() >= _flash_groups * 3:
		return
	for g in range(_flash_groups):
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_flash_pool.append(mi)
		var core := MeshInstance3D.new()
		core.visible = false
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		_flash_pool.append(core)
		_flash_pool_life.append(0.0)


static func _flash_tex() -> ImageTexture:
	if _flash_img != null:
		return _flash_img
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var data: PackedByteArray = img.get_data()
	data.resize(64 * 64 * 4)
	for y in range(64):
		for x in range(64):
			var dx: float = (x - 32.0) / 32.0
			var dy: float = (y - 32.0) / 32.0
			var d: float = sqrt(dx * dx + dy * dy)
			var core: float = smoothstep(1.0, 0.0, d)
			var star: float = pow(max(0.0, 1.0 - d), 2.0) * (0.6 + 0.4 * pow(abs(cos(atan2(dy, dx) * 4.0)), 8.0))
			var a: float = clampf(core * 0.9 + star, 0.0, 1.0)
			var i: int = (y * 64 + x) * 4
			data[i] = 255
			data[i + 1] = 245
			data[i + 2] = 220
			data[i + 3] = int(a * 255.0)
	img.set_data(64, 64, false, Image.FORMAT_RGBA8, data)
	_flash_img = ImageTexture.create_from_image(img)
	return _flash_img


func impact(pos: Vector3, normal: Vector3 = Vector3.UP, color: Color = Color(0.7, 0.6, 0.5), spark_count: int = 6) -> void:
	# dust spark particles（Web/Compatibility 不支持 GPU 粒子，跳过）
	if not IS_WEB:
		var parts := _setup_particles(GPUParticles3D.new())
		parts.amount = spark_count
		parts.lifetime = 0.45
		parts.one_shot = true
		parts.explosiveness = 1.0
		parts.position = pos + normal * 0.02
		parts.process_material = _spark_material(color)
		add_child(parts)
		parts.emitting = true
		parts.set_meta("auto_free", true)
		_trail_nodes.append(parts)
	# small decal
	if _decal_nodes.size() < 24:
		var mi := MeshInstance3D.new()
		mi.mesh = _get_decal_quad()
		mi.material_override = _get_decal_mat()
		mi.position = pos + normal * 0.015
		var basis := Basis()
		basis = basis.looking_at(normal)
		basis = basis.rotated(Vector3.UP, randf_range(0, 6.28))
		mi.basis = basis
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("life", 9.0)
		add_child(mi)
		_decal_nodes.append(mi)


func blood(pos: Vector3) -> void:
	if IS_WEB:
		return
	var parts := _setup_particles(GPUParticles3D.new())
	parts.amount = 10
	parts.lifetime = 0.6
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.position = pos
	parts.process_material = _get_blood_mat()
	add_child(parts)
	parts.emitting = true
	parts.set_meta("auto_free", true)
	_trail_nodes.append(parts)


func explosion(pos: Vector3, radius: float = 8.0) -> void:
	# Web（Compatibility 渲染器不支持 GPU 粒子）：只保留冲击环/灯光/焦痕，跳过粒子
	if not IS_WEB:
		var fire := _setup_particles(GPUParticles3D.new())
		fire.amount = 42
		fire.lifetime = 0.9
		fire.one_shot = true
		fire.explosiveness = 1.0
		fire.position = pos
		fire.process_material = _get_fireball_mat()
		add_child(fire)
		fire.emitting = true
		fire.set_meta("auto_free", true)
		_trail_nodes.append(fire)
		var smoke := _setup_particles(GPUParticles3D.new())
		smoke.amount = 26
		smoke.lifetime = 2.4
		smoke.one_shot = true
		smoke.explosiveness = 1.0
		smoke.position = pos + Vector3(0, 0.3, 0)
		smoke.process_material = _get_exp_smoke_mat()
		add_child(smoke)
		smoke.emitting = true
		smoke.set_meta("auto_free", true)
		_trail_nodes.append(smoke)
	# light pulse（一次性灯光：独立列表管理，淡出后真正释放，防止长期累积拖垮渲染）
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.35)
	light.omni_range = radius * 1.6
	light.light_energy = 16.0
	light.position = pos + Vector3(0, 1.0, 0)
	light.set_meta("life", 0.22)
	light.set_meta("active", true)
	add_child(light)
	_explosion_lights.append(light)
	# shockwave ring (per-instance material — _process mutates its alpha)
	var ring := MeshInstance3D.new()
	ring.mesh = _get_ring_mesh()
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.85, 0.55, 0.8)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.8, 0.5)
	rm.emission_energy_multiplier = 4.0
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position = pos + Vector3(0, 0.1, 0)
	ring.rotation.x = PI / 2
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_meta("life", 0.35)
	ring.set_meta("ring", true)
	add_child(ring)
	_trail_nodes.append(ring)
	# scorch decal
	if _decal_nodes.size() < 24:
		var dec: QuadMesh = _get_scorch_quad()
		dec.size = Vector2(radius * 0.5, radius * 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = MaterialLib.get_decal("scorch")
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = dec
		mi.material_override = mat
		mi.position = pos + Vector3(0, 0.02, 0)
		mi.rotation.x = -PI / 2
		mi.rotation.y = randf_range(0, 6.28)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_decal_nodes.append(mi)


func smoke(pos: Vector3, color: Color = Color(0.5, 0.47, 0.42)) -> void:
	if IS_WEB:
		return
	var smoke := _setup_particles(GPUParticles3D.new())
	smoke.amount = 40
	smoke.lifetime = 3.0
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	smoke.position = pos
	smoke.process_material = _get_smoke_mat(color)
	add_child(smoke)
	smoke.emitting = true
	smoke.set_meta("auto_free", true)
	_trail_nodes.append(smoke)


func shell_casing(pos: Vector3, dir: Vector3) -> void:
	if IS_WEB:
		return
	# 超过上限：丢弃最老的弹壳（优先保留最新弹壳的视觉效果）
	while _casings.size() >= MAX_CASINGS:
		var oldest: MeshInstance3D = _casings.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var casing := MeshInstance3D.new()
	casing.mesh = _get_casing_cyl()
	casing.material_override = _get_casing_mat()
	casing.position = pos
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	casing.set_meta("vel", dir * 2.5 + Vector3(0, 1.2, 0))
	casing.set_meta("rot", Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20)))
	add_child(casing)
	_casings.append(casing)


func smink_noise(m: ParticleProcessMaterial) -> void:
	m.color_ramp = null
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6


func _spark_material(color: Color) -> ParticleProcessMaterial:
	var key: String = color.to_html()
	if _spark_mat_cache.has(key):
		return _spark_mat_cache[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 160.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 4.0
	m.gravity = Vector3(0, -6.0, 0)
	m.damping_min = 1.0
	m.damping_max = 4.0
	m.scale_min = 0.015
	m.scale_max = 0.035
	m.color = color
	_spark_mat_cache[key] = m
	return m


func _process(delta: float) -> void:
	# 枪口闪光节点池衰减（复用节点，不创建/销毁）
	for g in range(_flash_pool_life.size()):
		var life: float = _flash_pool_life[g]
		if life <= 0.0:
			continue
		life -= delta
		_flash_pool_life[g] = life
		if life <= 0.0:
			var base: int = g * 3
			for k in 3:
				_flash_pool[base + k].visible = false
	# fade muzzle flash lights (pooled, reused, never freed)
	for l in _flash_lights:
		if not is_instance_valid(l):
			continue
		if not l.get_meta("active", false):
			continue
		var life: float = float(l.get_meta("life", 0.0))
		life -= delta
		l.set_meta("life", life)
		if life <= 0.0:
			l.light_energy = 0.0
			l.set_meta("active", false)
		else:
			l.light_energy = 9.0 * (life / 0.055)
	# fade + free one-shot explosion lights (they never came back to the muzzle pool)
	var k: int = _explosion_lights.size() - 1
	while k >= 0:
		var el: OmniLight3D = _explosion_lights[k]
		if not is_instance_valid(el):
			_explosion_lights.remove_at(k)
			k -= 1
			continue
		var elife: float = float(el.get_meta("life", 0.0)) - delta
		el.set_meta("life", elife)
		if elife <= 0.0:
			el.queue_free()
			_explosion_lights.remove_at(k)
		else:
			el.light_energy = 16.0 * (elife / 0.22)
		k -= 1
	# fade trails + rings
	var i: int = _trail_nodes.size() - 1
	while i >= 0:
		var n: Node = _trail_nodes[i]
		if not is_instance_valid(n):
			_trail_nodes.remove_at(i)
			i -= 1
			continue
		if n is MeshInstance3D:
			var life: float = float(n.get_meta("life", 0.0)) - delta
			n.set_meta("life", life)
			if life <= 0.0:
				n.queue_free()
				_trail_nodes.remove_at(i)
				i -= 1
				continue
			if n.get_meta("ring", false):
				var scale: float = 1.0 + (0.35 - life) * 14.0
				n.scale = Vector3(scale, scale, scale)
				var mat: Material = n.material_override
				if mat is StandardMaterial3D:
					mat.albedo_color.a = (life / 0.35) * 0.8
			elif n.get_meta("auto_free", false):
				pass
		elif n is GPUParticles3D:
			if n.get_meta("auto_free", false) and not n.is_emitting():
				n.queue_free()
				_trail_nodes.remove_at(i)
				i -= 1
				continue
		i -= 1
	# fade + free decals（弹痕/scorch 曾只设 life 从不释放，攒满 24 个后常驻内存）
	var d: int = _decal_nodes.size() - 1
	while d >= 0:
		var dn: MeshInstance3D = _decal_nodes[d]
		if not is_instance_valid(dn):
			_decal_nodes.remove_at(d)
			d -= 1
			continue
		var dlife: float = float(dn.get_meta("life", 0.0)) - delta
		dn.set_meta("life", dlife)
		if dlife <= 0.0:
			dn.queue_free()
			_decal_nodes.remove_at(d)
		d -= 1
	# casings physics
	var j: int = _casings.size() - 1
	while j >= 0:
		var c: MeshInstance3D = _casings[j]
		if not is_instance_valid(c):
			_casings.remove_at(j)
			j -= 1
			continue
		var vel: Vector3 = c.get_meta("vel")
		vel.y -= 9.8 * delta
		var np: Vector3 = c.position + vel * delta
		if np.y < 0.02:
			np.y = 0.02
			vel = vel * Vector3(0.5, -0.35, 0.5)
		c.position = np
		c.set_meta("vel", vel)
		var rot: Vector3 = c.get_meta("rot")
		c.rotation += rot * delta
		var age: float = float(c.get_meta("age", 0.0)) + delta
		c.set_meta("age", age)
		if age > 4.0:
			c.queue_free()
			_casings.remove_at(j)
		j -= 1


func clear_all() -> void:
	for n in _trail_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_trail_nodes.clear()
	for n in _decal_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_decal_nodes.clear()
	for n in _casings:
		if is_instance_valid(n):
			n.queue_free()
	_casings.clear()
	for l in _flash_lights:
		if is_instance_valid(l):
			l.queue_free()
	_flash_lights.clear()
	for l in _explosion_lights:
		if is_instance_valid(l):
			l.queue_free()
	_explosion_lights.clear()
	# 枪口闪光池节点同样释放（地图切换时整体重建）
	for n in _flash_pool:
		if is_instance_valid(n):
			n.queue_free()
	_flash_pool.clear()
	_flash_pool_life.clear()
