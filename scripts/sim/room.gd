# /# VibeHub/Mod + Bot # host/room.js
class_name Room
extends RefCounted

const PHYS = Constants.PHYS
const FINALE = Constants.FINALE
const TICK_MS = Constants.TICK_MS
const SNAPSHOT_INTERVAL_MS = Constants.SNAPSHOT_INTERVAL_MS

const BOT_NAMES: Array = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet"]

# Dictionary 
var state: Dictionary
# {"tick": Callable, "round_start": Callable, ...}
var events: Dictionary = {}
# 本地单进程模式标志：true 时跳过全量快照广播
var _local_only: bool = false
# broadcast / sendTo / drop_bomb / pick_spawn Callable
var broadcast: Callable = Callable()
var send_to: Callable = Callable()
var drop_bomb: Callable = Callable()
var pick_spawn: Callable = Callable()


func _init(opts: Dictionary) -> void:
	var mode: String = opts.mode
	var map_id: String = opts.mapId
	var max_players: int = int(opts.get("maxPlayers", Constants.MAX_PLAYERS))
	var bot_count: int = int(opts.get("botCount", Constants.BOT_COUNT))
	var map_data: Dictionary = MapData.get_map(map_id)
	# 本地单进程模式：无真实网络，跳过全量快照广播（避免每 50ms 数千 variant 分配后即丢弃）
	_local_only = bool(opts.get("localOnly", false))
	state = {
		"id": opts.get("id", "local"),
		"mode": mode,
		"mapId": map_id,
		"map": map_data,
		"maxPlayers": max_players,
		"botCount": bot_count,
		"players": {},                 # id -> Player
		"time": 0.0,
		"tickAcc": 0.0,
		"snapAcc": 0.0,
		"weapons": WeaponData.BUILTIN_WEAPONS.duplicate(),
		"projectiles": [],
		"nextProjId": 1,
		"ammoBoxes": _init_boxes(map_data.get("ammoBoxes", [])),
		"healthBoxes": _init_boxes(map_data.get("healthBoxes", [])),
		"bomb": {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0},
		"finaleActive": false,
		"noRespawn": false,
		"core": null,                  # DefusalRound ZombieMatch
		"roundNum": 0,
		"matchScore": {"CT": 0, "T": 0, "HUMAN": 0, "ZOMBIE": 0},
		"lossStreak": {"CT": 0, "T": 0},
		"globalState": "live",
		"phase": "live",
		"buyUntil": 0.0,
		"roundEndAt": 0.0,
		"matchEndAt": 0.0,
		"rotation": ["cinder", "obsidian"] if mode == Constants.MODE_DEFUSAL else ["containment", "obsidian"],
		"rotationIdx": 0,
		"nextBotId": 1,
		"events": events,
		"broadcast": Callable(),
		"sendTo": Callable(),
		"dropBomb": Callable(),
		"pickSpawn": Callable(),
	}
	# broadcast / sendTo / dropBomb / pickSpawn state Player room.x.call 
	_bind_state_callables()


# broadcast / sendTo / dropBomb / pickSpawn state 
func _bind_state_callables() -> void:
	state.broadcast = _make_broadcast()
	state.sendTo = _make_send_to()
	state.dropBomb = _make_drop_bomb()
	state.pickSpawn = _make_pick_spawn()
	# events dict 
	state.events = events


func _make_broadcast() -> Callable:
	# pending_messages
	return func(msg: Dictionary) -> void:
		for p in state.players.values():
			if not p.isBot and p.has("pendingMessages"):
				p.pendingMessages.append(msg)


func _make_send_to() -> Callable:
	return func(pid: String, msg: Dictionary) -> void:
		if state.players.has(pid):
			var p: Dictionary = state.players[pid]
			if not p.isBot and p.has("pendingMessages"):
				p.pendingMessages.append(msg)


func _make_drop_bomb() -> Callable:
	return func(p: Dictionary) -> void:
		_drop_bomb_impl(p)


func _make_pick_spawn() -> Callable:
	return func(team_key: String) -> Dictionary:
		return _pick_spawn_impl(team_key)


func _init_boxes(src: Array) -> Array:
	var out: Array = []
	for b in src:
		var copy: Dictionary = b.duplicate()
		copy.available = true
		copy.respawnAt = 0.0
		out.append(copy)
	return out


# ----------  ----------
func start() -> void:
	#  Mod 
	fill_bots()
	if state.mode == Constants.MODE_DEFUSAL:
		begin_buy_phase()
	else:
		start_round()
	print("[Room] started mode=%s map=%s bots=%d" % [state.mode, state.mapId, count_bots()])


func stop() -> void:
	# game controller  tick
	pass


# ----------  ----------
func humans() -> int:
	var n: int = 0
	for p in state.players.values():
		if not p.isBot:
			n += 1
	return n


func count_bots() -> int:
	var n: int = 0
	for p in state.players.values():
		if p.isBot:
			n += 1
	return n


func fill_bots() -> void:
	var want: int = min(state.botCount, state.maxPlayers - humans())
	var have: int = count_bots()
	while have < want:
		var bot_id: String = "b%d" % state.nextBotId
		state.nextBotId += 1
		var bot: Dictionary = Player.create(bot_id, "Bot-%s" % BOT_NAMES[have % BOT_NAMES.size()], true)
		bot.botBrain = BotBrain.create_brain()
		bot.pendingMessages = []
		state.players[bot_id] = bot
		have += 1


func add_local_player(p_name: String, team_pref: String = "random") -> Dictionary:
	if humans() >= state.maxPlayers:
		return {}
	var id: String = "h%d_%d" % [Time.get_ticks_msec(), randi() % 10000]
	var p: Dictionary = Player.create(id, p_name)
	p.pendingMessages = []
	p.teamPref = "random"
	if team_pref == "ct" or team_pref == "t":
		p.teamPref = team_pref
	if state.mode == Constants.MODE_DEFUSAL:
		# 
		if p.teamPref == "t":
			p.team = Constants.TEAM_T
		elif p.teamPref == "ct":
			p.team = Constants.TEAM_CT
		else:
			var ct: int = 0
			var t: int = 0
			for x in state.players.values():
				if x.team == Constants.TEAM_CT:
					ct += 1
				elif x.team == Constants.TEAM_T:
					t += 1
			p.team = Constants.TEAM_CT if ct <= t else Constants.TEAM_T
	state.players[id] = p
	# bot
	if state.players.size() > state.maxPlayers:
		var bot_to_kick: Variant = null
		var keys: Array = state.players.keys()
		keys.reverse()
		for k in keys:
			if state.players[k].isBot:
				bot_to_kick = k
				break
		if bot_to_kick != null:
			state.players.erase(bot_to_kick)
	print("[Room] player joined: %s (%s), total=%d" % [p_name, id, state.players.size()])
	return p


