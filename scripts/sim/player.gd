# 服务器玩家对象：创建、装备、生成、受伤、死亡。移植自 host/player.js
class_name Player
extends RefCounted

const PHYS = Constants.PHYS
const FINALE = Constants.FINALE


# 工厂方法：创建一个玩家状态字典（用 Dictionary 以便运行时增删字段，
# 与 JS 原实现保持一致；WeaponRuntime 作为对象存入）
static func create(id: String, p_name: String, is_bot: bool = false) -> Dictionary:
	return {
		"id": id,
		"name": p_name,
		"isBot": is_bot,
		"team": Constants.TEAM_NONE,
		"teamPref": "random",
		"alive": false,
		"pos": Vector3(0, 2, 0),
		"vel": Vector3(0, 0, 0),
		"yaw": 0.0,
		"pitch": 0.0,
		"grounded": true,
		"crouch": false,
		"hp": 100.0,
		"maxHp": 100.0,
		"armor": 0,
		"weapons": {},              # slot:int -> WeaponRuntime
		"activeSlot": 1,
		"grenadeCount": 1,
		"money": Economy.START_MONEY,
		"boughtItems": [],          # 购买阶段记录
		"bombCarrier": false,
		"isZombie": false,
		"score": 0,
		"kills": 0,
		"deaths": 0,
		"respawnAt": 0.0,
		"lastHitAt": -99.0,
		"input": {
			"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
			"yaw": 0.0, "pitch": 0.0, "fire": false, "ads": false,
			"r": false, "sw": -1, "swd": 0, "u": false,
		},
		"edge": {"sw": -1, "swd": 0, "r": false, "j": false, "u": false, "skill": false},
		"switchSeq": 0,
		"lastUseProgressAt": 0.0,
		"useProgress": 0.0,
		"useTarget": null,
		"weaponMoveMult": 1.0,
		"botBrain": null,           # BotBrain 实例
		"history": PositionHistory.new(),
		"inputAt": 0.0,
		"wasFiring": false,
		"slowTicks": 0,
		"selectedPrimary": null,    # 生化模式选枪
		"zombieMoneyInit": false,
		"zombieSince": 0.0,
		"damageMult": 1.0,
		"isCrystalHunter": false,
		"isZombieKing": false,
		"isZombieServant": false,
		"speedOverride": null,
		"boostUntil": 0.0,
		"skillReadyAt": 0.0,
		"boughtPhase": false,
	}


static func give_loadout(p: Dictionary, mode: String, team: int) -> void:
	p.weapons.clear()
	p.activeSlot = 1
	p.weaponMoveMult = 1.0
	p.grenadeCount = 0
	if p.isZombie:
		var claw_def: Dictionary = WeaponData.zombie_claw_def()
		var claw := WeaponData.WeaponRuntime.new(claw_def)
		p.weapons[0] = claw
		p.activeSlot = 0
		return
	p.weapons[0] = WeaponData.WeaponRuntime.new(WeaponData.BUILTIN_WEAPONS.fang)
	p.weapons[1] = WeaponData.WeaponRuntime.new(WeaponData.BUILTIN_WEAPONS.k9)
	p.weapons[3] = WeaponData.WeaponRuntime.new(WeaponData.BUILTIN_WEAPONS.thunder)
	if mode == Constants.MODE_DEFUSAL:
		# 拆弹模式开局：只持手枪（无免费主武器），主武器通过购买获得
		p.grenadeCount = 1
		p.activeSlot = 1
	else:
		# 生化模式：免费主武器
		var primary_def: Dictionary = WeaponData.BUILTIN_WEAPONS.arc17
		p.weapons[2] = WeaponData.WeaponRuntime.new(primary_def)
		p.grenadeCount = 3
		p.activeSlot = 2


# spawn 是字典（{x,y,z,yaw}），opts: {keepLoadout}
static func spawn_player(room: Dictionary, p: Dictionary, team: int, spawn: Dictionary, opts: Dictionary = {}) -> void:
	p.team = team
	p.alive = true
	var spawn_y: float = float(spawn.get("y", 0.05))
	p.pos = Vector3(spawn.x, spawn_y, spawn.z)
	p.vel = Vector3(0, 0, 0)
	p.yaw = float(spawn.get("yaw", 0.0))
	p.pitch = 0.0
	p.grounded = true
	p.crouch = false
	p.hp = float(PHYS.ZOMBIE_HP) if p.isZombie else 100.0
	p.maxHp = float(PHYS.ZOMBIE_HP) if p.isZombie else 100.0
	if opts.get("keepLoadout", false):
		p.useProgress = 0.0
		p.useTarget = null
	else:
		p.armor = 0 if p.isZombie else 50
		give_loadout(p, room.mode, team)
	p.lastHitAt = -99.0
	p.respawnAt = 0.0
	p.useProgress = 0.0
	p.useTarget = null
	p.speedOverride = null
	p.boostUntil = 0.0
	p.skillReadyAt = 0.0
	# 生化模式：加入者初始 1000；人类重生后保持所选主武器（非僵尸）
	if room.mode == Constants.MODE_ZOMBIE:
		if not p.zombieMoneyInit:
			p.money = Economy.ZOMBIE_START_MONEY
			p.zombieMoneyInit = true
		if not p.isZombie and p.selectedPrimary != null and room.weapons.has(p.selectedPrimary):
			p.weapons[2] = WeaponData.WeaponRuntime.new(room.weapons[p.selectedPrimary])
			p.activeSlot = 2
		# 琉璃决战期间新加入/重生的人类直接成为琉璃猎人
		if room.finaleActive and not p.isZombie:
			p.isCrystalHunter = true
			p.hp = float(FINALE.HUNTER_HP)
			p.maxHp = float(FINALE.HUNTER_HP)
			p.armor = FINALE.HUNTER_ARMOR
			p.damageMult = FINALE.HUNTER_DAMAGE


