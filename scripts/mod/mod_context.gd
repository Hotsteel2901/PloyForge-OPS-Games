# Mod 上下文：暴露给 Mod 脚本的唯一 API 表面。
# Mod 作者只需要 `extends ModBase` 或直接使用本类提供的方法。
class_name ModContext
extends RefCounted

var mod_id: String = ""
var mod_dir: String = ""
var manifest: Dictionary = {}
var _hooks: Dictionary = {}
var _store: Dictionary = {}
var _log_lines: Array = []


func _init(p_id: String, p_dir: String, p_manifest: Dictionary) -> void:
	mod_id = p_id
	mod_dir = p_dir
	manifest = p_manifest


# ---------------- 注册 API ----------------

## 注册一把武器。字段见 docs/MODDING.md；返回是否成功。
func add_weapon(def: Dictionary) -> bool:
	var d: Dictionary = def.duplicate(true)
	if not d.has("id"):
		d.id = "%s_%s" % [mod_id, str(d.get("name", "weapon")).to_lower().replace(" ", "_")]
	d["mod"] = mod_id
	var ok: bool = WeaponDB.register(d)
	_log("register weapon: %s -> %s" % [str(d.id), str(ok)])
	if ok:
		Bus.mod_loaded.emit(mod_id, {"weapon": d.id})
	return ok


## 注册一张地图。支持「极简描述」，自动生成碰撞体与导航。
## spec: { name, size:[w,h], boxes:[{x,z,sx,sz,h,y,type}], spawns:{CT:[{x,z,yaw}],T:[...]}, sites:[...] }
func add_map(id: String, spec: Dictionary) -> bool:
	var map_id: String = "%s_%s" % [mod_id, id]
	var m: Dictionary = ModMapBuilder.build(map_id, spec)
	if m.is_empty():
		_log("register map failed: " + id)
		return false
	var ok: bool = MapData.register_map(map_id, m)
	_log("register map: %s -> %s" % [map_id, str(ok)])
	if ok:
		Bus.mod_loaded.emit(mod_id, {"map": map_id})
	return ok


## 注册一个自定义模式。factory 返回一个 ModeBase 实例。
func add_mode(meta: Dictionary, factory: Callable) -> bool:
	var m: Dictionary = meta.duplicate(true)
	if not m.has("id"):
		return false
	m["id"] = "%s_%s" % [mod_id, str(m.id)]
	m["mod"] = mod_id
	ModeRegistry.register(m, factory)
	_log("register mode: " + str(m.id))
	Bus.mod_loaded.emit(mod_id, {"mode": m.id})
	return true


## 注册一条音效（wav/ogg 相对路径）
func add_sound(name: String, relative_path: String) -> bool:
	var path: String = asset(relative_path)
	if not ResourceLoader.exists(path):
		_log("sound missing: " + path)
		return false
	Sfx.register_custom(name, path)
	return true


# ---------------- 事件钩子 ----------------

## 订阅游戏事件。事件名见 docs/MODDING.md#事件表
func on(event: String, cb: Callable) -> void:
	if not _hooks.has(event):
		_hooks[event] = []
	_hooks[event].append(cb)


func hooks_for(event: String) -> Array:
	return _hooks.get(event, [])


## 主动触发自定义事件（供其它 Mod 监听）
func emit(event: String, payload: Dictionary = {}) -> void:
	Mods.dispatch("mod:" + event, payload)


# ---------------- 工具 ----------------

## 解析 Mod 目录内的资源路径
func asset(rel: String) -> String:
	if rel.begins_with("res://") or rel.begins_with("user://"):
		return rel
	return mod_dir.path_join(rel)


func log(msg: String) -> void:
	print("[Mod:%s] %s" % [mod_id, msg])
	_log(msg)


func warn(msg: String) -> void:
	push_warning("[Mod:%s] %s" % [mod_id, msg])
	_log("WARN " + msg)


## Mod 私有持久化存储（user://mods_data/<id>.cfg）
func store_get(key: String, default: Variant = null) -> Variant:
	if _store.is_empty():
		_load_store()
	return _store.get(key, default)


func store_set(key: String, value: Variant) -> void:
	_store[key] = value
	var cfg := ConfigFile.new()
	for k in _store:
		cfg.set_value("data", k, _store[k])
	DirAccess.make_dir_recursive_absolute("user://mods_data")
	cfg.save("user://mods_data/%s.cfg" % mod_id)


func _load_store() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://mods_data/%s.cfg" % mod_id) == OK:
		for k in cfg.get_section_keys("data"):
			_store[k] = cfg.get_value("data", k)


func _log(msg: String) -> void:
	_log_lines.append({"t": Time.get_ticks_msec(), "m": msg})
	if _log_lines.size() > 200:
		_log_lines.remove_at(0)


# ---------------- 便捷构造 ----------------

## 快速造一把枪（省略大量默认字段）
func quick_weapon(id: String, name: String, damage: float, fire_rate: int, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"id": "%s_%s" % [mod_id, id],
		"name": name, "slot": 2, "auto": true, "damage": damage, "fireRate": fire_rate,
		"magSize": 30, "reserve": 90, "reloadTime": 2.0, "spread": 0.03, "adsSpread": 0.01,
		"recoil": 0.02, "headshotMult": 1.8, "sound": "rifle", "category": "rifle",
		"falloffNear": 15.0, "falloffFar": 60.0, "falloffMin": 0.45, "cost": 2500,
	}
	for k in opts:
		d[k] = opts[k]
	return d


## 快速造一张竞技图（对称双出生点 + 中路掩体）
func quick_map(id: String, name: String, size: float = 50.0, site_count: int = 2) -> bool:
	var half: float = size * 0.5
	var spec: Dictionary = {
		"name": name,
		"size": [size, size],
		"boxes": [
			{"x": 0, "z": -half, "sx": size, "sz": 1, "h": 5},
			{"x": 0, "z": half, "sx": size, "sz": 1, "h": 5},
			{"x": -half, "z": 0, "sx": 1, "sz": size, "h": 5},
			{"x": half, "z": 0, "sx": 1, "sz": size, "h": 5},
			{"x": 0, "z": 0, "sx": 6, "sz": 6, "h": 2.2},
		],
		"spawns": {
			"CT": [{"x": 0, "z": half - 6, "yaw": 0.0}],
			"T": [{"x": 0, "z": -half + 6, "yaw": PI}],
			"HUMAN": [{"x": 0, "z": half - 6, "yaw": 0.0}],
			"ZOMBIE": [{"x": 0, "z": -half + 6, "yaw": PI}],
		},
		"sites": [],
	}
	for i in site_count:
		var ang: float = TAU * float(i) / float(maxi(1, site_count))
		spec.sites.append({
			"id": "ABCD"[i % 4],
			"x": cos(ang) * half * 0.55, "z": sin(ang) * half * 0.55,
			"radius": 4.0, "name": "包点 " + "ABCD"[i % 4],
		})
	return add_map(id, spec)
