# 扩展模式：团队死斗、自由混战、占点、夺旗、军备竞赛、生存波次。
# 全部基于 ModeBase，不修改 Room 的通用模拟代码。
class_name ModesExtra
extends RefCounted


# =====================================================================
# 团队死斗
# =====================================================================
class TDM extends ModeBase:
	func _init() -> void:
		id = "tdm"
		label = "团队死斗"
		short = "TDM"
		desc = "两支队伍，先达到击杀目标或时间结束时领先者获胜。"
		team_based = true
		team_count = 2
		respawn = true
		respawn_delay = 4.0
		round_time = 480.0
		score_limit = 100
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "score"]
		hud_objective = "先达到 100 击杀"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)

	func start_round(room) -> void:
		var all: Array = room.state.players.values()
		room.state.matchScore = {"CT": 0, "T": 0}
		var ct: int = 0
		var t: int = 0
		for p in all:
			p.isZombie = false
			if p.teamPref == "ct":
				p.team = Constants.TEAM_CT
			elif p.teamPref == "t":
				p.team = Constants.TEAM_T
			else:
				p.team = Constants.TEAM_NONE
			if p.team == Constants.TEAM_CT:
				ct += 1
			elif p.team == Constants.TEAM_T:
				t += 1
		for p in all:
			if p.team == Constants.TEAM_NONE:
				if ct <= t:
					p.team = Constants.TEAM_CT
					ct += 1
				else:
					p.team = Constants.TEAM_T
					t += 1
			p.kills = 0
			p.deaths = 0
			p.score = 0
		room.spawn_all()
		room.state.core.begin(round_time)

	func on_kill(room, victim: Dictionary, killer: Variant, _info: Dictionary) -> bool:
		if killer != null and killer != victim:
			var key: String = "CT" if int(killer.team) == Constants.TEAM_CT else "T"
			room.state.matchScore[key] = int(room.state.matchScore.get(key, 0)) + 1
			killer.score += 10
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func on_tick(room, _dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= _dt
		var ct: int = int(room.state.matchScore.get("CT", 0))
		var t: int = int(room.state.matchScore.get("T", 0))
		if ct >= score_limit or t >= score_limit:
			core.end_round("CT" if ct > t else "T", "score_limit")
		elif core.time_left <= 0.0:
			if ct == t:
				core.end_round("DRAW", "timeout")
			else:
				core.end_round("CT" if ct > t else "T", "timeout")

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)


# =====================================================================
# 自由混战
# =====================================================================
class FFA extends ModeBase:
	func _init() -> void:
		id = "ffa"
		label = "自由混战"
		short = "FFA"
		desc = "人人都是敌人，个人击杀数决定一切。"
		team_based = false
		friendly_fire = true
		respawn = true
		respawn_delay = 3.0
		round_time = 480.0
		score_limit = 30
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "score"]
		hud_objective = "先拿到 30 击杀"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)

	func start_round(room) -> void:
		var all: Array = room.state.players.values()
		for p in all:
			p.team = Constants.TEAM_NONE
			p.isZombie = false
			p.kills = 0
			p.deaths = 0
			p.score = 0
		room.spawn_all()
		room.state.core.begin(round_time)

	func on_kill(room, victim: Dictionary, killer: Variant, _info: Dictionary) -> bool:
		if killer != null and killer != victim:
			killer.score += 10
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func on_tick(room, _dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= _dt
		var best: Dictionary = {}
		for p in room.state.players.values():
			if best.is_empty() or int(p.kills) > int(best.kills):
				best = p
		if not best.is_empty() and int(best.kills) >= score_limit:
			core.end_round(str(best.team), "score_limit")
		elif core.time_left <= 0.0:
			core.end_round(str(best.get("team", "DRAW")), "timeout")

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)


