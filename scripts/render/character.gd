# CharacterFactory: 盒人风格第三人称角色，绑定到 Godot 标准动作模板（Mannequin）的骨骼上。
# 盒人部件（BoxMesh + 队伍色）每帧跟随骨骼全局姿态，动画直接使用
# AnimationLibrary_Godot_Standard.glb 的动画（Idle/Walk/Sprint/Jump/Death…），
# 武器挂在右手骨（DEF-hand.R）。
# 保留盒人特色：方块躯干/头/四肢，用标准人形骨骼驱动。
class_name CharacterFactory
extends RefCounted

const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"
const HAND_BONE := "DEF-hand.R"

static var _scene: PackedScene = null

# 盒人部件定义：parent=起点骨，child=终点骨（空=单骨），size=盒子尺寸
const BOX_PARTS := [
	{"name": "Head",   "parent": "DEF-head",      "child": "",              "size": Vector3(0.26, 0.28, 0.28)},
	{"name": "Torso",  "parent": "DEF-spine.001", "child": "DEF-spine.003", "size": Vector3(0.44, 0.5, 0.28)},
	{"name": "Hips",   "parent": "DEF-hips",      "child": "DEF-spine.001", "size": Vector3(0.32, 0.22, 0.28)},
	{"name": "UpperArm.L", "parent": "DEF-upper_arm.L", "child": "DEF-forearm.L", "size": Vector3(0.12, 0.3, 0.12)},
	{"name": "UpperArm.R", "parent": "DEF-upper_arm.R", "child": "DEF-forearm.R", "size": Vector3(0.12, 0.3, 0.12)},
	{"name": "Forearm.L", "parent": "DEF-forearm.L", "child": "DEF-hand.L", "size": Vector3(0.1, 0.26, 0.1)},
	{"name": "Forearm.R", "parent": "DEF-forearm.R", "child": "DEF-hand.R", "size": Vector3(0.1, 0.26, 0.1)},
	{"name": "Hand.L", "parent": "DEF-hand.L", "child": "", "size": Vector3(0.1, 0.12, 0.1)},
	{"name": "Hand.R", "parent": "DEF-hand.R", "child": "", "size": Vector3(0.1, 0.12, 0.1)},
	{"name": "Thigh.L", "parent": "DEF-thigh.L", "child": "DEF-shin.L", "size": Vector3(0.14, 0.4, 0.16)},
	{"name": "Thigh.R", "parent": "DEF-thigh.R", "child": "DEF-shin.R", "size": Vector3(0.14, 0.4, 0.16)},
	{"name": "Shin.L", "parent": "DEF-shin.L", "child": "DEF-foot.L", "size": Vector3(0.12, 0.36, 0.13)},
	{"name": "Shin.R", "parent": "DEF-shin.R", "child": "DEF-foot.R", "size": Vector3(0.12, 0.36, 0.13)},
	{"name": "Foot.L", "parent": "DEF-foot.L", "child": "", "size": Vector3(0.12, 0.1, 0.3)},
	{"name": "Foot.R", "parent": "DEF-foot.R", "child": "", "size": Vector3(0.12, 0.1, 0.3)},
]


static func _get_scene() -> PackedScene:
	if _scene == null:
		_scene = load(MANNEQUIN_SCENE)
	return _scene


static func _team_color(team: int, zombie: bool) -> Color:
	if zombie:
		return Color("4fe07a")
	if team == 1:
		return Color("4a9dff")
	return Color("ff5a3d")


