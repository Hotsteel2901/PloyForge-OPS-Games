# WorldRenderer: builds the map + dynamic entities (players, projectiles, bomb, boxes) and
# drives character animation. Reads the sim state every frame (interpolating transforms).
class_name WorldRenderer
extends Node3D

var _map_root: Node3D = null
var _players_root: Node3D = null
var _dyn_root: Node3D = null
var effects: Effects = null
var _player_nodes: Dictionary = {}   # id -> Node3D
var _player_prev_pos: Dictionary = {}  # id -> Vector3（平行数组，避免每帧字典分配）
var _player_prev_yaw: Dictionary = {}  # id -> float
var _proj_nodes: Dictionary = {}     # proj_id -> Node3D
var _bomb_node: Node3D = null
var _bomb_light: MeshInstance3D = null
var _bomb_beep: MeshInstance3D = null
var _box_nodes: Array = []
var _current_map_id: String = ""

var local_player_id: String = ""
var _anim_clock: float = 0.0


func _ready() -> void:
	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	_dyn_root = Node3D.new()
	_dyn_root.name = "Dynamic"
	add_child(_dyn_root)
	effects = Effects.new()
	effects.name = "Effects"
	add_child(effects)


func build_map(map_data: Dictionary, map_id: String) -> void:
	if map_id == _current_map_id and _map_root != null:
		return
	clear_map()
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child(_map_root)
	MapBuilder.build(_map_root, map_data)
	_current_map_id = map_id
	# atmosphere: sky, sun, fog, GI, post-FX
	var env_node: Node = get_node_or_null("Env")
	if env_node != null:
		env_node.queue_free()
	var env := GameEnvironment.create(map_data.get("sky", {}))
	env.name = "Env"
	add_child(env)
	# ammo / health boxes
	_box_nodes.clear()
	for box in map_data.get("ammoBoxes", []):
		var node_a := _build_box(Color("d9a92f"), Color("6b4d00"), 1.2, 0.8)
		var pos_a: Variant = box.get("pos", null)
		if pos_a != null and pos_a is Vector3:
			node_a.position = Vector3(pos_a.x, pos_a.y + 0.35, pos_a.z)
		_map_root.add_child(node_a)
		_box_nodes.append({"node": node_a, "box": box})
	for box in map_data.get("healthBoxes", []):
		var node_h := _build_box(Color("2fbf71"), Color("0c5c2e"), 1.2, 0.8)
		var pos_h: Variant = box.get("pos", null)
		if pos_h != null and pos_h is Vector3:
			node_h.position = Vector3(pos_h.x, pos_h.y + 0.35, pos_h.z)
		_map_root.add_child(node_h)
		_box_nodes.append({"node": node_h, "box": box})


func _build_box(body: Color, edge: Color, sx: float, sz: float) -> Node3D:
	var g := Node3D.new()
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(sx, 0.7, sz)
	m.mesh = box
	m.material_override = MaterialLib.solid(body, 0.15, 0.65)
	g.add_child(m)
	var top := MeshInstance3D.new()
	var box2 := BoxMesh.new()
	box2.size = Vector3(sx, 0.08, sz)
	top.mesh = box2
	top.material_override = MaterialLib.emissive(edge.lightened(0.4), 1.6)
	top.position.y = 0.36
	g.add_child(top)
	g.position.y = 0.35
	return g


func clear_map() -> void:
	if _map_root != null:
		_map_root.queue_free()
		_map_root = null
	_current_map_id = ""
	_bomb_node = null
	for n in _player_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	_player_nodes.clear()
	_player_prev_pos.clear()
	_player_prev_yaw.clear()
	for n in _proj_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	_proj_nodes.clear()
	_box_nodes.clear()
	effects.clear_all()


