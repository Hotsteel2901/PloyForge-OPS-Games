# 数据驱动武器：定义 + 运行时。移植自 shared/weapons.js
extends Node

# 内置武器定义
const BUILTIN_WEAPONS: Dictionary = {
	"fang": {
		"id": "fang",
		"name": "Fang 匕首",
		"slot": 0,
		"auto": true,
		"melee": true,
		"range": 2.4,
		"fireRate": 170,
		"damage": 40,
		"headshotMult": 1.0,
		"pellets": 1,
		"magSize": INF,
		"reserve": INF,
		"reloadTime": 0.0,
		"spread": 0.0,
		"adsSpread": 0.0,
		"recoil": 0.01,
		"moveMult": 1.05,
		"falloffNear": 1.5,
		"falloffFar": 2.4,
		"falloffMin": 0.9,
		"sound": "melee",
	},
	"k9": {
		"id": "k9",
		"name": "K9 手枪",
		"slot": 1,
		"auto": false,
		"fireRate": 300,
		"damage": 32,
		"headshotMult": 1.8,
		"pellets": 1,
		"magSize": 12,
		"reserve": 48,
		"reloadTime": 1.4,
		"spread": 0.03,
		"adsSpread": 0.008,
		"recoil": 0.025,
		"moveMult": 1.0,
		"falloffNear": 12,
		"falloffFar": 55,
		"falloffMin": 0.45,
		"sound": "pistol",
	},
	"vx9": {
		"id": "vx9",
		"name": "VX9 冲锋枪",
		"slot": 2,
		"auto": true,
		"fireRate": 900,
		"damage": 20,
		"headshotMult": 1.7,
		"pellets": 1,
		"magSize": 30,
		"reserve": 120,
		"reloadTime": 1.9,
		"spread": 0.045,
		"adsSpread": 0.012,
		"recoil": 0.016,
		"moveMult": 1.0,
		"falloffNear": 10,
		"falloffFar": 45,
		"falloffMin": 0.4,
		"sound": "smg",
	},
	"arc17": {
		"id": "arc17",
		"name": "ARC-17 突击步枪",
		"slot": 2,
		"auto": true,
		"fireRate": 660,
		"damage": 28,
		"headshotMult": 1.8,
		"pellets": 1,
		"magSize": 30,
		"reserve": 120,
		"reloadTime": 2.2,
		"spread": 0.035,
		"adsSpread": 0.008,
		"recoil": 0.02,
		"moveMult": 0.9,
		"falloffNear": 15,
		"falloffFar": 65,
		"falloffMin": 0.45,
		"sound": "rifle",
	},
	"warden": {
		"id": "warden",
		"name": "Warden 霰弹枪",
		"slot": 2,
		"auto": false,
		"fireRate": 85,
		"damage": 13,
		"headshotMult": 1.4,
		"pellets": 8,
		"magSize": 8,
		"reserve": 40,
		"reloadTime": 2.8,
		"spread": 0.09,
		"adsSpread": 0.045,
		"recoil": 0.06,
		"moveMult": 0.82,
		"falloffNear": 8,
		"falloffFar": 28,
		"falloffMin": 0.3,
		"sound": "shotgun",
	},
	"longshot": {
		"id": "longshot",
		"name": "Longshot 狙击枪",
		"slot": 2,
		"auto": false,
		"fireRate": 45,
		"damage": 120,
		"headshotMult": 2.2,
		"pellets": 1,
		"magSize": 5,
		"reserve": 25,
		"reloadTime": 3.2,
		"spread": 0.02,
		"adsSpread": 0.001,
		"recoil": 0.09,
		"moveMult": 0.72,
		"falloffNear": 30,
		"falloffFar": 200,
		"falloffMin": 0.75,
		"sound": "sniper",
	},
	"bruiser": {
		"id": "bruiser",
		"name": "Bruiser 轻机枪",
		"slot": 2,
		"auto": true,
		"fireRate": 720,
		"damage": 24,
		"headshotMult": 1.6,
		"pellets": 1,
		"magSize": 100,
		"reserve": 200,
		"reloadTime": 4.2,
		"spread": 0.05,
		"adsSpread": 0.016,
		"recoil": 0.022,
		"moveMult": 0.78,
		"falloffNear": 12,
		"falloffFar": 55,
		"falloffMin": 0.4,
		"sound": "lmg",
	},
	"thunder": {
		"id": "thunder",
		"name": "Thunder 手雷",
		"slot": 3,
		"auto": false,
		"projectile": "grenade",
		"fireRate": 55,
		"damage": 180,
		"headshotMult": 1.0,
		"pellets": 1,
		"magSize": 99,
		"reserve": 0,
		"reloadTime": 1.0,
		"spread": 0.0,
		"adsSpread": 0.0,
		"recoil": 0.0,
		"moveMult": 1.0,
		"falloffNear": 3,
		"falloffFar": 11,
		"falloffMin": 0.25,
		"sound": "throw",
	},
	"pc": {
		"id": "pc",
		"name": "PC 紧凑手枪",
		"slot": 1,
		"auto": false,
		"fireRate": 400,
		"damage": 34,
		"headshotMult": 1.9,
		"pellets": 1,
		"magSize": 13,
		"reserve": 26,
		"reloadTime": 1.6,
		"spread": 0.028,
		"adsSpread": 0.01,
		"recoil": 0.022,
		"moveMult": 1.0,
		"falloffNear": 12,
		"falloffFar": 55,
		"falloffMin": 0.45,
		"sound": "pistol",
		"cost": 400,
		"model": "Pistol_Compact_East.glb",
		"adsFov": 56,
	},
	"pf": {
		"id": "pf",
		"name": "PF 重型手枪",
		"slot": 1,
		"auto": false,
		"fireRate": 267,
		"damage": 62,
		"headshotMult": 2.1,
		"pellets": 1,
		"magSize": 7,
		"reserve": 35,
		"reloadTime": 2.2,
		"spread": 0.045,
		"adsSpread": 0.02,
		"recoil": 0.05,
		"moveMult": 1.0,
		"falloffNear": 15,
		"falloffFar": 60,
		"falloffMin": 0.6,
		"sound": "pistol",
		"cost": 700,
		"model": "Pistol_Full_East.glb",
		"adsFov": 52,
	},
	"ra": {
		"id": "ra",
		"name": "RA 突击步枪",
		"slot": 2,
		"auto": true,
		"fireRate": 600,
		"damage": 34,
		"headshotMult": 2.5,
		"pellets": 1,
		"magSize": 30,
		"reserve": 90,
		"reloadTime": 2.4,
		"spread": 0.024,
		"adsSpread": 0.008,
		"recoil": 0.03,
		"moveMult": 0.9,
		"falloffNear": 20,
		"falloffFar": 80,
		"falloffMin": 0.6,
		"sound": "rifle",
		"cost": 2700,
		"model": "Rifle_Assault_East.glb",
		"adsFov": 46,
	},
	"rb": {
		"id": "rb",
		"name": "RB 战斗步枪",
		"slot": 2,
		"auto": false,
		"fireRate": 350,
		"damage": 55,
		"headshotMult": 2.2,
		"pellets": 1,
		"magSize": 20,
		"reserve": 60,
		"reloadTime": 2.6,
		"spread": 0.02,
		"adsSpread": 0.006,
		"recoil": 0.045,
		"moveMult": 0.85,
		"falloffNear": 25,
		"falloffFar": 100,
		"falloffMin": 0.65,
		"sound": "rifle",
		"cost": 3200,
		"model": "Rifle_Battle_East.glb",
		"adsFov": 40,
	},
	"sc": {
		"id": "sc",
		"name": "SC 紧凑冲锋枪",
		"slot": 2,
		"auto": true,
		"fireRate": 857,
		"damage": 22,
		"headshotMult": 1.8,
		"pellets": 1,
		"magSize": 30,
		"reserve": 120,
		"reloadTime": 2.0,
		"spread": 0.034,
		"adsSpread": 0.012,
		"recoil": 0.018,
		"moveMult": 1.0,
		"falloffNear": 10,
		"falloffFar": 45,
		"falloffMin": 0.4,
		"sound": "smg",
		"cost": 1300,
		"model": "SMG_Compact_East.glb",
		"adsFov": 50,
	},
	"sf": {
		"id": "sf",
		"name": "SF 高速冲锋枪",
		"slot": 2,
		"auto": true,
		"fireRate": 900,
		"damage": 22,
		"headshotMult": 1.6,
		"pellets": 1,
		"magSize": 50,
		"reserve": 100,
		"reloadTime": 2.3,
		"spread": 0.032,
		"adsSpread": 0.01,
		"recoil": 0.015,
		"moveMult": 1.0,
		"falloffNear": 8,
		"falloffFar": 40,
		"falloffMin": 0.35,
		"sound": "smg",
		"cost": 2350,
		"model": "SMG_Full_East.glb",
		"adsFov": 52,
	},
	"sa": {
		"id": "sa",
		"name": "SA 自动霰弹枪",
		"slot": 2,
		"auto": true,
		"fireRate": 300,
		"damage": 18,
		"headshotMult": 1.4,
		"pellets": 7,
		"magSize": 7,
		"reserve": 32,
		"reloadTime": 2.9,
		"spread": 0.09,
		"adsSpread": 0.05,
		"recoil": 0.06,
		"moveMult": 0.82,
		"falloffNear": 8,
		"falloffFar": 28,
		"falloffMin": 0.3,
		"sound": "shotgun",
		"cost": 2000,
		"model": "Shotgun_Auto_East.glb",
		"adsFov": 48,
	},
	"sp": {
		"id": "sp",
		"name": "SP 泵动霰弹枪",
		"slot": 2,
		"auto": false,
		"fireRate": 68,
		"damage": 18,
		"headshotMult": 1.4,
		"pellets": 7,
		"magSize": 5,
		"reserve": 32,
		"reloadTime": 3.2,
		"spread": 0.07,
		"adsSpread": 0.04,
		"recoil": 0.07,
		"moveMult": 0.85,
		"falloffNear": 9,
		"falloffFar": 30,
		"falloffMin": 0.35,
		"sound": "shotgun",
		"cost": 1050,
		"model": "Shotgun_Pump_East.glb",
		"adsFov": 45,
	},
	"sm": {
		"id": "sm",
		"name": "SM 重型狙击枪",
		"slot": 2,
		"auto": false,
		"fireRate": 41,
		"damage": 115,
		"headshotMult": 4.0,
		"pellets": 1,
		"magSize": 5,
		"reserve": 30,
		"reloadTime": 3.6,
		"spread": 0.004,
		"adsSpread": 0.0005,
		"recoil": 0.09,
		"moveMult": 0.72,
		"falloffNear": 40,
		"falloffFar": 250,
		"falloffMin": 0.85,
		"sound": "sniper",
		"cost": 4750,
		"model": "Sniper_Material_East.glb",
		"adsFov": 22,
	},
	"sr": {
		"id": "sr",
		"name": "SR 侦察狙击枪",
		"slot": 2,
		"auto": false,
		"fireRate": 60,
		"damage": 72,
		"headshotMult": 2.0,
		"pellets": 1,
		"magSize": 10,
		"reserve": 90,
		"reloadTime": 2.4,
		"spread": 0.012,
		"adsSpread": 0.002,
		"recoil": 0.055,
		"moveMult": 0.8,
		"falloffNear": 25,
		"falloffFar": 150,
		"falloffMin": 0.7,
		"sound": "sniper",
		"cost": 1700,
		"model": "Sniper_Rifle_East.glb",
		"adsFov": 28,
	},
}

