# Cine: cinematic screenshot tool for visual QA review loop.
#
# Usage:
#   Godot --path . res://scenes/cine.tscn -- --map=cinder --res=2560x1440 --seed=7
#   Godot --path . res://scenes/cine.tscn -- --map=all --shots=1,2,3 --res=1920x1080
#
# Writes PNG files to shots/{map}_{name}.png
extends Node

var _camera: Camera3D
var _world_root: Node3D
var _map_root: Node3D
var _map_id: String = "cinder"
var _res: Vector2i = Vector2i(2560, 1440)
var _seed: int = 7
var _shot_filter: Array = []
var _shot_idx: int = 0
var _shots: Array = []
var _settle: int = 0
var _max_settle: int = 50
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const FALLBACK_SHOTS: Dictionary = {
	"cinder": [
		{"name": "01_t_spawn", "pos": Vector3(0, 3.0, 26), "look": Vector3(0, 1.5, 0), "fov": 64},
	],
}


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--res="):
			var r: PackedStringArray = a.get_slice("=", 1).split("x")
			_res = Vector2i(int(r[0]), int(r[1]))
		elif a.begins_with("--seed="):
			_seed = int(a.get_slice("=", 1))
		elif a.begins_with("--shots="):
			for s in a.get_slice("=", 1).split(","):
				_shot_filter.append(int(s))
		elif a == "--nosettle":
			_max_settle = 4

	get_window().mode = Window.MODE_WINDOWED
	get_window().size = _res
	get_window().position = Vector2i(40, 40)
	_rng.seed = _seed

	_build_world()
	_collect_shots()
	_begin_next_shot()


func _build_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "World"
	add_child(_world_root)

	var map: Dictionary = MapData.get_map(_map_id)
	_world_root.add_child(GameEnvironment.create(map.get("sky", {})))
	var light_count: int = 0
	for prop in map.get("props", []):
		if prop.type == "light":
			light_count += 1
	print("[CINE] map=", _map_id, " theme=", str(map.get("sky", {}).get("zenith", "none")), " lights=", light_count)

	_map_root = Node3D.new()
	_map_root.name = "Map"
	_world_root.add_child(_map_root)
	MapBuilder.build(_map_root, map)

	# staged characters for life in the scenes
	_stage_characters(map)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 66.0
	_camera.near = 0.05
	_camera.far = 900.0
	_camera.current = true
	add_child(_camera)


func _stage_characters(map: Dictionary) -> void:
	var spots: Array = []
	match _map_id:
		"cinder":
			spots = [
				{"pos": Vector3(-19, 0, 2), "yaw": 0.4, "team": 1, "zombie": false},
				{"pos": Vector3(16, 0, 12), "yaw": -2.6, "team": 2, "zombie": false},
				{"pos": Vector3(-13, 0, 18), "yaw": 2.4, "team": 2, "zombie": false},
				{"pos": Vector3(-24, 0, -16), "yaw": 1.2, "team": 1, "zombie": false},
				{"pos": Vector3(21, 0, -24), "yaw": -1.8, "team": 2, "zombie": false},
				{"pos": Vector3(-2, 0, 25), "yaw": 0.2, "team": 2, "zombie": false},
			]
		"containment":
			spots = [
				{"pos": Vector3(-12, 0, 0), "yaw": 0.3, "team": 1, "zombie": false},
				{"pos": Vector3(0, 0, 6), "yaw": -2.5, "team": 1, "zombie": true},
				{"pos": Vector3(12, 0, 4), "yaw": 2.2, "team": 2, "zombie": false},
			]
		"obsidian":
			spots = [
				{"pos": Vector3(-10, 0, 6), "yaw": 0.4, "team": 1, "zombie": false},
				{"pos": Vector3(10, 0, -4), "yaw": 2.6, "team": 2, "zombie": false},
				{"pos": Vector3(20, 3.2, 14), "yaw": -2.2, "team": 2, "zombie": false},
			]
	for s in spots:
		var root: Node3D = CharacterFactory.build(s.team, s.zombie)
		root.position = s.pos + Vector3(0, 0.0, 0)
		root.rotation.y = s.yaw
		_map_root.add_child(root)
		root.set_meta("cinestage", true)


func _collect_shots() -> void:
	_shots = []
	if _map_id == "all":
		for mid in ["cinder", "containment", "obsidian"]:
			var map: Dictionary = MapData.get_map(mid)
			for s in map.get("shots", FALLBACK_SHOTS.get(mid, [])):
				_shots.append({"name": "%s_%s" % [mid, s.name], "pos": Vector3(s.pos), "look": Vector3(s.look), "fov": float(s.get("fov", 64.0)), "map": mid})
		if not _shot_filter.is_empty():
			var filtered: Array = []
			for i in _shot_filter:
				if i >= 1 and i <= _shots.size():
					filtered.append(_shots[i - 1])
			_shots = filtered
		return
	var map2: Dictionary = MapData.get_map(_map_id)
	var lib: Array = map2.get("shots", FALLBACK_SHOTS.get(_map_id, []))
	var i2: int = 0
	for s in lib:
		i2 += 1
		if _shot_filter.is_empty() or _shot_filter.has(i2):
			_shots.append({"name": s.name, "pos": Vector3(s.pos), "look": Vector3(s.look), "fov": float(s.get("fov", 64.0))})


func _begin_next_shot() -> void:
	if _shot_idx >= _shots.size():
		print("CINE: all shots captured")
		get_tree().quit()
		return
	var s: Dictionary = _shots[_shot_idx]
	if s.has("map") and s.map != _map_id:
		_map_id = s.map
		var map: Dictionary = MapData.get_map(_map_id)
		_world_root.queue_free()
		_build_world()
	_say("shot %d/%d: %s" % [_shot_idx + 1, _shots.size(), s.name])
	_camera.position = Vector3(s.pos)
	_camera.look_at(Vector3(s.look), Vector3.UP)
	_camera.fov = float(s.get("fov", 64.0))
	_settle = _max_settle


func _say(msg: String) -> void:
	print("[CINE] " + msg)


func _process(delta: float) -> void:
	_settle -= 1
	if _settle <= 0:
		_capture()
		_shot_idx += 1
		_begin_next_shot()


func _capture() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var path: String
	if _shots[_shot_idx].has("map"):
		path = "res://shots/%s.png" % _shots[_shot_idx].name
	else:
		path = "res://shots/%s_%s.png" % [_map_id, _shots[_shot_idx].name]
	img.save_png(path)
	_say("saved " + path)