func render_state(state: Dictionary, alpha: float) -> void:
	# 动画时钟改用模拟时间（state.time）：与 lastHitAt 同源，消除硬编码 60Hz
	# 在高刷显示器（144Hz）或 Web（30fps）下动画/受击窗口错位的问题。
	var sim_time: float = float(state.get("time", 0.0))
	var dt: float = clampf(sim_time - _anim_clock, 0.0, 0.2)
	_anim_clock = sim_time
	var players: Dictionary = state.get("players", {})
	var seen: Dictionary = {}
	for pid in players:
		var p: Dictionary = players[pid]
		if pid == local_player_id:
			seen[pid] = true
			continue
		seen[pid] = true
		_update_player(p, alpha, dt)
	# cleanup
	var to_remove: Array = []
	for pid in _player_nodes:
		if not seen.has(pid):
			to_remove.append(pid)
	for pid in to_remove:
		if is_instance_valid(_player_nodes[pid]):
			_player_nodes[pid].queue_free()
		_player_nodes.erase(pid)
		_player_prev_pos.erase(pid)
		_player_prev_yaw.erase(pid)
	# projectiles
	var projs: Array = state.get("projectiles", [])
	var seen_proj: Dictionary = {}
	for pr in projs:
		seen_proj[pr.id] = true
		if not _proj_nodes.has(pr.id):
			var node := Node3D.new()
			var sm := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.08
			sph.height = 0.16
			sm.mesh = sph
			sm.material_override = MaterialLib.solid(Color("4a5a3a"), 0.2, 0.5)
			node.add_child(sm)
			_dyn_root.add_child(node)
			_proj_nodes[pr.id] = node
		var pn: Node3D = _proj_nodes[pr.id]
		pn.position = Vector3(pr.pos.x, pr.pos.y, pr.pos.z)
		pn.rotation.x = _anim_clock * 6.0
	for pid in _proj_nodes:
		if not seen_proj.has(pid):
			if is_instance_valid(_proj_nodes[pid]):
				_proj_nodes[pid].queue_free()
			_proj_nodes.erase(pid)
	# bomb
	_render_bomb(state)
	# boxes availability
	for b in _box_nodes:
		b.node.visible = bool(b.box.get("available", true))


func _update_player(p: Dictionary, alpha: float, dt: float) -> void:
	var pid: String = p.id
	var node: Node3D = _player_nodes.get(pid, null)
	if node == null or not is_instance_valid(node):
		node = CharacterFactory.build(int(p.team), bool(p.isZombie))
		_players_root.add_child(node)
		_player_nodes[pid] = node
		_player_prev_pos[pid] = p.pos
		_player_prev_yaw[pid] = float(p.yaw)
	# 队伍/僵尸状态变化时（如开局才分配队伍、人类被感染变僵尸）重建角色，否则颜色/外观永远是旧队伍
	var cur_team: int = int(node.get_meta("team_id", -99))
	var cur_zombie: bool = bool(node.get_meta("zombie_id", false))
	if cur_team != int(p.team) or cur_zombie != bool(p.isZombie):
		_players_root.remove_child(node)
		node.queue_free()
		node = CharacterFactory.build(int(p.team), bool(p.isZombie))
		node.position = Vector3(p.pos.x, p.pos.y, p.pos.z)
		node.rotation.y = float(p.yaw)
		_players_root.add_child(node)
		_player_nodes[pid] = node
		_player_prev_pos[pid] = p.pos
		_player_prev_yaw[pid] = float(p.yaw)
	node.set_meta("team_id", int(p.team))
	node.set_meta("zombie_id", bool(p.isZombie))
	# interpolation（平行数组替代每帧字典分配）
	var prev_pos: Vector3 = _player_prev_pos.get(pid, p.pos)
	var prev_yaw: float = _player_prev_yaw.get(pid, float(p.yaw))
	var pos := prev_pos.lerp(Vector3(p.pos.x, p.pos.y, p.pos.z), clampf(alpha, 0.0, 1.0))
	var yaw: float = lerp_angle(prev_yaw, float(p.yaw), clampf(alpha, 0.0, 1.0))
	node.position = pos
	node.rotation.y = yaw
	node.visible = bool(p.alive)
	_player_prev_pos[pid] = Vector3(p.pos.x, p.pos.y, p.pos.z)
	_player_prev_yaw[pid] = float(p.yaw)
	# weapon in hands
	var active_def: Dictionary = {}
	if p.weapons.has(int(p.activeSlot)):
		active_def = p.weapons[int(p.activeSlot)].def
	var wpn_id: String = "vx9"
	if not active_def.is_empty():
		wpn_id = str(active_def.get("id", "vx9"))
	if node.get_meta("wpn_id", "") != wpn_id:
		node.set_meta("wpn_id", wpn_id)
		CharacterFactory.set_weapon(node, wpn_id)
	# animation
	var speed: float = Vector2(p.vel.x, p.vel.z).length() if p.has("vel") else 0.0
	# 近战攻击检测：当前是近战武器且正在开火（挥砍/抓挠触发第三人称攻击动画）
	var melee_attacking: bool = false
	if not active_def.is_empty() and active_def.get("melee", false) and bool(p.input.fire):
		melee_attacking = true
	# 射击检测（非近战）：开火时播射击动画/武器后座
	var firing: bool = not active_def.is_empty() and not active_def.get("melee", false) and bool(p.input.fire)
	# 受击检测：最近 0.35s 内被打（_anim_clock 为秒数时钟）
	var hit: bool = float(p.get("lastHitAt", -99.0)) >= _anim_clock - 0.35
	# 移动方向与面朝方向的夹角（用于 strafe 动画判定）：
	# move_dot = 移动方向 · 面朝方向（1=正前走，-1=倒走，≈0=横移）
	var move_dot: float = 1.0
	if speed > 0.4 and p.has("vel"):
		var mvx: float = p.vel.x
		var mvz: float = p.vel.z
		var mvl: float = sqrt(mvx * mvx + mvz * mvz)
		if mvl > 0.001:
			var fx: float = -sin(float(p.yaw))
			var fz: float = -cos(float(p.yaw))
			move_dot = (mvx * fx + mvz * fz) / mvl
	CharacterFactory.animate(node, dt, speed, bool(p.crouch), bool(p.alive), _anim_clock, melee_attacking, wpn_id, firing, float(p.vel.y) if p.has("vel") else 0.0, bool(p.get("grounded", true)), hit, move_dot)
	_update_tag(node, p)


