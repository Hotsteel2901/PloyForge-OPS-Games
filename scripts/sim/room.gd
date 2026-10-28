# 房间：通用模拟层（物理 / 武器 / 伤害 / 投掷物 / 补给 / 快照）。
# v2 起「规则与胜负」全部交给 ModeBase，Room 只提供通用能力。
class_name Room
extends RefCounted

const PHYS = Constants.PHYS
const TICK_MS = Constants.TICK_MS
const SNAPSHOT_INTERVAL_MS = Constants.SNAPSHOT_INTERVAL_MS
const BOT_NAMES: Array = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet"]

var state: Dictionary
var events: Dictionary = {}
var mode: ModeBase = null
var _local_only: bool = false
var broadcast: Callable = Callable()
var send_to: Callable = Callable()
var drop_bomb: Callable = Callable()
var pick_spawn: Callable = Callable()


func _init(opts: Dictionary) -> void:
	var mode_id: String = str(opts.get("mode", "defusal"))
	var map_id: String = str(opts.get("mapId", "cinder"))
	var max_players: int = int(opts.get("maxPlayers", Constants.MAX_PLAYERS))
	var bot_count: int = int(opts.get("botCount", Constants.BOT_COUNT))
	var map_data: Dictionary = MapData.get_map(map_id)
	_local_only = bool(opts.get("localOnly", false))
	mode = ModeRegistry.create(mode_id)
	state = {
		"id": opts.get("id", "local"),
		"mode": mode_id,
		"modeLabel": mode.label,
		"mapId": map_id,
		"map": map_data,
		"maxPlayers": max_players,
		"botCount": bot_count,
		"players": {},
		"time": 0.0,
		"tickAcc": 0.0,
		"snapAcc": 0.0,
		"weapons": WeaponDB.all() if not WeaponDB.all().is_empty() else WeaponData.BUILTIN_WEAPONS.duplicate(),
		"projectiles": [],
		"smokes": [],
		"fires": [],
		"nextProjId": 1,
		"ammoBoxes": _init_boxes(map_data.get("ammoBoxes", [])),
		"healthBoxes": _init_boxes(map_data.get("healthBoxes", [])),
		"bomb": blank_bomb(),
		"finaleActive": false,
		"noRespawn": false,
		"core": null,
		"roundNum": 0,
		"matchScore": {"CT": 0, "T": 0, "HUMAN": 0, "ZOMBIE": 0},
		"lossStreak": {"CT": 0, "T": 0},
		"globalState": "live",
		"phase": "live",
		"buyUntil": 0.0,
		"roundEndAt": 0.0,
		"matchEndAt": 0.0,
		"rotation": _rotation_for(mode_id),
		"rotationIdx": 0,
		"nextBotId": 1,
		"events": events,
		"broadcast": Callable(),
		"sendTo": Callable(),
		"dropBomb": Callable(),
		"pickSpawn": Callable(),
		"onKilled": Callable(),
		"isHostile": Callable(),
		"modeExtra": Callable(),
		"modeImpl": null,
		# 模式派生
		"friendly_fire": mode.friendly_fire,
		"ffa": not mode.team_based,
		"uses_money": mode.uses_money,
		"team_based": mode.team_based,
		"roundLimit": mode.round_limit,
	}
	_bind_state_callables()
	state.matchScore = _blank_score()


func _rotation_for(mode_id: String) -> Array:
	match mode_id:
		"zombie", "survival":
			return ["containment", "obsidian"]
		"ctf", "koth":
			return ["cinder", "obsidian"]
		_:
			return ["cinder", "obsidian", "containment"]


static func blank_bomb() -> Dictionary:
	return {"planted": false, "carried": false, "carrierId": null, "pos": null, "timeLeft": 0.0}


func _blank_score() -> Dictionary:
	if state.mode == Constants.MODE_ZOMBIE:
		return {"HUMAN": 0, "ZOMBIE": 0}
	return {"CT": 0, "T": 0}


func _bind_state_callables() -> void:
	state.broadcast = _make_broadcast()
	state.sendTo = _make_send_to()
	state.dropBomb = _make_drop_bomb()
	state.pickSpawn = _make_pick_spawn()
	state.onKilled = func(victim: Dictionary, killer: Variant, info: Dictionary) -> void:
		on_player_killed(victim, killer, info)
	state.isHostile = func(a: Dictionary, c: Dictionary) -> bool: return is_hostile(a, c)
	state.modeImpl = mode
	state.modeExtra = func() -> Dictionary: return mode.snapshot_extra(self)
	state.events = events
	broadcast = state.broadcast
	send_to = state.sendTo
	drop_bomb = state.dropBomb
	pick_spawn = state.pickSpawn


# ---------------- 消息通道 ----------------

func _make_broadcast() -> Callable:
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
	return func(p: Dictionary) -> void: drop_bomb_impl(p)


func _make_pick_spawn() -> Callable:
	return func(team_key: String) -> Dictionary: return _pick_spawn_impl(team_key)


## 对外广播（网络层会覆盖为真实发送）
func broadcast_msg(msg: Dictionary) -> void:
	if broadcast.is_valid():
		broadcast.call(msg)


# ---------------- 生命周期 ----------------

func start() -> void:
	mode.setup(self)
	if state.core != null:
		state.core.bind(_on_core_end)
	fill_bots()
	state.matchScore = _blank_score()
	if mode.uses_buy_phase:
		begin_buy_phase()
	else:
		_begin_round()
	print("[Room] started mode=%s map=%s bots=%d" % [state.mode, state.mapId, count_bots()])


func stop() -> void:
	pass


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
	var want: int = mini(state.botCount, state.maxPlayers - humans())
	var have: int = count_bots()
	while have < want:
		spawn_bot("Bot-" + str(BOT_NAMES[have % BOT_NAMES.size()]))
		have += 1


func spawn_bot(name_prefix: String, difficulty: float = -1.0) -> Dictionary:
	var bot_id: String = "b%d" % state.nextBotId
	state.nextBotId += 1
	var bot: Dictionary = Player.create(bot_id, name_prefix, true)
	bot.botBrain = BotBrain.create_brain(difficulty)
	bot.pendingMessages = []
	state.players[bot_id] = bot
	return bot


