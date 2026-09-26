# Bot：BFS 导航寻路 + 索敌交火 + 目标行为（安放/拆除/拾取/追逃/回血）。
# 移植自 host/bots.js
class_name BotBrain
extends RefCounted



static func create_brain() -> Dictionary:
	return {
		"goal": null,
		"bombGoal": false,
		"path": [],
		"nextNode": null,
		"decideAt": 0.0,
		"strafeDir": 1,
		"strafeAt": 0.0,
		"attackAt": 0.0,
		"burstUntil": 0.0,
		"lastNodes": [],
		"target": null,
		"aimErrX": 0.0,
		"aimErrY": 0.0,
		"aimRefreshAt": 0.0,
		"stuckFor": 0.0,
		"lastPos": null,
		"slideDir": 1,
		"slideUntil": 0.0,
		"lastJumpAt": -99.0,
		# 难度梯度：skill 0.4~1.2（精度/反应/换位能力随 skill 提升），
		# 让不同 bot 手感差异明显，而非全员同一参数
		"skill": 0.4 + randf() * 0.8,
		# 反应延迟：发现目标后延迟一段时间才开始修正瞄准（模拟人反应）
		"reactAt": 0.0,
		"lastEnemyId": "",
	}


# 每回合重置 bot 大脑：清除上一回合残留的时间戳（attackAt/burstUntil/decideAt 等）
# 与目标/路径。state.time 归零后旧时间戳会让 bot 永远等不到"该开枪"的时刻，
# 导致第二回合起全员哑火；重置后下一 tick 立即重新决策、正常交火。
static func reset_brain(brain: Dictionary) -> void:
	var fresh: Dictionary = create_brain()
	for k in fresh:
		brain[k] = fresh[k]