var _bar_mat_cache: Dictionary = {}


func _bar_mat(c: Color) -> Material:
	var key: String = c.to_html()
	if _bar_mat_cache.has(key):
		return _bar_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_mat_cache[key] = m
	return m


# 玩家头顶名牌 + 血条：任何距离都能分清敌我（CT 蓝 / T 红 / 僵尸绿）
func _update_tag(node: Node3D, p: Dictionary) -> void:
	var tag: Node3D = node.get_node_or_null("Tag")
	if tag == null:
		tag = Node3D.new()
		tag.name = "Tag"
		tag.position = Vector3(0, 2.1, 0)
		node.add_child(tag)
		var lbl := Label3D.new()
		lbl.name = "Name"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true   # 血条始终可见，不被角色身体/墙体遮挡（修复不同角度时隐时现）
		lbl.pixel_size = 0.0032
		lbl.font_size = 64
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0, 0, 0, 0.92)
		lbl.position = Vector3(0, 0.22, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_child(lbl)
		var bg := MeshInstance3D.new()
		bg.name = "BarBg"
		var q := QuadMesh.new()
		q.size = Vector2(0.62, 0.06)
		q.orientation = PlaneMesh.FACE_Z
		bg.mesh = q
		bg.position = Vector3(0, 0.08, 0)
		bg.material_override = _bar_mat(Color(0, 0, 0, 0.85))
		bg.get_material_override().no_depth_test = true
		tag.add_child(bg)
		var fg := MeshInstance3D.new()
		fg.name = "BarFg"
		var q2 := QuadMesh.new()
		q2.size = Vector2(0.6, 0.045)
		q2.orientation = PlaneMesh.FACE_Z
		fg.mesh = q2
		fg.position = Vector3(0, 0.08, 0.01)
		fg.material_override = _bar_mat(Color(1, 1, 1))
		fg.get_material_override().no_depth_test = true
		tag.add_child(fg)
	var lbl: Label3D = null
	if tag.has_meta("name_lbl"):
		lbl = tag.get_meta("name_lbl")
	if lbl == null:
		lbl = tag.get_node("Name")
		tag.set_meta("name_lbl", lbl)
	var name_text: String = str(p.get("name", "?"))
	# Label3D 文本变更触发字体整形：仅名称变化时赋值（每帧 20 次整形 → 0 次）
	if lbl.text != name_text:
		lbl.text = name_text
	var team_col: Color = Color("4a9dff")
	if bool(p.isZombie):
		team_col = Color("4fe07a")
	elif int(p.team) == 2:
		team_col = Color("ff5a3d")
	lbl.modulate = team_col
	var fg: MeshInstance3D = null
	if tag.has_meta("bar_fg"):
		fg = tag.get_meta("bar_fg")
	if fg == null:
		fg = tag.get_node("BarFg")
		tag.set_meta("bar_fg", fg)
	var col_key: String = team_col.to_html()
	if tag.get_meta("bar_col", "") != col_key:
		tag.set_meta("bar_col", col_key)
		fg.material_override = _bar_mat(team_col)
	var frac: float = clampf(float(p.get("hp", 100)) / max(1.0, float(p.get("maxHp", 100))), 0.0, 1.0)
	fg.scale = Vector3(frac, 1, 1)
	fg.position.x = -(0.6 * (1.0 - frac)) / 2.0


func _hide_bomb() -> void:
	if _bomb_node != null and is_instance_valid(_bomb_node):
		_bomb_node.queue_free()
		_bomb_node = null
	_bomb_light = null
	_bomb_beep = null


func _render_bomb(state: Dictionary) -> void:
	var b: Dictionary = state.get("bomb", {})
	if b.is_empty() or (not b.get("planted", false) and not b.get("carried", false) and b.get("pos", null) == null):
		_hide_bomb()
		return
	var pos: Vector3
	if b.get("carried", false):
		var carrier_id: String = str(b.get("carrierId", ""))
		var players: Dictionary = state.get("players", {})
		if carrier_id != "" and players.has(carrier_id):
			var cp: Dictionary = players[carrier_id]
			pos = Vector3(cp.pos.x, cp.pos.y, cp.pos.z) + Vector3(0, 1.15, 0.0)
		else:
			# 携带者不存在/已移除：必须隐藏炸弹，否则残留上一帧位置的"假炸弹"
			_hide_bomb()
			return
	else:
		var bp: Variant = b.get("pos", null)
		if bp == null:
			_hide_bomb()
			return
		pos = Vector3(bp.x, bp.y, bp.z)
	if _bomb_node == null or not is_instance_valid(_bomb_node):
		_bomb_node = _build_bomb()
		_bomb_light = _bomb_node.get_node("Light")
		_bomb_beep = _bomb_node.get_node("Beep")
		_dyn_root.add_child(_bomb_node)
	_bomb_node.position = pos
	if b.get("planted", false):
		var blink: bool = fmod(_anim_clock, 0.6) < 0.3
		_bomb_light.visible = blink
		_bomb_beep.scale = Vector3.ONE * (1.0 + (0.6 - fmod(_anim_clock, 0.6)) * 2.0) if blink else Vector3.ONE


func _build_bomb() -> Node3D:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.16, 0.22)
	body.mesh = box
	body.material_override = MaterialLib.solid(Color("37413a"), 0.4, 0.5)
	g.add_child(body)
	var light := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.035
	sph.height = 0.07
	light.mesh = sph
	light.name = "Light"
	light.material_override = MaterialLib.emissive(Color("ff2020"), 3.0)
	light.position = Vector3(0.12, 0.08, 0.06)
	g.add_child(light)
	var beep := MeshInstance3D.new()
	var sph2 := SphereMesh.new()
	sph2.radius = 0.012
	sph2.height = 0.024
	beep.mesh = sph2
	beep.name = "Beep"
	beep.material_override = MaterialLib.emissive(Color("ff8080"), 2.0)
	beep.position = Vector3(0.12, 0.1, 0.06)
	g.add_child(beep)
	return g


func on_shot(from: Vector3, dir: Vector3, dist: float, weapon_id: String, hit_pos: Variant = null) -> void:
	var end: Vector3 = hit_pos if hit_pos != null else from + dir * min(dist, 80.0)
	effects.tracer(from, end)
	effects.muzzle_flash(from, dir)
	if hit_pos != null:
		effects.impact(hit_pos)


func on_hit(pos: Vector3, headshot: bool) -> void:
	effects.blood(pos)
	effects.impact(pos, Vector3.UP, Color("ff6060") if headshot else Color("ffaa50"))


func on_explosion(pos: Vector3) -> void:
	effects.explosion(pos)


func on_muzzle_flash(pos: Vector3, dir: Vector3 = Vector3.FORWARD) -> void:
	effects.muzzle_flash(pos, dir)


func on_shell(pos: Vector3, dir: Vector3) -> void:
	effects.shell_casing(pos, dir)


func clear_effects() -> void:
	effects.clear_all()
