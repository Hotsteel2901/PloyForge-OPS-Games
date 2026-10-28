# 武器注册表（v2）：内置 + JSON 数据包 + Mod 注入。
# 设计目标：Mod 作者只需丢一个 JSON 描述武器，运行时即可用、可买、可 AI 装备。
extends Node

signal registry_changed()

const REQUIRED_FIELDS: Array = ["id", "name", "slot", "damage", "fireRate"]

var _registry: Dictionary = {}
var _sources: Dictionary = {}   # id -> "builtin" | "data:path" | "mod:modid"
var _loaded: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_all()


func reload_all() -> void:
	_registry.clear()
	_sources.clear()
	# 1) 内置
	for id in WeaponData.BUILTIN_WEAPONS:
		_register_internal(WeaponData.BUILTIN_WEAPONS[id], "builtin")
	# 2) 随包数据（res://data/weapons/*.json）
	_load_dir("res://data/weapons", "data")
	# 3) 用户 Mod（user://mods/<mod>/weapons/*.json）——由 ModLoader 进一步接管热重载
	_load_dir("user://mods", "mod", true)
	_loaded = true
	registry_changed.emit()


func _load_dir(path: String, kind: String, recursive: bool = false) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if d.current_is_dir():
			if recursive and not f.begins_with("."):
				var sub: DirAccess = DirAccess.open(path.path_join(f))
				if sub != null:
					_load_dir(path.path_join(f).path_join("weapons"), kind + ":" + f)
			f = d.get_next()
			continue
		if f.ends_with(".json"):
			_load_json(path.path_join(f), kind)
		f = d.get_next()
	d.list_dir_end()


func _load_json(file: String, kind: String) -> void:
	var txt: String = FileAccess.get_file_as_string(file)
	if txt.is_empty():
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_warning("[WeaponDB] JSON 解析失败: %s" % file)
		return
	if parsed is Dictionary:
		# 支持 { "weapons": [...] } 或单个武器对象
		if parsed.has("weapons"):
			for w in parsed.weapons:
				if w is Dictionary:
					_register_internal(w, kind + ":" + file)
		else:
			_register_internal(parsed, kind + ":" + file)
	elif parsed is Array:
		for w in parsed:
			if w is Dictionary:
				_register_internal(w, kind + ":" + file)


func _register_internal(raw: Dictionary, source: String) -> bool:
	var def: Dictionary = normalize(raw)
	if def.is_empty():
		return false
	var id: String = str(def.id)
	if id == "":
		return false
	_registry[id] = def
	_sources[id] = source
	return true


## 校验并补全默认值；失败返回空字典
func normalize(raw: Dictionary) -> Dictionary:
	var d: Dictionary = raw.duplicate(true)
	for f in REQUIRED_FIELDS:
		if not d.has(f):
			push_warning("[WeaponDB] 缺少字段 %s: %s" % [f, str(raw.get("id", "?"))])
			return {}
	var defaults: Dictionary = {
		"auto": false, "melee": false, "pellets": 1, "magSize": 30, "reserve": 90,
		"reloadTime": 2.0, "spread": 0.03, "adsSpread": 0.01, "recoil": 0.02, "moveMult": 1.0,
		"falloffNear": 15.0, "falloffFar": 60.0, "falloffMin": 0.45, "headshotMult": 1.5,
		"sound": "rifle", "penetration": 0.2, "armorPen": 0.5, "loudness": 1.0,
		"category": "rifle", "cost": 2000, "desc": "", "projectile": "", "range": 2.4,
		"adsFov": 50.0, "adsTime": 0.18, "flashScale": 1.0, "attachments": [],
	}
	for k in defaults:
		if not d.has(k):
			d[k] = defaults[k]
	# 布尔/数值类型兜底，避免 Mod 写字符串导致运行时崩
	d.slot = int(d.slot)
	d.damage = float(d.damage)
	d.fireRate = int(d.fireRate)
	d.headshotMult = float(d.headshotMult)
	d.pellets = maxi(1, int(d.pellets))
	if d.pellets > 32:
		d.pellets = 32
	# 唯一冲突提示
	if _registry.has(str(d.id)) and str(_sources.get(str(d.id), "")) == "builtin":
		print("[WeaponDB] Mod 覆盖内置武器: %s" % d.id)
	return d