func add_local_player(p_name: String, team_pref: String = "random") -> Dictionary:
	if humans() >= state.maxPlayers:
		return {}
	var id: String = "h%d_%d" % [Time.get_ticks_msec(), randi() % 10000]
	var p: Dictionary = Player.create(id, p_name)
	p.pendingMessages = []
	p.teamPref = team_pref if team_pref in ["ct", "t"] else "random"
	state.players[id] = p
	if state.players.size() > state.maxPlayers:
		for k in state.players.keys().duplicate():
			if state.players[k].isBot:
				state.players.erase(k)
				break
	print("[Room] player joined: %s (%s), total=%d" % [p_name, id, state.players.size()])
	return p


## 网络层加入的远端玩家
func add_remote_player(id: String, p_name: String, team_pref: String = "random") -> Dictionary:
	var p: Dictionary = Player.create(id, p_name)
	p.isRemote = true
	p.pendingMessages = []
	p.teamPref = team_pref if team_pref in ["ct", "t"] else "random"
	state.players[id] = p
	# 挤掉一个 bot
	if state.players.size() > state.maxPlayers:
		for k in state.players.keys().duplicate():
			if state.players[k].isBot:
				state.players.erase(k)
				break
	return p


func spawn_joiner(p: Dictionary) -> void:
	if p.alive:
		return
	if state.core != null and state.core.state == "ended":
		return
	# 交给模式决定分队
	if mode.uses_buy_phase or mode.team_based:
		var team: int = _auto_team()
		p.team = team
	else:
		p.team = Constants.TEAM_NONE
	p.isZombie = false
	var key: String = "CT" if p.team == Constants.TEAM_CT else ("T" if p.team == Constants.TEAM_T else "HUMAN")
	var spot: Dictionary = _pick_spawn_impl(key)
	Player.spawn_player(state, p, p.team, spot)
	mode.on_player_spawn(self, p)


func _auto_team() -> int:
	if not mode.team_based:
		return Constants.TEAM_NONE
	if p_balanced_needed():
		var ct: int = 0
		var t: int = 0
		for x in state.players.values():
			if int(x.team) == Constants.TEAM_CT:
				ct += 1
			elif int(x.team) == Constants.TEAM_T:
				t += 1
		return Constants.TEAM_CT if ct <= t else Constants.TEAM_T
	return Constants.TEAM_NONE


func p_balanced_needed() -> bool:
	return state.mode in [Constants.MODE_DEFUSAL, "tdm", "koth", "ctf"]


func remove_player(id: String) -> void:
	if not state.players.has(id):
		return
	var p: Dictionary = state.players[id]
	drop_bomb_impl(p)
	mode.on_player_leave(self, p)
	state.players.erase(id)
	if not p.isBot:
		fill_bots()


# ---------------- 回合流程 ----------------

func begin_buy_phase() -> void:
	if not mode.uses_buy_phase:
		return
	state.roundNum += 1
	mode.start_round(self)
	state.phase = "buy"
	state.buyUntil = state.time + mode.buy_time
	state.roundEndAt = state.buyUntil
	broadcast_msg({"type": "buy_phase", "until": state.buyUntil, "round": state.roundNum})


func _begin_round() -> void:
	state.roundNum += 1
	state.phase = "live"
	state.roundEndAt = 0.0
	state.buyUntil = 0.0
	mode.start_round(self)
	broadcast_msg({"type": "round_start", "mode": state.mode, "round": state.roundNum})


func _next_round() -> void:
	if mode.uses_buy_phase:
		begin_buy_phase()
	else:
		_begin_round()


func _on_core_end(winner: String, reason: String) -> void:
	mode.award_round(self, winner, reason)


## 模式调用：结束本回合
func finish_round(winner: String, reason: String, final: bool, delay: float) -> void:
	if state.phase == "over":
		return
	state.phase = "over"
	state.roundEndAt = state.time + delay
	if final:
		state.matchEndAt = state.time + delay + 3.0
		broadcast_msg({
			"type": "match_end", "winner": winner, "reason": reason,
			"scores": state.matchScore.duplicate(), "round": state.roundNum,
		})
	broadcast_msg({
		"type": "round_end", "winner": winner, "reason": reason,
		"scores": state.matchScore.duplicate(), "round": state.roundNum,
		"matchWinner": winner if final else null,
	})


func _new_match() -> void:
	state.matchScore = _blank_score()
	state.matchEndAt = 0.0
	state.roundEndAt = 0.0
	state.phase = "live"
	reset_economy()
	next_map()
	if mode.uses_buy_phase:
		begin_buy_phase()
	else:
		_begin_round()


func reset_economy() -> void:
	for p in state.players.values():
		p.money = Economy.START_MONEY


# ---------------- 生成 ----------------

func spawn_all() -> void:
	for p in state.players.values():
		var key: String = "ZOMBIE" if p.isZombie else ("CT" if int(p.team) == Constants.TEAM_CT else ("T" if int(p.team) == Constants.TEAM_T else "HUMAN"))
		var spot: Dictionary = _pick_spawn_impl(key)
		Player.spawn_player(state, p, p.team, spot, {})


func _pick_spawn_impl(team_key: String) -> Dictionary:
	var spawns: Dictionary = state.map.get("spawns", {})
	var spots: Array = spawns.get(team_key, spawns.get("HUMAN", [{"x": 0.0, "z": 0.0, "yaw": 0.0}]))
	if spots.is_empty():
		return {"x": 0.0, "y": 0.05, "z": 0.0, "yaw": 0.0}
	var order: Array = []
	for i in spots.size():
		order.append(i)
	order.shuffle()
	for i in order:
		var s: Dictionary = spots[i]
		var taken: bool = false
		for q in state.players.values():
			if q.alive:
				var dx: float = q.pos.x - float(s.x)
				var dz: float = q.pos.z - float(s.z)
				if sqrt(dx * dx + dz * dz) < 2.2:
					taken = true
					break
		if not taken:
			return s
	return spots[order[0]]