# 主 tick：根据房间状态更新 bot.input
static func tick_bot(room: Dictionary, bot: Dictionary) -> void:
	var b: Dictionary = bot.botBrain
	var input: Dictionary = bot.input
	# 卡住检测
	var wants_move: bool = input.mv[0] or input.mv[1] or input.mv[2] or input.mv[3]
	var moved: float = 0.0
	if b.lastPos != null:
		moved = _distance_pos(bot.pos, b.lastPos)
	b.lastPos = Vector3(bot.pos.x, bot.pos.y, bot.pos.z)

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

	if wants_move and moved < 0.1:
		b.stuckFor = float(b.stuckFor) + 1.0 / 30.0
		var now2: float = float(room.time)
		if b.stuckFor > 0.35:
			# 贴墙滑动：左右横移交替，单方向持续时间长一些才能有效沿墙移动
			# 滑动输入在 tick_bot 末尾应用（避免被 engage/move_along_path 覆盖）
			if b.slideUntil == 0.0 or now2 >= b.slideUntil:
				b.slideDir = -1 if b.slideDir == 1 else 1
				b.slideUntil = now2 + 0.9
			# 卡了 0.55s 后尝试跳跃越过低矮障碍（有冷却+头顶检查，避免连续跳/跳穿天花板）
			if b.stuckFor > 0.55 and _try_jump(room, bot, b, now2):
				input.j = true
			# 卡了 1.2s 仍未脱困：后撤 + 跳跃 + 智能绕行
			if b.stuckFor > 1.2:
				b.stuckFor = 0.0
				input.j = true
				# 后撤一步远离墙面
				input.mv[1] = 1
				# 智能绕行：选择垂直于目标方向的导航节点，而非随机
				var nav: Array = room.map.nav
				if not nav.is_empty():
					var goal_v: Variant = b.goal
					var best_node: Dictionary = nav[0]
					var best_score: float = -INF
					var gdx: float = 0.0
					var gdz: float = 0.0
					if goal_v != null:
						gdx = float(goal_v.x) - bot.pos.x
						gdz = float(goal_v.z) - bot.pos.z
						var glen: float = sqrt(gdx * gdx + gdz * gdz)
						if glen > 0.1:
							gdx /= glen
							gdz /= glen
					for n in nav:
						var nd: float = _distance_pos(bot.pos, n)
						if nd < 3.0 or nd > 18.0:
							continue
						var ndx: float = n.x - bot.pos.x
						var ndz: float = n.z - bot.pos.z
						var nlen: float = sqrt(ndx * ndx + ndz * ndz)
						if nlen < 0.1:
							continue
						ndx /= nlen
						ndz /= nlen
						# 评分：垂直于目标方向得分高（绕墙），同方向得分低（可能又撞墙）
						var perp: float = abs(ndx * (-gdz) + ndz * gdx)
						var fwd: float = ndx * gdx + ndz * gdz
						var score: float = perp * 2.0 + fwd * 0.3 - nlen * 0.05
						if score > best_score:
							best_score = score
							best_node = n
					b.goal = {"x": best_node.x, "z": best_node.z, "y": float(best_node.get("y", 0.0))}
					b.bombGoal = false
					b.path = plan_path(room.map, bot, b.goal)
					if not b.path.is_empty():
						b.nextNode = b.path.pop_front()
					else:
						b.nextNode = best_node
					# 立刻刷新决策计时器，避免 decideAt 阻止使用新路径
					b.decideAt = now2 + 2.0
				else:
					b.path = []
					b.nextNode = null
				b.slideUntil = now2 + 1.2
		else:
			# 缓慢衰减
			b.stuckFor = max(0.0, float(b.stuckFor) - 0.05)

	var enemy: Variant = find_enemy(room, bot)
	var now: float = float(room.time)

	# 决策刷新：路径走完或目标改变时才重新规划（间隔 1.2~2.4s）
	if now >= b.decideAt:
		b.decideAt = now + 1.2 + randf() * 1.2
		b.target = enemy
		var prev_goal: Variant = b.goal
		if room.mode == Constants.MODE_DEFUSAL:
			var bomb_planted: bool = room.core.bomb_planted if room.core != null else false
			var bomb_pos: Variant = room.bomb.pos if room.bomb.has("pos") else null
			var need_pickup: bool = bot.team == Constants.TEAM_T and not bot.bombCarrier and room.bomb != null and not room.bomb.planted and room.bomb.has("pos") and room.bomb.pos != null
			if bot.team == Constants.TEAM_CT and bomb_planted and bomb_pos != null:
				b.goal = {"x": bomb_pos.x, "z": bomb_pos.z, "y": float(bomb_pos.y)}
				b.bombGoal = true
			elif need_pickup:
				b.goal = {"x": room.bomb.pos.x, "z": room.bomb.pos.z, "y": float(room.bomb.pos.y)}
				b.bombGoal = true
			elif b.goal == null or b.bombGoal:
				b.bombGoal = false
				b.goal = choose_goal(room, bot)
		else:
			b.goal = choose_goal(room, bot)
		var goal_changed: bool = (prev_goal == null) or prev_goal.x != b.goal.x or prev_goal.z != b.goal.z
		if goal_changed or b.path.is_empty():
			b.path = plan_path(room.map, bot, b.goal)
			if b.path.is_empty() and b.goal != null:
				# 寻路失败：跳到一个中间导航节点
				var nav: Array = room.map.nav
				if not nav.is_empty():
					var mid: Dictionary = nav[randi() % nav.size()]
					b.goal = {"x": mid.x, "z": mid.z, "y": float(mid.get("y", 0.0))}
					b.path = plan_path(room.map, bot, b.goal)
			b.nextNode = null
		b.lastNodes = []
	elif enemy != null:
		b.target = enemy

	var dist_enemy: float = INF if enemy == null else _distance_pos(bot.pos, enemy.pos)
	var visible: bool = false
	if enemy != null:
		visible = has_los(room, bot, enemy)

	# 丧尸近战：即使视线被墙挡，贴身距离内也允许攻击
	var melee_range: float = 0.0
	if enemy != null and bot.isZombie:
		var zw: Variant = bot.weapons.get(bot.activeSlot, null)
		var zde: Dictionary = zw.def if zw != null else {}
		melee_range = float(zde.get("range", 2.4))

	# 交战中 bot 面向敌人（横移 strafe 是正常战斗姿态）；非交战则面向移动方向
	var engaged: bool = false
	if enemy != null and dist_enemy < 45.0 and (visible or (bot.isZombie and dist_enemy <= melee_range)):
		engaged = true
		engage(room, bot, enemy, dist_enemy)
	else:
		move_along_path(room, bot, b)

	# 行为动作：安放/拆除/弹药箱
	handle_objective(room, bot)

	# bot 分离：避免多个 bot 挤到同一个敌人/目标点
	_apply_separation(room, bot)

	# 卡墙滑动：在 engage/move_along_path/handle_objective 之后再应用，
	# 否则横移输入会被覆盖导致贴墙时无法脱困（表现为原地不动/反复转向）
	if float(b.stuckFor) > 0.35 and now < float(b.slideUntil) and not input.u:
		input.mv = [0, 0, 0, 0]
		if b.slideDir == 1:
			input.mv[3] = 1
		else:
			input.mv[2] = 1

	# 非交战时身体朝向由 move_along_path 决定（朝路径点/目标点），横移只做位置调整。
	# 注意：不能把"输入合成方向"（含 strafe 横移）当目标朝向——那会让 bot 把 yaw
	# 转到横移方向，看起来横着前进。yaw 必须由路径方向权威设置。
	# （_align_yaw_to_move 曾导致此问题，已移除）


