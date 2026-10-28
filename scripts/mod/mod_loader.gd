# Mod 加载器：扫描 → 校验 → 加载 → 注册 → 事件分发。
# 目录约定：
#   user://mods/<mod_id>/mod.json
#   user://mods/<mod_id>/main.gd          (入口，extends ModBase)
#   user://mods/<mod_id>/weapons/*.json   (自动注册武器)
#   user://mods/<mod_id>/assets/...       (贴图/音效/模型)
# 也支持 .pfmod 打包文件（由 tools/modc 生成，本质是 zip）。
extends Node

signal mods_ready()
signal mod_state_changed(id: String, state: String)

const API_VERSION: int = 2
const BUILTIN_DIR: String = "res://mods"
const USER_DIR: String = "user://mods"

var loaded: Dictionary = {}      # id -> {manifest, instance, ctx, dir}
var errors: Array = []
var enabled_ids: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	scan_all()
	_connect_bus()


# ---------------- 扫描 & 加载 ----------------

func scan_all() -> void:
	_scan_dir(BUILTIN_DIR, true)
	_scan_dir(USER_DIR, false)
	# 打包的 .pfmod
	_scan_pfmod(USER_DIR)
	mods_ready.emit()
	Bus.mods_changed.emit()


func _scan_dir(root: String, builtin: bool) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if d.current_is_dir() and not f.begins_with(".") and not f.begins_with("_"):
			load_mod(root.path_join(f), builtin)
		f = d.get_next()
	d.list_dir_end()


func _scan_pfmod(root: String) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if f.ends_with(".pfmod"):
			var path: String = root.path_join(f)
			var target: String = root.path_join(f.get_basename())
			if not DirAccess.dir_exists_absolute(target):
				DirAccess.make_dir_recursive_absolute(target)
				var zip := ZIPReader.new()
				if zip.open(path) == OK:
					for file in zip.get_files():
						var data: PackedByteArray = zip.read_file(file)
						var out: String = target.path_join(file)
						DirAccess.make_dir_recursive_absolute(out.get_base_dir())
						var fa := FileAccess.open(out, FileAccess.WRITE)
						if fa != null:
							fa.store_buffer(data)
							fa.close()
					zip.close()
			load_mod(target, false)
		f = d.get_next()
	d.list_dir_end()


func load_mod(dir: String, builtin: bool = false) -> bool:
	var man_path: String = dir.path_join("mod.json")
	if not FileAccess.file_exists(man_path):
		return false
	var txt: String = FileAccess.get_file_as_string(man_path)
	var man: Variant = JSON.parse_string(txt)
	if man == null or not (man is Dictionary):
		_fail(dir.get_file(), "mod.json 不是合法 JSON")
		return false
	var id: String = str(man.get("id", dir.get_file()))
	if id == "":
		_fail(dir.get_file(), "缺少 id")
		return false
	# API 版本
	var api: int = int(man.get("api", 1))
	if api > API_VERSION:
		_fail(id, "需要更新的游戏版本 (api %d > %d)" % [api, API_VERSION])
		return false
	# 依赖
	for dep in man.get("dependencies", []):
		var dep_id: String = str(dep) if not (dep is Dictionary) else str(dep.get("id", ""))
		if dep_id != "" and not loaded.has(dep_id):
			_fail(id, "缺少依赖: " + dep_id)
			return false
	var ctx := ModContext.new(id, dir, man)
	# 自动注册 weapons/*.json
	_auto_weapons(dir, ctx)
	# 入口脚本
	var inst: Variant = null
	var entry: String = str(man.get("entry", "main.gd"))
	var entry_path: String = dir.path_join(entry)
	if FileAccess.file_exists(entry_path):
		var script: Resource = load(entry_path)
		if script != null and script is GDScript:
			if script.can_instantiate():
				inst = script.new()
		if inst != null:
			if inst is ModBase:
				inst.ctx = ctx
				inst.setup(ctx)
			elif inst.has_method("setup"):
				inst.set("ctx", ctx)
				inst.call("setup", ctx)
			else:
				_fail(id, "入口脚本缺少 setup(ctx)")
				inst = null
	else:
		# 只有内容没有脚本也允许（纯数据 Mod）
		pass
	loaded[id] = {"manifest": man, "instance": inst, "ctx": ctx, "dir": dir, "builtin": builtin}
	if not enabled_ids.has(id):
		enabled_ids.append(id)
	print("[Mods] loaded %s v%s (%d content)" % [id, str(man.get("version", "0.0.0")), _content_count(dir)])
	mod_state_changed.emit(id, "loaded")
	Bus.mod_loaded.emit(id, man)
	return true