# =====================================================================
# 占点（KOTH）
# =====================================================================
class KOTH extends ModeBase:
	var hill_pos: Vector3 = Vector3.ZERO
	var hill_radius: float = 5.0
	var contest_seconds: float = 0.0
	var owner_team: int = Constants.TEAM_NONE
	var tick_rate: float = 1.0   # 每秒得分

	func _init() -> void:
		id = "koth"
		label = "占点模式"
		short = "KOTH"
		desc = "控制中央据点累积分数，先到 200 分获胜。"
		team_based = true
		team_count = 2
		respawn = true
		respawn_delay = 4.0
		round_time = 420.0
		score_limit = 200
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "objective"]
		hud_objective = "占领并守住据点"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)
		hill_pos = _find_hill(room)

	func _find_hill(room) -> Vector3:
		var m: Dictionary = room.state.map
		# 优先地图显式声明
		if m.has("hill"):
			var h: Dictionary = m.hill
			return Vector3(float(h.x), float(h.get("y", 0.0)), float(h.z))
		# 否则取 A 点
		var sites: Array = m.get("sites", [])
		if not sites.is_empty():
			return sites[0].pos
		# 再退化为导航点重心
		var nav: Array = m.get("nav", [])
		if not nav.is_empty():
			var acc := Vector3.ZERO
			for n in nav:
				acc += Vector3(n.x, n.y, n.z)
			return acc / float(nav.size())
		return Vector3.ZERO

	func start_round(room) -> void:
		room.state.matchScore = {"CT": 0, "T": 0}
		var all: Array = room.state.players.values()
		var ct: int = 0
		var t: int = 0
		for p in all:
			p.isZombie = false
			if p.teamPref == "ct":
				p.team = Constants.TEAM_CT
			elif p.teamPref == "t":
				p.team = Constants.TEAM_T
			else:
				p.team = Constants.TEAM_NONE
			if p.team == Constants.TEAM_CT:
				ct += 1
			elif p.team == Constants.TEAM_T:
				t += 1
		for p in all:
			if p.team == Constants.TEAM_NONE:
				if ct <= t:
					p.team = Constants.TEAM_CT
					ct += 1
				else:
					p.team = Constants.TEAM_T
					t += 1
		room.spawn_all()
		room.state.core.begin(round_time)

	func on_tick(room, dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= dt
		var ct_in: int = 0
		var t_in: int = 0
		for p in room.state.players.values():
			if not p.alive:
				continue
			if _in_hill(p.pos):
				if int(p.team) == Constants.TEAM_CT:
					ct_in += 1
				else:
					t_in += 1
		var new_owner: int = Constants.TEAM_NONE
		if ct_in > 0 and t_in == 0:
			new_owner = Constants.TEAM_CT
		elif t_in > 0 and ct_in == 0:
			new_owner = Constants.TEAM_T
		elif ct_in > 0 and t_in > 0:
			contest_seconds += dt
		if new_owner != owner_team:
			owner_team = new_owner
		if owner_team != Constants.TEAM_NONE:
			var key: String = "CT" if owner_team == Constants.TEAM_CT else "T"
			room.state.matchScore[key] = float(room.state.matchScore.get(key, 0.0)) + dt * tick_rate
			for p in room.state.players.values():
				if p.alive and int(p.team) == owner_team and _in_hill(p.pos):
					p.score += int(dt * tick_rate * 2.0)
		var ct_s: float = float(room.state.matchScore.get("CT", 0.0))
		var t_s: float = float(room.state.matchScore.get("T", 0.0))
		if ct_s >= score_limit or t_s >= score_limit:
			core.end_round("CT" if ct_s > t_s else "T", "score_limit")
		elif core.time_left <= 0.0:
			if absf(ct_s - t_s) < 0.5:
				core.end_round("DRAW", "timeout")
			else:
				core.end_round("CT" if ct_s > t_s else "T", "timeout")

	func on_kill(room, victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)

	func snapshot_extra(_room) -> Dictionary:
		return {"hill": hill_pos, "hillR": hill_radius, "owner": owner_team}

	func _in_hill(pos: Vector3) -> bool:
		var dx: float = pos.x - hill_pos.x
		var dz: float = pos.z - hill_pos.z
		return dx * dx + dz * dz <= hill_radius * hill_radius and absf(pos.y - hill_pos.y) < 4.0


# =====================================================================
# 夺旗（CTF）
# =====================================================================
class CTF extends ModeBase:
	var base_ct: Vector3 = Vector3.ZERO
	var base_t: Vector3 = Vector3.ZERO
	var flag_ct: Dictionary = {}
	var flag_t: Dictionary = {}
	var carry_ct: String = ""
	var carry_t: String = ""

	func _init() -> void:
		id = "ctf"
		label = "夺旗模式"
		short = "CTF"
		desc = "夺取敌方旗帜带回己方基地，先得 5 分获胜。"
		team_based = true
		team_count = 2
		respawn = true
		respawn_delay = 5.0
		round_time = 600.0
		score_limit = 5
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "captures"]
		hud_objective = "夺取敌方旗帜"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)
		var spawns: Dictionary = room.state.map.get("spawns", {})
		base_ct = _spawn_vec(spawns, "CT")
		base_t = _spawn_vec(spawns, "T")
		reset_flags()

	func _spawn_vec(spawns: Dictionary, key: String) -> Vector3:
		var arr: Array = spawns.get(key, spawns.get("HUMAN", []))
		if arr.is_empty():
			return Vector3.ZERO
		var s: Dictionary = arr[0]
		return Vector3(float(s.x), float(s.get("y", 0.0)), float(s.z))

	func reset_flags() -> void:
		flag_ct = {"home": base_ct, "pos": base_ct, "at_home": true, "dropped": false}
		flag_t = {"home": base_t, "pos": base_t, "at_home": true, "dropped": false}
		carry_ct = ""
		carry_t = ""

	func start_round(room) -> void:
		room.state.matchScore = {"CT": 0, "T": 0}
		reset_flags()
		var all: Array = room.state.players.values()
		var ct: int = 0
		var t: int = 0
		for p in all:
			p.isZombie = false
			if p.teamPref == "ct":
				p.team = Constants.TEAM_CT
			elif p.teamPref == "t":
				p.team = Constants.TEAM_T
			else:
				p.team = Constants.TEAM_NONE
			if p.team == Constants.TEAM_CT:
				ct += 1
			elif p.team == Constants.TEAM_T:
				t += 1
		for p in all:
			if p.team == Constants.TEAM_NONE:
				if ct <= t:
					p.team = Constants.TEAM_CT
					ct += 1
				else:
					p.team = Constants.TEAM_T
					t += 1
		room.spawn_all()
		room.state.core.begin(round_time)

	func on_tick(room, dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= dt
		# 拾取 / 归还
		for p in room.state.players.values():
			if not p.alive:
				continue
			var team: int = int(p.team)
			var enemy_flag: Dictionary = flag_t if team == Constants.TEAM_CT else flag_ct
			var own_flag: Dictionary = flag_ct if team == Constants.TEAM_CT else flag_t
			# 拾取敌旗
			if enemy_flag.at_home and p.pos.distance_to(enemy_flag.pos) < 2.0:
				enemy_flag.at_home = false
				enemy_flag.dropped = false
				if team == Constants.TEAM_CT:
					carry_ct = p.id
				else:
					carry_t = p.id
				room.broadcast_msg({"type": "flag_taken", "team": team})
			# 归还己方旗
			if own_flag.dropped and p.pos.distance_to(own_flag.pos) < 2.0:
				own_flag.dropped = false
				own_flag.at_home = true
				own_flag.pos = own_flag.home
				room.broadcast_msg({"type": "flag_returned", "team": team})
			# 得分
			if team == Constants.TEAM_CT and carry_ct == p.id and p.pos.distance_to(base_ct) < 3.0:
				if not flag_t.at_home:
					room.state.matchScore.CT = int(room.state.matchScore.get("CT", 0)) + 1
					p.score += 50
					p.captures = int(p.get("captures", 0)) + 1
					flag_t.at_home = true
					flag_t.dropped = false
					flag_t.pos = base_t
					carry_ct = ""
					room.broadcast_msg({"type": "flag_captured", "team": Constants.TEAM_CT})
			elif team == Constants.TEAM_T and carry_t == p.id and p.pos.distance_to(base_t) < 3.0:
				if not flag_ct.at_home:
					room.state.matchScore.T = int(room.state.matchScore.get("T", 0)) + 1
					p.score += 50
					p.captures = int(p.get("captures", 0)) + 1
					flag_ct.at_home = true
					flag_ct.dropped = false
					flag_ct.pos = base_ct
					carry_t = ""
					room.broadcast_msg({"type": "flag_captured", "team": Constants.TEAM_T})
		# 携带者死亡 → 掉落
		if carry_ct != "" and not room.state.players.has(carry_ct):
			carry_ct = ""
			flag_t.at_home = true
			flag_t.pos = base_t
		if carry_t != "" and not room.state.players.has(carry_t):
			carry_t = ""
			flag_ct.at_home = true
			flag_ct.pos = base_ct
		var ct_s: int = int(room.state.matchScore.get("CT", 0))
		var t_s: int = int(room.state.matchScore.get("T", 0))
		if ct_s >= score_limit or t_s >= score_limit:
			core.end_round("CT" if ct_s > t_s else "T", "score_limit")
		elif core.time_left <= 0.0:
			core.end_round("CT" if ct_s >= t_s else "T", "timeout")

	func on_kill(room, victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
		if victim.id == carry_ct:
			carry_ct = ""
			flag_t.at_home = false
			flag_t.dropped = true
			flag_t.pos = victim.pos
		if victim.id == carry_t:
			carry_t = ""
			flag_ct.at_home = false
			flag_ct.dropped = true
			flag_ct.pos = victim.pos
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)

	func snapshot_extra(_room) -> Dictionary:
		return {
			"flagCT": {"x": flag_ct.get("pos", Vector3.ZERO).x, "z": flag_ct.get("pos", Vector3.ZERO).z, "home": flag_ct.get("at_home", true)},
			"flagT": {"x": flag_t.get("pos", Vector3.ZERO).x, "z": flag_t.get("pos", Vector3.ZERO).z, "home": flag_t.get("at_home", true)},
		}


# =====================================================================
# 军备竞赛（Gun Game）
# =====================================================================
class GunGame extends ModeBase:
	const LADDER: Array = [
		"k9", "pc", "mp9", "vx9", "sc", "pdw", "arc17", "ak", "rb", "warden",
		"sp", "sa", "dmr", "sr", "longshot", "sm", "fang",
	]

	func _init() -> void:
		id = "gungame"
		label = "军备竞赛"
		short = "GUN"
		desc = "每击杀一人升级一把武器，最后用匕首终结对手。"
		team_based = false
		respawn = true
		respawn_delay = 2.0
		round_time = 600.0
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "level"]
		hud_objective = "击杀升级武器"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)

	func start_round(room) -> void:
		for p in room.state.players.values():
			p.team = Constants.TEAM_NONE
			p.isZombie = false
			p.weaponLevel = 0
			p.kills = 0
			p.deaths = 0
		room.spawn_all()
		if room.state.core != null:
			room.state.core.begin(round_time)

	func on_player_spawn(room, p: Dictionary) -> void:
		_give_level(room, p)

	func on_kill(room, victim: Dictionary, killer: Variant, _info: Dictionary) -> bool:
		if killer != null and killer != victim:
			killer.weaponLevel = int(killer.get("weaponLevel", 0)) + 1
			if killer.weaponLevel >= LADDER.size():
				killer.weaponLevel = LADDER.size() - 1
				room.state.core.end_round(str(killer.team), "gungame_win")
			else:
				_give_level(room, killer)
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func on_tick(room, _dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= _dt
		if core.time_left <= 0.0:
			var best: Variant = null
			for p in room.state.players.values():
				if best == null or int(p.get("weaponLevel", 0)) > int(best.get("weaponLevel", 0)):
					best = p
			core.end_round(str(best.get("team", "DRAW")) if best != null else "DRAW", "timeout")

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)

	func _give_level(_room, p: Dictionary) -> void:
		var lvl: int = clampi(int(p.get("weaponLevel", 0)), 0, LADDER.size() - 1)
		var wid: String = str(LADDER[lvl])
		var def: Dictionary = WeaponDB.get_def(wid)
		if def.is_empty():
			def = WeaponDbFallback.lookup(wid)
		if def.is_empty():
			def = WeaponData.BUILTIN_WEAPONS.get("k9", {})
		if def.is_empty():
			return
		p.weapons.clear()
		var rt = WeaponData.WeaponRuntime.new(def.duplicate(true))
		p.weapons[2] = rt
		p.activeSlot = 2