# 索敌：优先最近的敌对目标，限制「同一实体最多同时被 3 个 bot 瞄准」。
# 加 70m 索敌距离上限：杜绝 bot 锁定超远目标后"追空气"（同时减少每 tick 计算量）。
const ENEMY_SIGHT_RANGE: float = 70.0


static func find_enemy(room: Dictionary, bot: Dictionary) -> Variant:
	var target_count: Dictionary = {}
	for p in room.players.values():
		if p == bot or not p.isBot:
			continue
		var t: Variant = p.botBrain.target if p.botBrain != null else null
		if t != null and t.has("id"):
			target_count[t.id] = int(target_count.get(t.id, 0)) + 1
	var best: Variant = null
	var best_d: float = INF
	var best_over: Variant = null
	var best_over_d: float = INF
	for p in room.players.values():
		if p == bot or not p.alive:
			continue
		var hostile: bool = false
		if room.mode == Constants.MODE_ZOMBIE:
			hostile = p.isZombie != bot.isZombie
		else:
			hostile = p.team != bot.team
		if not hostile:
			continue
		var d: float = _distance_pos(bot.pos, p.pos)
		if d > ENEMY_SIGHT_RANGE:
			continue
		var count: int = int(target_count.get(p.id, 0))
		if count >= 3:
			# 兜底
			if d < best_over_d:
				best_over_d = d
				best_over = p
		elif d < best_d:
			best_d = d
			best = p
	return best if best != null else best_over


static func wid_is_sniper(wid: String) -> bool:
	return wid in ["longshot", "sm", "sr"]


static func has_los(room: Dictionary, from_p: Dictionary, to_p: Dictionary) -> bool:
	var origin := Vector3(from_p.pos.x, from_p.pos.y + 1.55, from_p.pos.z)
	var dx: float = to_p.pos.x - origin.x
	var dy: float = to_p.pos.y + 1.3 - origin.y
	var dz: float = to_p.pos.z - origin.z
	var len: float = sqrt(dx * dx + dy * dy + dz * dz)
	if len == 0:
		len = 1.0
	var dir := Vector3(dx / len, dy / len, dz / len)
	var max_d: float = _distance_pos(from_p.pos, to_p.pos)
	var t: float = Hitscan.trace_world(room.map, origin, dir, max_d)
	return t >= max_d - 0.3