func _auto_weapons(dir: String, ctx: ModContext) -> void:
	var wdir: String = dir.path_join("weapons")
	var d := DirAccess.open(wdir)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if f.ends_with(".json"):
			var txt: String = FileAccess.get_file_as_string(wdir.path_join(f))
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				if parsed.has("weapons"):
					for w in parsed.weapons:
						ctx.add_weapon(w)
				else:
					ctx.add_weapon(parsed)
			elif parsed is Array:
				for w in parsed:
					ctx.add_weapon(w)
		f = d.get_next()
	d.list_dir_end()


func _content_count(dir: String) -> int:
	var n: int = 0
	for sub in ["weapons", "maps", "modes", "assets"]:
		var d := DirAccess.open(dir.path_join(sub))
		if d != null:
			n += d.get_files().size()
	return n


func _fail(id: String, reason: String) -> void:
	errors.append({"id": id, "reason": reason, "t": Time.get_ticks_msec()})
	push_warning("[Mods] %s: %s" % [id, reason])
	Bus.mod_failed.emit(id, reason)
	mod_state_changed.emit(id, "failed")


func unload(id: String) -> void:
	if not loaded.has(id):
		return
	var rec: Dictionary = loaded[id]
	if rec.instance != null and rec.instance.has_method("teardown"):
		rec.instance.call("teardown")
	loaded.erase(id)
	enabled_ids.erase(id)
	mod_state_changed.emit(id, "unloaded")
	Bus.mods_changed.emit()


func reload_all() -> void:
	for id in loaded.keys().duplicate():
		unload(id)
	WeaponDB.reload_all()
	scan_all()


# ---------------- 事件分发 ----------------

func _connect_bus() -> void:
	Bus.player_spawned.connect(func(pid, info): dispatch("player_spawn", {"id": pid, "info": info}))
	Bus.player_died.connect(func(v, k, info): dispatch("player_kill", {"victim": v, "killer": k, "info": info}))
	Bus.player_damaged.connect(func(v, a, amt, info): dispatch("player_damage", {"victim": v, "attacker": a, "amount": amt, "info": info}))
	Bus.weapon_fired.connect(func(pid, wid, info): dispatch("weapon_fire", {"id": pid, "weapon": wid, "info": info}))
	Bus.round_started.connect(func(info): dispatch("round_start", info))
	Bus.round_ended.connect(func(info): dispatch("round_end", info))
	Bus.match_started.connect(func(info): dispatch("match_start", info))
	Bus.match_ended.connect(func(info): dispatch("match_end", info))
	Bus.explosion_happened.connect(func(pos, r, o): dispatch("explosion", {"pos": pos, "radius": r, "owner": o}))


## 把事件分发给所有已加载 Mod 的钩子
func dispatch(event: String, payload: Dictionary) -> void:
	for id in loaded:
		var ctx: ModContext = loaded[id].ctx
		for cb in ctx.hooks_for(event):
			if cb is Callable and cb.is_valid():
				cb.call(payload)


func list() -> Array:
	var out: Array = []
	for id in loaded:
		var m: Dictionary = loaded[id].manifest
		out.append({
			"id": id, "name": str(m.get("name", id)), "version": str(m.get("version", "0.0.0")),
			"author": str(m.get("author", "")), "desc": str(m.get("desc", "")),
			"enabled": enabled_ids.has(id), "builtin": bool(loaded[id].builtin),
		})
	return out


func is_enabled(id: String) -> bool:
	return enabled_ids.has(id)


func set_enabled(id: String, on: bool) -> void:
	if on and not enabled_ids.has(id):
		enabled_ids.append(id)
	elif not on:
		enabled_ids.erase(id)
	mod_state_changed.emit(id, "enabled" if on else "disabled")


## 打开 Mod 目录（桌面端）
func open_mod_dir() -> void:
	var abs: String = ProjectSettings.globalize_path(USER_DIR)
	DirAccess.make_dir_recursive_absolute(abs)
	OS.shell_open(abs)