func reset_bomb_at_t_spawn() -> void:
	var spawns: Dictionary = state.map.get("spawns", {})
	var t_spawns: Array = spawns.get("T", [{"x": 0.0, "z": 0.0, "yaw": 0.0}])
	if t_spawns.is_empty():
		state.bomb = blank_bomb()
		return
	var s: Dictionary = t_spawns[0]
	var yaw: float = float(s.get("yaw", 0.0))
	state.bomb = {
		"planted": false, "carried": false, "carrierId": null,
		"pos": Vector3(float(s.x) - sin(yaw) * 3.2, float(s.get("y", 0.0)) + 0.06, float(s.z) - cos(yaw) * 3.2),
		"timeLeft": 0.0,
	}


func drop_bomb_impl(p: Dictionary) -> void:
	if state.mode != Constants.MODE_DEFUSAL or not bool(p.get("bombCarrier", false)):
		return
	p.bombCarrier = false
	if state.bomb == null:
		return
	state.bomb.carried = false
	state.bomb.carrierId = null
	state.bomb.pos = Vector3(p.pos.x, p.pos.y + 0.2, p.pos.z)
	broadcast_msg({"type": "bomb_dropped", "pos": state.bomb.pos})


func infect(p: Dictionary) -> void:
	p.isZombie = true
	p.team = Constants.TEAM_ZOMBIE
	p.zombieSince = state.time
	p.hp = float(PHYS.ZOMBIE_HP)
	p.maxHp = float(PHYS.ZOMBIE_HP)
	p.armor = 0
	p.speedOverride = null
	p.isCrystalHunter = false
	Player.give_loadout(p, state.mode, Constants.TEAM_ZOMBIE)
	if state.core != null:
		state.core.infect(p.id)
	broadcast_msg({"type": "infected", "id": p.id})


func refill_ammo(p: Dictionary) -> void:
	for w in p.weapons.values():
		if w == null:
			continue
		w.reset(0.0)


# ---------------- 阵营判定 ----------------

func is_hostile(a: Dictionary, b: Dictionary) -> bool:
	if a == b:
		return false
	if not mode.team_based:
		return true
	if mode.zombie_infection:
		return bool(a.isZombie) != bool(b.isZombie)
	return int(a.team) != int(b.team)


# ---------------- 主循环 ----------------

func tick() -> void:
	var dt: float = TICK_MS / 1000.0
	state.time += dt
	state.snapAcc += TICK_MS

	if state.matchEndAt > 0.0 and state.time >= state.matchEndAt:
		_new_match()
		return
	if state.roundEndAt > 0.0 and state.time >= state.roundEndAt:
		if state.phase == "buy":
			_begin_round()
		elif state.phase == "over":
			if state.matchEndAt <= 0.0:
				_next_round()
		return

	for p in state.players.values():
		if not p.isBot:
			p.yaw = float(p.input.yaw)
			p.pitch = float(p.input.pitch)
		if state.phase == "buy":
			# 购买阶段：冻结移动与开火，仅允许转视角与购买
			p.vel = Vector3.ZERO
			p.input.fire = false
			continue
		if not p.alive:
			if mode.respawn and not state.noRespawn and float(p.respawnAt) > 0.0 and state.time >= float(p.respawnAt):
				_respawn(p)
			continue
		# 加速技能到期
		if float(p.boostUntil) > 0.0 and state.time >= float(p.boostUntil):
			p.boostUntil = 0.0
			p.speedOverride = null
		# 电击定身
		if float(p.get("stunUntil", 0.0)) > state.time:
			p.input.mv = [0, 0, 0, 0]
			p.input.fire = false
			p.input.j = false
		if p.isBot:
			BotBrain.tick_bot(state, p)
			p.inputAt = state.time
		_process_input(p)
		SimPhysics.move_player(p, p.input, dt, state.map.colliders)
		if p.history != null:
			p.history.push(state.time, {
				"pos": p.pos, "yaw": p.yaw, "pitch": p.pitch,
				"crouch": p.crouch, "alive": true,
			})
			p.history.prune(state.time)
		_process_weapons(p)
		_process_use(p, dt)
		if p.isZombie:
			if state.time - float(p.lastHitAt) > 3.0:
				p.hp = minf(float(p.maxHp), float(p.hp) + PHYS.ZOMBIE_REGEN * dt)
			if int(p.slowTicks) > 0:
				p.slowTicks -= 1
		# 火焰伤害
		if state.time - float(p.lastHitAt) > 6.0 and float(p.hp) < float(p.maxHp) * 0.35 and not p.isBot:
			pass

	_update_projectiles(dt)
	_update_smokes(dt)
	_update_fires(dt)
	mode.on_tick(self, dt)
	_update_boxes()

	if state.phase == "buy" and mode.uses_buy_phase:
		for bot in state.players.values():
			if bot.isBot and not bool(bot.boughtPhase):
				bot.boughtPhase = true
				auto_buy(bot)

	if state.snapAcc >= SNAPSHOT_INTERVAL_MS:
		state.snapAcc = 0.0
		if not _local_only:
			broadcast_msg(snapshot())
	if events.has("tick"):
		events.tick.call({"time": state.time})


func _respawn(p: Dictionary) -> void:
	var key: String = "ZOMBIE" if p.isZombie else ("CT" if int(p.team) == Constants.TEAM_CT else ("T" if int(p.team) == Constants.TEAM_T else "HUMAN"))
	var spot: Dictionary = _pick_spawn_impl(key)
	Player.spawn_player(state, p, p.team, spot)
	mode.on_player_spawn(self, p)