static func choose_goal(room: Dictionary, bot: Dictionary) -> Variant:
	if room.mode == Constants.MODE_DEFUSAL:
		# 兜底：地图没有安放点（如 containment）时不能访问 sites 空数组（会除零/越界卡死），
		# 改为随机巡逻点。
		var sites: Array = room.map.get("sites", [])
		if sites.is_empty():
			var nav: Array = room.map.get("nav", [])
			if not nav.is_empty():
				var mid: Dictionary = nav[randi() % nav.size()]
				return {"x": mid.x, "z": mid.z, "y": float(mid.get("y", 0.0))}
			return {"x": 0.0, "z": 0.0, "y": 0.0}
		if bot.team == Constants.TEAM_T:
			if bot.bombCarrier:
				var site: Dictionary = sites[randi() % sites.size()]
				return {"x": site.pos.x, "z": site.pos.z, "y": float(site.pos.y), "site": site}
			var site: Dictionary = sites[0 if randf() < 0.5 else 1]
			return {"x": site.pos.x, "z": site.pos.z, "y": float(site.pos.y), "site": site}
		var bomb_planted: bool = room.core.bomb_planted if room.core != null else false
		if bomb_planted and room.bomb.has("pos") and room.bomb.pos != null:
			return {"x": room.bomb.pos.x, "z": room.bomb.pos.z, "y": float(room.bomb.pos.y)}
		var site2: Dictionary = sites[0 if randf() < 0.5 else 1]
		return {"x": site2.pos.x, "z": site2.pos.z, "y": float(site2.pos.y), "site": site2}

	if not bot.isZombie and bot.hp < bot.maxHp * 0.5:
		# 人类血量过低：优先去最近的可用回血箱
		var avail: Array = []
		for box in room.healthBoxes:
			if box.available:
				avail.append(box)
		if not avail.is_empty():
			var best_box: Dictionary = avail[0]
			var best_d: float = INF
			for box in avail:
				var d: float = sqrt(pow(box.pos.x - bot.pos.x, 2) + pow(box.pos.z - bot.pos.z, 2))
				if d < best_d:
					best_d = d
					best_box = box
			return {"x": best_box.pos.x, "z": best_box.pos.z, "y": float(best_box.pos.y)}
	if bot.isZombie:
		# 追击最近的活人：每次决策重新计算，目标死亡后自动换下一个
		var best_human: Variant = null
		var best_d: float = INF
		for p in room.players.values():
			if p.alive and not p.isZombie:
				var d: float = _distance_pos(bot.pos, p.pos)
				if d < best_d:
					best_d = d
					best_human = p
		if best_human != null:
			return {"x": best_human.pos.x, "z": best_human.pos.z, "y": best_human.pos.y}
		return {"x": 0.0, "z": 0.0, "y": 0.0}
	# 人类：远离 / 追击僵尸
	var zombie: Variant = null
	for p in room.players.values():
		if p.alive and p.isZombie:
			zombie = p
			break
	if zombie != null:
		var d: float = _distance_pos(bot.pos, zombie.pos)
		if d < 14.0:
			# 逃跑（反向延伸）
			return {"x": bot.pos.x * 2 - zombie.pos.x, "z": bot.pos.z * 2 - zombie.pos.z, "y": bot.pos.y}
		return {"x": zombie.pos.x, "z": zombie.pos.z, "y": zombie.pos.y}
	return {"x": 0.0, "z": 0.0, "y": 0.0}


static func _nav_dist(a: Dictionary, b: Dictionary) -> float:
	var ay: float = float(a.get("y", 0.0))
	var by: float = float(b.get("y", 0.0))
	return sqrt(pow(a.x - b.x, 2) + pow(a.z - b.z, 2)) + abs(ay - by) * 2.0


static func _nearest_nav(nav: Array, pos: Vector3) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(nav.size()):
		var d: float = _nav_dist(nav[i], {"x": pos.x, "y": pos.y, "z": pos.z})
		if d < best_d:
			best_d = d
			best = i
	return best


# BFS 最短路（O(N+E)，比 O(N^2) Dijkstra 快两个数量级；网格导航边权近似均匀）
static func plan_path(map_data: Dictionary, bot: Dictionary, goal: Variant) -> Array:
	if goal == null:
		return []
	var nav: Array = map_data.nav
	if nav.is_empty():
		return []
	var start: int = _nearest_nav(nav, bot.pos)
	var goal_idx: int = _nearest_nav(nav, Vector3(goal.x, goal.y, goal.z))
	if start == goal_idx:
		return [nav[start]]
	var prev: Array = []
	prev.resize(nav.size())
	prev.fill(-2)
	# 头尾索引环形队列：Array.pop_front() 是 O(n) 整段搬移（V≈4000 时最坏千万次/次寻路），
	# 预分配 + 头尾索引把 BFS 降到严格 O(N+E)，消除主线程尖峰（Web 单线程尤其关键）。
	var q: Array = []
	q.resize(nav.size())
	var head: int = 0
	var tail: int = 0
	q[tail] = start
	tail += 1
	prev[start] = -1
	while head < tail:
		var u: int = q[head]
		head += 1
		if u == goal_idx:
			break
		for li in nav[u].get("links", []):
			if prev[li] == -2:
				prev[li] = u
				q[tail] = li
				tail += 1
	if prev[goal_idx] == -2:
		return []
	# 反向构建 + reverse：避免 push_front 的 O(n²)
	var path: Array = []
	var cur: int = goal_idx
	while cur != -1:
		path.push_back(nav[cur])
		cur = prev[cur]
	path.reverse()
	return path