func spawn_joiner(p: Dictionary) -> void:
	if state.core != null and state.core.state == "ended":
		return
	if p.alive:
		return
	if state.mode == Constants.MODE_DEFUSAL:
		p.isZombie = false
		if p.teamPref == "t":
			p.team = Constants.TEAM_T
		elif p.teamPref == "ct":
			p.team = Constants.TEAM_CT
		else:
			var ct: int = 0
			var t: int = 0
			for x in state.players.values():
				if x.team == Constants.TEAM_CT:
					ct += 1
				elif x.team == Constants.TEAM_T:
					t += 1
			p.team = Constants.TEAM_CT if ct <= t else Constants.TEAM_T
		var spot: Dictionary = _pick_spawn_impl("CT" if p.team == Constants.TEAM_CT else "T")
		Player.spawn_player(state, p, p.team, spot)
	else:
		p.team = Constants.TEAM_ZOMBIE if p.isZombie else Constants.TEAM_HUMAN
		var spot2: Dictionary = _pick_spawn_impl("ZOMBIE" if p.isZombie else "HUMAN")
		Player.spawn_player(state, p, p.team, spot2)


func remove_player(id: String) -> void:
	if not state.players.has(id):
		return
	var p: Dictionary = state.players[id]
	_drop_bomb_impl(p)
	state.players.erase(id)
	if not p.isBot:
		fill_bots()


# ----------  ----------
func start_round() -> void:
	state.roundNum += 1
	state.time = 0.0
	state.projectiles = []
	state.bomb = {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0}
	state.roundEndAt = 0.0
	state.globalState = "live"
	state.phase = "live"
	state.buyUntil = 0.0
	state.finaleActive = false
	state.noRespawn = false
	var all: Array = []
	for p in state.players.values():
		all.append(p)
	for p in all:
		p.boughtPhase = false
		p.bombCarrier = false
		p.damageMult = 1.0
		p.isCrystalHunter = false
		p.isZombieKing = false
		p.isZombieServant = false
		p.useProgress = 0.0
		p.useTarget = null
	for p in all:
		if p.isBot:
			# 新回合重置 bot：清除上一回合残留的时间戳（attackAt/burstUntil/decideAt 等）
			# 与目标/路径——state.time 归零后旧时间戳会让 bot 永远等不到开火时机，
			# 表现为"第一回合生猛、之后个个哑火"；武器也复位为满弹就绪，避免残留
			# 上一回合的换弹锁/空仓/主动槽状态影响本回合。
			if p.botBrain != null:
				BotBrain.reset_brain(p.botBrain)
			p.activeSlot = 1
			refill_ammo(p)
			p.input.fire = false
			p.edge.sw = -1
			p.edge.swd = 0

	if state.mode == Constants.MODE_DEFUSAL:
		# 
		var survived: Dictionary = {}
		for p in all:
			survived[p.id] = p.alive
		for p in all:
			p.isZombie = false
			if p.teamPref == "ct":
				p.team = Constants.TEAM_CT
			elif p.teamPref == "t":
				p.team = Constants.TEAM_T
			else:
				p.team = Constants.TEAM_NONE
		# K/D 不清零：整场比赛累计（计分板语义），next_map 时才重置
		var ct_count: int = 0
		var t_count: int = 0
		for p in all:
			if p.team == Constants.TEAM_CT:
				ct_count += 1
			elif p.team == Constants.TEAM_T:
				t_count += 1
		for p in all:
			if p.team == Constants.TEAM_NONE:
				if ct_count <= t_count:
					p.team = Constants.TEAM_CT
					ct_count += 1
				else:
					p.team = Constants.TEAM_T
					t_count += 1
		# 
		for p in all:
			if survived[p.id]:
				refill_ammo(p)
		_spawn_all({"keepLoadout": func(p): return survived[p.id]})
		# 
		for p in all:
			for rec in p.boughtItems:
				if rec.has("slot"):
					rec.runtime.reset(0.0)
					p.weapons[rec.slot] = rec.runtime
					if rec.slot == 2:
						p.activeSlot = 2
				elif rec.item == "armor":
					p.armor = 100
				elif rec.item == "grenade":
					p.grenadeCount = min(5, p.grenadeCount + 1)
			p.boughtItems = []
		_place_bomb_at_spawn()
		state.core = DefusalRound.new({"roundTime": 105.0, "bombTime": 40.0, "onEvent": _on_round_event, "getState": func() -> Dictionary: return state})
		state.core.start({})
	else:
		for p in all:
			p.isZombie = false
			p.team = Constants.TEAM_HUMAN
			p.money = Economy.ZOMBIE_START_MONEY
			p.zombieMoneyInit = true
			p.zombieSince = 0.0
		# 1~3 
		var zombie_count: int = max(1, min(3, int(floor(all.size() * 0.2)), all.size()))
		var pool: Array = []
		for p in all:
			pool.append(p)
		pool.shuffle()
		for i in range(zombie_count):
			pool[i].isZombie = true
			pool[i].team = Constants.TEAM_ZOMBIE
		_spawn_all({})
		state.core = ZombieMatch.new({"duration": 300.0, "onEvent": _on_round_event, "getState": func() -> Dictionary: return state})
		var humans_arr: Array = []
		var zombies_arr: Array = []
		for p in all:
			if p.isZombie:
				zombies_arr.append(p.id)
			else:
				humans_arr.append(p.id)
		state.core.start({"humans": humans_arr, "zombies": zombies_arr})


func _place_bomb_at_spawn() -> void:
	var t_spawns: Array = state.map.spawns.get("T", [{"x": 0.0, "z": 0.0, "yaw": 0.0}])
	var s: Dictionary = t_spawns[0]
	var fx: float = -sin(float(s.get("yaw", 0.0)))
	var fz: float = -cos(float(s.get("yaw", 0.0)))
	state.bomb = {
		"planted": false,
		"carried": false,
		"carrierId": null,
		"pos": Vector3(s.x + fx * 3.2, float(s.get("y", 0.0)) + 0.06, s.z + fz * 3.2),
		"timeLeft": 0.0,
	}


func _drop_bomb_impl(p: Dictionary) -> void:
	if state.mode != Constants.MODE_DEFUSAL or not p.bombCarrier:
		return
	p.bombCarrier = false
	if state.bomb == null:
		return
	state.bomb.carried = false
	state.bomb.carrierId = null
	state.bomb.pos = Vector3(p.pos.x, p.pos.y + 0.2, p.pos.z)
	state.broadcast.call({"type": "bomb_dropped", "pos": state.bomb.pos})


func _pick_spawn_impl(team_key: String) -> Dictionary:
	var spots: Array = state.map.spawns.get(team_key, state.map.spawns.get("HUMAN", [{"x": 0.0, "z": 0.0, "yaw": 0.0}]))
	var order: Array = []
	for i in range(spots.size()):
		order.append(i)
	order.shuffle()
	for i in order:
		var s: Dictionary = spots[i]
		var taken: bool = false
		for q in state.players.values():
			if q.alive and sqrt(pow(q.pos.x - s.x, 2) + pow(q.pos.z - s.z, 2)) < 2.2:
				taken = true
				break
		if not taken:
			return s
	return spots[order[0]]


