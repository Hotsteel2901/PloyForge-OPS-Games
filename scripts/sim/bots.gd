# Bot AI v2：感知 → 记忆 → 决策（效用）→ 移动（A*）→ 战斗（人类化瞄准）。
# 设计目标：
#   1) 看起来像人：反应时间、预瞄、抖动、点射节奏、假动作、後撤
#   2) 会打目标：按模式接管控点/拆包/夺旗/生存
#   3) 便宜：寻路 A* + 路径缓存，单帧 O(节点)，不产生 GC 压力
class_name BotBrain
extends RefCounted

# ---------------- 难度档 ----------------
const DIFFICULTY: Dictionary = {
	"easy":   {"skill": 0.30, "react": 0.42, "err": 1.55, "fov": 110.0, "hearing": 18.0, "aim_speed": 0.55, "burst": 0.5},
	"normal": {"skill": 0.55, "react": 0.28, "err": 1.10, "fov": 130.0, "hearing": 24.0, "aim_speed": 0.85, "burst": 0.75},
	"hard":   {"skill": 0.78, "react": 0.19, "err": 0.72, "fov": 150.0, "hearing": 30.0, "aim_speed": 1.20, "burst": 0.9},
	"elite":  {"skill": 0.95, "react": 0.13, "err": 0.45, "fov": 170.0, "hearing": 36.0, "aim_speed": 1.6, "burst": 1.0},
	"insane": {"skill": 1.10, "react": 0.09, "err": 0.28, "fov": 200.0, "hearing": 44.0, "aim_speed": 2.1, "burst": 1.0},
}

const SIGHT_RANGE: float = 80.0
const NAV_ARRIVE: float = 1.2
const REPATH_INTERVAL: float = 1.4


static func create_brain(difficulty: float = -1.0) -> Dictionary:
	var skill: float = difficulty
	if skill < 0.0:
		skill = 0.35 + randf() * 0.75
	var tier: int = clampi(int(skill * 4.0), 0, 4)
	var keys: Array = ["easy", "normal", "hard", "elite", "insane"]
	var prof: Dictionary = DIFFICULTY[keys[tier]]
	return {
		"skill": skill,
		"profile": prof,
		"tier": keys[tier],
		# 感知
		"target": null, "target_id": "", "seen_at": -99.0, "last_seen_pos": null,
		"alert": 0.0, "react_at": 0.0, "fov": float(prof.fov),
		"memory": {},          # enemy_id -> {pos, t, conf}
		"hear_pos": null, "hear_at": -99.0,
		# 瞄准
		"aim_err": Vector2.ZERO, "aim_refresh": 0.0, "aim_smooth": Vector2.ZERO,
		"recoil_comp": 0.0,
		# 移动
		"goal": null, "goal_kind": "", "path": [], "next_node": null,
		"repath_at": 0.0, "stuck": 0.0, "last_pos": null, "slide_dir": 1, "slide_until": 0.0,
		"strafe_dir": 1, "strafe_at": 0.0, "jump_at": -99.0,
		# 战斗节奏
		"burst_until": 0.0, "attack_at": 0.0, "reload_at": 0.0,
		# 目标行为
		"role": "entry", "hold_until": 0.0, "cover_pos": null,
		# 统计
		"kills": 0, "deaths": 0,
	}


static func reset_brain(brain: Dictionary) -> void:
	var fresh: Dictionary = create_brain(float(brain.get("skill", 0.6)))
	for k in fresh:
		brain[k] = fresh[k]