static func move_along_path(room: Dictionary, bot: Dictionary, b: Dictionary) -> void:
	var nav: Array = room.map.nav
	if nav.is_empty():
		return
	var waypoint: Variant = b.nextNode
	if waypoint == null or _distance_pos(bot.pos, Vector3(waypoint.x, 0.0, waypoint.z)) < 1.1:
		if not b.path.is_empty():
			waypoint = b.path.pop_front()
			b.nextNode = waypoint
		else:
			waypoint = b.goal if b.goal != null else nav[0]
	if waypoint == null:
		return
	var dx: float = waypoint.x - bot.pos.x
	var dz: float = waypoint.z - bot.pos.z
	var dy: float = float(waypoint.get("y", 0.0)) - bot.pos.y
	var h_dist: float = sqrt(dx * dx + dz * dz)
	# 明显更高的平台且靠近时才跳跃
	if dy > 0.5 and h_dist < 2.4 and dy < 2.2:
		bot.input.j = true
	var len: float = h_dist if h_dist > 0 else 1.0
	var tx: float = dx / len
	var tz: float = dz / len
	var fx: float = -sin(bot.yaw)
	var fz: float = -cos(bot.yaw)
	var rx: float = -fz
	var rz: float = fx
	var forward: float = tx * fx + tz * fz
	var strafe: float = tx * rx + tz * rz
	if forward > 0.15:
		_input_set(bot, 0, 1)
	elif forward < -0.15:
		_input_set(bot, 1, 1)
	if strafe > 0.2:
		_input_set(bot, 3, 1)
	elif strafe < -0.2:
		_input_set(bot, 2, 1)
	# 平滑转向路径方向（最终由 _align_yaw_to_move 对准实际移动方向）
	bot.yaw = MathUtil.ang_lerp(bot.yaw, atan2(-dx, -dz), 0.2)


static func _input_set(bot: Dictionary, idx: int, _v: int) -> void:
	bot.input.mv[idx] = 1


static func _apply_separation(room: Dictionary, bot: Dictionary) -> void:
	# 只在 bot 正在移动时施加分离力，避免覆盖拆包/拾取/射击等静止行为
	if bot.input.mv[0] == 0 and bot.input.mv[1] == 0 and bot.input.mv[2] == 0 and bot.input.mv[3] == 0:
		return
	var sep_x: float = 0.0
	var sep_z: float = 0.0
	var radius: float = 2.4
	var radius_sq: float = radius * radius
	for p in room.players.values():
		if p == bot or not p.alive:
			continue
		var dx: float = bot.pos.x - p.pos.x
		var dz: float = bot.pos.z - p.pos.z
		var d2: float = dx * dx + dz * dz
		if d2 < 0.0001 or d2 > radius_sq:
			continue
		var d: float = sqrt(d2)
		var push: float = (radius - d) / radius
		sep_x += (dx / d) * push
		sep_z += (dz / d) * push
	if absf(sep_x) < 0.15 and absf(sep_z) < 0.15:
		return
	var fx: float = -sin(bot.yaw)
	var fz: float = -cos(bot.yaw)
	var rx: float = -fz
	var rz: float = fx
	var fwd: float = sep_x * fx + sep_z * fz
	var side: float = sep_x * rx + sep_z * rz
	var threshold: float = 0.12
	if fwd > threshold:
		bot.input.mv[0] = 1
	elif fwd < -threshold:
		bot.input.mv[1] = 1
	if side > threshold:
		bot.input.mv[3] = 1
	elif side < -threshold:
		bot.input.mv[2] = 1


