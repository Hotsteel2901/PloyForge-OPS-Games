# 武器数据 + 运行时（v2）。
# v2 变更：
#   - 武器数量 18 → 32（含 5 种投掷物、2 种近战、3 把霰弹、4 把狙击）
#   - 新增穿透 / 护甲穿透 / 多段变焦 / 配件系统 / 皮肤接口
#   - 全部为纯数据，Mod 可通过 WeaponDB.register() 追加
extends Node

# 配件：slot ∈ optic / muzzle / grip / mag / stock
# deltas 中的 "*Mult" 为乘法，其余为加法
const ATTACHMENTS: Dictionary = {
	# ---- 瞄具 ----
	"optic_iron": {"slot": "optic", "name": "机瞄", "deltas": {}, "cost": 0},
	"optic_red_dot": {"slot": "optic", "name": "红点镜", "deltas": {"adsSpreadMult": 0.78, "adsFovMult": 0.92}, "cost": 300},
	"optic_holo": {"slot": "optic", "name": "全息镜", "deltas": {"adsSpreadMult": 0.72, "adsFovMult": 0.95}, "cost": 400},
	"optic_scope_2x": {"slot": "optic", "name": "2 倍镜", "deltas": {"adsSpreadMult": 0.55, "adsFovMult": 0.7}, "cost": 550},
	"optic_scope_4x": {"slot": "optic", "name": "4 倍镜", "deltas": {"adsSpreadMult": 0.35, "adsFovMult": 0.45, "moveMult": -0.04}, "cost": 900},
	# ---- 枪口 ----
	"muzzle_suppressor": {"slot": "muzzle", "name": "消音器", "deltas": {"recoilMult": 0.86, "loudnessMult": 0.35, "damageMult": 0.95, "spreadMult": 0.95}, "cost": 700},
	"muzzle_compensator": {"slot": "muzzle", "name": "补偿器", "deltas": {"recoilMult": 0.78}, "cost": 500},
	"muzzle_flash_hider": {"slot": "muzzle", "name": "消焰器", "deltas": {"recoilMult": 0.92, "flashMult": 0.3}, "cost": 350},
	# ---- 握把 ----
	"grip_vertical": {"slot": "grip", "name": "垂直握把", "deltas": {"recoilMult": 0.85, "spreadMult": 0.92}, "cost": 450},
	"grip_angled": {"slot": "grip", "name": "斜角握把", "deltas": {"spreadMult": 0.86, "adsTimeMult": 0.85}, "cost": 450},
	"grip_laser": {"slot": "grip", "name": "激光指示器", "deltas": {"hipSpreadMult": 0.72, "loudnessMult": 1.05}, "cost": 500},
	# ---- 弹匣 ----
	"mag_extended": {"slot": "mag", "name": "扩容弹匣", "deltas": {"magSizeAdd": 10, "reloadTimeMult": 1.12, "moveMult": -0.02}, "cost": 400},
	"mag_fast": {"slot": "mag", "name": "快速弹匣", "deltas": {"reloadTimeMult": 0.72}, "cost": 400},
	# ---- 枪托 ----
	"stock_light": {"slot": "stock", "name": "轻量枪托", "deltas": {"moveMult": 0.04, "recoilMult": 1.08}, "cost": 300},
	"stock_heavy": {"slot": "stock", "name": "稳定枪托", "deltas": {"recoilMult": 0.82, "moveMult": -0.05}, "cost": 350},
}

const SLOTS: Array = ["optic", "muzzle", "grip", "mag", "stock"]