# =====================================================================
# 主入口
# =====================================================================
static func tick_bot(room: Dictionary, bot: Dictionary) -> void:
	var b: Dictionary = bot.botBrain
	var input: Dictionary = bot.input
	# 重置输入
	input.mv = [0, 0, 0, 0]
	input.j = false
	input.fire = false
	input.r = false
	input.u = false
	input.s = false
	input.c = false
	input.ads = false
	input.sw = -1
	input.swd = 0
	bot.edge.sw = -1
	bot.edge.swd = 0
	if not bot.alive:
		return
	var now: float = float(room.time)

	_update_stuck(room, bot, b, now)
	var enemy: Variant = _perceive(room, bot, b, now)
	_decide(room, bot, b, enemy, now)

	if enemy != null:
		var ed: float = _dist(bot.pos, enemy.pos)
		var los: bool = _has_los(room, bot, enemy)
		if los and ed < SIGHT_RANGE:
			_engage(room, bot, b, enemy, ed, now)
		elif b.last_seen_pos != null and now - float(b.seen_at) < 6.0:
			# 追踪最后已知位置
			if b.goal == null or b.goal_kind != "hunt":
				b.goal = b.last_seen_pos
				b.goal_kind = "hunt"
				_repath(room, bot, b, now)
			_follow_path(room, bot, b, now)
		else:
			_follow_path(room, bot, b, now)
	else:
		_follow_path(room, bot, b, now)

	_objective(room, bot, b, now)
	_separate(room, bot, b)
	if float(b.stuck) > 0.35 and now < float(b.slide_until) and not input.u:
		input.mv = [0, 0, 0, 0]
		input.mv[3 if int(b.slide_dir) == 1 else 2] = 1