static func engage(room: Dictionary, bot: Dictionary, enemy: Dictionary, dist_enemy: float) -> void:
	var b: Dictionary = bot.botBrain
	var now: float = float(room.time)
	var w: Variant = bot.weapons.get(bot.activeSlot, null)
	var def: Dictionary = w.def if w != null else {}

	if bot.isZombie:
		# 丧尸 Bot：追击敌人时使用 F 加速技能。冷却(20s)本身就是频率限制，
		# 冷却好了且在追击范围内就触发（edge.skill 每帧被消费，概率过滤会浪费机会）。
		if dist_enemy > 3.0 and dist_enemy < 25.0 and room.time >= float(bot.skillReadyAt):
			bot.edge.skill = true
		var dx: float = enemy.pos.x - bot.pos.x
		var dz: float = enemy.pos.z - bot.pos.z
		bot.yaw = atan2(-dx, -dz)
		bot.pitch = atan2(enemy.pos.y + 1.2 - (bot.pos.y + 1.55), sqrt(dx * dx + dz * dz))
		var zrange: float = float(def.get("range", 2.4))
		if dist_enemy <= zrange:
			bot.input.fire = true
			bot.input.mv = [0, 0, 0, 0]
		else:
			_move_toward(room, bot, enemy.pos)
		return

	# 切枪：主武器 / 手枪切换
	var primary: Variant = bot.weapons.get(2, null)
	var pistol: Variant = bot.weapons.get(1, null)
	var want_slot: int = bot.activeSlot
	if primary != null:
		var prim_ready: bool = primary.state == "ready" and primary.ammo > 0
		var pistol_ready: bool = (pistol != null and pistol.state == "ready" and pistol.ammo > 0)
		if want_slot == 2 and not prim_ready and pistol_ready:
			want_slot = 1
		elif want_slot == 1 and prim_ready:
			want_slot = 2
		elif want_slot == 1 and not pistol_ready:
			want_slot = 2
	elif pistol != null and want_slot != 1:
		want_slot = 1
	if want_slot != bot.activeSlot:
		bot.edge.sw = want_slot

	# 瞄准：带缓慢刷新的持续误差（误差越大越不准），精度随 skill 提升。
	# 反应延迟：目标切换/首次发现后延迟才开始修正（模拟人反应，skill 越高反应越快）
	var skill: float = float(b.get("skill", 0.8))
	var zombie_mode: bool = room.mode == Constants.MODE_ZOMBIE
	var enemy_id: String = enemy.id if enemy != null else ""
	if enemy_id != b.lastEnemyId:
		b.lastEnemyId = enemy_id
		b.reactAt = now + 0.28 - skill * 0.2
	var reacted: bool = now >= float(b.reactAt)
	var err_scale: float
	if zombie_mode:
		err_scale = min(1.5, 0.7 + dist_enemy * 0.025)
	else:
		err_scale = min(1.2, 0.55 + dist_enemy * 0.02)
	# 难度缩放：skill 1.2 的精英误差 ×0.55，skill 0.4 的新手 ×1.35
	err_scale *= (1.7 - skill)
	if reacted and now >= b.aimRefreshAt:
		b.aimRefreshAt = now + (0.3 - skill * 0.15) * (1.0 - randf() * 0.4)
		b.aimErrX = (randf() - 0.5) * err_scale
		b.aimErrY = (randf() - 0.5) * err_scale
	var dx: float = enemy.pos.x - bot.pos.x
	var dy: float = enemy.pos.y + 1.3 - (bot.pos.y + 1.55)
	var dz: float = enemy.pos.z - bot.pos.z
	var converge: float = (0.1 if zombie_mode else 0.12) + (1.0 - skill) * 0.1
	var target_yaw: float = atan2(-dx, -dz) + b.aimErrX
	var target_pitch: float = atan2(dy, sqrt(dx * dx + dz * dz)) + b.aimErrY
	# 反应延迟期内保持当前朝向（不瞬移瞄准），出延迟后平滑收敛
	if reacted:
		bot.yaw = MathUtil.ang_lerp(bot.yaw, target_yaw, converge)
		bot.pitch = MathUtil.ang_lerp(bot.pitch, target_pitch, converge)

	var aw: Variant = bot.weapons.get(bot.activeSlot, null)
	var adef: Dictionary = aw.def if aw != null else {}

	# 开镜（ADS）：中远距离用瞄具压散布，近距离/近战/僵尸不开镜。
	# bot 用 yaw/pitch 直接驱动瞄准，ADS 只影响散布 → 是"更准"的正向行为。
	var want_ads: bool = false
	if adef.get("adsFov", 0.0) > 0.0 and not adef.get("melee", false):
		var is_sniper: bool = wid_is_sniper(adef.id)
		want_ads = dist_enemy > (6.0 if is_sniper else 12.0)
	if want_ads and reacted:
		bot.input.ads = true

	# 主动换弹：弹匣过低且当前没在连发时换弹；空仓时立即换弹
	if aw != null and aw.ammo == 0:
		bot.input.r = true
	elif aw != null and aw.state == "ready" and aw.ammo <= float(adef.magSize) * 0.3 and now >= b.attackAt:
		bot.input.r = true
		b.attackAt = now + 0.35

	# 开火：全自动=短点射+停顿；半自动按射速点射；近战按频率挥击
	if now >= b.attackAt and aw != null and aw.can_fire(now):
		if adef.get("melee", false):
			bot.input.fire = true
			b.attackAt = now + 0.22 + randf() * 0.1
		elif adef.get("auto", false):
			if now < float(b.burstUntil):
				bot.input.fire = true
				b.attackAt = now + 0.07
			else:
				# 点射开始：先打出第一发，再设置本轮连发窗口。
				# 修复：之前 else 只"预热"下一轮却不 fire，而 burstUntil 总被
				# attackAt 超越 → 全自动武器永远打不出第一发（人类 bot 拿步枪完全哑火）。
				b.burstUntil = now + 0.16 + randf() * 0.12
				b.attackAt = now + 0.28 + randf() * 0.4
				bot.input.fire = true
		else:
			bot.input.fire = true
			b.attackAt = now + max(0.24, 60.0 / max(1, int(adef.fireRate)) * 1.4 + 0.08)

	# 走位：保持中远距离施压 + 横向移动
	# 间隔拉长 + 保持方向稳定，避免短时间内反复变向导致原地转圈
	if now >= b.strafeAt:
		b.strafeDir = -1 if randf() < 0.5 else 1
		b.strafeAt = now + 0.9 + randf() * 0.8
	bot.input.mv = [0, 0, 0, 0]
	if dist_enemy < 3.5:
		bot.input.mv[1] = 1
	elif dist_enemy > 7.0:
		bot.input.mv[0] = 1
	else:
		# 中距离加入轻微前压，避免只横移导致绕圈不前
		bot.input.mv[0] = 1
	bot.input.mv[3 if b.strafeDir > 0 else 2] = 1

	# 人类 Bot：丧尸近身时按 F 加速拉开距离（生化模式人类加速 5s/45s 冷却）
	if room.mode == Constants.MODE_ZOMBIE and not bot.isZombie:
		var enemy_is_zombie: bool = bool(enemy.get("isZombie", false)) if enemy != null else false
		if enemy_is_zombie and dist_enemy < 6.0 and room.time >= float(bot.skillReadyAt):
			bot.edge.skill = true