static func build(team: int, zombie: bool) -> Node3D:
	var scene: PackedScene = _get_scene()
	var root := Node3D.new()
	root.name = "Character"
	root.set_meta("zombie", zombie)
	root.set_meta("team", team)
	root.set_meta("weapon_id", "")
	var body: Node3D = scene.instantiate() as Node3D
	body.name = "Body"
	# 骨架坐标系：Mannequin 脸朝局部 +Z、腿迈步沿 ±Z（正常人形），而游戏约定
	# yaw=0 面朝 -Z。body 绕 Y 转 180° 即可同时把脸转到 -Z、迈步转到 ±Z（前后迈步）。
	# 注意不能转 -90°：那会把迈步轴转到 ±X（看起来横着迈步），且脸转到 -X。
	body.rotation.y = PI
	root.add_child(body)
	root.set_meta("body", body)
	# 把 Rig(骨骼) 与 AnimationPlayer 移入 model_root（只用于部件旋转修正）：
	# body(-90°) 使位移 -X→世界 -Z ✓，但摆动轴 +Z 也被转到 -X（横着摆）。
	# 在骨骼旋转上再乘 mr(-90°)：把摆动轴从 -X 翻回世界 -Z（前后迈步）。
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	model_root.rotation.y = -PI * 0.5
	body.add_child(model_root)
	var moving: Array = []
	for c in body.get_children():
		if c != model_root:
			moving.append(c)
	for c in moving:
		body.remove_child(c)
		c.owner = null
		model_root.add_child(c)
	root.set_meta("model_root", model_root)
	# 隐藏 Mannequin 网格（只取骨骼与动画）
	var sk: Skeleton3D = null
	var ap: AnimationPlayer = null
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			sk = n
		if n is AnimationPlayer:
			ap = n
		for c in n.get_children():
			stack.append(c)
	root.set_meta("skeleton", sk)
	root.set_meta("animplayer", ap)
	if sk != null:
		_hide_meshes(sk)
	# 盒人部件（挂在 root 下，每帧按骨骼姿态摆放）
	var parts: Array = _build_parts(root, sk, team, zombie)
	root.set_meta("parts", parts)
	# 右手骨挂武器
	var att := BoneAttachment3D.new()
	att.name = "WeaponAttach"
	if sk != null and sk.find_bone(HAND_BONE) != -1:
		att.bone_name = HAND_BONE
	body.add_child(att)
	root.set_meta("attach", att)
	set_weapon(root, "zclaw" if zombie else "vx9")
	# 默认 Idle
	if ap != null:
		ap.play("Idle")
	return root


static func _hide_meshes(sk: Skeleton3D) -> void:
	# 隐藏模板网格（Mannequin 网格是 Skeleton 的子节点）
	for c in sk.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		elif c is Node3D:
			_hide_node_meshes(c as Node3D)


static func _hide_node_meshes(n: Node3D) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		elif c is Node3D:
			_hide_node_meshes(c as Node3D)


# 盒人部件材质/网格缓存：颜色仅 3 种（CT/T/僵尸）、部件尺寸 15 种，
# 全量缓存避免每角色重复创建（20 人局 = 300+ 次 StandardMaterial3D/BoxMesh 创建）
static var _part_mat_cache: Dictionary = {}
static var _part_mesh_cache: Dictionary = {}


static func _build_parts(root: Node3D, sk: Skeleton3D, team: int, zombie: bool) -> Array:
	var parts: Array = []
	var color: Color = _team_color(team, zombie)
	var mat: Material = _part_mat(color)
	for spec in BOX_PARTS:
		var pidx: int = sk.find_bone(str(spec.parent)) if sk != null else -1
		var cidx: int = sk.find_bone(str(spec.child)) if sk != null and str(spec.child) != "" else -1
		var mi := MeshInstance3D.new()
		mi.mesh = _part_mesh(spec.size)
		mi.material_override = mat
		mi.name = str(spec.name)
		root.add_child(mi)
		parts.append({"mi": mi, "pidx": pidx, "cidx": cidx})
	return parts


static func _part_mat(c: Color) -> Material:
	var key: String = c.to_html()
	if _part_mat_cache.has(key):
		return _part_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.05
	m.roughness = 0.8
	_part_mat_cache[key] = m
	return m