# =====================================================================
# 感知
# =====================================================================
static func _perceive(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> Variant:
	var fwd: Vector3 = MathUtil.direction_from_angles(float(bot.yaw), float(bot.pitch))
	var best: Variant = null
	var best_score: float = -INF
	var mem: Dictionary = b.memory
	for p in room.players.values():
		if p == bot or not p.alive:
			continue
		if not bool(room.isHostile.call(bot, p)):
			continue
		var d: float = _dist(bot.pos, p.pos)
		if d > SIGHT_RANGE:
			continue
		var to: Vector3 = (p.pos - bot.pos)
		to.y = 0.0
		var dot: float = fwd.normalized().dot(to.normalized()) if to.length() > 0.01 else -1.0
		var half_fov: float = cos(deg_to_rad(float(b.fov) * 0.5))
		var visible: bool = false
		if dot > half_fov or d < 4.0:
			visible = _has_los(room, bot, p)
		# 听觉：最近的开枪声会暴露位置
		if not visible and b.hear_pos != null and now - float(b.hear_at) < 2.0:
			if _dist(p.pos, b.hear_pos) < 6.0:
				visible = true
		if visible:
			mem[p.id] = {"pos": p.pos, "t": now, "conf": 1.0}
			b.last_seen_pos = p.pos
			b.seen_at = now
			# 评分：近 + 正对 + 血量低 优先
			var score: float = 200.0 - d * 2.0 + dot * 40.0
			if float(p.hp) < 40.0:
				score += 25.0
			if p == b.target:
				score += 12.0
			if score > best_score:
				best_score = score
				best = p
		elif mem.has(p.id):
			var m: Dictionary = mem[p.id]
			if now - float(m.t) > 12.0:
				mem.erase(p.id)
	# 目标切换 → 重置反应计时
	if best != null and str(best.id) != str(b.target_id):
		b.target_id = str(best.id)
		b.react_at = now + float(b.profile.react) * (1.25 - float(b.skill) * 0.4)
		b.aim_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(b.profile.err) * 0.6
	if best == null:
		b.target = null
		b.target_id = ""
	b.target = best
	return best


static func _has_los(room: Dictionary, a: Dictionary, c: Dictionary) -> bool:
	var origin := Vector3(a.pos.x, a.pos.y + 1.55, a.pos.z)
	var target := Vector3(c.pos.x, c.pos.y + 1.25, c.pos.z)
	var d: float = origin.distance_to(target)
	if d < 0.5:
		return true
	var dir: Vector3 = (target - origin) / d
	var tw: float = Hitscan.trace_world(room.map, origin, dir, d)
	if tw < d - 0.4:
		return false
	if Room.smoke_blocked(room.smokes, origin, target):
		return false
	return true


# =====================================================================
# 决策
# =====================================================================
static func _decide(room: Dictionary, bot: Dictionary, b: Dictionary, _enemy: Variant, now: float) -> void:
	if now < float(b.repath_at) and b.goal != null:
		return
	b.repath_at = now + REPATH_INTERVAL * (0.7 + randf() * 0.6)
	var goal: Variant = _choose_goal(room, bot, b, now)
	if goal == null:
		return
	var changed: bool = b.goal == null or _goal_changed(b.goal, goal)
	b.goal = goal
	if changed:
		_repath(room, bot, b, now)


static func _goal_changed(a: Variant, c: Variant) -> bool:
	if a == null or c == null:
		return true
	if a is Vector3 and c is Vector3:
		return a.distance_to(c) > 3.0
	return true


static func _choose_goal(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> Variant:
	var mode: String = str(room.mode)
	if mode == Constants.MODE_DEFUSAL:
		return _goal_defusal(room, bot, b, now)
	if mode == "koth":
		return _goal_koth(room, bot, b)
	if mode == "ctf":
		return _goal_ctf(room, bot, b)
	if mode == Constants.MODE_ZOMBIE or mode == "survival":
		return _goal_zombie(room, bot, b, now)
	return _goal_deathmatch(room, bot, b, now)


static func _goal_defusal(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> Variant:
	var sites: Array = room.map.get("sites", [])
	var bomb: Dictionary = room.bomb
	var core = room.core
	var planted: bool = core != null and bool(core.bomb_planted)
	if bot.team == Constants.TEAM_T:
		if bool(bot.bombCarrier):
			# 带包：去人少的点
			var pick: Dictionary = sites[randi() % maxi(1, sites.size())] if not sites.is_empty() else {}
			if pick.is_empty():
				return _nav_point(room)
			return pick.pos
		if planted:
			# 守包
			if bomb.pos != null:
				return _offset_near(bomb.pos, 7.0)
			return _nav_point(room)
		if bomb.pos != null and not bomb.carried and now - float(b.seen_at) > 3.0:
			return bomb.pos
		var site: Dictionary = sites[randi() % maxi(1, sites.size())]
		return site.pos if not sites.is_empty() else _nav_point(room)
	# CT
	if planted and bomb.pos != null:
		return bomb.pos
	# 分散守点
	var idx: int = abs(hash(bot.id)) % maxi(1, sites.size())
	if not sites.is_empty():
		return _offset_near(sites[idx].pos, 6.0)
	return _nav_point(room)


static func _goal_koth(room: Dictionary, bot: Dictionary, _b: Dictionary) -> Variant:
	var m: Dictionary = room.modeExtra.call()
	if m.has("hill"):
		return m.hill
	return _nav_point(room)


static func _goal_ctf(room: Dictionary, bot: Dictionary, b: Dictionary) -> Variant:
	var ex: Dictionary = room.modeExtra.call()
	var key: String = "flagT" if bot.team == Constants.TEAM_CT else "flagCT"
	if ex.has(key):
		var f: Dictionary = ex[key]
		return Vector3(float(f.x), 0.0, float(f.z))
	return _nav_point(room)


static func _goal_zombie(room: Dictionary, bot: Dictionary, _b: Dictionary, _now: float) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for p in room.players.values():
		if not p.alive:
			continue
		if bool(room.isHostile.call(bot, p)):
			var d: float = _dist(bot.pos, p.pos)
			if d < best_d:
				best_d = d
				best = p
	if best != null:
		return best.pos
	return _nav_point(room)


static func _goal_deathmatch(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> Variant:
	# 血量低 → 找血包
	if float(bot.hp) < float(bot.maxHp) * 0.45:
		var hb: Variant = _nearest_box(room.healthBoxes, bot.pos)
		if hb != null:
			return hb.pos
	# 没子弹 → 找弹药
	var w: Variant = bot.weapons.get(int(bot.activeSlot), null)
	if w != null and is_finite(float(w.reserve)) and float(w.reserve) <= 0.0:
		var ab: Variant = _nearest_box(room.ammoBoxes, bot.pos)
		if ab != null:
			return ab.pos
	if b.target != null and now - float(b.seen_at) < 3.0:
		return b.target.pos
	# 巡逻：优先地图热点
	return _nav_point(room)


static func _nav_point(room: Dictionary) -> Variant:
	var nav: Array = room.map.get("nav", [])
	if nav.is_empty():
		return Vector3.ZERO
	var n: Dictionary = nav[randi() % nav.size()]
	return Vector3(n.x, float(n.get("y", 0.0)), n.z)


static func _offset_near(p: Vector3, r: float) -> Vector3:
	var a: float = randf() * TAU
	return Vector3(p.x + cos(a) * r, p.y, p.z + sin(a) * r)


static func _nearest_box(boxes: Array, pos: Vector3) -> Variant:
	var best: Variant = null
	var bd: float = INF
	for bx in boxes:
		if not bool(bx.get("available", true)):
			continue
		var d: float = _dist(pos, bx.pos)
		if d < bd:
			bd = d
			best = bx
	return best


# =====================================================================
# 寻路（A*，带二叉堆）
# =====================================================================
static func _repath(room: Dictionary, bot: Dictionary, b: Dictionary, _now: float) -> void:
	b.path = plan_path(room.map, bot.pos, b.goal)
	b.next_node = null
	if not b.path.is_empty():
		b.next_node = b.path.pop_front()


static var _path_cache: Dictionary = {}
static var _cache_tick: int = 0


## A*（二叉堆）。复杂度 O(E log V)，4000 节点约 1ms。
## 路径结果按 (起点, 终点) 缓存 3 秒，多个 bot 共享。
static func plan_path(map_data: Dictionary, from: Vector3, goal: Variant) -> Array:
	var nav: Array = map_data.get("nav", [])
	if nav.is_empty() or goal == null:
		return []
	var gp: Vector3 = goal if goal is Vector3 else Vector3(goal.x, goal.y, goal.z)
	var start: int = _nearest_nav(nav, from)
	var goal_idx: int = _nearest_nav(nav, gp)
	if start < 0 or goal_idx < 0:
		return []
	if start == goal_idx:
		return [nav[start]]
	var now: int = Time.get_ticks_msec()
	if now - _cache_tick > 4000:
		_cache_tick = now
		_path_cache.clear()
	var key: String = "%d:%d" % [start, goal_idx]
	if _path_cache.has(key):
		return _path_cache[key]
	var n: int = nav.size()
	var g: PackedFloat32Array = PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(n)
	closed.fill(0)
	g[start] = 0.0
	# 二叉堆：heap 存节点，hf 存 f 值
	var heap: PackedInt32Array = PackedInt32Array()
	var hf: PackedFloat32Array = PackedFloat32Array()
	heap.append(start)
	hf.append(_heur(nav[start], gp))
	var found: bool = false
	while not heap.is_empty():
		# pop
		var u: int = heap[0]
		var last: int = heap.size() - 1
		heap[0] = heap[last]
		hf[0] = hf[last]
		heap.resize(last)
		hf.resize(last)
		if last > 0:
			var i: int = 0
			while true:
				var l: int = i * 2 + 1
				var r: int = l + 1
				var m: int = i
				if l < heap.size() and hf[l] < hf[m]:
					m = l
				if r < heap.size() and hf[r] < hf[m]:
					m = r
				if m == i:
					break
				var tv: int = heap[i]
				heap[i] = heap[m]
				heap[m] = tv
				var tf: float = hf[i]
				hf[i] = hf[m]
				hf[m] = tf
				i = m
		if closed[u] == 1:
			continue
		closed[u] = 1
		if u == goal_idx:
			found = true
			break
		for li in nav[u].get("links", []):
			var v: int = int(li)
			if v < 0 or v >= n or closed[v] == 1:
				continue
			var ng: float = g[u] + _nav_cost(nav[u], nav[v])
			if ng < g[v]:
				g[v] = ng
				prev[v] = u
				# push
				heap.append(v)
				hf.append(ng + _heur(nav[v], gp))
				var c: int = heap.size() - 1
				while c > 0:
					var par: int = (c - 1) / 2
					if hf[par] <= hf[c]:
						break
					var tv2: int = heap[par]
					heap[par] = heap[c]
					heap[c] = tv2
					var tf2: float = hf[par]
					hf[par] = hf[c]
					hf[c] = tf2
					c = par
	if not found and prev[goal_idx] == -1:
		return []
	var path: Array = []
	var cur: int = goal_idx
	var guard: int = 0
	while cur != -1 and guard < 512:
		path.push_back(nav[cur])
		cur = prev[cur]
		guard += 1
	path.reverse()
	_path_cache[key] = path
	return path


static func _heur(a: Dictionary, gp: Vector3) -> float:
	return absf(float(a.x) - gp.x) + absf(float(a.z) - gp.z)


static func _nav_cost(a: Dictionary, c: Dictionary) -> float:
	var d: float = absf(float(a.x) - float(c.x)) + absf(float(a.z) - float(c.z))
	var dy: float = absf(float(a.get("y", 0.0)) - float(c.get("y", 0.0)))
	return d + dy * 2.5


static func _nearest_nav(nav: Array, pos: Vector3) -> int:
	var best: int = -1
	var bd: float = INF
	for i in nav.size():
		var p: Dictionary = nav[i]
		var dx: float = float(p.x) - pos.x
		var dy: float = float(p.get("y", 0.0)) - pos.y
		var dz: float = float(p.z) - pos.z
		var d: float = dx * dx + dz * dz + dy * dy * 3.0
		if d < bd:
			bd = d
			best = i
	return best


# =====================================================================
# 移动
# =====================================================================
static func _follow_path(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> void:
	var wp: Variant = b.next_node
	if wp == null:
		if not b.path.is_empty():
			wp = b.path.pop_front()
			b.next_node = wp
		elif b.goal != null:
			wp = b.goal
		else:
			return
	var target: Vector3 = wp if wp is Vector3 else Vector3(wp.x, float(wp.get("y", 0.0)), wp.z)
	var dx: float = target.x - bot.pos.x
	var dz: float = target.z - bot.pos.z
	var hd: float = sqrt(dx * dx + dz * dz)
	if hd < NAV_ARRIVE and wp == b.next_node:
		b.next_node = null
		if b.path.is_empty() and b.goal != null and hd < NAV_ARRIVE * 1.6:
			b.goal = null
		return
	# 需要跳跃
	var dy: float = target.y - bot.pos.y
	if dy > 0.55 and hd < 2.6 and dy < 2.2 and now - float(b.jump_at) > 0.8:
		b.jump_at = now
		bot.input.j = true
	if hd < 0.01:
		return
	var tx: float = dx / hd
	var tz: float = dz / hd
	# 朝向路径方向
	bot.yaw = MathUtil.ang_lerp(bot.yaw, atan2(-dx, -dz), 0.22)
	var fx: float = -sin(bot.yaw)
	var fz: float = -cos(bot.yaw)
	var rx: float = -fz
	var rz: float = fx
	var fwd: float = tx * fx + tz * fz
	var side: float = tx * rx + tz * rz
	if fwd > 0.15:
		bot.input.mv[0] = 1
	elif fwd < -0.15:
		bot.input.mv[1] = 1
	if side > 0.25:
		bot.input.mv[3] = 1
	elif side < -0.25:
		bot.input.mv[2] = 1
	# 空地冲刺
	if hd > 14.0 and dy < 0.2:
		bot.input.s = true


static func _update_stuck(_room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> void:
	var moved: float = 0.0
	if b.last_pos != null:
		moved = _dist(bot.pos, b.last_pos)
	b.last_pos = bot.pos
	var wants: bool = bot.input.mv[0] == 1 or bot.input.mv[1] == 1 or bot.input.mv[2] == 1 or bot.input.mv[3] == 1
	if wants and moved < 0.02:
		b.stuck = float(b.stuck) + 1.0 / float(Constants.TICK_RATE)
	else:
		b.stuck = maxf(0.0, float(b.stuck) - 0.06)
	if float(b.stuck) > 0.4:
		if now >= float(b.slide_until):
			b.slide_dir = -int(b.slide_dir)
			b.slide_until = now + 1.1
		if float(b.stuck) > 1.6:
			b.stuck = 0.0
			b.goal = _nav_point({"map": {"nav": []}}) if false else b.goal
			b.path = []
			b.next_node = null
			b.repath_at = 0.0


static func _separate(room: Dictionary, bot: Dictionary, _b: Dictionary) -> void:
	if bot.input.mv[0] == 0 and bot.input.mv[1] == 0 and bot.input.mv[2] == 0 and bot.input.mv[3] == 0:
		return
	var sx: float = 0.0
	var sz: float = 0.0
	for p in room.players.values():
		if p == bot or not p.alive:
			continue
		var dx: float = bot.pos.x - p.pos.x
		var dz: float = bot.pos.z - p.pos.z
		var d2: float = dx * dx + dz * dz
		if d2 < 0.01 or d2 > 5.76:
			continue
		var d: float = sqrt(d2)
		var push: float = (2.4 - d) / 2.4
		sx += (dx / d) * push
		sz += (dz / d) * push
	if absf(sx) < 0.2 and absf(sz) < 0.2:
		return
	# 只做侧向避让，避免破坏前进方向
	var fx: float = -sin(bot.yaw)
	var fz: float = -cos(bot.yaw)
	var side: float = sx * (-fz) + sz * fx
	if side > 0.25:
		bot.input.mv[3] = 1
	elif side < -0.25:
		bot.input.mv[2] = 1


# =====================================================================
# 战斗
# =====================================================================
static func _engage(room: Dictionary, bot: Dictionary, b: Dictionary, enemy: Dictionary, dist: float, now: float) -> void:
	# 切枪
	_manage_weapon(room, bot, b, dist)
	var w: Variant = bot.weapons.get(int(bot.activeSlot), null)
	var def: Dictionary = w.def if w != null else {}
	if bot.isZombie:
		_melee_zombie(room, bot, b, enemy, dist)
		return
	# 瞄准点：预瞄头部 + 移动提前量
	var aim := Vector3(enemy.pos.x, enemy.pos.y + 1.42, enemy.pos.z)
	var evel: Vector3 = enemy.get("vel", Vector3.ZERO)
	var travel: float = dist / maxf(80.0, float(def.get("muzzleVelocity", 300.0)))
	aim += evel * travel * 0.55
	var eye := Vector3(bot.pos.x, bot.pos.y + 1.55, bot.pos.z)
	var d: Vector3 = aim - eye
	var want_yaw: float = atan2(-d.x, -d.z)
	var want_pitch: float = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
	# 反应延迟
	var reacted: bool = now >= float(b.react_at)
	# 抖动：以「目标相对角速度」为尺度，远距离误差更小（更难）
	if now >= float(b.aim_refresh):
		b.aim_refresh = now + 0.18 + randf() * 0.22
		var err: float = float(b.profile.err) * (1.7 - float(b.skill)) * clampf(dist / 26.0, 0.25, 1.5)
		b.aim_err = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * err * 0.035
	# 平滑收敛（技能越高越快，且带轻微超调 = 人类手感）
	var spd: float = 0.10 + float(b.profile.aim_speed) * 0.09
	if reacted:
		var dyaw: float = MathUtil.clamp_angle(want_yaw - bot.yaw)
		var dpitch: float = want_pitch - bot.pitch
		bot.yaw = MathUtil.clamp_angle(bot.yaw + dyaw * spd + float(b.aim_err.x))
		bot.pitch = clampf(bot.pitch + dpitch * spd + float(b.aim_err.y), -1.5, 1.5)
	# 后坐力补偿：连续开火时向下压
	if bot.input.fire or now < float(b.burst_until):
		b.recoil_comp = lerpf(float(b.recoil_comp), float(def.get("recoil", 0.02)) * 22.0, 0.2)
		bot.pitch = clampf(bot.pitch - float(b.recoil_comp) * 0.0012, -1.5, 1.5)
	else:
		b.recoil_comp = lerpf(float(b.recoil_comp), 0.0, 0.15)

	# 开镜
	if float(def.get("adsFov", 0.0)) > 0.0 and not bool(def.get("melee", false)):
		var sniper: bool = dist > 18.0 and float(def.get("adsFov", 50.0)) < 35.0
		if dist > (5.0 if sniper else 11.0):
			bot.input.ads = true
	# 换弹
	if w != null and float(w.ammo) <= 0.0:
		bot.input.r = true
	elif w != null and w.state == "ready" and float(w.ammo) <= float(def.get("magSize", 30)) * 0.25 and now >= float(b.reload_at):
		bot.input.r = true
		b.reload_at = now + 0.6
	# 开火节奏
	var aligned: bool = absf(MathUtil.clamp_angle(want_yaw - bot.yaw)) < 0.10 + dist * 0.0012
	if reacted and aligned and w != null and w.can_fire(now):
		if bool(def.get("melee", false)):
			bot.input.fire = true
			b.attack_at = now + 0.25
		elif bool(def.get("auto", false)):
			if now < float(b.burst_until):
				bot.input.fire = true
			else:
				b.burst_until = now + float(b.profile.burst) * (0.18 + randf() * 0.16)
				b.attack_at = now + 0.22 + randf() * 0.35
				bot.input.fire = true
		else:
			bot.input.fire = true
			b.attack_at = now + maxf(0.2, 60.0 / maxf(1.0, float(def.fireRate)) * 1.35)
	# 走位：近身后撤、中距横移、远距前压
	bot.input.mv = [0, 0, 0, 0]
	if now >= float(b.strafe_at):
		b.strafe_dir = -int(b.strafe_dir) if randf() < 0.7 else int(b.strafe_dir)
		b.strafe_at = now + 0.55 + randf() * 0.7
	var ideal: float = 9.0
	if bool(def.get("melee", false)):
		ideal = 1.2
	elif float(def.get("falloffNear", 15.0)) > 25.0:
		ideal = 22.0
	if dist < ideal * 0.55:
		bot.input.mv[1] = 1
	elif dist > ideal * 1.4:
		bot.input.mv[0] = 1
	bot.input.mv[3 if int(b.strafe_dir) > 0 else 2] = 1
	# 血量低时寻找掩体后撤
	if float(bot.hp) < float(bot.maxHp) * 0.3 and randf() < 0.02:
		b.goal = _find_cover(room, bot, enemy.pos)
		b.goal_kind = "cover"
		_repath(room, bot, b, now)


static func _melee_zombie(room: Dictionary, bot: Dictionary, b: Dictionary, enemy: Dictionary, dist: float) -> void:
	var dx: float = enemy.pos.x - bot.pos.x
	var dz: float = enemy.pos.z - bot.pos.z
	bot.yaw = atan2(-dx, -dz)
	var w: Variant = bot.weapons.get(int(bot.activeSlot), null)
	var rng: float = float(w.def.get("range", 2.4)) if w != null else 2.4
	if dist <= rng:
		bot.input.fire = true
		bot.input.mv = [0, 0, 0, 0]
		return
	if dist < 26.0 and float(room.time) >= float(bot.skillReadyAt):
		bot.edge.skill = true
	# 直线追击（贴脸时用跳跃拉近距离）
	bot.input.mv[0] = 1
	if dist < 4.0 and bot.grounded and randf() < 0.02:
		bot.input.j = true


static func _manage_weapon(room: Dictionary, bot: Dictionary, b: Dictionary, dist: float) -> void:
	var primary: Variant = bot.weapons.get(2, null)
	var pistol: Variant = bot.weapons.get(1, null)
	if primary == null and pistol == null:
		return
	var want: int = int(bot.activeSlot)
	var p_ok: bool = primary != null and primary.state == "ready" and float(primary.ammo) > 0.0
	var s_ok: bool = pistol != null and pistol.state == "ready" and float(pistol.ammo) > 0.0
	if dist > 22.0 and p_ok:
		want = 2
	elif dist < 22.0 and p_ok:
		want = 2
	elif not p_ok and s_ok:
		want = 1
	elif not s_ok and p_ok:
		want = 2
	if want != int(bot.activeSlot):
		bot.edge.sw = want


static func _find_cover(room: Dictionary, bot: Dictionary, threat: Vector3) -> Vector3:
	var best: Vector3 = bot.pos
	var best_score: float = -INF
	var nav: Array = room.map.get("nav", [])
	var start: int = _nearest_nav(nav, bot.pos)
	for i in range(maxi(0, start - 12), mini(nav.size(), start + 12)):
		var p: Dictionary = nav[i]
		var v := Vector3(p.x, float(p.get("y", 0.0)), p.z)
		var d_threat: float = _dist(v, threat)
		if d_threat < 6.0:
			continue
		# 该点是否被威胁直视
		var origin := Vector3(v.x, v.y + 1.55, v.z)
		var dir: Vector3 = (threat - origin).normalized()
		var tw: float = Hitscan.trace_world(room.map, origin, dir, d_threat)
		var exposed: bool = tw >= d_threat - 0.5
		var score: float = (0.0 if exposed else 60.0) + d_threat * 0.4 - _dist(v, bot.pos) * 0.5
		if score > best_score:
			best_score = score
			best = v
	return best


# =====================================================================
# 目标交互
# =====================================================================
static func _objective(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> void:
	var mode: String = str(room.mode)
	if mode == Constants.MODE_DEFUSAL:
		var bomb: Dictionary = room.bomb
		var core = room.core
		if core == null or core.state != "live":
			return
		# T 捡包
		if bot.team == Constants.TEAM_T and not bool(bot.bombCarrier) and not bool(bomb.carried) and not bool(bomb.planted) and bomb.pos != null:
			if _dist(bot.pos, bomb.pos) < 2.2:
				bot.input.u = true
				bot.input.mv = [0, 0, 0, 0]
				return
		# T 安放
		if bot.team == Constants.TEAM_T and bool(bot.bombCarrier) and not bool(core.bomb_planted):
			for site in room.map.get("sites", []):
				if _dist(bot.pos, site.pos) < float(site.radius):
					bot.input.u = true
					bot.input.mv = [0, 0, 0, 0]
					return
		# CT 拆弹
		if bot.team == Constants.TEAM_CT and bool(core.bomb_planted) and bomb.pos != null:
			if _dist(bot.pos, bomb.pos) < 2.2:
				bot.input.u = true
				bot.input.mv = [0, 0, 0, 0]
				return
	# 通用补给
	if not bot.isZombie:
		if float(bot.hp) < float(bot.maxHp) * 0.55:
			for hb in room.healthBoxes:
				if bool(hb.available) and _dist(bot.pos, hb.pos) < 2.0:
					bot.input.u = true
					return
		var w: Variant = bot.weapons.get(2, null)
		if w != null and is_finite(float(w.reserve)) and float(w.reserve) < float(w.def.reserve) * 0.2:
			for ab in room.ammoBoxes:
				if bool(ab.available) and _dist(bot.pos, ab.pos) < 2.0:
					bot.input.u = true
					return


static func _dist(a: Vector3, c: Variant) -> float:
	if c == null:
		return INF
	var bx: float = c.x if c is Vector3 else float(c.get("x", 0.0))
	var by: float = c.y if c is Vector3 else float(c.get("y", 0.0))
	var bz: float = c.z if c is Vector3 else float(c.get("z", 0.0))
	var dx: float = a.x - bx
	var dy: float = a.y - by
	var dz: float = a.z - bz
	return sqrt(dx * dx + dy * dy + dz * dz)


# 兼容旧接口
static func find_enemy(room: Dictionary, bot: Dictionary) -> Variant:
	return _perceive(room, bot, bot.botBrain, float(room.time))


static func has_los(room: Dictionary, a: Dictionary, c: Dictionary) -> bool:
	return _has_los(room, a, c)


static func choose_goal(room: Dictionary, bot: Dictionary) -> Variant:
	return _choose_goal(room, bot, bot.botBrain, float(room.time))


static func move_along_path(room: Dictionary, bot: Dictionary, b: Dictionary) -> void:
	_follow_path(room, bot, b, float(room.time))


static func engage(room: Dictionary, bot: Dictionary, enemy: Dictionary, dist: float) -> void:
	_engage(room, bot, bot.botBrain, enemy, dist, float(room.time))