## 供 Mod 调用：注册/覆盖一把武器
func register(raw: Dictionary) -> bool:
	var ok: bool = _register_internal(raw, "runtime")
	if ok:
		registry_changed.emit()
	return ok


func get_def(id: String) -> Dictionary:
	return _registry.get(id, {})


func has(id: String) -> bool:
	return _registry.has(id)


func all() -> Dictionary:
	return _registry


func source_of(id: String) -> String:
	return str(_sources.get(id, ""))


func ids() -> Array:
	return _registry.keys()


func by_slot(slot: int) -> Array:
	var out: Array = []
	for id in _registry:
		var d: Dictionary = _registry[id]
		if int(d.slot) == slot:
			out.append(d)
	out.sort_custom(func(a, b): return int(a.get("cost", 0)) < int(b.get("cost", 0)))
	return out


func by_category(cat: String) -> Array:
	var out: Array = []
	for id in _registry:
		var d: Dictionary = _registry[id]
		if str(d.get("category", "")) == cat:
			out.append(d)
	return out


## 给 Bot / 随机装备用：按预算挑一把主武器
func pick_primary_for_budget(money: int, rng: RandomNumberGenerator = null) -> String:
	var pool: Array = []
	for id in _registry:
		var d: Dictionary = _registry[id]
		if int(d.slot) != 2:
			continue
		if d.get("melee", false) or str(d.get("projectile", "")) != "":
			continue
		if int(d.get("cost", 9999)) <= money:
			pool.append(id)
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return str(pool[0])
	# 偏好中高价，但不总是最贵
	var idx: int = 0
	if rng != null:
		idx = rng.randi_range(0, pool.size() - 1)
	else:
		idx = randi() % pool.size()
	return str(pool[idx])


## 校验一把武器的字段完整性，返回错误列表（Mod 编译器 / 编辑器用）
func validate(raw: Dictionary) -> Array:
	var errs: Array = []
	for f in REQUIRED_FIELDS:
		if not raw.has(f):
			errs.append("缺少字段: " + f)
	if raw.has("slot") and int(raw.slot) < 0 or int(raw.get("slot", -1)) > 3:
		errs.append("slot 必须在 0..3")
	if raw.has("damage") and float(raw.damage) < 0:
		errs.append("damage 不能为负")
	if raw.has("fireRate") and int(raw.fireRate) <= 0:
		errs.append("fireRate 必须 > 0")
	if raw.has("pellets") and int(raw.pellets) > 32:
		errs.append("pellets 上限 32")
	if raw.has("magSize") and float(raw.magSize) <= 0:
		errs.append("magSize 必须 > 0")
	return errs


# ---------------- 统计面板（给 UI 画雷达/条形图） ----------------

## 归一化到 0..1 的五维属性，用于 UI 对比
func stat_bars(def: Dictionary) -> Dictionary:
	var dmg: float = clampf(float(def.get("damage", 20)) * float(def.get("pellets", 1)) / 160.0, 0.0, 1.0)
	var rpm: float = clampf(float(def.get("fireRate", 600)) / 1200.0, 0.0, 1.0)
	var acc: float = 1.0 - clampf(float(def.get("adsSpread", 0.01)) / 0.12, 0.0, 1.0)
	var ctrl: float = 1.0 - clampf(float(def.get("recoil", 0.02)) / 0.12, 0.0, 1.0)
	var mob: float = clampf((float(def.get("moveMult", 1.0)) - 0.55) / 0.5, 0.0, 1.0)
	return {"damage": dmg, "rate": rpm, "accuracy": acc, "control": ctrl, "mobility": mob}
