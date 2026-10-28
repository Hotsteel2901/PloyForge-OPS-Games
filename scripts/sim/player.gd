# 玩家对象：创建、装备、生成、受伤、死亡。v2 起把「模式规则」全部交给 ModeBase。
class_name Player
extends RefCounted

const PHYS = Constants.PHYS
const FINALE = Constants.FINALE


static func create(id: String, p_name: String, is_bot: bool = false) -> Dictionary:
	return {
		"id": id, "name": p_name, "isBot": is_bot,
		"team": Constants.TEAM_NONE, "teamPref": "random",
		"alive": false, "pos": Vector3(0, 2, 0), "vel": Vector3(0, 0, 0),
		"yaw": 0.0, "pitch": 0.0, "grounded": true, "crouch": false,
		"hp": 100.0, "maxHp": 100.0, "armor": 0,
		"weapons": {}, "activeSlot": 1, "grenadeCount": 1,
		"money": Economy.START_MONEY, "boughtItems": [], "bombCarrier": false,
		"isZombie": false, "score": 0, "kills": 0, "deaths": 0,
		"assists": 0, "captures": 0, "weaponLevel": 0, "wave": 0,
		"respawnAt": 0.0, "lastHitAt": -99.0,
		"input": {
			"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
			"yaw": 0.0, "pitch": 0.0, "fire": false, "ads": false,
			"r": false, "sw": -1, "swd": 0, "u": false,
		},
		"edge": {"sw": -1, "swd": 0, "r": false, "j": false, "u": false, "skill": false},
		"switchSeq": 0, "lastUseProgressAt": 0.0, "useProgress": 0.0, "useTarget": null,
		"weaponMoveMult": 1.0,
		"botBrain": null,
		"history": PositionHistory.new(),
		"inputAt": 0.0, "wasFiring": false, "slowTicks": 0,
		"selectedPrimary": null, "zombieMoneyInit": false, "zombieSince": 0.0,
		"damageMult": 1.0, "isCrystalHunter": false, "isZombieKing": false, "isZombieServant": false,
		"speedOverride": null, "boostUntil": 0.0, "skillReadyAt": 0.0, "boughtPhase": false,
		# v2 新增
		"stunUntil": 0.0, "flashUntil": 0.0, "lastDamageFrom": "", "lastDamageAt": -99.0,
		"ping": 0, "packetLoss": 0.0, "connected": true, "isRemote": false,
		"killedBy": "", "spawnProtectUntil": 0.0, "inHill": false, "waveBot": false,
	}


static func give_loadout(p: Dictionary, mode: String, team: int) -> void:
	p.weapons.clear()
	p.activeSlot = 1
	p.weaponMoveMult = 1.0
	p.grenadeCount = 0
	if p.isZombie:
		p.weapons[0] = WeaponData.WeaponRuntime.new(WeaponData.zombie_claw_def())
		p.activeSlot = 0
		return
	p.weapons[0] = WeaponData.WeaponRuntime.new(_def("fang"))
	p.weapons[1] = WeaponData.WeaponRuntime.new(_def("k9"))
	p.weapons[3] = WeaponData.WeaponRuntime.new(_def("thunder"))
	if mode == Constants.MODE_DEFUSAL or mode == "tdm" or mode == "ffa" or mode == "koth" or mode == "ctf":
		p.grenadeCount = 1
		p.activeSlot = 1
	else:
		p.weapons[2] = WeaponData.WeaponRuntime.new(_def("arc17"))
		p.grenadeCount = 3
		p.activeSlot = 2


static func _def(id: String) -> Dictionary:
	var d: Dictionary = WeaponDB.get_def(id)
	if d.is_empty():
		d = WeaponData.BUILTIN_WEAPONS.get(id, {})
	return d


# spawn 是字典（{x,y,z,yaw}），opts: {keepLoadout}
static func spawn_player(room: Dictionary, p: Dictionary, team: int, spawn: Dictionary, opts: Dictionary = {}) -> void:
	p.team = team
	p.alive = true
	p.pos = Vector3(spawn.x, float(spawn.get("y", 0.05)), spawn.z)
	p.vel = Vector3.ZERO
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
		give_loadout(p, str(room.get("mode", "defusal")), team)
	p.lastHitAt = -99.0
	p.respawnAt = 0.0
	p.useProgress = 0.0
	p.useTarget = null
	p.speedOverride = null
	p.boostUntil = 0.0
	p.skillReadyAt = 0.0
	p.stunUntil = 0.0
	p.spawnProtectUntil = float(room.get("time", 0.0)) + 1.2
	p.inHill = false
	if room.get("mode", "") == Constants.MODE_ZOMBIE:
		if not p.zombieMoneyInit:
			p.money = Economy.ZOMBIE_START_MONEY
			p.zombieMoneyInit = true
		if not p.isZombie and p.selectedPrimary != null and room.weapons.has(p.selectedPrimary):
			p.weapons[2] = WeaponData.WeaponRuntime.new(room.weapons[p.selectedPrimary])
			p.activeSlot = 2
		if room.finaleActive and not p.isZombie:
			p.isCrystalHunter = true
			p.hp = float(FINALE.HUNTER_HP)
			p.maxHp = float(FINALE.HUNTER_HP)
			p.armor = FINALE.HUNTER_ARMOR
			p.damageMult = FINALE.HUNTER_DAMAGE