func _process_input(p: Dictionary) -> void:
	var inp: Dictionary = p.input
	if not p.isBot:
		p.yaw = float(inp.yaw)
		p.pitch = float(inp.pitch)
	p.crouch = bool(inp.c)
	var slot_before: int = int(p.activeSlot)
	var edge: Dictionary = p.edge
	if typeof(edge.sw) == TYPE_INT and int(edge.sw) >= 0:
		if p.weapons.has(int(edge.sw)):
			p.activeSlot = int(edge.sw)
			p.useProgress = 0.0
		else:
			var cur: Variant = p.weapons.get(int(p.activeSlot), null)
			p.switchSeq = int(p.switchSeq) + 1
			send_to.call(p.id, {"type": "switch", "w": str(cur.def.id) if cur != null else "", "slot": p.activeSlot, "seq": p.switchSeq})
	if int(edge.swd) != 0:
		var slots: Array = p.weapons.keys()
		slots.sort()
		if slots.size() > 1:
			var idx: int = slots.find(int(p.activeSlot))
			var dir_idx: int = 1 if int(edge.swd) > 0 else (slots.size() - 1)
			p.activeSlot = int(slots[(idx + dir_idx) % slots.size()])
			p.useProgress = 0.0
	edge.sw = -1
	edge.swd = 0
	if bool(edge.j):
		inp.j = true
		edge.j = false
	if bool(edge.r):
		inp.r = true
		edge.r = false
	if bool(edge.skill):
		edge.skill = false
		if p.isZombie:
			trigger_zombie_boost(p)
		else:
			trigger_human_boost(p)
	if slot_before != int(p.activeSlot):
		p.switchSeq = int(p.switchSeq) + 1
		var w_now: Variant = p.weapons.get(int(p.activeSlot), null)
		send_to.call(p.id, {"type": "switch", "w": str(w_now.def.id) if w_now != null else "", "slot": p.activeSlot, "seq": p.switchSeq})
	var def: Dictionary = {}
	var w_active: Variant = p.weapons.get(int(p.activeSlot), null)
	if w_active != null:
		def = w_active.def
	var ads: bool = bool(inp.ads) and not p.isZombie and not def.is_empty() and not def.get("melee", false) and not def.has("projectile")
	p.weaponMoveMult = float(def.moveMult) * (0.78 if ads else 1.0) if not def.is_empty() else 1.0
	if str(def.get("projectile", "")) != "":
		p.weaponMoveMult = minf(float(p.weaponMoveMult), 0.9)