static func _move_toward(_room: Dictionary, bot: Dictionary, target: Variant) -> void:
	var ty: float = 0.0
	if target is Dictionary:
		ty = float(target.get("y", 0.0))
	else:
		ty = float(target.y)
	var dy: float = ty - bot.pos.y
	var dx: float = target.x - bot.pos.x
	var dz: float = target.z - bot.pos.z
	if dy > 0.5 and sqrt(dx * dx + dz * dz) < 2.4 and dy < 2.2:
		bot.input.j = true
	var len: float = sqrt(dx * dx + dz * dz)
	if len == 0:
		len = 1.0
	var fx: float = -sin(bot.yaw)
	var fz: float = -cos(bot.yaw)
	var forward: float = (dx / len) * fx + (dz / len) * fz
	bot.input.mv = [1 if forward > 0 else 0, 1 if forward <= 0 else 0, 0, 0]
	bot.yaw = atan2(-dx, -dz)


static func handle_objective(room: Dictionary, bot: Dictionary) -> void:
	var input: Dictionary = bot.input
	if room.mode == Constants.MODE_DEFUSAL:
		# 拾取：T 机器人靠近实体炸弹按 E
		if room.core != null and room.core.state == "live" and bot.team == Constants.TEAM_T and not bot.bombCarrier and room.bomb != null and not room.bomb.carried and not room.bomb.planted and room.bomb.has("pos") and room.bomb.pos != null:
			var d: float = sqrt(pow(bot.pos.x - room.bomb.pos.x, 2) + pow(bot.pos.z - room.bomb.pos.z, 2))
			if d < 2.4:
				input.u = true
				input.mv = [0, 0, 0, 0]
		if bot.team == Constants.TEAM_T and bot.bombCarrier and room.core != null and room.core.state == "live" and not room.core.bomb_planted:
			for site in room.map.sites:
				var d: float = sqrt(pow(bot.pos.x - site.pos.x, 2) + pow(bot.pos.z - site.pos.z, 2))
				if d < site.radius:
					input.u = true
					input.mv = [0, 0, 0, 0]
					break
		if bot.team == Constants.TEAM_CT and room.core != null and room.core.state == "live" and room.core.bomb_planted and room.bomb.has("pos") and room.bomb.pos != null:
			var d: float = sqrt(pow(bot.pos.x - room.bomb.pos.x, 2) + pow(bot.pos.z - room.bomb.pos.z, 2))
			if d < 2.4:
				input.u = true
				input.mv = [0, 0, 0, 0]
	elif not bot.isZombie:
		# 弹药不足 → 用弹药箱
		var w: Variant = bot.weapons.get(2, null)
		if w == null:
			w = bot.weapons.get(bot.activeSlot, null)
		if w != null and w.ammo < float(w.def.magSize) * 0.4:
			for box in room.ammoBoxes:
				if box.available and sqrt(pow(box.pos.x - bot.pos.x, 2) + pow(box.pos.z - bot.pos.z, 2)) < 2.0:
					input.u = true
					break
		# 血量过低 → 用回血箱
		if bot.hp < bot.maxHp * 0.6:
			for hb in room.healthBoxes:
				if hb.available and sqrt(pow(hb.pos.x - bot.pos.x, 2) + pow(hb.pos.z - bot.pos.z, 2)) < 2.0:
					input.u = true
					break