# =====================================================================
# 生存波次
# =====================================================================
class Survival extends ModeBase:
	var wave: int = 0
	var wave_timer: float = 0.0     # 下一波倒计时
	var spawn_budget: int = 0
	var alive_wave_bots: int = 0
	var intermission: bool = true

	func _init() -> void:
		id = "survival"
		label = "生存模式"
		short = "SURV"
		desc = "一波又一波的感染者，撑得越久分数越高。"
		team_based = false
		respawn = false
		respawn_delay = 0.0
		round_time = 0.0
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "wave"]
		hud_objective = "活下去"

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(99999.0, 0.0)

	func start_round(room) -> void:
		wave = 0
		wave_timer = 5.0
		intermission = true
		for p in room.state.players.values():
			p.team = Constants.TEAM_HUMAN
			p.isZombie = false
			p.wave = 0
			p.kills = 0
			p.deaths = 0
		room.spawn_all()
		room.state.core.begin(99999.0)

	func on_tick(room, dt: float) -> void:
		if intermission:
			wave_timer -= dt
			if wave_timer <= 0.0:
				intermission = false
				_build_wave(room)
			return
		# 波次清空 → 进入下一波间隔
		var remaining: int = 0
		for p in room.state.players.values():
			if p.isBot and p.alive and p.get("waveBot", false):
				remaining += 1
		if remaining == 0:
			wave += 1
			for p in room.state.players.values():
				if not p.isBot:
					p.wave = wave
					p.money = mini(Economy.MONEY_CAP, p.money + 500 + wave * 100)
			intermission = true
			wave_timer = 8.0
			room.broadcast_msg({"type": "wave_clear", "wave": wave})

	func _build_wave(room) -> void:
		wave += 1
		var count: int = 3 + wave * 2
		var hp_mult: float = 1.0 + (wave - 1) * 0.18
		for i in count:
			var bot: Dictionary = room.spawn_wave_bot(wave, hp_mult)
			if bot.is_empty():
				break

	func on_kill(_room, victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
		victim.respawnAt = 0.0
		return true

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 8.0)


# 兜底：当 WeaponDB 未就绪时直接查内置表
class WeaponDbFallback:
	static func lookup(wid: String) -> Dictionary:
		return WeaponData.BUILTIN_WEAPONS.get(wid, {})