# 内置武器定义
const BUILTIN_WEAPONS: Dictionary = {
	# ===================== 近战 =====================
	"fang": {
		"id": "fang", "name": "Fang 战术匕首", "slot": 0, "auto": true, "melee": true,
		"range": 2.4, "fireRate": 170, "damage": 42, "headshotMult": 1.0, "pellets": 1,
		"magSize": INF, "reserve": INF, "reloadTime": 0.0, "spread": 0.0, "adsSpread": 0.0,
		"recoil": 0.01, "moveMult": 1.06, "falloffNear": 1.5, "falloffFar": 2.4, "falloffMin": 0.9,
		"sound": "melee", "penetration": 0.0, "armorPen": 0.55, "loudness": 0.2,
		"desc": "轻快、跑刀首选。", "category": "melee",
	},
	"axe": {
		"id": "axe", "name": "Breacher 破拆斧", "slot": 0, "auto": false, "melee": true,
		"range": 2.6, "fireRate": 62, "damage": 95, "headshotMult": 1.0, "pellets": 1,
		"magSize": INF, "reserve": INF, "reloadTime": 0.0, "spread": 0.0, "adsSpread": 0.0,
		"recoil": 0.02, "moveMult": 0.98, "falloffNear": 2.0, "falloffFar": 2.6, "falloffMin": 0.85,
		"sound": "melee_heavy", "penetration": 0.0, "armorPen": 0.8, "loudness": 0.35,
		"desc": "一刀 95，慢但毁天灭地。", "category": "melee",
	},
	# ===================== 手枪 =====================
	"k9": {
		"id": "k9", "name": "K9 制式手枪", "slot": 1, "auto": false, "fireRate": 300,
		"damage": 32, "headshotMult": 1.8, "pellets": 1, "magSize": 12, "reserve": 48,
		"reloadTime": 1.4, "spread": 0.030, "adsSpread": 0.008, "recoil": 0.025, "moveMult": 1.0,
		"falloffNear": 12, "falloffFar": 55, "falloffMin": 0.45, "sound": "pistol",
		"penetration": 0.15, "armorPen": 0.5, "loudness": 0.8, "adsFov": 58,
		"desc": "免费配枪。稳定、可靠。", "category": "pistol", "cost": 400,
	},
	"pc": {
		"id": "pc", "name": "PC 紧凑手枪", "slot": 1, "auto": false, "fireRate": 400,
		"damage": 34, "headshotMult": 1.9, "pellets": 1, "magSize": 13, "reserve": 26,
		"reloadTime": 1.6, "spread": 0.028, "adsSpread": 0.010, "recoil": 0.022, "moveMult": 1.0,
		"falloffNear": 12, "falloffFar": 55, "falloffMin": 0.45, "sound": "pistol",
		"penetration": 0.15, "armorPen": 0.5, "loudness": 0.8, "adsFov": 56,
		"cost": 400, "model": "Pistol_Compact_East.glb",
		"desc": "射速更快，弹匣更小。", "category": "pistol",
	},
	"pf": {
		"id": "pf", "name": "PF 重型手枪", "slot": 1, "auto": false, "fireRate": 267,
		"damage": 62, "headshotMult": 2.1, "pellets": 1, "magSize": 7, "reserve": 35,
		"reloadTime": 2.2, "spread": 0.045, "adsSpread": 0.020, "recoil": 0.05, "moveMult": 1.0,
		"falloffNear": 15, "falloffFar": 60, "falloffMin": 0.60, "sound": "pistol_heavy",
		"penetration": 0.35, "armorPen": 0.75, "loudness": 1.0, "adsFov": 52,
		"cost": 700, "model": "Pistol_Full_East.glb",
		"desc": "两枪带走无甲，后坐力大。", "category": "pistol",
	},
	"rv": {
		"id": "rv", "name": "RV 战斗左轮", "slot": 1, "auto": false, "fireRate": 150,
		"damage": 92, "headshotMult": 2.4, "pellets": 1, "magSize": 6, "reserve": 24,
		"reloadTime": 2.8, "spread": 0.035, "adsSpread": 0.006, "recoil": 0.085, "moveMult": 0.96,
		"falloffNear": 22, "falloffFar": 70, "falloffMin": 0.65, "sound": "revolver",
		"penetration": 0.5, "armorPen": 0.85, "loudness": 1.15, "adsFov": 48,
		"cost": 1500,
		"desc": "一枪爆头的浪漫。开火间隔长。", "category": "pistol",
	},
	"mp9": {
		"id": "mp9", "name": "MP9 机关手枪", "slot": 1, "auto": true, "fireRate": 1000,
		"damage": 17, "headshotMult": 1.6, "pellets": 1, "magSize": 20, "reserve": 60,
		"reloadTime": 1.7, "spread": 0.055, "adsSpread": 0.020, "recoil": 0.018, "moveMult": 1.05,
		"falloffNear": 9, "falloffFar": 38, "falloffMin": 0.35, "sound": "pistol_auto",
		"penetration": 0.1, "armorPen": 0.4, "loudness": 0.85, "adsFov": 60,
		"cost": 1100,
		"desc": "副武器位的冲锋枪，近身压制。", "category": "pistol",
	},
	# ===================== 冲锋枪 =====================
	"vx9": {
		"id": "vx9", "name": "VX9 冲锋枪", "slot": 2, "auto": true, "fireRate": 900,
		"damage": 20, "headshotMult": 1.7, "pellets": 1, "magSize": 30, "reserve": 120,
		"reloadTime": 1.9, "spread": 0.045, "adsSpread": 0.012, "recoil": 0.016, "moveMult": 1.0,
		"falloffNear": 10, "falloffFar": 45, "falloffMin": 0.4, "sound": "smg",
		"penetration": 0.1, "armorPen": 0.45, "loudness": 0.9, "adsFov": 55,
		"desc": "万金油起手，弹道好控。", "category": "smg", "cost": 1300,
	},
	"sc": {
		"id": "sc", "name": "SC 紧凑冲锋枪", "slot": 2, "auto": true, "fireRate": 857,
		"damage": 22, "headshotMult": 1.8, "pellets": 1, "magSize": 30, "reserve": 120,
		"reloadTime": 2.0, "spread": 0.034, "adsSpread": 0.012, "recoil": 0.018, "moveMult": 1.0,
		"falloffNear": 10, "falloffFar": 45, "falloffMin": 0.4, "sound": "smg",
		"penetration": 0.1, "armorPen": 0.45, "loudness": 0.9, "adsFov": 50,
		"cost": 1300, "model": "SMG_Compact_East.glb",
		"desc": "更稳的一把，适合点射。", "category": "smg",
	},
	"sf": {
		"id": "sf", "name": "SF 高速冲锋枪", "slot": 2, "auto": true, "fireRate": 900,
		"damage": 22, "headshotMult": 1.6, "pellets": 1, "magSize": 50, "reserve": 100,
		"reloadTime": 2.3, "spread": 0.032, "adsSpread": 0.010, "recoil": 0.015, "moveMult": 1.0,
		"falloffNear": 8, "falloffFar": 40, "falloffMin": 0.35, "sound": "smg",
		"penetration": 0.1, "armorPen": 0.45, "loudness": 0.9, "adsFov": 52,
		"cost": 2350, "model": "SMG_Full_East.glb",
		"desc": "50 发大弹匣，扫射压制。", "category": "smg",
	},
	"pdw": {
		"id": "pdw", "name": "PDW-9 特种冲锋枪", "slot": 2, "auto": true, "fireRate": 780,
		"damage": 24, "headshotMult": 1.75, "pellets": 1, "magSize": 35, "reserve": 140,
		"reloadTime": 2.1, "spread": 0.026, "adsSpread": 0.008, "recoil": 0.014, "moveMult": 1.0,
		"falloffNear": 14, "falloffFar": 52, "falloffMin": 0.48, "sound": "smg",
		"penetration": 0.2, "armorPen": 0.55, "loudness": 0.85, "adsFov": 52,
		"cost": 2900,
		"desc": "冲锋枪里的精准异类，中距离可用。", "category": "smg",
	},
	# ===================== 步枪 =====================
	"arc17": {
		"id": "arc17", "name": "ARC-17 突击步枪", "slot": 2, "auto": true, "fireRate": 660,
		"damage": 28, "headshotMult": 1.8, "pellets": 1, "magSize": 30, "reserve": 120,
		"reloadTime": 2.2, "spread": 0.035, "adsSpread": 0.008, "recoil": 0.020, "moveMult": 0.9,
		"falloffNear": 15, "falloffFar": 65, "falloffMin": 0.45, "sound": "rifle",
		"penetration": 0.35, "armorPen": 0.65, "loudness": 1.0, "adsFov": 45,
		"desc": "生化模式免费主武器，均衡。", "category": "rifle", "cost": 2700,
	},
	"ra": {
		"id": "ra", "name": "RA 突击步枪", "slot": 2, "auto": true, "fireRate": 600,
		"damage": 34, "headshotMult": 2.5, "pellets": 1, "magSize": 30, "reserve": 90,
		"reloadTime": 2.4, "spread": 0.024, "adsSpread": 0.008, "recoil": 0.030, "moveMult": 0.9,
		"falloffNear": 20, "falloffFar": 80, "falloffMin": 0.60, "sound": "rifle",
		"penetration": 0.45, "armorPen": 0.7, "loudness": 1.05, "adsFov": 46,
		"cost": 2700, "model": "Rifle_Assault_East.glb",
		"desc": "爆头 2.5 倍，点射极强。", "category": "rifle",
	},
	"rb": {
		"id": "rb", "name": "RB 战斗步枪", "slot": 2, "auto": false, "fireRate": 350,
		"damage": 55, "headshotMult": 2.2, "pellets": 1, "magSize": 20, "reserve": 60,
		"reloadTime": 2.6, "spread": 0.020, "adsSpread": 0.006, "recoil": 0.045, "moveMult": 0.85,
		"falloffNear": 25, "falloffFar": 100, "falloffMin": 0.65, "sound": "rifle_heavy",
		"penetration": 0.6, "armorPen": 0.8, "loudness": 1.15, "adsFov": 40,
		"cost": 3200, "model": "Rifle_Battle_East.glb",
		"desc": "半自动大伤害，两枪带走。", "category": "rifle",
	},
	"ak": {
		"id": "ak", "name": "VK-47 突击步枪", "slot": 2, "auto": true, "fireRate": 600,
		"damage": 36, "headshotMult": 2.1, "pellets": 1, "magSize": 30, "reserve": 90,
		"reloadTime": 2.5, "spread": 0.040, "adsSpread": 0.011, "recoil": 0.042, "moveMult": 0.88,
		"falloffNear": 18, "falloffFar": 75, "falloffMin": 0.55, "sound": "rifle_heavy",
		"penetration": 0.55, "armorPen": 0.78, "loudness": 1.2, "adsFov": 44,
		"cost": 3000,
		"desc": "伤害高、后坐力大，压枪是门手艺。", "category": "rifle",
	},
	"dmr": {
		"id": "dmr", "name": "DM7 精确射手步枪", "slot": 2, "auto": false, "fireRate": 240,
		"damage": 68, "headshotMult": 2.6, "pellets": 1, "magSize": 10, "reserve": 50,
		"reloadTime": 2.6, "spread": 0.012, "adsSpread": 0.002, "recoil": 0.05, "moveMult": 0.84,
		"falloffNear": 40, "falloffFar": 140, "falloffMin": 0.75, "sound": "dmr",
		"penetration": 0.7, "armorPen": 0.9, "loudness": 1.2, "adsFov": 34,
		"cost": 4200,
		"desc": "中远距离的统治者，机动性差。", "category": "rifle",
	},
	# ===================== 霰弹枪 =====================
	"warden": {
		"id": "warden", "name": "Warden 霰弹枪", "slot": 2, "auto": false, "fireRate": 85,
		"damage": 13, "headshotMult": 1.4, "pellets": 8, "magSize": 8, "reserve": 40,
		"reloadTime": 2.8, "spread": 0.090, "adsSpread": 0.045, "recoil": 0.060, "moveMult": 0.82,
		"falloffNear": 8, "falloffFar": 28, "falloffMin": 0.30, "sound": "shotgun",
		"penetration": 0.05, "armorPen": 0.35, "loudness": 1.3, "adsFov": 52,
		"desc": "8 颗弹丸，贴脸一枪一个。", "category": "shotgun", "cost": 1800,
	},
	"sa": {
		"id": "sa", "name": "SA 自动霰弹枪", "slot": 2, "auto": true, "fireRate": 300,
		"damage": 18, "headshotMult": 1.4, "pellets": 7, "magSize": 7, "reserve": 32,
		"reloadTime": 2.9, "spread": 0.090, "adsSpread": 0.050, "recoil": 0.060, "moveMult": 0.82,
		"falloffNear": 8, "falloffFar": 28, "falloffMin": 0.30, "sound": "shotgun",
		"penetration": 0.05, "armorPen": 0.35, "loudness": 1.3, "adsFov": 48,
		"cost": 2000, "model": "Shotgun_Auto_East.glb",
		"desc": "全自动霰弹，清点神器。", "category": "shotgun",
	},
	"sp": {
		"id": "sp", "name": "SP 泵动霰弹枪", "slot": 2, "auto": false, "fireRate": 68,
		"damage": 18, "headshotMult": 1.4, "pellets": 7, "magSize": 5, "reserve": 32,
		"reloadTime": 3.2, "spread": 0.070, "adsSpread": 0.040, "recoil": 0.070, "moveMult": 0.85,
		"falloffNear": 9, "falloffFar": 30, "falloffMin": 0.35, "sound": "shotgun",
		"penetration": 0.05, "armorPen": 0.35, "loudness": 1.3, "adsFov": 45,
		"cost": 1050, "model": "Shotgun_Pump_East.glb",
		"desc": "便宜的近战之王。", "category": "shotgun",
	},
	"ksg": {
		"id": "ksg", "name": "KSG 双管霰弹", "slot": 2, "auto": false, "fireRate": 180,
		"damage": 16, "headshotMult": 1.4, "pellets": 10, "magSize": 2, "reserve": 24,
		"reloadTime": 2.4, "spread": 0.10, "adsSpread": 0.055, "recoil": 0.10, "moveMult": 0.84,
		"falloffNear": 7, "falloffFar": 24, "falloffMin": 0.25, "sound": "shotgun_heavy",
		"penetration": 0.05, "armorPen": 0.35, "loudness": 1.45, "adsFov": 50,
		"cost": 1400,
		"desc": "两发，但每发能清空走廊。", "category": "shotgun",
	},
	# ===================== 机枪 =====================
	"bruiser": {
		"id": "bruiser", "name": "Bruiser 轻机枪", "slot": 2, "auto": true, "fireRate": 720,
		"damage": 24, "headshotMult": 1.6, "pellets": 1, "magSize": 100, "reserve": 200,
		"reloadTime": 4.2, "spread": 0.050, "adsSpread": 0.016, "recoil": 0.022, "moveMult": 0.78,
		"falloffNear": 12, "falloffFar": 55, "falloffMin": 0.40, "sound": "lmg",
		"penetration": 0.55, "armorPen": 0.7, "loudness": 1.25, "adsFov": 48,
		"desc": "100 发，压制与穿墙。", "category": "lmg", "cost": 4200,
	},
	"minigun": {
		"id": "minigun", "name": "Vulcan 转管机枪", "slot": 2, "auto": true, "fireRate": 1200,
		"damage": 18, "headshotMult": 1.3, "pellets": 1, "magSize": 150, "reserve": 300,
		"reloadTime": 6.0, "spread": 0.070, "adsSpread": 0.028, "recoil": 0.014, "moveMult": 0.62,
		"falloffNear": 10, "falloffFar": 45, "falloffMin": 0.35, "sound": "minigun",
		"penetration": 0.4, "armorPen": 0.6, "loudness": 1.5, "adsFov": 55,
		"cost": 6000, "spinUp": 0.6,
		"desc": "转管预热 0.6 秒，之后是金属风暴。", "category": "lmg",
	},
	# ===================== 狙击 =====================
	"longshot": {
		"id": "longshot", "name": "Longshot 狙击枪", "slot": 2, "auto": false, "fireRate": 45,
		"damage": 120, "headshotMult": 2.2, "pellets": 1, "magSize": 5, "reserve": 25,
		"reloadTime": 3.2, "spread": 0.020, "adsSpread": 0.001, "recoil": 0.090, "moveMult": 0.72,
		"falloffNear": 30, "falloffFar": 200, "falloffMin": 0.75, "sound": "sniper",
		"penetration": 0.85, "armorPen": 0.95, "loudness": 1.4, "adsFov": 25,
		"desc": "栓动，一枪一个。", "category": "sniper", "cost": 4600,
	},
	"sm": {
		"id": "sm", "name": "SM 重型狙击枪", "slot": 2, "auto": false, "fireRate": 41,
		"damage": 115, "headshotMult": 4.0, "pellets": 1, "magSize": 5, "reserve": 30,
		"reloadTime": 3.6, "spread": 0.004, "adsSpread": 0.0005, "recoil": 0.090, "moveMult": 0.72,
		"falloffNear": 40, "falloffFar": 250, "falloffMin": 0.85, "sound": "sniper_heavy",
		"penetration": 0.95, "armorPen": 1.0, "loudness": 1.5, "adsFov": 18,
		"cost": 4750, "model": "Sniper_Material_East.glb",
		"desc": "8 倍镜，爆头 4 倍。", "category": "sniper",
	},
	"sr": {
		"id": "sr", "name": "SR 侦察狙击枪", "slot": 2, "auto": false, "fireRate": 60,
		"damage": 72, "headshotMult": 2.0, "pellets": 1, "magSize": 10, "reserve": 90,
		"reloadTime": 2.4, "spread": 0.012, "adsSpread": 0.002, "recoil": 0.055, "moveMult": 0.80,
		"falloffNear": 25, "falloffFar": 150, "falloffMin": 0.70, "sound": "sniper",
		"penetration": 0.7, "armorPen": 0.85, "loudness": 1.2, "adsFov": 28,
		"cost": 1700, "model": "Sniper_Rifle_East.glb",
		"desc": "半自动连狙，容错高。", "category": "sniper",
	},
	"railgun": {
		"id": "railgun", "name": "ARC 磁轨炮", "slot": 2, "auto": false, "fireRate": 28,
		"damage": 200, "headshotMult": 1.5, "pellets": 1, "magSize": 2, "reserve": 6,
		"reloadTime": 4.5, "spread": 0.0, "adsSpread": 0.0, "recoil": 0.12, "moveMult": 0.7,
		"falloffNear": 200, "falloffFar": 400, "falloffMin": 1.0, "sound": "railgun",
		"penetration": 1.0, "armorPen": 1.0, "loudness": 1.6, "adsFov": 30,
		"cost": 9000, "charge": 1.1,
		"desc": "蓄力 1.1 秒，穿透一切。昂贵。", "category": "sniper",
	},
	# ===================== 特种 =====================
	"taser": {
		"id": "taser", "name": "ZEUS 电击枪", "slot": 1, "auto": false, "fireRate": 60,
		"damage": 5, "headshotMult": 1.0, "pellets": 1, "magSize": 1, "reserve": 2,
		"reloadTime": 3.5, "spread": 0.02, "adsSpread": 0.02, "recoil": 0.0, "moveMult": 1.0,
		"falloffNear": 8, "falloffFar": 8, "falloffMin": 1.0, "sound": "taser",
		"penetration": 0.0, "armorPen": 0.0, "loudness": 0.6, "adsFov": 60,
		"stun": 3.0, "cost": 2000,
		"desc": "命中即定身 3 秒。", "category": "special",
	},
	"crossbow": {
		"id": "crossbow", "name": "X-Bow 战术弩", "slot": 2, "auto": false, "fireRate": 40,
		"damage": 110, "headshotMult": 1.6, "pellets": 1, "magSize": 1, "reserve": 12,
		"reloadTime": 2.0, "spread": 0.004, "adsSpread": 0.001, "recoil": 0.02, "moveMult": 0.95,
		"falloffNear": 60, "falloffFar": 120, "falloffMin": 0.8, "sound": "crossbow",
		"penetration": 0.5, "armorPen": 0.9, "loudness": 0.15, "adsFov": 40,
		"cost": 2400, "projectile": "bolt", "projectileSpeed": 90.0,
		"desc": "几乎无声，弹道有下坠。", "category": "special",
	},
	# ===================== 投掷物 =====================
	"thunder": {
		"id": "thunder", "name": "Thunder 破片手雷", "slot": 3, "auto": false,
		"projectile": "grenade", "fireRate": 55, "damage": 180, "headshotMult": 1.0,
		"pellets": 1, "magSize": 99, "reserve": 0, "reloadTime": 1.0, "spread": 0.0,
		"adsSpread": 0.0, "recoil": 0.0, "moveMult": 1.0, "falloffNear": 3, "falloffFar": 11,
		"falloffMin": 0.25, "sound": "throw", "loudness": 0.4, "radius": 11.0,
		"desc": "11 米范围，越近越痛。", "category": "grenade", "cost": 300,
	},
	"flashbang": {
		"id": "flashbang", "name": "M8 闪光弹", "slot": 3, "auto": false,
		"projectile": "flash", "fireRate": 55, "damage": 0, "headshotMult": 1.0,
		"pellets": 1, "magSize": 99, "reserve": 0, "reloadTime": 1.0, "spread": 0.0,
		"adsSpread": 0.0, "recoil": 0.0, "moveMult": 1.0, "falloffNear": 3, "falloffFar": 14,
		"falloffMin": 0.2, "sound": "throw", "loudness": 0.5, "radius": 14.0, "flashTime": 3.6,
		"desc": "致盲正面 3.6 秒，背对可减免。", "category": "grenade", "cost": 200,
	},
	"smoke": {
		"id": "smoke", "name": "S9 烟雾弹", "slot": 3, "auto": false,
		"projectile": "smoke", "fireRate": 55, "damage": 0, "headshotMult": 1.0,
		"pellets": 1, "magSize": 99, "reserve": 0, "reloadTime": 1.0, "spread": 0.0,
		"adsSpread": 0.0, "recoil": 0.0, "moveMult": 1.0, "falloffNear": 3, "falloffFar": 8,
		"falloffMin": 0.2, "sound": "throw", "loudness": 0.4, "radius": 5.5, "smokeTime": 18.0,
		"desc": "18 秒烟墙，阻断所有视线。", "category": "grenade", "cost": 300,
	},
	"incendiary": {
		"id": "incendiary", "name": "F2 燃烧弹", "slot": 3, "auto": false,
		"projectile": "fire", "fireRate": 55, "damage": 22, "headshotMult": 1.0,
		"pellets": 1, "magSize": 99, "reserve": 0, "reloadTime": 1.0, "spread": 0.0,
		"adsSpread": 0.0, "recoil": 0.0, "moveMult": 1.0, "falloffNear": 3, "falloffFar": 9,
		"falloffMin": 0.3, "sound": "throw", "loudness": 0.5, "radius": 6.0, "fireTime": 8.0,
		"desc": "8 秒火墙，每秒灼烧。", "category": "grenade", "cost": 500,
	},
	"decoy": {
		"id": "decoy", "name": "D3 诱饵弹", "slot": 3, "auto": false,
		"projectile": "decoy", "fireRate": 55, "damage": 0, "headshotMult": 1.0,
		"pellets": 1, "magSize": 99, "reserve": 0, "reloadTime": 1.0, "spread": 0.0,
		"adsSpread": 0.0, "recoil": 0.0, "moveMult": 1.0, "falloffNear": 3, "falloffFar": 8,
		"falloffMin": 0.2, "sound": "throw", "loudness": 0.4, "decoyTime": 15.0,
		"desc": "模拟枪声，骗 bot 与人类。", "category": "grenade", "cost": 150,
	},
}

