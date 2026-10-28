# 经典模式：拆弹（Defusal）与生化（Zombie）。
# 逻辑从 v1 的 room.gd 迁移而来，行为保持一致，但不再污染通用模拟层。
class_name ModesClassic
extends RefCounted


# =====================================================================
# 拆弹模式
# =====================================================================
class Defusal extends ModeBase:
	var plant_time: float = 3.0
	var defuse_time: float = 5.0
	var bomb_time: float = 40.0
	var round_win_score: int = 8

	func _init() -> void:
		id = "defusal"
		label = "拆弹模式"
		short = "DEFUSAL"
		desc = "T 方安放炸弹，CT 方阻止或拆除。经济与购买阶段完整。"
		team_based = true
		team_count = 2
		respawn = false
		round_time = 105.0
		uses_money = true
		uses_buy_phase = true
		buy_time = 10.0
		needs_sites = true
		columns = ["kills", "deaths", "adr", "money"]
		hud_objective = "安放 / 拆除炸弹"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, bomb_time)

	func start_round(room) -> void:
		var all: Array = room.state.players.values()
		# 1) 依据队伍偏好分边，再补平
		var survived: Dictionary = {}
		for p in all:
			survived[p.id] = p.alive
			p.isZombie = false
			if p.teamPref == "ct":
				p.team = Constants.TEAM_CT
			elif p.teamPref == "t":
				p.team = Constants.TEAM_T
			else:
				p.team = Constants.TEAM_NONE
		var ct: int = 0
		var t: int = 0
		for p in all:
			if p.team == Constants.TEAM_CT:
				ct += 1
			elif p.team == Constants.TEAM_T:
				t += 1
		for p in all:
			if p.team != Constants.TEAM_NONE:
				continue
			if ct <= t:
				p.team = Constants.TEAM_CT
				ct += 1
			else:
				p.team = Constants.TEAM_T
				t += 1
		# 2) 存活者保留装备并补弹
		for p in all:
			if survived[p.id]:
				room.refill_ammo(p)
		# 3) 出生
		for p in all:
			var key: String = "CT" if p.team == Constants.TEAM_CT else "T"
			var spot: Dictionary = room.pick_spawn.call(key)
			Player.spawn_player(room.state, p, p.team, spot, {"keepLoadout": survived[p.id]})
		# 4) 回放上回合购买（存活者继续持有）
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
		# 5) 炸弹落点
		room.reset_bomb_at_t_spawn()
		room.state.core.begin(round_time)

	func on_tick(room, dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		if core.bomb_planted:
			core.bomb_time_left -= dt
			room.state.bomb.timeLeft = maxf(0.0, core.bomb_time_left)
			if core.bomb_time_left <= 0.0:
				core.bomb_planted = false
				room.state.bomb = room.blank_bomb()
				core.end_round("T", "bomb_exploded")
			return
		core.time_left -= dt
		if core.time_left <= 0.0:
			core.end_round("CT", "timeout")
			return
		# 全灭判定
		var ct: int = alive_count(room, Constants.TEAM_CT)
		var t: int = alive_count(room, Constants.TEAM_T)
		if t == 0 and ct > 0:
			core.end_round("CT", "t_eliminated")
		elif ct == 0 and t > 0:
			core.end_round("T", "ct_eliminated")

	func process_use(room, p: Dictionary, dt: float) -> bool:
		var core = room.state.core
		if core == null or core.state != "live":
			return false
		var b: Dictionary = room.state.bomb
		# T 拾取
		if p.team == Constants.TEAM_T and not p.bombCarrier and not b.carried and not b.planted and b.pos != null:
			if _dist2(p.pos, b.pos) < 2.4:
				p.bombCarrier = true
				b.carried = true
				b.carrierId = p.id
				b.pos = null
				room.send_to.call(p.id, {"type": "bomb_pickup"})
				p.useProgress = 0.0
				p.useTarget = null
				return true
		# T 安放
		if p.team == Constants.TEAM_T and p.bombCarrier and not core.bomb_planted:
			var site: Variant = null
			for s in room.state.map.get("sites", []):
				if _dist2(p.pos, s.pos) < float(s.get("radius", 4.0)):
					site = s
					break
			if site != null:
				p.useTarget = "plant_%s" % str(site.id)
				p.useProgress += dt
				if p.useProgress >= plant_time:
					core.bomb_planted = true
					core.bomb_time_left = bomb_time
					b.planted = true
					b.carried = false
					b.carrierId = null
					b.pos = Vector3(p.pos.x, p.pos.y + 0.05, p.pos.z)
					p.bombCarrier = false
					p.money = mini(Economy.MONEY_CAP, p.money + Economy.PLANT_REWARD)
					p.useProgress = 0.0
					room.broadcast_msg({"type": "bomb_planted", "pos": b.pos, "site": str(site.id)})
				else:
					room.push_use_progress(p, "plant", p.useProgress / plant_time)
			else:
				p.useProgress = 0.0
			return true
		# CT 拆弹
		if p.team == Constants.TEAM_CT and core.bomb_planted and b.pos != null:
			if _dist2(p.pos, b.pos) < 2.4:
				p.useTarget = "defuse"
				p.useProgress += dt
				if p.useProgress > 0.0 and room.state.time - float(p.get("lastDefuseBeepAt", -99.0)) >= 0.35:
					p.lastDefuseBeepAt = room.state.time
					room.broadcast_msg({"type": "defuse_beep", "pos": Vector3(p.pos.x, p.pos.y, p.pos.z)})
				if p.useProgress >= defuse_time:
					core.bomb_planted = false
					room.state.bomb = room.blank_bomb()
					p.money = mini(Economy.MONEY_CAP, p.money + Economy.DEFUSE_REWARD)
					p.useProgress = 0.0
					core.end_round("CT", "bomb_defused")
				else:
					room.push_use_progress(p, "defuse", p.useProgress / defuse_time)
			else:
				p.useProgress = 0.0
			return true
		return false

	func on_kill(room, victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
		# 携带者死亡 → 掉落炸弹
		room.drop_bomb_impl(victim)
		# 立即判全灭（避免等到下一 tick）
		var ct: int = alive_count(room, Constants.TEAM_CT)
		var t: int = alive_count(room, Constants.TEAM_T)
		var core = room.state.core
		if core != null and core.state == "live":
			if int(victim.team) == Constants.TEAM_T and t == 0 and ct > 0 and not core.bomb_planted:
				core.end_round("CT", "t_eliminated")
			elif int(victim.team) == Constants.TEAM_CT and ct == 0 and t > 0:
				core.end_round("T", "ct_eliminated")
		return false

	func award_round(room, winner: String, reason: String) -> void:
		room.state.matchScore[winner] = int(room.state.matchScore.get(winner, 0)) + 1
		var loser: String = "T" if winner == "CT" else "CT"
		var streak: int = int(room.state.lossStreak.get(loser, 0)) + 1
		room.state.lossStreak[loser] = streak
		room.state.lossStreak[winner] = 0
		for p in room.state.players.values():
			var won: bool = int(p.team) == (Constants.TEAM_CT if winner == "CT" else Constants.TEAM_T)
			var reward: int = Economy.WIN_REWARD if won else Economy.loss_reward(streak)
			p.money = mini(Economy.MONEY_CAP, p.money + reward)
		var final: bool = int(room.state.matchScore.get(winner, 0)) >= round_win_score
		room.finish_round(winner, reason, final, 10.0)

	func check_round_end(_room) -> Dictionary:
		return {"end": false}

	func extra_columns() -> Dictionary:
		return {"adr": "ADR", "money": "$"}

	static func _dist2(a: Vector3, b: Variant) -> float:
		if b == null or not (b is Vector3):
			return INF
		var dx: float = a.x - b.x
		var dz: float = a.z - b.z
		return sqrt(dx * dx + dz * dz)


# =====================================================================
# 生化模式
# =====================================================================
class Zombie extends ModeBase:
	const FINALE = Constants.FINALE
	var initial_zombies: int = 3

	func _init() -> void:
		id = "zombie"
		label = "生化模式"
		short = "ZOMBIE"
		desc = "人类抵御感染，末段进入「琉璃决战」。"
		team_based = true
		team_count = 2
		respawn = true
		respawn_delay = 3.5
		round_time = 300.0
		uses_money = false
		uses_buy_phase = false
		needs_sites = false
		zombie_infection = true
		columns = ["kills", "deaths", "infects", "score"]
		hud_objective = "活下去，或者感染所有人"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)

	func start_round(room) -> void:
		var all: Array = room.state.players.values()
		for p in all:
			p.isZombie = false
			p.team = Constants.TEAM_HUMAN
			if not p.zombieMoneyInit:
				p.money = Economy.ZOMBIE_START_MONEY
				p.zombieMoneyInit = true
			p.zombieSince = 0.0
		var zc: int = clampi(int(floor(all.size() * 0.2)), 1, mini(initial_zombies, maxi(1, all.size())))
		var pool: Array = all.duplicate()
		pool.shuffle()
		for i in zc:
			var p: Dictionary = pool[i]
			p.isZombie = true
			p.team = Constants.TEAM_ZOMBIE
		room.spawn_all()
		room.state.core.begin(round_time)
		var humans: Array = []
		var zombies: Array = []
		for p in all:
			if p.isZombie:
				zombies.append(p.id)
			else:
				humans.append(p.id)
		room.state.core.humans = humans
		room.state.core.zombies = zombies
		room.state.finaleActive = false

	func on_tick(room, _dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		var humans: Array = []
		var zombies: Array = []
		for p in room.state.players.values():
			if not p.alive:
				continue
			if p.isZombie:
				zombies.append(p)
			else:
				humans.append(p)
		if not room.state.finaleActive and core.time_left <= FINALE.DURATION:
			room.state.finaleActive = true
			room.state.noRespawn = true
			if not humans.is_empty() or not zombies.is_empty():
				_activate_finale(room, humans, zombies)
		if room.state.finaleActive:
			if zombies.is_empty() and humans.is_empty():
				core.end_round("DRAW", "mutual_annihilation")
			elif zombies.is_empty():
				core.end_round("HUMAN", "zombies_eliminated")
			elif humans.is_empty():
				core.end_round("ZOMBIE", "infected_all")
		else:
			if humans.is_empty():
				core.end_round("ZOMBIE", "infected_all")
			elif zombies.is_empty():
				# 最后一只僵尸被打死 → 随机感染一个人类，避免局面空转
				var pick: Dictionary = humans[randi() % humans.size()]
				room.infect(pick)

	func on_kill(room, victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
		if room.state.noRespawn:
			victim.respawnAt = 0.0
			return true
		if not victim.isZombie:
			room.infect(victim)
		else:
			victim.respawnAt = room.state.time + 4.0
		return true

	func award_round(room, winner: String, _reason: String) -> void:
		if winner == "DRAW":
			room.state.matchScore.HUMAN = int(room.state.matchScore.get("HUMAN", 0)) + 1
			room.state.matchScore.ZOMBIE = int(room.state.matchScore.get("ZOMBIE", 0)) + 1
		else:
			room.state.matchScore[winner] = int(room.state.matchScore.get(winner, 0)) + 1
		room.finish_round(winner, _reason, true, 8.0)

	func process_use(_room, _p: Dictionary, _dt: float) -> bool:
		return false

	func _activate_finale(room, humans: Array, zombies: Array) -> void:
		for h in humans:
			h.isCrystalHunter = true
			h.hp = float(FINALE.HUNTER_HP)
			h.maxHp = float(FINALE.HUNTER_HP)
			h.armor = FINALE.HUNTER_ARMOR
			h.damageMult = FINALE.HUNTER_DAMAGE
			room.refill_ammo(h)
		var king: Variant = null
		var servants: int = 0
		if not zombies.is_empty():
			zombies.sort_custom(func(a, b): return float(a.zombieSince) < float(b.zombieSince))
			king = zombies[0]
			king.isZombieKing = true
			king.hp = float(FINALE.KING_HP)
			king.maxHp = float(FINALE.KING_HP)
			king.armor = FINALE.KING_ARMOR
			king.damageMult = FINALE.KING_DAMAGE
			var rest: Array = zombies.slice(1)
			rest.shuffle()
			for i in mini(3, rest.size()):
				var s: Dictionary = rest[i]
				s.isZombieServant = true
				s.hp = float(FINALE.SERVANT_HP)
				s.maxHp = float(FINALE.SERVANT_HP)
				s.armor = FINALE.SERVANT_ARMOR
				s.damageMult = FINALE.SERVANT_DAMAGE
				servants += 1
			for z in zombies:
				if z.isZombieKing or z.isZombieServant:
					continue
				z.hp = ceil(z.maxHp * FINALE.ZOMBIE_HP_MULT)
				z.maxHp = z.hp
				z.damageMult = 1.0
		room.broadcast_msg({
			"type": "finale_start", "hunters": humans.size(),
			"king": king.name if king != null else "", "servants": servants,
		})