# info: {weapon, headshot, dist}
static func damage_player(room: Dictionary, shooter: Variant, victim: Dictionary, amount: float, info: Dictionary = {}) -> Variant:
	if not victim.alive:
		return null
	# 友伤拦截：同队伤害直接忽略
	if shooter != null and shooter != victim and shooter.team == victim.team:
		return null
	if victim.isZombie:
		victim.slowTicks = int(PHYS.ZOMBIE_SLOW_TICKS)
	# 变身倍率（琉璃猎人 / 尸王 / 尸仆 的伤害加成）
	var mult: float = 1.0
	if shooter != null and shooter != victim:
		mult = float(shooter.get("damageMult", 1.0))
	var dmg_int: int = int(round(amount * mult))
	var ar := MathUtil.apply_armor(dmg_int, victim.armor)
	var damage: int = ar.damage
	victim.armor = ar.armor
	victim.hp -= float(damage)
	victim.lastHitAt = float(room.time)
	var result := {
		"victim": victim,
		"damage": damage,
		"armor": ar.armor,
		"headshot": bool(info.get("headshot", false)),
		"weapon": info.get("weapon", "unknown"),
	}
	# 事件钩子（room.on_event 字典映射，外部房间负责调用）
	if room.events.has("player_damage"):
		room.events.player_damage.call({"result": result, "attacker": shooter})
	if victim.hp <= 0.0:
		kill_player(room, shooter, victim, info)
	return result


static func kill_player(room: Dictionary, killer: Variant, victim: Dictionary, info: Dictionary = {}) -> void:
	victim.alive = false
	victim.deaths += 1
	room.dropBomb.call(victim)  # 携带者阵亡 → 炸弹掉落
	if killer != null and killer != victim:
		killer.kills += 1
		killer.score += 10
		# 生化模式：只有击杀丧尸才给 200；拆弹模式维持原有击杀奖励
		if room.mode == Constants.MODE_ZOMBIE:
			if victim.isZombie:
				killer.money = min(Economy.MONEY_CAP, killer.money + Economy.ZOMBIE_KILL_REWARD)
		else:
			killer.money = min(Economy.MONEY_CAP, killer.money + Economy.KILL_REWARD)
	else:
		victim.score -= 5
	var event := {
		"type": "kill",
		"killer": killer.id if killer != null else null,
		"killerName": killer.name if killer != null else "",
		"victim": victim.id,
		"victimName": victim.name,
		"weapon": info.get("weapon", "unknown"),
		"headshot": bool(info.get("headshot", false)),
		"zombie": 1 if victim.isZombie else 0,
	}
	if room.events.has("player_death"):
		room.events.player_death.call({"killer": killer, "victim": victim, "info": info})
	room.broadcast.call(event)

	if room.mode == Constants.MODE_ZOMBIE:
		if room.noRespawn:
			# 琉璃决战阶段：所有实体死亡后均不能复活 / 感染
			victim.respawnAt = 0.0
		elif not victim.isZombie:
			victim.isZombie = true
			victim.team = Constants.TEAM_ZOMBIE
			victim.zombieSince = float(room.time)
			victim.respawnAt = float(room.time) + 3.5
			if room.core != null:
				room.core.infect(victim.id)
			room.broadcast.call({"type": "infected", "id": victim.id})
		else:
			victim.respawnAt = float(room.time) + 4.0
		return

	# 拆弹模式：检查整队是否全灭
	if room.mode == Constants.MODE_DEFUSAL:
		var t_alive := false
		var ct_alive := false
		for q in room.players.values():
			if q.alive:
				if q.team == Constants.TEAM_T:
					t_alive = true
				elif q.team == Constants.TEAM_CT:
					ct_alive = true
		if not t_alive and room.core != null:
			room.core.team_eliminated(Constants.TEAM_T)
		elif not ct_alive and room.core != null:
			room.core.team_eliminated(Constants.TEAM_CT)


static func respawn_zombie(room: Dictionary, p: Dictionary) -> void:
	var spawn: Dictionary = room.pickSpawn.call("ZOMBIE")
	spawn_player(room, p, Constants.TEAM_ZOMBIE, spawn)


static func eye_height(p: Dictionary) -> float:
	return p.pos.y + (1.05 if p.crouch else 1.62)