# 尸爪武器定义（运行时生成）
static func zombie_claw_def() -> Dictionary:
	return {
		"id": "zclaw",
		"name": "尸爪",
		"slot": 0,
		"auto": true,
		"melee": true,
		"range": 2.3,
		"fireRate": 68,
		"damage": 60,
		"headshotMult": 1.0,
		"pellets": 1,
		"magSize": INF,
		"reserve": INF,
		"reloadTime": 0.0,
		"spread": 0.0,
		"adsSpread": 0.0,
		"recoil": 0.0,
		"moveMult": 1.0,
		"falloffNear": 2.3,
		"falloffFar": 2.3,
		"falloffMin": 1.0,
		"sound": "melee",
	}


static func get_weapon_ids() -> Array:
	return BUILTIN_WEAPONS.keys()


# 计算射击伤害（含距离衰减 + 爆头倍率）
static func compute_shot_damage(def: Dictionary, headshot: bool, dist: float) -> int:
	var base: float = _damage_falloff_safe(def, dist)
	var mult: float = def.headshotMult if headshot else 1.0
	return max(1, int(round(base * mult)))


static func _damage_falloff_safe(def: Dictionary, dist: float) -> float:
	if def.get("melee", false):
		return float(def.damage)
	var near: float = def.get("falloffNear", 15.0)
	var far: float = def.get("falloffFar", 60.0)
	var min_val: float = def.get("falloffMin", 0.45)
	if dist <= near:
		return float(def.damage)
	if dist >= far:
		return float(def.damage) * min_val
	var t: float = (dist - near) / (far - near)
	return float(def.damage) * (1.0 - t * (1.0 - min_val))