# 尝试跳跃：有冷却（与玩家跳高/重力算出的滞空+恢复一致）、且头顶净空足够才跳。
# 判定与玩家一致：跳跃初速 PHYS.JUMP、重力 PHYS.GRAVITY，最高约 1.2m；
# 头顶检查以跳跃最高时的头部位置（站高 1.8 + 跳高 1.2 + 0.4 缓冲）为界，
# 防止 bot 跳起后脑袋顶进上方的天花板/平台。
static func _try_jump(room: Dictionary, bot: Dictionary, b: Dictionary, now: float) -> bool:
	if now - float(b.lastJumpAt) < 1.0:
		return false
	if not bot.grounded:
		return false
	var head_y: float = bot.pos.y + 1.8 + 1.2 + 0.4
	for c in room.map.colliders:
		if c.type == "ceiling":
			continue
		var mn: Vector3 = c.min
		var mx: Vector3 = c.max
		if mn.y >= head_y:
			continue
		if bot.pos.x + 0.4 > mn.x and bot.pos.x - 0.4 < mx.x and bot.pos.z + 0.4 > mn.z and bot.pos.z - 0.4 < mx.z:
			return false
	b.lastJumpAt = now
	return true


static func _distance_pos(a: Variant, b: Variant) -> float:
	# 接受 Vector3 或 Dictionary {x,y,z}
	var ax: float = a.x
	var ay: float = a.y
	var az: float = a.z
	var bx: float = b.x
	var by: float = b.y
	var bz: float = b.z
	return sqrt(pow(ax - bx, 2) + pow(ay - by, 2) + pow(az - bz, 2))