# info: {weapon, headshot, dist, armor_pen}
static func damage_player(room: Dictionary, shooter: Variant, victim: Dictionary, amount: float, info: Dictionary = {}) -> Variant:
	if not victim.alive:
		return null
	# 出生保护
	if float(room.get("time", 0.0)) < float(victim.get("spawnProtectUntil", 0.0)):
		return null
	# 友伤：由模式决定
	if shooter != null and shooter != victim and not room.get("friendly_fire", false):
		if shooter.team == victim.team and not room.get("ffa", false):
			return null
	var mult: float = 1.0
	if shooter != null and shooter != victim:
		mult = float(shooter.get("damageMult", 1.0))
	var dmg_int: int = int(round(amount * mult))
	# 护甲穿透：pen 越高，护甲吸收越少
	var pen: float = clampf(float(info.get("armor_pen", 0.5)), 0.0, 1.0)
	var eff_armor: int = int(float(victim.armor) * (1.0 - pen * 0.8))
	var ar := MathUtil.apply_armor(dmg_int, eff_armor)
	var damage: int = ar.damage
	var armor_spent: int = eff_armor - int(ar.armor)
	victim.armor = clampi(int(victim.armor) - armor_spent, 0, 100)
	victim.hp -= float(damage)
	victim.lastHitAt = float(room.time)
	if shooter != null and shooter != victim:
		victim.lastDamageFrom = str(shooter.id)
		victim.lastDamageAt = float(room.time)
	if victim.isZombie:
		victim.slowTicks = int(PHYS.ZOMBIE_SLOW_TICKS)
	# 电击枪定身
	if info.has("stun"):
		victim.stunUntil = float(room.time) + float(info.stun)
	var result := {
		"victim": victim, "damage": damage, "armor": victim.armor,
		"headshot": bool(info.get("headshot", false)),
		"weapon": info.get("weapon", "unknown"),
		"attacker": shooter.id if shooter != null else "",
	}
	if room.events.has("player_damage"):
		room.events.player_damage.call({"result": result, "attacker": shooter})
	if victim.hp <= 0.0:
		kill_player(room, shooter, victim, info)
	return result


static func kill_player(room: Dictionary, killer: Variant, victim: Dictionary, info: Dictionary = {}) -> void:
	if not victim.alive:
		return
	victim.alive = false
	victim.deaths += 1
	victim.killedBy = str(killer.id) if killer != null else ""
	if killer != null and killer != victim:
		killer.kills += 1
		killer.score += 10
		if room.mode == Constants.MODE_ZOMBIE:
			if victim.isZombie:
				killer.money = mini(Economy.MONEY_CAP, killer.money + Economy.ZOMBIE_KILL_REWARD)
		elif room.get("uses_money", false):
			killer.money = mini(Economy.MONEY_CAP, killer.money + Economy.KILL_REWARD)
	else:
		victim.score -= 5
	var event := {
		"type": "kill",
		"killer": killer.id if killer != null else null,
		"killerName": killer.name if killer != null else "",
		"victim": victim.id, "victimName": victim.name,
		"weapon": info.get("weapon", "unknown"),
		"headshot": bool(info.get("headshot", false)),
		"zombie": 1 if victim.isZombie else 0,
	}
	if room.events.has("player_death"):
		room.events.player_death.call({"killer": killer, "victim": victim, "info": info})
	room.broadcast.call(event)
	# 模式接管后续（复活/感染/掉落）
	if room.get("onKilled", Callable()).is_valid():
		room.onKilled.call(victim, killer, info)


static func respawn_zombie(room: Dictionary, p: Dictionary) -> void:
	var spawn: Dictionary = room.pickSpawn.call("ZOMBIE")
	spawn_player(room, p, Constants.TEAM_ZOMBIE, spawn)


static func eye_height(p: Dictionary) -> float:
	return p.pos.y + (1.05 if p.crouch else 1.62)
