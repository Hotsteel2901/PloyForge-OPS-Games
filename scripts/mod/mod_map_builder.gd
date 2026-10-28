# 把「极简地图描述」编译成引擎可用的地图字典（碰撞体 + 装饰 + 导航 + 出生点）。
# 让 Mod 作者只写几十行 JSON 就能得到一张可玩的地图。
class_name ModMapBuilder
extends RefCounted


## spec:
## {
##   name: String,
##   size: [w, h] 或 float,
##   theme: {sky:{...}, ...},             # 可选，缺省用通用黄昏主题
##   boxes: [ {x,z,sx,sz,h, y=0, type="crate"} ],
##   spawns: { CT:[{x,z,yaw}], T:[...], HUMAN:[...], ZOMBIE:[...] },
##   sites: [ {id,x,z,radius} ],
##   ammo: [ {x,z,respawn=20} ], health: [...]
## }
static func build(map_id: String, spec: Dictionary) -> Dictionary:
	var name: String = str(spec.get("name", map_id))
	var sz: Array = spec.get("size", [60, 60])
	var w: float = float(sz[0]) if sz.size() > 0 else 60.0
	var h: float = float(sz[1]) if sz.size() > 1 else w
	var half_w: float = w * 0.5
	var half_h: float = h * 0.5

	var colliders: Array = []
	var deco: Array = []

	# 地面
	colliders.append({"min": Vector3(-half_w - 10, -1.0, -half_h - 10), "max": Vector3(half_w + 10, 0.0, half_h + 10), "type": "floor"})
	# 边界墙
	var th: float = 1.0
	var wh: float = 7.0
	colliders.append(_wall(-half_w, -half_h, half_w, -half_h + th, wh))
	colliders.append(_wall(-half_w, half_h - th, half_w, half_h, wh))
	colliders.append(_wall(-half_w, -half_h, -half_w + th, half_h, wh))
	colliders.append(_wall(half_w - th, -half_h, half_w, half_h, wh))

	# 用户方块
	for b in spec.get("boxes", []):
		var bx: float = float(b.get("x", 0.0))
		var bz: float = float(b.get("z", 0.0))
		var sx: float = float(b.get("sx", 2.0))
		var sz2: float = float(b.get("sz", 2.0))
		var bh: float = float(b.get("h", 3.0))
		var by: float = float(b.get("y", 0.0))
		var type: String = str(b.get("type", "crate"))
		if type == "wall" or type == "crate":
			colliders.append({
				"min": Vector3(bx - sx * 0.5, by, bz - sz2 * 0.5),
				"max": Vector3(bx + sx * 0.5, by + bh, bz + sz2 * 0.5),
				"type": "wall" if type == "wall" else "crate",
			})
		# 装饰（按比例缩放，控制数量）
		var count: int = 1
		if sx > 6.0 or sz2 > 6.0:
			count = int(clampf(sx * sz2 / 30.0, 1.0, 6.0))
		for i in count:
			var ox: float = 0.0
			var oz: float = 0.0
			if count > 1:
				ox = (float(i) / float(count - 1) - 0.5) * (sx - 1.0)
			deco.append({
				"type": "crate" if type != "barrel" else "barrel",
				"pos": Vector3(bx + ox, by, bz + oz),
				"rot": 0.0,
				"scale": Vector3(sx / count * 0.9, bh, sz2 * 0.9),
			})

	# 出生点（缺省回退到两端）
	var spawns: Dictionary = {}
	var raw_spawns: Dictionary = spec.get("spawns", {})
	if raw_spawns.is_empty():
		raw_spawns = {
			"CT": [{"x": 0.0, "z": half_h - 6.0, "yaw": 0.0}],
			"T": [{"x": 0.0, "z": -half_h + 6.0, "yaw": PI}],
		}
	for key in raw_spawns:
		var arr: Array = []
		for s in raw_spawns[key]:
			arr.append({"x": float(s.get("x", 0.0)), "z": float(s.get("z", 0.0)), "y": float(s.get("y", 0.05)), "yaw": float(s.get("yaw", 0.0))})
		spawns[key] = arr
	if not spawns.has("HUMAN"):
		spawns["HUMAN"] = spawns.get("CT", [{"x": 0.0, "z": 0.0, "yaw": 0.0}])
	if not spawns.has("ZOMBIE"):
		spawns["ZOMBIE"] = spawns.get("T", spawns["HUMAN"])

	# 包点
	var sites: Array = []
	for s in spec.get("sites", []):
		var col := Color("ffcf4a")
		sites.append({
			"id": str(s.get("id", "A")), "pos": Vector3(float(s.get("x", 0.0)), float(s.get("y", 0.0)), float(s.get("z", 0.0))),
			"radius": float(s.get("radius", 3.0)), "color": col,
		})
	# 生化/生存图不放包点，避免误导
	if sites.is_empty():
		for i in 2:
			var ang: float = PI * float(i) + PI * 0.5
			sites.append({
				"id": "AB"[i], "pos": Vector3(cos(ang) * half_w * 0.5, 0.0, sin(ang) * half_h * 0.5),
				"radius": 3.0, "color": Color("ffcf4a") if i == 0 else Color("5fd0ff"),
			})

	var ammo: Array = []
	for a in spec.get("ammo", []):
		ammo.append({"pos": Vector3(float(a.get("x", 0.0)), float(a.get("y", 0.0)), float(a.get("z", 0.0))), "respawn": float(a.get("respawn", 20))})
	if ammo.is_empty():
		ammo = [
			{"pos": Vector3(-half_w * 0.5, 0.0, 0.0), "respawn": 20.0},
			{"pos": Vector3(half_w * 0.5, 0.0, 0.0), "respawn": 20.0},
		]
	var health: Array = []
	for hb in spec.get("health", []):
		health.append({"pos": Vector3(float(hb.get("x", 0.0)), float(hb.get("y", 0.0)), float(hb.get("z", 0.0))), "respawn": float(hb.get("respawn", 30))})
	if health.is_empty():
		health = [{"pos": Vector3(0.0, 0.0, 0.0), "respawn": 30.0}]

	var theme: Dictionary = spec.get("theme", {}) if spec.has("theme") else {}
	var map: Dictionary = {
		"id": map_id, "name": name, "mode": "any",
		"size": Vector2(w, h), "open_world": true,
		"sky": _default_sky(theme),
		"spawns": spawns, "sites": sites,
		"colliders": colliders, "props": [], "deco": deco,
		"ammoBoxes": ammo, "healthBoxes": health,
		"nav": [], "custom": true,
	}
	# 导航生成（复用引擎内置算法）
	if MapData != null:
		map["nav"] = MapData._generate_nav(map)
	return map


static func _wall(x1: float, z1: float, x2: float, z2: float, h: float) -> Dictionary:
	return {
		"min": Vector3(minf(x1, x2), 0.0, minf(z1, z2)),
		"max": Vector3(maxf(x1, x2), h, maxf(z1, z2)),
		"type": "wall",
	}


static func _default_sky(theme: Dictionary) -> Dictionary:
	var base: Dictionary = {
		"zenith": Color("2a3f66"), "horizon": Color("c9a97a"), "ground": Color("6a5a44"),
		"fog": Color("a89678"), "fog_density": 0.0022,
		"sun_dir": Vector3(0.5, 0.42, -0.7), "sun_color": Color("ffddb0"), "sun_energy": 2.4,
		"ambient_energy": 0.9, "fill_energy": 0.18, "fill_color": Color("9fb4ff"),
		"glow_intensity": 0.9, "glow_strength": 0.12, "saturation": 1.1, "contrast": 1.06,
		"cloud_coverage": 0.3, "cloud_density": 0.5, "haze": 0.25, "volumetric": 0.02,
		"exposure": 1.0, "hdri_exposure": 0.5,
	}
	for k in theme:
		base[k] = theme[k]
	return base