func _spawn_all(opts: Dictionary) -> void:
	for p in state.players.values():
		var team_key: String = "ZOMBIE" if p.isZombie else ("CT" if p.team == Constants.TEAM_CT else ("T" if p.team == Constants.TEAM_T else "HUMAN"))
		var spot: Dictionary = _pick_spawn_impl(team_key)
		var keep: bool = false
		if opts.has("keepLoadout") and opts.keepLoadout.is_valid():
			keep = bool(opts.keepLoadout.call(p))
		Player.spawn_player(state, p, p.team, spot, {"keepLoadout": keep})


func refill_ammo(p: Dictionary) -> void:
	for w in p.weapons.values():
		w.reset(0.0)
		if is_finite(w.def.magSize):
			w.ammo = w.def.magSize
		if is_finite(w.def.reserve):
			w.reserve = w.def.reserve


func _on_round_event(e: Dictionary) -> void:
	if events.has(e.type):
		events[e.type].call(e)
	if e.type == "round_start":
		state.broadcast.call({"type": "round_start", "mode": state.mode, "round": state.roundNum})
	elif e.type == "round_end":
		var winner: String = e.winner
		if state.mode == Constants.MODE_DEFUSAL:
			# 回合结束：炸弹清空（未爆/未拆时残留的掉落/携带状态会在地图上留下"假炸弹"）
			state.bomb = {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0}
			state.matchScore[winner] += 1
			# 连败补偿（CS2）：输方连败计数 +1，赢方清零；输局奖励按连败数递增
			var loser_key: String = "T" if winner == "CT" else "CT"
			var loss_streak: int = int(state.lossStreak.get(loser_key, 0)) + 1
			state.lossStreak[loser_key] = loss_streak
			state.lossStreak[winner] = 0
			for p in state.players.values():
				var won: bool = p.team == (Constants.TEAM_CT if winner == "CT" else Constants.TEAM_T)
				var reward: int = Economy.WIN_REWARD if won else Economy.loss_reward(loss_streak)
				p.money = min(Economy.MONEY_CAP, p.money + reward)
			var match_winner: Variant = winner if state.matchScore[winner] >= 8 else null
			state.phase = "over" if match_winner != null else "buy"
			state.buyUntil = 0.0 if match_winner != null else state.time + 10.0
			state.roundEndAt = state.time + (5.0 if match_winner != null else 10.0)
			state.broadcast.call({"type": "round_end", "winner": winner, "reason": e.reason, "round": state.roundNum, "scores": state.matchScore, "matchWinner": match_winner})
			if match_winner != null:
				state.matchEndAt = state.time + 8.0
				state.broadcast.call({"type": "match_end", "winner": match_winner, "scores": state.matchScore})
		else:
			var z_winner: String = e.winner
			if z_winner == "DRAW":
				state.matchScore.HUMAN += 1
				state.matchScore.ZOMBIE += 1
			else:
				state.matchScore[z_winner] += 1
			state.phase = "over"
			state.broadcast.call({"type": "round_end", "winner": z_winner, "reason": e.reason, "round": state.roundNum, "scores": state.matchScore, "matchWinner": z_winner})
			state.matchEndAt = state.time + 8.0
			state.roundEndAt = state.time + 5.0
			state.broadcast.call({"type": "match_end", "winner": z_winner, "scores": state.matchScore})
	elif e.type == "bomb_planted":
		state.bomb.planted = true
		state.bomb.carried = false
		state.bomb.carrierId = null
		state.bomb.pos = e.pos
		state.bomb.timeLeft = 40.0
		state.broadcast.call({"type": "bomb_planted", "pos": e.pos})
	elif e.type == "bomb_exploded":
		var expl_pos: Vector3 = state.bomb.pos
		state.bomb = {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0}
		state.broadcast.call({"type": "bomb_exploded", "pos": expl_pos})
	elif e.type == "bomb_defused":
		state.bomb = {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0}
		state.broadcast.call({"type": "bomb_defused", "pos": Vector3.ZERO})


# ----------  ----------
func activate_finale() -> void:
	state.phase = "finale"
	var players: Array = []
	for p in state.players.values():
		players.append(p)
	var humans_arr: Array = []
	for p in players:
		if p.alive and not p.isZombie:
			humans_arr.append(p)
	var zombies_arr: Array = []
	for p in players:
		if p.alive and p.isZombie:
			zombies_arr.append(p)
	# zombieSince 
	zombies_arr.sort_custom(func(a, b): return float(a.zombieSince) < float(b.zombieSince))
	# 
	for h in humans_arr:
		h.isCrystalHunter = true
		h.hp = float(FINALE.HUNTER_HP)
		h.maxHp = float(FINALE.HUNTER_HP)
		h.armor = FINALE.HUNTER_ARMOR
		h.damageMult = FINALE.HUNTER_DAMAGE
		refill_ammo(h)
	var king: Variant = null
	var servants: int = 0
	if not zombies_arr.is_empty():
		king = zombies_arr[0]
		king.isZombieKing = true
		king.hp = float(FINALE.KING_HP)
		king.maxHp = float(FINALE.KING_HP)
		king.armor = FINALE.KING_ARMOR
		king.damageMult = FINALE.KING_DAMAGE
		#  3 
		var rest: Array = zombies_arr.slice(1)
		rest.shuffle()
		var servant_count: int = min(3, rest.size())
		for i in range(servant_count):
			var s: Dictionary = rest[i]
			s.isZombieServant = true
			s.hp = float(FINALE.SERVANT_HP)
			s.maxHp = float(FINALE.SERVANT_HP)
			s.armor = FINALE.SERVANT_ARMOR
			s.damageMult = FINALE.SERVANT_DAMAGE
			servants += 1
		# 
		for z in zombies_arr:
			if z.isZombieKing or z.isZombieServant:
				continue
			z.hp = ceil(z.maxHp * FINALE.ZOMBIE_HP_MULT)
			z.maxHp = z.hp
			z.damageMult = 1.0
	state.broadcast.call({"type": "finale_start", "hunters": humans_arr.size(), "king": king.name if king != null else "", "servants": servants})


# 
func trigger_zombie_boost(p: Dictionary) -> bool:
	if state.mode != Constants.MODE_ZOMBIE or not p.isZombie or not p.alive:
		return false
	if state.time < float(p.skillReadyAt):
		return false
	p.speedOverride = Constants.ZOMBIE_BOOST_SPEED
	p.boostUntil = state.time + Constants.ZOMBIE_BOOST_DURATION
	p.skillReadyAt = state.time + Constants.ZOMBIE_BOOST_COOLDOWN
	# 加速视觉/音效统一走 broadcast（sendTo 的 zombie_boost 无 id 字段在 game.gd 永不匹配，已移除）
	state.broadcast.call({"type": "zombie_boost_visual", "id": p.id})
	return true


# 人类加速（F 键）：生化模式人类阵营，5 秒加速、45 秒冷却（与丧尸加速对称）
func trigger_human_boost(p: Dictionary) -> bool:
	if state.mode != Constants.MODE_ZOMBIE or p.isZombie or not p.alive:
		return false
	if state.time < float(p.skillReadyAt):
		return false
	p.speedOverride = Constants.HUMAN_BOOST_SPEED
	p.boostUntil = state.time + Constants.HUMAN_BOOST_DURATION
	p.skillReadyAt = state.time + Constants.HUMAN_BOOST_COOLDOWN
	state.broadcast.call({"type": "zombie_boost_visual", "id": p.id})
	return true