static func apply_spread(def: Dictionary, ads: bool) -> float:
	var max_val: float = def.adsSpread if ads else def.spread
	return randf() * max_val


# 半自动武器只在"松开→按下"的边沿开火；全自动/近战按住即连发
static func should_fire(def: Dictionary, held: bool, was_held: bool) -> bool:
	if not held:
		return false
	if def.get("auto", false) or def.get("melee", false):
		return true
	return not was_held


# 武器运行时状态（弹药、换弹、射速限速）
class WeaponRuntime:
	var def: Dictionary
	var ammo: float
	var reserve: float
	var state: String = "ready" # ready | reloading | empty
	var next_fire_at: float = 0.0
	var reload_end: float = 0.0

	func _init(d: Dictionary):
		def = d
		ammo = d.magSize
		reserve = d.reserve

	var interval: float:
		get:
			return 60.0 / max(1, int(def.fireRate))

	func can_fire(time: float) -> bool:
		return state == "ready" and ammo > 0 and time >= next_fire_at

	func fire(time: float) -> Dictionary:
		if not can_fire(time):
			return {"ok": false}
		ammo -= 1
		next_fire_at = time + interval
		if ammo == 0:
			state = "empty"
		return {"ok": true, "ammo": ammo}

	func start_reload(time: float) -> Dictionary:
		if state == "reloading" or reserve <= 0 or ammo == def.magSize:
			return {"ok": false}
		state = "reloading"
		reload_end = time + float(def.reloadTime)
		return {"ok": true}

	func update(time: float) -> Dictionary:
		if state == "reloading" and time >= reload_end:
			var need: float = def.magSize - ammo
			var take: float = min(need, reserve)
			ammo += take
			reserve -= take
			state = "ready" if ammo > 0 else "empty"
			return {"type": "reloaded", "ammo": ammo, "reserve": reserve}
		return {}

	func reset(time: float = 0.0) -> void:
		state = "ready"
		next_fire_at = time
		reload_end = 0.0