static func _part_mesh(size: Vector3) -> BoxMesh:
	var key: String = str(size)
	if _part_mesh_cache.has(key):
		return _part_mesh_cache[key]
	var bm := BoxMesh.new()
	bm.size = size
	_part_mesh_cache[key] = bm
	return bm


# 每帧把盒人部件摆到骨骼姿态上：双骨部件取两骨中点、长轴沿骨骼方向；
# 单骨部件（头/手/脚）直接取骨骼原点与朝向。
static func _pose_parts(root: Node3D) -> void:
	var sk: Skeleton3D = root.get_meta("skeleton", null)
	var body: Node3D = root.get_meta("body", null)
	var parts: Array = root.get_meta("parts", [])
	if sk == null or body == null or parts.is_empty():
		return
	# body = R(180°)：骨架脸(+Z)/迈步(±Z) → 世界 -Z/∓Z（面朝前进、前后迈步）。
	# 所有部件直接 body × 骨全局变换即可，无需额外旋转修正。
	var xf: Transform3D = body.transform
	for part in parts:
		var mi: MeshInstance3D = part.mi
		var pidx: int = part.pidx
		var cidx: int = part.cidx
		if pidx < 0 or pidx >= sk.get_bone_count():
			continue
		var bp: Transform3D = sk.get_bone_global_pose(pidx)
		if cidx >= 0 and cidx < sk.get_bone_count():
			var cp: Transform3D = sk.get_bone_global_pose(cidx)
			# 双骨部件（躯干/臀/四肢）：位置取两骨中点，旋转继承起始骨
			var pos: Vector3 = (bp.origin + cp.origin) * 0.5
			mi.transform = xf * Transform3D(Basis(bp.basis), pos)
		else:
			# 单骨部件（头/手/脚）：直接继承骨全局变换
			mi.transform = xf * bp


static func set_team_material(root: Node3D, team: int) -> void:
	var zombie: bool = bool(root.get_meta("zombie"))
	root.set_meta("team", team)
	var color: Color = _team_color(team, zombie)
	var parts: Array = root.get_meta("parts", [])
	for part in parts:
		var mi: MeshInstance3D = part.mi
		mi.material_override = _part_mat(color)


# 挂武器到右手骨：ViewmodelFactory 的武器模型作为 BoneAttachment 子节点
static func set_weapon(root: Node3D, weapon_id: String) -> void:
	var wid: String = weapon_id
	if wid == "":
		wid = "zclaw" if bool(root.get_meta("zombie")) else "vx9"
	var attach: Node3D = root.get_meta("attach", null)
	if attach == null:
		return
	for c in attach.get_children():
		c.queue_free()
	var vm: Node3D = ViewmodelFactory.build(wid)
	vm.scale = Vector3(0.45, 0.45, 0.45)
	# 武器把手对齐右手骨：沿 Z 前伸（枪口朝前）；盒人手臂较短，位置稍贴手
	vm.position = Vector3(0.02, 0.0, -0.06)
	vm.rotation = Vector3(0, 0, 0)
	attach.add_child(vm)
	root.set_meta("weapon_id", wid)
	root.set_meta("weapon_vm", vm)


static func _is_pistol(wid: String) -> bool:
	return wid in ["k9", "pc", "pf"]


static func _is_melee(wid: String) -> bool:
	return wid == "fang" or wid == "zclaw"