# ---------- ----------
func tick() -> void:
	var dt: float = TICK_MS / 1000.0
	state.time += dt
	state.tickAcc += TICK_MS
	state.snapAcc += TICK_MS

	if state.matchEndAt > 0.0 and state.time >= state.matchEndAt:
		state.matchScore = {"CT": 0, "T": 0, "HUMAN": 0, "ZOMBIE": 0}
		state.matchEndAt = 0.0
		state.roundEndAt = 0.0
		reset_economy()
		next_map()
		if state.mode == Constants.MODE_DEFUSAL:
			begin_buy_phase()
		else:
			start_round()
		return
	if state.roundEndAt > 0.0 and state.matchEndAt == 0.0 and state.time >= state.roundEndAt:
		start_round()
		return

	for p in state.players.values():
		#  / 
		if not p.isBot:
			p.yaw = float(p.input.yaw)
			p.pitch = float(p.input.pitch)
		# CS2 式冻结期：购买阶段不可移动/射击/换弹/使用（视角可转）。
		# 修复"购买阶段杀人白杀、击杀奖励照发"的问题——双方原地待命直至开赛。
		# 例外：允许拾取炸弹（T 方开局即可拿包，避免"假炸弹捡不起来"的困惑；
		# 安放/拆除依赖 core.state==live 天然被禁止）
		if state.phase == "buy":
			if p.input.u:
				_process_use(p, dt)
			continue
		if not p.alive:
			if p.respawnAt > 0.0 and state.time >= p.respawnAt and state.mode == Constants.MODE_ZOMBIE and not state.noRespawn:
				Player.respawn_zombie(state, p)
			continue
		# 
		if p.boostUntil > 0.0 and state.time >= p.boostUntil:
			p.boostUntil = 0.0
			p.speedOverride = null
		if p.isBot:
			BotBrain.tick_bot(state, p)
			p.inputAt = state.time
		_process_input(p)
		SimPhysics.move_player(p, p.input, dt, state.map.colliders)
		if p.history != null:
			p.history.push(state.time, {
				"pos": p.pos,
				"yaw": p.yaw,
				"pitch": p.pitch,
				"crouch": p.crouch,
				"alive": true,
			})
			p.history.prune(state.time)
		_process_weapons(p)
		_process_use(p, dt)
		if p.isZombie:
			if state.time - p.lastHitAt > 3.0:
				p.hp = min(p.maxHp, p.hp + PHYS.ZOMBIE_REGEN * dt)
			if p.slowTicks > 0:
				p.slowTicks -= 1

	_update_projectiles(dt)
	if state.core != null:
		state.core.update(dt)
		# 同步炸弹倒计时到 state.bomb（客户端 HUD 读它）
		if state.mode == Constants.MODE_DEFUSAL and state.core.bomb_planted:
			state.bomb.timeLeft = max(0.0, float(state.core.bomb_time_left))
	_update_ammo_boxes(dt)
	if state.phase == "buy" and state.mode == Constants.MODE_DEFUSAL:
		for bot in state.players.values():
			if bot.isBot and not bot.boughtPhase:
				bot.boughtPhase = true
				auto_buy(bot)
	# / 
	if state.mode == Constants.MODE_ZOMBIE and state.core != null and state.core.state == "live":
		var alive_human: Array = []
		var alive_zombie: Array = []
		for p in state.players.values():
			if p.alive:
				if p.isZombie:
					alive_zombie.append(p)
				else:
					alive_human.append(p)
		if not state.finaleActive and state.core.time_left <= FINALE.DURATION:
			state.finaleActive = true
			state.noRespawn = true
			if not alive_human.is_empty() or not alive_zombie.is_empty():
				activate_finale()
		if state.finaleActive:
			if alive_zombie.is_empty() and alive_human.is_empty():
				state.core.end("DRAW", "mutual_annihilation")
			elif alive_zombie.is_empty():
				state.core.end("HUMAN", "zombies_eliminated")
			elif alive_human.is_empty():
				state.core.end("ZOMBIE", "infected_all")
		else:
			if alive_human.is_empty():
				state.core.end("ZOMBIE", "infected_all")
			if alive_zombie.is_empty() and not alive_human.is_empty():
				var pick: Dictionary = alive_human[randi() % alive_human.size()]
				pick.isZombie = true
				pick.team = Constants.TEAM_ZOMBIE
				pick.zombieSince = state.time
				pick.hp = float(PHYS.ZOMBIE_HP)
				pick.maxHp = float(PHYS.ZOMBIE_HP)
				pick.armor = 0
				pick.speedOverride = null
				Player.give_loadout(pick, state.mode, Constants.TEAM_ZOMBIE)
				state.core.infect(pick.id)
				state.broadcast.call({"type": "infected", "id": pick.id})

	if state.snapAcc >= SNAPSHOT_INTERVAL_MS:
		state.snapAcc = 0.0
		if not _local_only:
			state.broadcast.call(snapshot())

	if events.has("tick"):
		events.tick.call({"time": state.time})


func _process_input(p: Dictionary) -> void:
	var inp: Dictionary = p.input
	# 视角：本地玩家/人类由 input.yaw/pitch 驱动；Bot 直接在 tick_bot 里写入 p.yaw/p.pitch，
	# 若这里覆盖会把机器人朝向重置为 0，导致所有 NPC 斜着走、不转向。
	if not p.isBot:
		p.yaw = float(inp.yaw)
		p.pitch = float(inp.pitch)
	p.crouch = bool(inp.c)
	var slot_before: int = p.activeSlot
	var edge: Dictionary = p.edge
	# 
	if typeof(edge.sw) == TYPE_INT and edge.sw >= 0:
		if p.weapons.has(edge.sw):
			p.activeSlot = edge.sw
			p.useProgress = 0.0
		else:
			# 
			var cur: Variant = p.weapons.get(p.activeSlot, null)
			p.switchSeq += 1
			state.sendTo.call(p.id, {"type": "switch", "w": cur.def.id if cur != null else "", "slot": p.activeSlot, "seq": p.switchSeq})
	# 
	if edge.swd != 0:
		var slots: Array = []
		for k in p.weapons.keys():
			slots.append(k)
		slots.sort()
		if slots.size() > 1:
			var idx: int = slots.find(p.activeSlot)
			var dir_idx: int = 1 if edge.swd > 0 else (slots.size() - 1)
			p.activeSlot = slots[(idx + dir_idx) % slots.size()]
			p.useProgress = 0.0
	edge.sw = -1
	edge.swd = 0
	if edge.j:
		inp.j = true
		edge.j = false
	if edge.r:
		inp.r = true
		edge.r = false
	if edge.skill:
		edge.skill = false
		# F 技能：丧尸用丧尸加速，人类用人类加速（生化模式）
		if p.isZombie:
			trigger_zombie_boost(p)
		else:
			trigger_human_boost(p)
	#  + 
	if slot_before != p.activeSlot:
		p.switchSeq += 1
		var w_now: Variant = p.weapons.get(p.activeSlot, null)
		state.sendTo.call(p.id, {"type": "switch", "w": w_now.def.id if w_now != null else "", "slot": p.activeSlot, "seq": p.switchSeq})
	var def: Dictionary = {}
	var w_active: Variant = p.weapons.get(p.activeSlot, null)
	if w_active != null:
		def = w_active.def
	var ads: bool = inp.ads and not p.isZombie and not def.is_empty() and not def.get("melee", false) and not def.has("projectile")
	p.weaponMoveMult = float(def.moveMult) * (0.78 if ads else 1.0) if not def.is_empty() else 1.0
	if def.get("projectile", "") != "":
		p.weaponMoveMult = min(p.weaponMoveMult, 0.9)


