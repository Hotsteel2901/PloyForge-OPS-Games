# 模式注册表：UI 列表 + 工厂。Mod 可注册自定义模式（继承 ModeBase）。
class_name ModeRegistry
extends RefCounted

const BUILTIN: Array = [
	{"id": "defusal", "label": "拆弹模式", "short": "DEFUSAL", "desc": "T 安放炸弹，CT 拆除。五五开的经济博弈。", "min": 2, "max": 12, "color": "ff8b3d", "tag": "竞技"},
	{"id": "tdm", "label": "团队死斗", "short": "TDM", "desc": "两支队伍对枪，先到 100 击杀。", "min": 2, "max": 12, "color": "5a9dff", "tag": "休闲"},
	{"id": "ffa", "label": "自由混战", "short": "FFA", "desc": "人人都是敌人，个人秀场。", "min": 2, "max": 12, "color": "ffd83d", "tag": "休闲"},
	{"id": "gungame", "label": "军备竞赛", "short": "GUN", "desc": "每击杀升级一把枪，匕首收尾。", "min": 2, "max": 12, "color": "c08bff", "tag": "休闲"},
	{"id": "koth", "label": "占点模式", "short": "KOTH", "desc": "争夺中央据点，站住就加分。", "min": 2, "max": 12, "color": "7ddc8f", "tag": "目标"},
	{"id": "ctf", "label": "夺旗模式", "short": "CTF", "desc": "偷旗回基地，团队配合至上。", "min": 4, "max": 12, "color": "54d6d6", "tag": "目标"},
	{"id": "zombie", "label": "生化模式", "short": "ZOMBIE", "desc": "感染扩散，末段琉璃决战。", "min": 2, "max": 12, "color": "b05a2a", "tag": "PVE"},
	{"id": "survival", "label": "生存模式", "short": "SURV", "desc": "无尽波次，能撑多久？", "min": 1, "max": 8, "color": "ff5a7d", "tag": "PVE"},
]

static var _custom: Dictionary = {}


static func register(def: Dictionary, factory: Callable) -> void:
	var id: String = str(def.get("id", ""))
	if id == "":
		return
	_custom[id] = {"meta": def, "factory": factory}


static func unregister(id: String) -> void:
	_custom.erase(id)


static func all() -> Array:
	var out: Array = BUILTIN.duplicate(true)
	for id in _custom:
		out.append(_custom[id].meta)
	return out


static func meta(id: String) -> Dictionary:
	for m in BUILTIN:
		if str(m.id) == id:
			return m
	if _custom.has(id):
		return _custom[id].meta
	return {}


static func exists(id: String) -> bool:
	return id in ["defusal", "tdm", "ffa", "gungame", "koth", "ctf", "zombie", "survival"] or _custom.has(id)


static func create(id: String) -> ModeBase:
	if _custom.has(id):
		var f: Callable = _custom[id].factory
		if f.is_valid():
			var m: Variant = f.call()
			if m is ModeBase:
				return m
	match id:
		"defusal":
			return ModesClassic.Defusal.new()
		"zombie":
			return ModesClassic.Zombie.new()
		"tdm":
			return ModesExtra.TDM.new()
		"ffa":
			return ModesExtra.FFA.new()
		"gungame":
			return ModesExtra.GunGame.new()
		"koth":
			return ModesExtra.KOTH.new()
		"ctf":
			return ModesExtra.CTF.new()
		"survival":
			return ModesExtra.Survival.new()
	return ModesClassic.Defusal.new()


## 该模式适合哪张地图（地图未声明 modes 时视为通用）
static func map_supports(map_data: Dictionary, mode_id: String) -> bool:
	var modes: Array = map_data.get("modes", [])
	if modes.is_empty():
		return true
	return mode_id in modes