# 动画状态机（模板动画库）：
# - 姿态（循环）：Idle / Walk / Sprint / Crouch_*；手枪用 Pistol_Idle/Pistol_Aim_Neutral；
#   近战待机 Sword_Idle；跳跃 Jump。move_dot 表示移动相对面朝方向的角度
#   （1=正前，≈0=横移，<0=后退）：斜走/横移/后退一律不播跑步，只播 Walk（3A 行为）
# - 覆盖（一次性，播完回姿态）：近战攻击 Sword_Attack/Punch_Jab、手枪射击 Pistol_Shoot、
#   受击 Hit_Chest、落地 Jump_Land
# - 死亡 Death01（播完停住）
static func animate(root: Node3D, dt: float, speed: float, crouch: bool, alive: bool, time: float, melee_attacking: bool = false, weapon_id: String = "", firing: bool = false, vy: float = 0.0, grounded: bool = true, hit: bool = false, move_dot: float = 1.0) -> void:
	var ap: AnimationPlayer = root.get_meta("animplayer", null)
	if ap == null:
		_pose_parts(root)
		return
	if not alive:
		if ap.current_animation != "Death01":
			ap.play("Death01")
		_pose_parts(root)
		return
	# 落地检测：前一帧快速下落且现在接地/不再下落 → 触发 Jump_Land 覆盖
	var prev_vy: float = float(root.get_meta("prev_vy", 0.0))
	var land_until: float = float(root.get_meta("land_until", -1.0))
	if prev_vy < -0.8 and (vy >= -0.4 or grounded):
		land_until = time + 0.7
		root.set_meta("land_until", land_until)
	root.set_meta("prev_vy", vy)
	# 受击/落地/攻击/射击覆盖
	var cover: String = _cover_anim(weapon_id, melee_attacking, firing, hit, time < land_until)
	if cover != "":
		if ap.current_animation != cover:
			ap.play(cover, -1, 1.0, false)
		_pose_parts(root)
		_weapon_recoil(root, time, firing)
		return
	# 覆盖播完或常态：回到姿态动画（普通 play；from_end 会导致切换后 current 清空）
	var pose: String = _pose_anim(speed, crouch, weapon_id, vy, move_dot)
	if ap.current_animation != pose:
		ap.play(pose, -1, 1.0, false)
	_pose_parts(root)
	_weapon_recoil(root, time, firing)


# 一次性覆盖动画（优先级：攻击 > 受击 > 射击 > 落地）
static func _cover_anim(weapon_id: String, melee_attacking: bool, firing: bool, hit: bool, landing: bool) -> String:
	if melee_attacking:
		if _is_melee(weapon_id) and weapon_id != "zclaw":
			return "Sword_Attack"
		return "Punch_Jab"
	if hit:
		return "Hit_Chest"
	if firing and _is_pistol(weapon_id):
		return "Pistol_Shoot"
	if landing:
		return "Jump_Land"
	return ""


# 循环姿态动画。move_dot：移动相对面朝的角度（1 正前 / ≈0 横移 / <0 后退）。
# 只有"明显向前"才 Sprint；斜走/横移/后退降级为 Walk（播放速度按实际速率缩放）。
static func _pose_anim(speed: float, crouch: bool, weapon_id: String, vy: float, move_dot: float = 1.0) -> String:
	if crouch:
		return "Crouch_Fwd" if speed > 0.3 else "Crouch_Idle"
	if vy > 0.8 or vy < -0.8:
		return "Jump"
	if _is_pistol(weapon_id):
		if speed < 0.3:
			return "Pistol_Idle"
		if speed >= 5.0 and move_dot > 0.7:
			return "Sprint"
		return "Pistol_Aim_Neutral"
	if _is_melee(weapon_id) and speed < 0.3:
		return "Sword_Idle"
	if speed < 0.3:
		return "Idle"
	if speed >= 5.0 and move_dot > 0.7:
		return "Sprint"
	return "Walk"


# 射击后座：持枪时开火，武器向前短促前冲（长枪无射击动画，用后座表现）
static func _weapon_recoil(root: Node3D, time: float, firing: bool) -> void:
	var vm: Node3D = root.get_meta("weapon_vm", null)
	if vm == null:
		return
	if firing:
		var kick: float = absf(sin(time * 22.0)) * 0.02
		vm.position.z = -0.06 - kick
	else:
		vm.position.z = lerpf(vm.position.z, -0.06, 0.2)