func _process_weapons(p: Dictionary) -> void:
	var w: Variant = p.weapons.get(int(p.activeSlot), null)
	if w == null:
		return
	var def: Dictionary = w.def
	var held: bool = bool(p.input.fire)
	var fire_now: bool = WeaponData.should_fire(def, held, bool(p.wasFiring))
	p.wasFiring = held
	var now: float = state.time
	var reload_event: Dictionary = w.update(now)
	if not reload_event.is_empty():
		send_to.call(p.id, {"type": "reloaded", "ammo": reload_event.ammo, "reserve": reload_event.reserve})
	if w.state == "empty":
		if w.start_reload(now).ok:
			send_to.call(p.id, {"type": "reloading", "weapon": def.id})
	elif bool(p.input.r) and w.state == "ready" and float(w.ammo) < float(def.magSize):
		if w.start_reload(now).ok:
			send_to.call(p.id, {"type": "reloading", "weapon": def.id})
	# 蓄力 / 预热
	if float(def.get("charge", 0.0)) > 0.0:
		if held:
			w.charge = minf(1.0, float(w.charge) + (1.0 / float(def.charge)) * (TICK_MS / 1000.0))
		else:
			w.charge = maxf(0.0, float(w.charge) - 2.0 * (TICK_MS / 1000.0))
		if w.charge < 1.0:
			return
	if float(def.get("spinUp", 0.0)) > 0.0:
		if held:
			w.spin_up = minf(1.0, float(w.spin_up) + (1.0 / float(def.spinUp)) * (TICK_MS / 1000.0))
		else:
			w.spin_up = maxf(0.0, float(w.spin_up) - 3.0 * (TICK_MS / 1000.0))
		if w.spin_up < 1.0:
			return
	if not fire_now or (p.isZombie and not def.get("melee", false)):
		return
	if def.get("melee", false):
		if w.can_fire(now):
			w.fire(now)
			Hitscan.perform_shot(state, p, def, {"rewindTime": p.inputAt if float(p.inputAt) > 0 else state.time})
			broadcast_msg({"type": "shot_visual", "id": p.id, "weapon": def.id, "melee": true,
				"pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch})
			send_to.call(p.id, {"type": "shot", "weapon": def.id, "ammo": w.ammo, "reserve": w.reserve})
		return
	if str(def.get("projectile", "")) != "":
		if w.can_fire(now) and int(p.grenadeCount) > 0:
			w.fire(now)
			p.grenadeCount = int(p.grenadeCount) - 1
			Hitscan.perform_shot(state, p, def, {})
			broadcast_msg({"type": "throw_visual", "id": p.id,
				"pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch})
			send_to.call(p.id, {"type": "throw_ack", "grenades": p.grenadeCount})
		return
	if w.can_fire(now):
		w.fire(now)
		var res: Array = Hitscan.perform_shot(state, p, def, {"rewindTime": p.inputAt if float(p.inputAt) > 0 else state.time})
		broadcast_msg({"type": "shot_visual", "id": p.id, "weapon": def.id,
			"pos": Vector3(p.pos.x, p.pos.y, p.pos.z), "yaw": p.yaw, "pitch": p.pitch, "res": _res_brief(res)})
		send_to.call(p.id, {"type": "shot", "weapon": def.id, "ammo": w.ammo, "reserve": w.reserve})
		# 电击枪
		if float(def.get("stun", 0.0)) > 0.0:
			for r in res:
				var v: Dictionary = r.get("victim", {})
				if not v.is_empty():
					v.stunUntil = state.time + float(def.stun)
		if float(def.get("charge", 0.0)) > 0.0:
			w.charge = 0.0
		if int(w.ammo) == 0:
			w.state = "empty"


func _res_brief(res: Array) -> Array:
	var out: Array = []
	for r in res:
		out.append({"id": str(r.get("victim", {}).get("id", "")), "hs": bool(r.get("headshot", false)), "d": int(r.get("damage", 0))})
	return out


func _process_use(p: Dictionary, dt: float) -> void:
	if not bool(p.input.u):
		p.useProgress = 0.0
		p.useTarget = null
		return
	if mode.process_use(self, p, dt):
		return
	if p.isZombie:
		p.useProgress = 0.0
		p.useTarget = null
		return
	# 通用：弹药箱 / 回血箱
	for box in state.ammoBoxes:
		if bool(box.available) and _dist2d(p.pos, box.pos) < 2.0:
			var refilled: bool = false
			for w in p.weapons.values():
				if w != null and is_finite(float(w.def.reserve)) and float(w.reserve) < float(w.def.reserve):
					w.reserve = float(w.def.reserve)
					refilled = true
			if refilled:
				box.available = false
				box.respawnAt = state.time + float(box.respawn)
				send_to.call(p.id, {"type": "ammo_refill"})
				broadcast_msg({"type": "ammo_box", "id": p.id, "pos": box.pos})
			break
	if float(p.hp) < float(p.maxHp):
		for hb in state.healthBoxes:
			if bool(hb.available) and _dist2d(p.pos, hb.pos) < 2.0:
				var before: float = float(p.hp)
				p.hp = minf(float(p.maxHp), float(p.hp) + Constants.HEALTH_BOX_HEAL)
				hb.available = false
				hb.respawnAt = state.time + float(hb.respawn)
				send_to.call(p.id, {"type": "health_refill", "hp": int(ceil(float(p.hp)))})
				broadcast_msg({"type": "health_box", "id": p.id, "pos": hb.pos, "amount": int(round(float(p.hp) - before))})
				break


func push_use_progress(p: Dictionary, action: String, ratio: float) -> void:
	if state.time - float(p.get("lastUseProgressAt", 0.0)) < 0.1:
		return
	p.lastUseProgressAt = state.time
	send_to.call(p.id, {"type": "use_progress", "action": action, "progress": clampf(ratio, 0.0, 1.0)})


# ---------------- 投掷物 ----------------

func _update_projectiles(dt: float) -> void:
	var dead: Array = []
	for proj in state.projectiles:
		var kind: String = str(proj.get("kind", "grenade"))
		if kind == "bolt":
			_step_bolt(proj, dt, dead)
			continue
		proj.fuse = float(proj.fuse) - dt
		proj.vel.y += -9.8 * dt
		var next_pos := Vector3(proj.pos.x + proj.vel.x * dt, proj.pos.y + proj.vel.y * dt, proj.pos.z + proj.vel.z * dt)
		var bounced: bool = false
		for box in state.map.colliders:
			if _in_aabb(next_pos, box):
				var pen_x: float = minf(next_pos.x - box.min.x, box.max.x - next_pos.x)
				var pen_y: float = minf(next_pos.y - box.min.y, box.max.y - next_pos.y)
				var pen_z: float = minf(next_pos.z - box.min.z, box.max.z - next_pos.z)
				var mp: float = minf(pen_x, minf(pen_y, pen_z))
				if mp == pen_y:
					proj.vel.y *= -0.4
				elif mp == pen_x:
					proj.vel.x *= -0.4
				else:
					proj.vel.z *= -0.4
				proj.bounces = int(proj.bounces) + 1
				bounced = true
				break
		if bounced:
			proj.pos = Vector3((proj.pos.x + next_pos.x) * 0.5, (proj.pos.y + next_pos.y) * 0.5, (proj.pos.z + next_pos.z) * 0.5)
			if int(proj.bounces) >= 3 or Vector3(proj.vel).length() < 1.2:
				proj.vel = Vector3.ZERO
		else:
			proj.pos = next_pos
		if proj.pos.y < 0.1:
			proj.pos.y = 0.1
			proj.vel.y *= -0.35
			var fric: float = 6.0
			proj.vel.x *= maxf(0.0, 1.0 - fric * dt)
			proj.vel.z *= maxf(0.0, 1.0 - fric * dt)
			if Vector2(proj.vel.x, proj.vel.z).length() < 0.05:
				proj.vel.x = 0.0
				proj.vel.z = 0.0
		if float(proj.fuse) <= 0.0:
			_detonate(proj)
			dead.append(proj)
	for p in dead:
		state.projectiles.erase(p)


func _step_bolt(proj: Dictionary, dt: float, dead: Array) -> void:
	var step: Vector3 = proj.vel * dt
	proj.vel.y += -3.2 * dt
	var nxt: Vector3 = proj.pos + step
	var dist: float = step.length()
	if dist > 0.001:
		var dir: Vector3 = step.normalized()
		var tw: float = Hitscan.trace_world(state.map, proj.pos, dir, dist)
		if tw < dist:
			# 命中玩家？先看是否有人挡在墙前
			var sh: Dictionary = state.players.get(proj.owner, {})
			var hit: Dictionary = Hitscan.raycast_players(state, sh, proj.pos, dir, tw, null)
			if not hit.is_empty():
				var def: Dictionary = WeaponDB.get_def(str(proj.get("weapon", "")))
				var dmg: int = WeaponData.compute_shot_damage(def, bool(hit.headshot), float(hit.t)) if not def.is_empty() else int(proj.damage)
				Player.damage_player(state, sh, hit.player, float(dmg), {"weapon": str(proj.get("weapon", "crossbow")), "headshot": bool(hit.headshot), "dist": float(hit.t)})
			dead.append(proj)
			broadcast_msg({"type": "bolt_land", "pos": proj.pos})
			return
	proj.pos = nxt
	if float(proj.fuse) <= 0.0 or proj.pos.y < -5.0:
		dead.append(proj)


func _detonate(proj: Dictionary) -> void:
	var kind: String = str(proj.get("kind", "grenade"))
	var pos: Vector3 = proj.pos
	match kind:
		"smoke":
			state.smokes.append({"pos": pos, "radius": float(proj.radius), "until": state.time + 18.0})
			broadcast_msg({"type": "smoke_pop", "pos": pos, "radius": float(proj.radius)})
		"fire":
			state.fires.append({"pos": pos, "radius": float(proj.radius), "until": state.time + 8.0,
				"owner": str(proj.owner), "next": 0.0})
			broadcast_msg({"type": "fire_pop", "pos": pos, "radius": float(proj.radius)})
		"flash":
			_apply_flash(pos, float(proj.radius), str(proj.owner))
			broadcast_msg({"type": "flash_pop", "pos": pos})
		"decoy":
			state.fires.append({"pos": pos, "radius": 0.0, "until": state.time + 15.0, "owner": str(proj.owner), "next": 0.0, "decoy": true})
			broadcast_msg({"type": "decoy_pop", "pos": pos})
		_:
			broadcast_msg({"type": "explosion", "pos": pos, "owner": proj.owner})
			_explode_damage(pos, float(proj.radius), float(proj.damage), str(proj.get("weapon", "thunder")), str(proj.owner))


func _explode_damage(pos: Vector3, radius: float, base_dmg: float, weapon: String, owner_id: String) -> void:
	var owner: Variant = state.players.get(owner_id, null)
	for p in state.players.values():
		if not p.alive:
			continue
		var dx: float = p.pos.x - pos.x
		var dy: float = p.pos.y + 0.9 - pos.y
		var dz: float = p.pos.z - pos.z
		var d: float = sqrt(dx * dx + dy * dy + dz * dz)
		if d > radius:
			continue
		# 墙体遮挡：爆炸不穿墙（射线检测）
		var dir: Vector3 = Vector3(dx, dy, dz).normalized() if d > 0.01 else Vector3.UP
		var tw: float = Hitscan.trace_world(state.map, pos, dir, d)
		if tw < d - 0.4:
			continue
		var t: float = clampf(d / radius, 0.0, 1.0)
		var dmg: float = base_dmg * (1.0 - t * 0.78)
		Player.damage_player(state, owner, p, roundf(dmg), {"weapon": weapon, "dist": d, "armor_pen": 0.4})


func _apply_flash(pos: Vector3, radius: float, owner_id: String) -> void:
	for p in state.players.values():
		if not p.alive:
			continue
		var d: float = p.pos.distance_to(pos)
		if d > radius:
			continue
		# 视线方向：背对爆炸时致盲时间大幅缩短
		var eye := Vector3(p.pos.x, p.pos.y + 1.55, p.pos.z)
		var to_bomb: Vector3 = (pos - eye).normalized()
		var fwd: Vector3 = MathUtil.direction_from_angles(float(p.yaw), float(p.pitch))
		var dot: float = fwd.dot(to_bomb)
		var facing: float = clampf((dot + 0.2) / 1.2, 0.0, 1.0)
		var dist_f: float = 1.0 - clampf(d / radius, 0.0, 1.0)
		var dur: float = 3.6 * facing * dist_f
		if dur < 0.35:
			continue
		p.flashUntil = maxf(float(p.get("flashUntil", 0.0)), state.time + dur)
		if not p.isBot:
			send_to.call(p.id, {"type": "flashed", "dur": dur, "from": owner_id})


func _update_smokes(_dt: float) -> void:
	var dead: Array = []
	for s in state.smokes:
		if state.time >= float(s.until):
			dead.append(s)
	for s in dead:
		state.smokes.erase(s)
		broadcast_msg({"type": "smoke_gone", "pos": s.pos})


func _update_fires(dt: float) -> void:
	var dead: Array = []
	for f in state.fires:
		if state.time >= float(f.until):
			dead.append(f)
			continue
		if f.get("decoy", false):
			f.next = float(f.next) - dt
			if float(f.next) <= 0.0:
				f.next = 1.4
				if not _local_only:
					broadcast_msg({"type": "decoy_sound", "pos": f.pos})
			continue
		f.next = float(f.next) - dt
		if float(f.next) <= 0.0:
			f.next = 1.0
			var owner: Variant = state.players.get(str(f.owner), null)
			for p in state.players.values():
				if not p.alive:
					continue
				if _dist2d(p.pos, f.pos) < float(f.radius):
					Player.damage_player(state, owner, p, 22.0, {"weapon": "incendiary", "armor_pen": 0.2})
	for f in dead:
		state.fires.erase(f)


func _update_boxes() -> void:
	for b in state.ammoBoxes:
		if not bool(b.available) and state.time >= float(b.respawnAt):
			b.available = true
	for b in state.healthBoxes:
		if not bool(b.available) and state.time >= float(b.respawnAt):
			b.available = true


# ---------------- 技能 ----------------

func trigger_zombie_boost(p: Dictionary) -> bool:
	if not p.isZombie or not p.alive:
		return false
	if state.time < float(p.skillReadyAt):
		return false
	p.speedOverride = Constants.ZOMBIE_BOOST_SPEED
	p.boostUntil = state.time + Constants.ZOMBIE_BOOST_DURATION
	p.skillReadyAt = state.time + Constants.ZOMBIE_BOOST_COOLDOWN
	broadcast_msg({"type": "zombie_boost_visual", "id": p.id})
	return true


func trigger_human_boost(p: Dictionary) -> bool:
	if p.isZombie or not p.alive:
		return false
	if state.time < float(p.skillReadyAt):
		return false
	p.speedOverride = Constants.HUMAN_BOOST_SPEED
	p.boostUntil = state.time + Constants.HUMAN_BOOST_DURATION
	p.skillReadyAt = state.time + Constants.HUMAN_BOOST_COOLDOWN
	broadcast_msg({"type": "zombie_boost_visual", "id": p.id})
	return true


func activate_finale() -> void:
	# 兼容旧接口：仅生化模式有效
	if mode is ModesClassic.Zombie:
		var humans: Array = []
		var zombies: Array = []
		for p in state.players.values():
			if p.alive and p.isZombie:
				zombies.append(p)
			elif p.alive:
				humans.append(p)
		state.finaleActive = true
		state.noRespawn = true
		mode._activate_finale(self, humans, zombies)


# ---------------- 击杀回调（由 Player 调用） ----------------

func on_player_killed(victim: Dictionary, killer: Variant, info: Dictionary) -> void:
	var handled: bool = mode.on_kill(self, victim, killer, info)
	if not handled:
		# 通用：按模式 respawn 设置复活时间
		if mode.respawn and not state.noRespawn:
			victim.respawnAt = state.time + mode.respawn_delay
		else:
			victim.respawnAt = 0.0
	# Bot 之间互杀后立即补位（保持节奏）
	_check_bots_after_kill()


func _check_bots_after_kill() -> void:
	if not mode.respawn:
		return
	var alive_bots: int = 0
	for p in state.players.values():
		if p.isBot and p.alive:
			alive_bots += 1
	if alive_bots == 0 and state.phase == "live" and state.mode in ["tdm", "ffa"]:
		for p in state.players.values():
			if p.isBot:
				_respawn(p)


# ---------------- 经济 ----------------

func handle_buy(p: Dictionary, item: String) -> Dictionary:
	if not mode.uses_money or state.phase != "buy":
		return {"ok": false, "reason": "phase"}
	if p.is_empty():
		return {"ok": false, "reason": "player"}
	var cost: int = Economy.cost_of(item, int(p.armor))
	if cost < 0:
		return {"ok": false, "reason": "item"}
	if cost == 0:
		return {"ok": false, "reason": "already"}
	if int(p.money) < cost:
		return {"ok": false, "reason": "money"}
	if item == "armor":
		p.boughtItems.append({"item": item, "cost": cost, "prevArmor": p.armor})
		p.armor = 100
	elif item == "grenade":
		if int(p.grenadeCount) >= 5:
			return {"ok": false, "reason": "max"}
		p.grenadeCount = int(p.grenadeCount) + 1
		p.boughtItems.append({"item": item, "cost": cost})
	else:
		if not state.weapons.has(item):
			return {"ok": false, "reason": "item"}
		var def: Dictionary = state.weapons[item]
		var prev: Variant = p.weapons.get(int(def.slot), null)
		var runtime = WeaponData.WeaponRuntime.new(def)
		p.weapons[int(def.slot)] = runtime
		p.boughtItems.append({"item": item, "cost": cost, "slot": int(def.slot), "prev": prev, "runtime": runtime})
		if int(def.slot) == 2:
			p.activeSlot = 2
	p.money = int(p.money) - cost
	send_to.call(p.id, {"type": "buy_ok", "item": item, "money": p.money})
	return {"ok": true}


func handle_refund(p: Dictionary, item: String) -> Dictionary:
	if not mode.uses_money or state.phase != "buy":
		return {"ok": false, "reason": "phase"}
	var idx: int = -1
	for i in range(p.boughtItems.size()):
		if str(p.boughtItems[i].item) == item:
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": "not_bought"}
	var rec: Dictionary = p.boughtItems[idx]
	if item == "armor":
		p.armor = rec.prevArmor
	elif item == "grenade":
		p.grenadeCount = maxi(0, int(p.grenadeCount) - 1)
	elif p.weapons.get(int(rec.slot), null) == rec.runtime:
		if rec.prev != null:
			p.weapons[int(rec.slot)] = rec.prev
		else:
			p.weapons.erase(int(rec.slot))
		if rec.prev == null and int(p.activeSlot) == int(rec.slot) and p.weapons.has(1):
			p.activeSlot = 1
	else:
		p.boughtItems.remove_at(idx)
		send_to.call(p.id, {"type": "refund_fail", "item": item, "reason": "replaced"})
		return {"ok": false, "reason": "replaced"}
	p.money = mini(Economy.MONEY_CAP, int(p.money) + int(rec.cost))
	p.boughtItems.remove_at(idx)
	send_to.call(p.id, {"type": "refund_ok", "item": item, "money": p.money})
	return {"ok": true}


func auto_buy(bot: Dictionary) -> Dictionary:
	if not bot.weapons.has(2):
		var wid: String = WeaponDB.pick_primary_for_budget(int(bot.money))
		if wid != "":
			return handle_buy(bot, wid)
	if int(bot.money) >= Economy.PRICES.armor and int(bot.armor) < 60:
		return handle_buy(bot, "armor")
	if int(bot.money) >= Economy.PRICES.grenade and int(bot.grenadeCount) < 2:
		return handle_buy(bot, "grenade")
	return {"ok": false}


func handle_zombie_select(p: Dictionary, item: String) -> Dictionary:
	if state.mode != Constants.MODE_ZOMBIE:
		return {"ok": false, "reason": "phase"}
	if p.is_empty() or p.isZombie:
		return {"ok": false, "reason": "player"}
	if not state.weapons.has(item):
		return {"ok": false, "reason": "item"}
	var def: Dictionary = state.weapons[item]
	if int(def.slot) != 2:
		return {"ok": false, "reason": "item"}
	p.weapons[2] = WeaponData.WeaponRuntime.new(def)
	p.selectedPrimary = def.id
	p.activeSlot = 2
	send_to.call(p.id, {"type": "buy_ok", "item": item, "money": p.money})
	send_to.call(p.id, {"type": "zselect_ok", "item": item, "money": p.money})
	return {"ok": true}


func next_map() -> void:
	state.rotationIdx = (int(state.rotationIdx) + 1) % state.rotation.size()
	state.mapId = str(state.rotation[int(state.rotationIdx)])
	state.map = MapData.get_map(state.mapId)
	state.ammoBoxes = _init_boxes(state.map.get("ammoBoxes", []))
	state.healthBoxes = _init_boxes(state.map.get("healthBoxes", []))
	for p in state.players.values():
		p.alive = false
		p.weapons.clear()
		p.activeSlot = 1
		p.grenadeCount = 0
		p.armor = 0
		p.bombCarrier = false
		p.boughtItems = []
		p.money = Economy.START_MONEY
		p.kills = 0
		p.deaths = 0
		p.score = 0
		p.input.fire = false
		p.edge.sw = -1
		p.edge.swd = 0
		if p.isBot and p.botBrain != null:
			BotBrain.reset_brain(p.botBrain)
	broadcast_msg({"type": "map_change", "map": state.mapId, "mapName": str(state.map.get("name", ""))})
	print("[Room] next map: %s" % state.mapId)


# ---------------- 生存模式 ----------------

func spawn_wave_bot(wave: int, hp_mult: float) -> Dictionary:
	if state.players.size() >= state.maxPlayers + 8:
		return {}
	var bot: Dictionary = spawn_bot("Infect-%d" % (state.nextBotId))
	bot.waveBot = true
	bot.isZombie = true
	bot.team = Constants.TEAM_ZOMBIE
	spawn_joiner(bot)
	bot.hp = float(PHYS.ZOMBIE_HP) * hp_mult
	bot.maxHp = bot.hp
	bot.money = 0
	if bot.botBrain != null:
		bot.botBrain.skill = clampf(0.5 + wave * 0.05, 0.4, 1.2)
	return bot


# ---------------- 辅助 ----------------

func _init_boxes(src: Array) -> Array:
	var out: Array = []
	for b in src:
		var copy: Dictionary = b.duplicate()
		copy.available = true
		copy.respawnAt = 0.0
		out.append(copy)
	return out


func _dist2d(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _in_aabb(p: Vector3, box: Dictionary) -> bool:
	return p.x > box.min.x and p.x < box.max.x and p.y > box.min.y and p.y < box.max.y and p.z > box.min.z and p.z < box.max.z


## 烟雾是否遮挡两点连线（Bot 视线 / 命中提示用）
static func smoke_blocked(smokes: Array, a: Vector3, b: Vector3) -> bool:
	if smokes.is_empty():
		return false
	var ab: Vector3 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 < 0.001:
		return false
	for s in smokes:
		var c: Vector3 = s.pos + Vector3(0, 1.2, 0)
		var t: float = clampf((c - a).dot(ab) / ab_len2, 0.0, 1.0)
		var closest: Vector3 = a + ab * t
		if closest.distance_to(c) < float(s.radius) * 0.92:
			return true
	return false


# ---------------- 快照 ----------------

func snapshot() -> Dictionary:
	var players: Array = []
	for p in state.players.values():
		var w: Variant = p.weapons.get(int(p.activeSlot), null)
		players.append({
			"i": p.id, "n": str(p.name).substr(0, 12), "t": p.team,
			"zb": 1 if p.isZombie else 0,
			"h": maxi(0, int(ceil(float(p.hp)))), "mx": maxi(1, int(ceil(float(p.maxHp)))),
			"a": maxi(0, int(ceil(float(p.armor)))),
			"ft": 1 if p.isCrystalHunter else (2 if p.isZombieKing else (3 if p.isZombieServant else 0)),
			"x": snappedf(p.pos.x, 0.01), "y": snappedf(p.pos.y, 0.01), "z": snappedf(p.pos.z, 0.01),
			"ya": snappedf(float(p.yaw), 0.001), "pi": snappedf(float(p.pitch), 0.001),
			"al": 1 if p.alive else 0, "cr": 1 if p.crouch else 0,
			"w": str(w.def.id) if w != null else "",
			"am": (-1 if (w != null and bool(w.def.get("melee", false))) else mini(int(w.ammo) if w != null else 0, 999)),
			"rs": (-1 if (w != null and bool(w.def.get("melee", false))) else mini(int(w.reserve) if w != null else 0, 9999)),
			"bc": 1 if p.bombCarrier else 0, "ws": int(p.switchSeq),
			"sc": int(p.score), "k": int(p.kills), "d": int(p.deaths), "g": int(p.grenadeCount),
			"mo": int(p.money), "bi": _bought_ids(p.boughtItems),
			"skillCd": maxi(0, int(ceil(float(p.skillReadyAt) - state.time))),
			"bo": 1 if (float(p.boostUntil) > 0.0 and state.time < float(p.boostUntil)) else 0,
			"lv": int(p.get("weaponLevel", 0)), "wv": int(p.get("wave", 0)),
			"st": 1 if float(p.get("stunUntil", 0.0)) > state.time else 0,
			"fl": snappedf(maxf(0.0, float(p.get("flashUntil", 0.0)) - state.time), 0.05),
			"pg": int(p.get("ping", 0)), "rm": 1 if p.isRemote else 0,
		})
	var r := {
		"st": state.core.state if state.core != null else state.globalState,
		"rn": int(state.roundNum),
		"tl": maxi(0, int(ceil(state.core.time_left if state.core != null else 0.0))),
		"bl": maxi(0, int(ceil(float(state.bomb.timeLeft)))),
		"sc": state.matchScore.duplicate(),
		"ph": state.phase,
		"bu": maxi(0, int(ceil(float(state.buyUntil) - state.time))),
		"extra": mode.snapshot_extra(self),
	}
	return {
		"type": "state", "t": snappedf(state.time, 0.01), "p": players,
		"b": _bomb_snapshot(), "proj": _proj_snapshot(), "r": r,
		"sm": state.smokes.size(), "fire": state.fires.size(),
	}


func _bought_ids(items: Array) -> Array:
	var out: Array = []
	for r in items:
		out.append(str(r.item))
	return out


func _bomb_snapshot() -> Variant:
	var b: Dictionary = state.bomb
	if bool(b.planted):
		return {"planted": 1, "carried": 0, "x": b.pos.x, "y": b.pos.y, "z": b.pos.z,
			"tl": maxi(0, int(ceil(state.core.bomb_time_left if state.core != null else 0.0)))}
	if bool(b.carried):
		return {"carried": 1, "carrierId": b.carrierId, "planted": 0}
	if b.pos != null:
		return {"planted": 0, "carried": 0, "x": b.pos.x, "y": b.pos.y, "z": b.pos.z}
	return null


func _proj_snapshot() -> Array:
	var out: Array = []
	for pr in state.projectiles:
		out.append({"id": pr.id, "x": snappedf(pr.pos.x, 0.01), "y": snappedf(pr.pos.y, 0.01), "z": snappedf(pr.pos.z, 0.01), "k": pr.kind})
	return out


# ---------------- 回合核心（通用计时器） ----------------

class RoundCore:
	extends RefCounted
	var state: String = "idle"
	var time_left: float = 0.0
	var bomb_planted: bool = false
	var bomb_time_left: float = 0.0
	var humans: Array = []
	var zombies: Array = []
	var _end_cb: Callable = Callable()

	func _init(rt: float = 0.0, _bt: float = 0.0) -> void:
		time_left = rt

	func bind(cb: Callable) -> void:
		_end_cb = cb

	func begin(rt: float) -> void:
		state = "live"
		time_left = rt
		bomb_planted = false
		bomb_time_left = 0.0

	func end_round(winner: String, reason: String) -> void:
		if state != "live":
			return
		state = "ended"
		if _end_cb.is_valid():
			_end_cb.call(winner, reason)

	func infect(pid: String) -> void:
		var i: int = humans.find(pid)
		if i != -1:
			humans.remove_at(i)
			zombies.append(pid)