func _process_weapons(p: Dictionary) -> void:
	var w: Variant = p.weapons.get(p.activeSlot, null)
	var held: bool = bool(p.input.fire)
	var fire_now: bool = WeaponData.should_fire(w.def, held, p.wasFiring) if w != null else false
	p.wasFiring = held
	if w == null:
		return
	var def: Dictionary = w.def
	var now: float = state.time
	var reload_event: Dictionary = w.update(now)
	if not reload_event.is_empty():
		state.sendTo.call(p.id, {"type": "reloaded", "ammo": reload_event.ammo, "reserve": reload_event.reserve})
	if w.state == "empty":
		# 
		if w.start_reload(now).ok:
			state.sendTo.call(p.id, {"type": "reloading", "weapon": def.id})
	elif p.input.r and w.state == "ready" and w.ammo < float(def.magSize):
		# R 
		if w.start_reload(now).ok:
			state.sendTo.call(p.id, {"type": "reloading", "weapon": def.id})
	if fire_now and (not p.isZombie or def.get("melee", false)):
		if def.get("melee", false):
			if w.can_fire(now):
				w.fire(now)
				Hitscan.perform_shot(state, p, def, {"rewindTime": p.inputAt if p.inputAt > 0 else state.time})
				state.broadcast.call({"type": "shot_visual", "id": p.id, "weapon": def.id, "melee": true, "pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch})
				state.sendTo.call(p.id, {"type": "shot", "weapon": def.id, "ammo": w.ammo, "reserve": w.reserve})
		elif def.get("projectile", "") != "":
			if w.can_fire(now) and p.grenadeCount > 0:
				w.fire(now)
				p.grenadeCount -= 1
				Hitscan.perform_shot(state, p, def, {"rewindTime": p.inputAt if p.inputAt > 0 else state.time})
				state.broadcast.call({"type": "throw_visual", "id": p.id, "pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch})
				state.sendTo.call(p.id, {"type": "throw_ack", "grenades": p.grenadeCount})
		elif w.can_fire(now):
			w.fire(now)
			Hitscan.perform_shot(state, p, def, {"rewindTime": p.inputAt if p.inputAt > 0 else state.time})
			state.broadcast.call({"type": "shot_visual", "id": p.id, "weapon": def.id, "pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch})
			state.sendTo.call(p.id, {"type": "shot", "weapon": def.id, "ammo": w.ammo, "reserve": w.reserve})


func _process_use(p: Dictionary, dt: float) -> void:
	if not p.input.u:
		p.useProgress = 0.0
		p.useTarget = null
		return
	if state.mode == Constants.MODE_DEFUSAL:
		# 1) T  E
		if state.core != null and state.core.state == "live" and p.team == Constants.TEAM_T and not p.bombCarrier and state.bomb != null and not state.bomb.carried and not state.bomb.planted and state.bomb.pos != null:
			var d: float = sqrt(pow(p.pos.x - state.bomb.pos.x, 2) + pow(p.pos.z - state.bomb.pos.z, 2))
			if d < 2.4:
				p.bombCarrier = true
				state.bomb.carried = true
				state.bomb.carrierId = p.id
				state.bomb.pos = null
				state.sendTo.call(p.id, {"type": "bomb_pickup"})
				p.useProgress = 0.0
				p.useTarget = null
				return
		# 2) T E
		if state.core != null and state.core.state == "live" and p.team == Constants.TEAM_T and p.bombCarrier and not state.core.bomb_planted:
			var site_found: Variant = null
			for site in state.map.sites:
				var d: float = sqrt(pow(p.pos.x - site.pos.x, 2) + pow(p.pos.z - site.pos.z, 2))
				if d < site.radius:
					site_found = site
					break
			if site_found != null:
				p.useTarget = "plant_%s" % site_found.id
				p.useProgress += dt
				if p.useProgress >= 3.0:
					state.core.plant_bomb({"x": p.pos.x, "y": p.pos.y, "z": p.pos.z, "site": site_found.id})
					state.bomb.planted = true
					state.bomb.carried = false
					state.bomb.carrierId = null
					p.bombCarrier = false
					p.money = min(Economy.MONEY_CAP, p.money + Economy.PLANT_REWARD)
					p.useProgress = 0.0
			else:
				p.useProgress = 0.0
			#  10Hz
			if p.useProgress > 0.0 and state.time - p.lastUseProgressAt >= 0.1:
				p.lastUseProgressAt = state.time
				state.sendTo.call(p.id, {"type": "use_progress", "action": "plant", "progress": min(1.0, snappedf(p.useProgress / 3.0, 0.01))})
			return
		# 3) CT
		if state.core != null and state.core.state == "live" and p.team == Constants.TEAM_CT and state.core.bomb_planted and state.bomb.has("pos") and state.bomb.pos != null:
			var d: float = sqrt(pow(p.pos.x - state.bomb.pos.x, 2) + pow(p.pos.z - state.bomb.pos.z, 2))
			if d < 2.4:
				p.useTarget = "defuse"
				p.useProgress += dt
				# 拆弹进行中广播"滴滴"提示（CS 风格：T 能听到 CT 在拆弹）
				# 节流 0.35s，防止每 tick 广播刷屏
				if p.useProgress > 0.0 and state.time - float(p.get("lastDefuseBeepAt", -99.0)) >= 0.35:
					p.lastDefuseBeepAt = state.time
					state.broadcast.call({"type": "defuse_beep", "pos": Vector3(p.pos.x, p.pos.y, p.pos.z)})
				if p.useProgress >= 5.0:
					state.core.defuse_bomb()
					p.money = min(Economy.MONEY_CAP, p.money + Economy.DEFUSE_REWARD)
					p.useProgress = 0.0
			else:
				p.useProgress = 0.0
			if p.useProgress > 0.0 and state.time - p.lastUseProgressAt >= 0.1:
				p.lastUseProgressAt = state.time
				state.sendTo.call(p.id, {"type": "use_progress", "action": "defuse", "progress": min(1.0, snappedf(p.useProgress / 5.0, 0.01))})
			return
		p.useProgress = 0.0
		p.useTarget = null
	elif not p.isZombie:
		# 
		var box_found: Variant = null
		for box in state.ammoBoxes:
			if box.available and sqrt(pow(box.pos.x - p.pos.x, 2) + pow(box.pos.z - p.pos.z, 2)) < 2.0:
				box_found = box
				break
		if box_found != null:
			var refilled: bool = false
			for w in p.weapons.values():
				if is_finite(w.def.reserve) and w.reserve < w.def.reserve:
					w.reserve = w.def.reserve
					refilled = true
			if refilled:
				box_found.available = false
				box_found.respawnAt = state.time + float(box_found.respawn)
				state.sendTo.call(p.id, {"type": "ammo_refill"})
				state.broadcast.call({"type": "ammo_box", "id": p.id, "pos": box_found.pos})
		# 
		if p.hp < p.maxHp:
			var hb_found: Variant = null
			for hb in state.healthBoxes:
				if hb.available and sqrt(pow(hb.pos.x - p.pos.x, 2) + pow(hb.pos.z - p.pos.z, 2)) < 2.0:
					hb_found = hb
					break
			if hb_found != null:
				var before: float = p.hp
				p.hp = min(p.maxHp, p.hp + Constants.HEALTH_BOX_HEAL)
				hb_found.available = false
				hb_found.respawnAt = state.time + float(hb_found.respawn)
				state.sendTo.call(p.id, {"type": "health_refill", "hp": int(ceil(p.hp))})
				state.broadcast.call({"type": "health_box", "id": p.id, "pos": hb_found.pos, "amount": int(round(p.hp - before))})
	else:
		# 僵尸按 E 无任何交互：重置进度，避免残留进度条
		p.useProgress = 0.0
		p.useTarget = null


func _update_projectiles(dt: float) -> void:
	var to_remove: Array = []
	for proj in state.projectiles:
		proj.fuse -= dt
		proj.vel.y += -9.8 * dt
		var next_pos := Vector3(proj.pos.x + proj.vel.x * dt, proj.pos.y + proj.vel.y * dt, proj.pos.z + proj.vel.z * dt)
		var bounced: bool = false
		for box in state.map.colliders:
			if next_pos.x > box.min.x and next_pos.x < box.max.x and \
			   next_pos.y > box.min.y and next_pos.y < box.max.y and \
			   next_pos.z > box.min.z and next_pos.z < box.max.z:
				var pen_x: float = min(next_pos.x - box.min.x, box.max.x - next_pos.x)
				var pen_y: float = min(next_pos.y - box.min.y, box.max.y - next_pos.y)
				var pen_z: float = min(next_pos.z - box.min.z, box.max.z - next_pos.z)
				var min_pen: float = min(pen_x, min(pen_y, pen_z))
				if min_pen == pen_y:
					proj.vel.y *= -0.4
				elif min_pen == pen_x:
					proj.vel.x *= -0.4
				else:
					proj.vel.z *= -0.4
				proj.bounces += 1
				bounced = true
				break
		if bounced:
			proj.pos = Vector3((proj.pos.x + next_pos.x) / 2.0, (proj.pos.y + next_pos.y) / 2.0, (proj.pos.z + next_pos.z) / 2.0)
			if proj.bounces >= 3 or sqrt(proj.vel.x * proj.vel.x + proj.vel.y * proj.vel.y + proj.vel.z * proj.vel.z) < 1.2:
				proj.vel = Vector3(0, 0, 0)
		else:
			proj.pos = next_pos
		if proj.pos.y < 0.1:
			proj.pos.y = 0.1
			proj.vel.y *= -0.35
			# 地面摩擦力：手雷贴地滚动时水平速度按指数衰减（现实化——不再一丢滑出老远）
			var fric: float = 6.0
			proj.vel.x *= maxf(0.0, 1.0 - fric * dt)
			proj.vel.z *= maxf(0.0, 1.0 - fric * dt)
			# 完全停住后标记静止，避免持续微动
			if sqrt(proj.vel.x * proj.vel.x + proj.vel.z * proj.vel.z) < 0.05:
				proj.vel.x = 0.0
				proj.vel.z = 0.0
		if proj.fuse <= 0.0:
			_explode_grenade(proj)
			to_remove.append(proj)
	for proj in to_remove:
		state.projectiles.erase(proj)


func _explode_grenade(proj: Dictionary) -> void:
	var def: Dictionary = state.weapons.thunder
	# 爆炸特效/音效统一走 "explosion" 广播消息（game.gd 消息分支处理），
	# 不再双发 events.explosion——本地玩家此前会看到两次爆炸特效
	state.broadcast.call({"type": "explosion", "pos": proj.pos, "owner": proj.owner})
	var owner: Variant = state.players.get(proj.owner, null)
	for p in state.players.values():
		if not p.alive:
			continue
		var dx: float = p.pos.x - proj.pos.x
		var dy: float = p.pos.y + 0.9 - proj.pos.y
		var dz: float = p.pos.z - proj.pos.z
		var d: float = sqrt(dx * dx + dy * dy + dz * dz)
		if d > 11.0:
			continue
		var dmg: float = float(def.damage) * (1.0 if d <= 3.0 else 1.0 - ((d - 3.0) / 8.0) * 0.75)
		Player.damage_player(state, owner, p, float(round(dmg)), {"weapon": "thunder", "dist": d})


func _update_ammo_boxes(_dt: float) -> void:
	for b in state.ammoBoxes:
		if not b.available and state.time >= b.respawnAt:
			b.available = true
	for b in state.healthBoxes:
		if not b.available and state.time >= b.respawnAt:
			b.available = true


# ----------  /  ----------
func handle_buy(p: Dictionary, item: String) -> Dictionary:
	if state.mode != Constants.MODE_DEFUSAL or state.phase != "buy":
		return {"ok": false, "reason": "phase"}
	if p.is_empty():
		return {"ok": false, "reason": "player"}
	var cost: int = Economy.cost_of(item, p.armor)
	if cost < 0:
		return {"ok": false, "reason": "item"}
	if cost == 0:
		return {"ok": false, "reason": "already"}
	if p.money < cost:
		return {"ok": false, "reason": "money"}
	if item == "armor":
		p.boughtItems.append({"item": item, "cost": cost, "prevArmor": p.armor})
		p.armor = 100
	elif item == "grenade":
		if p.grenadeCount >= 5:
			return {"ok": false, "reason": "max"}
		p.grenadeCount += 1
		p.boughtItems.append({"item": item, "cost": cost})
	else:
		if not state.weapons.has(item):
			return {"ok": false, "reason": "item"}
		var def: Dictionary = state.weapons[item]
		var prev: Variant = p.weapons.get(def.slot, null)
		var runtime = WeaponData.WeaponRuntime.new(def)
		p.weapons[def.slot] = runtime
		p.boughtItems.append({"item": item, "cost": cost, "slot": def.slot, "prev": prev, "runtime": runtime})
		if def.slot == 2:
			p.activeSlot = 2
	p.money -= cost
	state.sendTo.call(p.id, {"type": "buy_ok", "item": item, "money": p.money})
	return {"ok": true}


func handle_refund(p: Dictionary, item: String) -> Dictionary:
	if state.mode != Constants.MODE_DEFUSAL or state.phase != "buy":
		return {"ok": false, "reason": "phase"}
	if p.is_empty():
		return {"ok": false, "reason": "player"}
	var idx: int = -1
	for i in range(p.boughtItems.size()):
		if p.boughtItems[i].item == item:
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": "not_bought"}
	var rec: Dictionary = p.boughtItems[idx]
	if item == "armor":
		p.armor = rec.prevArmor
	elif item == "grenade":
		p.grenadeCount = max(0, p.grenadeCount - 1)
	elif p.weapons.get(rec.slot, null) == rec.runtime:
		# 当前槽位仍是本次购买的那把枪：正常退回
		if rec.prev != null:
			p.weapons[rec.slot] = rec.prev
		else:
			p.weapons.erase(rec.slot)
		if rec.prev == null and p.activeSlot == rec.slot and p.weapons.has(1):
			p.activeSlot = 1
	else:
		# 该槽位已被后续购买覆盖（rec.runtime 已不在手上）：
		# 记录作废且不退款——堵住"买 A→买 B 覆盖→退 A"白嫖 2700 却保留 B 的漏洞
		p.boughtItems.remove_at(idx)
		state.sendTo.call(p.id, {"type": "refund_fail", "item": item, "reason": "replaced"})
		return {"ok": false, "reason": "replaced"}
	p.money = min(Economy.MONEY_CAP, p.money + rec.cost)
	p.boughtItems.remove_at(idx)
	state.sendTo.call(p.id, {"type": "refund_ok", "item": item, "money": p.money})
	return {"ok": true}


func auto_buy(bot: Dictionary) -> Dictionary:
	# 买主武器（slot 2）：从买得起的中档枪里随机挑，避免"永远买最贵的枪"造成
	# 连胜方（通常 CT）枪械碾压连败方（通常 T）→ 看起来 CT 打得"更准"。
	if not bot.weapons.has(2):
		var candidates: Array = []
		for wid in state.weapons:
			var def: Dictionary = state.weapons[wid]
			if def.get("slot", 9) == 2 and not def.get("melee", false):
				candidates.append({"id": wid, "cost": Economy.weapon_price(def)})
		candidates.sort_custom(func(a, b): return int(a.cost) > int(b.cost))
		var affordable: Array = []
		for c in candidates:
			if bot.money >= int(c.cost):
				affordable.append(c)
		if not affordable.is_empty():
			var pick: Dictionary
			if affordable.size() > 2 and randf() < 0.65:
				# 65% 概率：在"买得起的中高段"随机（从第 35% 分位往后），避免最强枪
				var lo: int = maxi(0, int(affordable.size() * 0.35))
				pick = affordable[lo + randi() % maxi(1, affordable.size() - lo)]
			else:
				# 35% 概率或枪太少：直接买最贵的
				pick = affordable[0]
			return handle_buy(bot, pick.id)
	if bot.money >= Economy.PRICES.armor and bot.armor < 60:
		return handle_buy(bot, "armor")
	if bot.money >= Economy.PRICES.grenade and bot.grenadeCount < 2:
		return handle_buy(bot, "grenade")
	return {"ok": false}


# 
func handle_zombie_select(p: Dictionary, item: String) -> Dictionary:
	if state.mode != Constants.MODE_ZOMBIE:
		return {"ok": false, "reason": "phase"}
	if p.is_empty() or p.isZombie:
		return {"ok": false, "reason": "player"}
	if not state.weapons.has(item):
		return {"ok": false, "reason": "item"}
	var def: Dictionary = state.weapons[item]
	if def.slot != 2:
		return {"ok": false, "reason": "item"}
	# 生化模式选枪免费（购买菜单标注"免费"），允许随时更换主武器
	p.weapons[2] = WeaponData.WeaponRuntime.new(def)
	p.selectedPrimary = def.id
	p.activeSlot = 2
	state.sendTo.call(p.id, {"type": "buy_ok", "item": item, "money": p.money})
	state.sendTo.call(p.id, {"type": "zselect_ok", "item": item, "money": p.money})
	return {"ok": true}


func reset_economy() -> void:
	for p in state.players.values():
		p.money = Economy.START_MONEY


func begin_buy_phase() -> void:
	if state.mode != Constants.MODE_DEFUSAL:
		return
	state.phase = "buy"
	state.buyUntil = state.time + 10.0
	state.roundEndAt = state.time + 10.0
	state.broadcast.call({"type": "buy_phase", "until": state.buyUntil})
	print("[Room] buy phase started")


func next_map() -> void:
	state.rotationIdx = (state.rotationIdx + 1) % state.rotation.size()
	state.mapId = state.rotation[state.rotationIdx]
	state.map = MapData.get_map(state.mapId)
	state.ammoBoxes = _init_boxes(state.map.get("ammoBoxes", []))
	state.healthBoxes = _init_boxes(state.map.get("healthBoxes", []))
	# 每局结束切换到下一张地图：彻底清空所有玩家的装备与状态（含 bot 大脑），
	# 确保不会把上一局的武器带到下一局；新对局的装备由随后的 start_round 重建。
	for p in state.players.values():
		p.alive = false
		p.weapons.clear()
		p.activeSlot = 1
		p.grenadeCount = 0
		p.armor = 0
		p.bombCarrier = false
		p.boughtItems = []
		p.money = Economy.START_MONEY
		# K/D 按整场比赛累计（CS2 语义）：仅在换图（新比赛）时清零
		p.kills = 0
		p.deaths = 0
		p.input.fire = false
		p.edge.sw = -1
		p.edge.swd = 0
		if p.isBot:
			if p.botBrain != null:
				BotBrain.reset_brain(p.botBrain)
	state.broadcast.call({"type": "map_change", "map": state.mapId, "mapName": state.map.name})
	print("[Room] next map: %s" % state.mapId)


# ----------  ----------
func snapshot() -> Dictionary:
	var players: Array = []
	for p in state.players.values():
		var w: Variant = p.weapons.get(p.activeSlot, null)
		players.append({
			"i": p.id,
			"n": p.name.substr(0, 12),
			"t": p.team,
			"zb": 1 if p.isZombie else 0,
			"h": max(0, int(ceil(p.hp))),
			"mx": max(1, int(ceil(p.maxHp))),
			"a": max(0, int(ceil(p.armor))),
			"ft": 1 if p.isCrystalHunter else (2 if p.isZombieKing else (3 if p.isZombieServant else 0)),
			"x": snappedf(p.pos.x, 0.01),
			"y": snappedf(p.pos.y, 0.01),
			"z": snappedf(p.pos.z, 0.01),
			"ya": snappedf(p.yaw, 0.001),
			"pi": snappedf(p.pitch, 0.001),
			"al": 1 if p.alive else 0,
			"cr": 1 if p.crouch else 0,
			"w": w.def.id if w != null else "",
			# 近战/无限弹药武器用 -1 表示"无限"，避免 int(INF) 溢出成巨大负数
			"am": (-1 if (w != null and w.def.get("melee", false)) else min(int(w.ammo) if w != null else 0, 999)),
			"rs": (-1 if (w != null and w.def.get("melee", false)) else min(int(w.reserve) if w != null else 0, 9999)),
			"bc": 1 if p.bombCarrier else 0,
			"ws": p.switchSeq,
			"sc": p.score,
			"k": p.kills,
			"d": p.deaths,
			"g": p.grenadeCount,
			"mo": p.money,
			"bi": _bought_items_list(p.boughtItems),
			"skillCd": max(0, int(ceil(float(p.skillReadyAt) - state.time))),
			"bo": 1 if (p.boostUntil > 0 and state.time < p.boostUntil) else 0,
		})
	var r := {
		"st": state.core.state if state.core != null else state.globalState,
		"rn": state.roundNum,
		"tl": max(0, int(ceil(state.core.time_left if state.core != null else 0.0))),
		"bl": max(0, int(ceil(state.bomb.timeLeft))),
		"sc": state.matchScore,
		"ph": state.phase,
		"bu": max(0, int(ceil(state.buyUntil - state.time))),
	}
	return {
		"type": "state",
		"t": snappedf(state.time, 0.01),
		"p": players,
		"b": _bomb_snapshot(),
		"proj": _proj_snapshot(),
		"r": r,
	}


func _bought_items_list(items: Array) -> Array:
	var out: Array = []
	for r in items:
		out.append(r.item)
	return out


func _bomb_snapshot() -> Variant:
	var b: Dictionary = state.bomb
	if b.planted:
		return {"planted": 1, "carried": 0, "x": b.pos.x, "y": b.pos.y, "z": b.pos.z, "tl": max(0, int(ceil(state.core.bomb_time_left if state.core != null else 0.0)))}
	if b.carried:
		return {"carried": 1, "carrierId": b.carrierId, "planted": 0}
	if b.pos != null:
		return {"planted": 0, "carried": 0, "x": b.pos.x, "y": b.pos.y, "z": b.pos.z}
	return null


func _proj_snapshot() -> Array:
	var out: Array = []
	for pr in state.projectiles:
		out.append({"id": pr.id, "x": snappedf(pr.pos.x, 0.01), "y": snappedf(pr.pos.y, 0.01), "z": snappedf(pr.pos.z, 0.01), "k": pr.kind})
	return out

# 拆弹模式回合核心：回合计时、炸弹计时、胜负判定。
class DefusalRound:
	extends RefCounted

	var round_time: float
	var bomb_time: float
	var on_event: Callable = Callable()
	var get_state: Callable = Callable()
	var state: String = "ended"
	var time_left: float = 0.0
	var bomb_planted: bool = false
	var bomb_time_left: float = 0.0

	func _init(cfg: Dictionary) -> void:
		round_time = float(cfg.get("roundTime", 105.0))
		bomb_time = float(cfg.get("bombTime", 40.0))
		on_event = cfg.get("onEvent", Callable())
		get_state = cfg.get("getState", Callable())

	func start(_opts: Dictionary) -> void:
		state = "live"
		time_left = round_time
		bomb_planted = false
		bomb_time_left = 0.0
		if on_event.is_valid():
			on_event.call({"type": "round_start"})

	func update(dt: float) -> void:
		if state != "live":
			return
		if bomb_planted:
			bomb_time_left -= dt
			if bomb_time_left <= 0.0:
				_explode()
				return
		else:
			time_left -= dt
			if time_left <= 0.0:
				end("CT", "timeout")
				return
			var st: Dictionary = get_state.call() if get_state.is_valid() else {}
			var ct: int = 0
			var t: int = 0
			for p in st.get("players", {}).values():
				if bool(p.alive):
					if int(p.team) == Constants.TEAM_CT:
						ct += 1
					elif int(p.team) == Constants.TEAM_T:
						t += 1
			if t == 0 and ct > 0:
				end("CT", "t_eliminated")
			elif ct == 0 and t > 0:
				end("T", "ct_eliminated")

	func plant_bomb(pos: Dictionary) -> void:
		bomb_planted = true
		bomb_time_left = bomb_time
		if on_event.is_valid():
			on_event.call({"type": "bomb_planted", "pos": Vector3(float(pos.x), float(pos.y), float(pos.z)), "site": pos.get("site", "")})

	func team_eliminated(team: int) -> void:
		# 队伍全灭：CT 全灭 → T 胜；T 全灭 → CT 胜
		if state != "live":
			return
		# 炸弹已安放时，T 全灭不立即结束（T 仍可靠爆炸获胜，CT 需拆除）
		if bomb_planted and team == Constants.TEAM_T:
			return
		if team == Constants.TEAM_CT:
			end("T", "ct_eliminated")
		elif team == Constants.TEAM_T:
			end("CT", "t_eliminated")

	func defuse_bomb() -> void:
		bomb_planted = false
		if on_event.is_valid():
			on_event.call({"type": "bomb_defused", "pos": Vector3.ZERO})
		end("CT", "bomb_defused")

	func _explode() -> void:
		bomb_planted = false
		if on_event.is_valid():
			on_event.call({"type": "bomb_exploded", "pos": Vector3.ZERO})
		end("T", "bomb_exploded")

	func end(winner: String, reason: String) -> void:
		if state != "live":
			return
		state = "ended"
		if on_event.is_valid():
			on_event.call({"type": "round_end", "winner": winner, "reason": reason})


# 生化模式回合核心：时长倒计时。
class ZombieMatch:
	extends RefCounted

	var duration: float
	var on_event: Callable = Callable()
	var get_state: Callable = Callable()
	var state: String = "ended"
	var time_left: float = 0.0
	var humans: Array = []
	var zombies: Array = []

	func _init(cfg: Dictionary) -> void:
		duration = float(cfg.get("duration", 300.0))
		on_event = cfg.get("onEvent", Callable())
		get_state = cfg.get("getState", Callable())

	func start(opts: Dictionary) -> void:
		state = "live"
		time_left = duration
		humans = opts.get("humans", [])
		zombies = opts.get("zombies", [])
		if on_event.is_valid():
			on_event.call({"type": "round_start"})

	func update(dt: float) -> void:
		if state != "live":
			return
		time_left -= dt
		if time_left <= 0.0:
			if humans.size() > 0:
				end("HUMAN", "survived")
			else:
				end("ZOMBIE", "infected_all")

	func infect(player_id: String) -> void:
		# 人类被击杀 → 变为僵尸（追踪核心内的人/尸数量，用于判胜与琉璃决战）
		if state != "live":
			return
		var hi: int = humans.find(player_id)
		if hi != -1:
			humans.remove_at(hi)
			zombies.append(player_id)
		if on_event.is_valid():
			on_event.call({"type": "infected", "playerId": player_id})
		if humans.is_empty():
			end("ZOMBIE", "infected_all")

	func end(winner: String, reason: String) -> void:
		if state != "live":
			return
		state = "ended"
		if on_event.is_valid():
			on_event.call({"type": "round_end", "winner": winner, "reason": reason})