const CATEGORY_ORDER: Array = ["rifle", "smg", "shotgun", "sniper", "lmg", "pistol", "melee", "special", "grenade"]
const CATEGORY_LABEL: Dictionary = {
	"rifle": "步枪", "smg": "冲锋枪", "shotgun": "霰弹枪", "sniper": "狙击枪",
	"lmg": "机枪", "pistol": "手枪", "melee": "近战", "special": "特种", "grenade": "投掷物",
}


# 尸爪武器定义（运行时生成）
static func zombie_claw_def() -> Dictionary:
	return {
		"id": "zclaw", "name": "尸爪", "slot": 0, "auto": true, "melee": true,
		"range": 2.3, "fireRate": 68, "damage": 60, "headshotMult": 1.0, "pellets": 1,
		"magSize": INF, "reserve": INF, "reloadTime": 0.0, "spread": 0.0, "adsSpread": 0.0,
		"recoil": 0.0, "moveMult": 1.0, "falloffNear": 2.3, "falloffFar": 2.3, "falloffMin": 1.0,
		"sound": "melee", "penetration": 0.0, "armorPen": 0.3, "loudness": 0.3,
		"category": "melee", "desc": "感染者的爪子。",
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
	var t: float = (dist - near) / maxf(0.001, far - near)
	return float(def.damage) * (1.0 - t * (1.0 - min_val))


## 弹道散布：基础散布 + 移动惩罚 + 连发累积，ADS 时按 adsSpread 收敛
static func effective_spread(def: Dictionary, ads: bool, move_speed: float, shots_fired: int = 0) -> float:
	var base: float = float(def.get("adsSpread", 0.0)) if ads else float(def.get("spread", 0.02))
	var move_pen: float = clampf(move_speed / 5.5, 0.0, 1.4) * (0.012 if ads else 0.03)
	var bloom: float = minf(0.03, float(shots_fired) * 0.0018) * (0.35 if ads else 1.0)
	return base + move_pen + bloom


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


# ---------------- 配件 ----------------

static func attachments_for_slot(def: Dictionary, slot: String) -> Array:
	var out: Array = []
	var allowed: Array = def.get("attach", [])
	for aid in ATTACHMENTS:
		var a: Dictionary = ATTACHMENTS[aid]
		if str(a.slot) != slot:
			continue
		if not allowed.is_empty() and not allowed.has(aid):
			continue
		out.append({"id": aid, "def": a})
	return out


## 把配件数值合并进武器定义，返回新的 def（不修改原字典）
static func apply_attachments(base: Dictionary, ids: Array) -> Dictionary:
	var d: Dictionary = base.duplicate(true)
	var recoil_mult: float = 1.0
	var spread_mult: float = 1.0
	var hip_mult: float = 1.0
	var ads_fov_mult: float = 1.0
	var ads_spread_mult: float = 1.0
	var reload_mult: float = 1.0
	var ads_time_mult: float = 1.0
	var loud_mult: float = 1.0
	var dmg_mult: float = 1.0
	var flash_mult: float = 1.0
	var mag_add: int = 0
	var move_add: float = 0.0
	for aid in ids:
		if not ATTACHMENTS.has(aid):
			continue
		var dl: Dictionary = ATTACHMENTS[aid].get("deltas", {})
		recoil_mult *= float(dl.get("recoilMult", 1.0))
		spread_mult *= float(dl.get("spreadMult", 1.0))
		hip_mult *= float(dl.get("hipSpreadMult", 1.0))
		ads_fov_mult *= float(dl.get("adsFovMult", 1.0))
		ads_spread_mult *= float(dl.get("adsSpreadMult", 1.0))
		reload_mult *= float(dl.get("reloadTimeMult", 1.0))
		ads_time_mult *= float(dl.get("adsTimeMult", 1.0))
		loud_mult *= float(dl.get("loudnessMult", 1.0))
		dmg_mult *= float(dl.get("damageMult", 1.0))
		flash_mult *= float(dl.get("flashMult", 1.0))
		mag_add += int(dl.get("magSizeAdd", 0))
		move_add += float(dl.get("moveMult", 0.0))
	d.recoil = float(base.get("recoil", 0.02)) * recoil_mult
	d.spread = float(base.get("spread", 0.02)) * spread_mult * hip_mult
	d.adsSpread = float(base.get("adsSpread", 0.01)) * spread_mult * ads_spread_mult
	d.reloadTime = float(base.get("reloadTime", 2.0)) * reload_mult
	d.loudness = float(base.get("loudness", 1.0)) * loud_mult
	d.damage = float(base.get("damage", 10)) * dmg_mult
	d.magSize = float(base.get("magSize", 30)) + float(mag_add)
	d.moveMult = clampf(float(base.get("moveMult", 1.0)) + move_add, 0.5, 1.2)
	if base.has("adsFov"):
		d.adsFov = float(base.adsFov) * ads_fov_mult
	if base.has("adsTime"):
		d.adsTime = float(base.adsTime) * ads_time_mult
	d.flashScale = flash_mult
	d.attachments = ids.duplicate()
	return d


# ---------------- 运行时 ----------------

# 武器运行时状态（弹药、换弹、射速限速）
class WeaponRuntime:
	var def: Dictionary
	var base_def: Dictionary
	var attachments: Array = []
	var ammo: float
	var reserve: float
	var state: String = "ready" # ready | reloading | empty
	var next_fire_at: float = 0.0
	var reload_end: float = 0.0
	var shots_fired: int = 0
	var spin_up: float = 0.0     # 转管机枪预热进度 0..1
	var charge: float = 0.0      # 蓄力武器进度 0..1
	var skin: String = "default"

	func _init(d: Dictionary):
		base_def = d
		def = d
		ammo = float(d.get("magSize", 1))
		reserve = float(d.get("reserve", 0))

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
		shots_fired += 1
		if ammo == 0:
			state = "empty"
		return {"ok": true, "ammo": ammo}

	func start_reload(time: float) -> Dictionary:
		if state == "reloading" or reserve <= 0 or ammo >= def.magSize:
			return {"ok": false}
		state = "reloading"
		reload_end = time + float(def.reloadTime)
		shots_fired = 0
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

	func set_attachments(ids: Array) -> void:
		attachments = ids.duplicate()
		var old_mag: float = float(def.get("magSize", 1))
		def = WeaponData.apply_attachments(base_def, attachments)
		var new_mag: float = float(def.get("magSize", 1))
		if is_finite(new_mag) and is_finite(old_mag) and old_mag > 0.0:
			ammo = minf(new_mag, ammo * (new_mag / old_mag))

	func reset(time: float = 0.0) -> void:
		state = "ready"
		next_fire_at = time
		reload_end = 0.0
		shots_fired = 0
		spin_up = 0.0
		charge = 0.0
		var mag: Variant = def.get("magSize", 1)
		var res: Variant = def.get("reserve", 0)
		if typeof(mag) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(mag)):
			ammo = float(mag)
		if typeof(res) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(res)):
			reserve = float(res)

	## 紧凑序列化（用于快照，字段名极短）
	func to_wire() -> Dictionary:
		return {"i": str(def.get("id", "")), "a": int(ammo), "r": int(reserve), "s": state}

	func from_wire(w: Dictionary) -> void:
		ammo = float(w.get("a", ammo))
		reserve = float(w.get("r", reserve))
		state = str(w.get("s", "ready"))
