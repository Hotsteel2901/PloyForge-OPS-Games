# 命中判定（v2）：世界射线 + 玩家（身体/头部球体）+ 近战 + 穿透 + 投掷物多类型。
class_name Hitscan
extends RefCounted

const PHYS = Constants.PHYS


# 世界射线检测，返回最近碰撞距离
static func trace_world(map_data: Dictionary, origin: Vector3, dir: Vector3, max_dist: float = 300.0) -> float:
	var best: float = max_dist
	for box in map_data.colliders:
		var t: float = MathUtil.ray_aabb(origin, dir, box.min, box.max)
		if t < best:
			best = t
	return best


## 带法线与厚度的世界命中，用于弹孔贴花与穿透
static func trace_world_ex(map_data: Dictionary, origin: Vector3, dir: Vector3, max_dist: float = 300.0) -> Dictionary:
	var best_t: float = max_dist
	var best_box: Variant = null
	for box in map_data.colliders:
		var t: float = MathUtil.ray_aabb(origin, dir, box.min, box.max)
		if t < best_t:
			best_t = t
			best_box = box
	if best_box == null:
		return {"t": max_dist, "normal": Vector3.UP, "thickness": 0.0, "hit": false}
	# 估算穿出距离：从入射点继续走，看能走多远才离开该 AABB
	var p: Vector3 = origin + dir * best_t
	var thick: float = _exit_distance(p, dir, best_box.min, best_box.max)
	var n: Vector3 = _guess_normal(p, best_box.min, best_box.max)
	return {"t": best_t, "normal": n, "thickness": thick, "hit": true}


static func _exit_distance(p: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3) -> float:
	var t: float = 0.0
	var eps: float = 0.01
	var cur: Vector3 = p + dir * eps
	for _i in 8:
		if cur.x < bmin.x or cur.x > bmax.x or cur.y < bmin.y or cur.y > bmax.y or cur.z < bmin.z or cur.z > bmax.z:
			return t
		t += 0.25
		cur = p + dir * (t + eps)
	return 3.0


static func _guess_normal(p: Vector3, bmin: Vector3, bmax: Vector3) -> Vector3:
	var dx: float = minf(absf(p.x - bmin.x), absf(p.x - bmax.x))
	var dy: float = minf(absf(p.y - bmin.y), absf(p.y - bmax.y))
	var dz: float = minf(absf(p.z - bmin.z), absf(p.z - bmax.z))
	if dx <= dy and dx <= dz:
		return Vector3(signf(p.x - (bmin.x + bmax.x) * 0.5), 0, 0)
	if dy <= dz:
		return Vector3(0, signf(p.y - (bmin.y + bmax.y) * 0.5), 0)
	return Vector3(0, 0, signf(p.z - (bmin.z + bmax.z) * 0.5))


# 倒带：用快照获取每个玩家在 time 时刻的状态
static func rewind_players(room: Dictionary, shooter: Dictionary, time: float) -> Dictionary:
	var rewound := {}
	for p in room.players.values():
		if p == shooter:
			continue
		var snap: Variant = p.history.get_at(time) if p.history != null else null
		if snap == null:
			snap = {"pos": p.pos, "yaw": p.yaw, "pitch": p.pitch, "crouch": p.crouch, "alive": p.alive}
		rewound[p.id] = snap
	return rewound


# 玩家射线检测：返回 {player, headshot, t} 或 {}
static func raycast_players(room: Dictionary, shooter: Dictionary, origin: Vector3, dir: Vector3, max_dist: float, rewound: Variant = null, skip = null) -> Dictionary:
	var hit: Dictionary = {}
	var best: float = max_dist
	for p in room.players.values():
		if p == shooter:
			continue
		if skip != null and skip.has(p.id):
			continue
		var snap: Dictionary = {}
		if rewound != null and rewound.has(p.id):
			snap = rewound[p.id]
		var alive: bool = snap.get("alive", p.alive) if not snap.is_empty() else p.alive
		if not alive:
			continue
		var pos: Vector3 = snap.get("pos", p.pos) if not snap.is_empty() else p.pos
		var crouch: bool = snap.get("crouch", p.crouch) if not snap.is_empty() else p.crouch
		var h: float = PHYS.CROUCH_H if crouch else PHYS.STAND_H
		var body_c := Vector3(pos.x, pos.y + h * 0.55, pos.z)
		var head_c := Vector3(pos.x, pos.y + h * 0.88, pos.z)
		var tb: float = MathUtil.ray_sphere(origin, dir, body_c, 0.42)
		var th: float = MathUtil.ray_sphere(origin, dir, head_c, 0.23)
		if th < best:
			best = th
			hit = {"player": p, "headshot": true, "t": th}
		elif tb < best:
			best = tb
			hit = {"player": p, "headshot": false, "t": tb}
	return hit


# 执行一次射击。返回命中结果列表。
static func perform_shot(room: Dictionary, shooter: Dictionary, def: Dictionary, opts: Dictionary = {}) -> Array:
	if not shooter.alive:
		return []
	var results: Array = []
	var rewound: Variant = null
	if opts.has("rewindTime"):
		rewound = rewind_players(room, shooter, float(opts.rewindTime))

	# ---- 近战 ----
	if def.get("melee", false):
		var origin := Vector3(shooter.pos.x, Player.eye_height(shooter), shooter.pos.z)
		var fwd := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
		var best := {"t": INF, "target": null, "hs": false}
		for p in room.players.values():
			if p == shooter:
				continue
			var snap: Dictionary = {}
			if rewound != null and rewound.has(p.id):
				snap = rewound[p.id]
			var alive: bool = snap.get("alive", p.alive) if not snap.is_empty() else p.alive
			if not alive:
				continue
			var pos: Vector3 = snap.get("pos", p.pos) if not snap.is_empty() else p.pos
			var crouch: bool = snap.get("crouch", p.crouch) if not snap.is_empty() else p.crouch
			var h: float = PHYS.CROUCH_H if crouch else PHYS.STAND_H
			var c := Vector3(pos.x, pos.y + h * 0.5, pos.z)
			var dx: float = c.x - origin.x
			var dy: float = c.y - origin.y
			var dz: float = c.z - origin.z
			var dist: float = sqrt(dx * dx + dy * dy + dz * dz)
			if dist > float(def.range):
				continue
			var dot: float = (dx * fwd.x + dy * fwd.y + dz * fwd.z) / (dist if dist > 0 else 1.0)
			if dot < cos(0.95):
				continue
			if dist < best.t:
				# 近战也能爆头：瞄准点高于肩线即判定
				var hs: bool = (origin.y + fwd.y * dist) > (pos.y + h * 0.78)
				best = {"t": dist, "target": p, "hs": hs}
		if best.target != null:
			var dmg: int = WeaponData.compute_shot_damage(def, best.hs, best.t)
			var r: Variant = Player.damage_player(room, shooter, best.target, float(dmg), {
				"weapon": def.id, "headshot": best.hs, "dist": best.t,
				"armor_pen": float(def.get("armorPen", 0.5)),
			})
			if r != null:
				results.append(r)
		return results

	# ---- 投掷物 ----
	var proj_kind: String = str(def.get("projectile", ""))
	if proj_kind != "":
		throw_projectile(room, shooter, def)
		return results

	# ---- 枪械 ----
	var pellets: int = int(def.get("pellets", 1))
	var origin := Vector3(shooter.pos.x, Player.eye_height(shooter), shooter.pos.z)
	var move_speed: float = Vector2(shooter.vel.x, shooter.vel.z).length()
	var ads: bool = bool(shooter.input.ads)
	var shots: int = 0
	var w: Variant = shooter.weapons.get(shooter.activeSlot, null)
	if w != null:
		shots = int(w.shots_fired)
	var spread: float = WeaponData.effective_spread(def, ads, move_speed, shots)
	var pen: float = float(def.get("penetration", 0.0))
	var base := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
	var last_hit_pos: Variant = null
	for i in range(pellets):
		var dir: Vector3 = MathUtil.random_in_cone(base, spread) if spread > 0.0 else base
		var wex: Dictionary = trace_world_ex(room.map, origin, dir, 300.0)
		var t_world: float = float(wex.t)
		var hit := raycast_players(room, shooter, origin, dir, t_world, rewound)
		var skip: Dictionary = {}
		var cur_dist: float = 0.0
		var dmg_scale: float = 1.0
		var hops: int = 0
		while true:
			if hit.is_empty():
				# 没打到人：尝试穿墙后继续
				if pen > 0.55 and hops < 1:
					var thick: float = float(wex.thickness)
					if thick < 1.2 * pen:
						hops += 1
						cur_dist = t_world + thick + 0.05
						var dir2: Vector3 = dir
						var wex2: Dictionary = trace_world_ex(room.map, origin, dir2, 300.0)
						# 从墙后重新求最近玩家
						var t2: float = trace_world(room.map, origin + dir * cur_dist, dir, 300.0 - cur_dist)
						var h2: Dictionary = raycast_players(room, shooter, origin + dir * cur_dist, dir, t2, rewound, skip)
						if h2.is_empty():
							break
						h2.t += cur_dist
						hit = h2
						dmg_scale *= 0.55
						continue
				break
			var dist: float = float(hit.t)
			var dmg: int = WeaponData.compute_shot_damage(def, bool(hit.headshot), dist)
			dmg = maxi(1, int(round(float(dmg) * dmg_scale)))
			var r: Variant = Player.damage_player(room, shooter, hit.player, float(dmg), {
				"weapon": def.id, "headshot": bool(hit.headshot), "dist": dist,
				"armor_pen": float(def.get("armorPen", 0.5)),
			})
			if r != null:
				var hp: Vector3 = origin + dir * dist
				r["pos"] = hp
				r["dir"] = dir
				last_hit_pos = hp
				results.append(r)
			skip[hit.player.id] = true
			# 继续穿透后续目标
			if pen > 0.25 and hops < 4:
				hops += 1
				dmg_scale *= (0.8 - 0.1 * hops)
				var nh: Dictionary = raycast_players(room, shooter, origin, dir, t_world, rewound, skip)
				if nh.is_empty() or float(nh.get("t", INF)) >= t_world - 0.01:
					break
				hit = nh
				continue
			break
	return results


## 投掷物统一出口：类型由 def.projectile 决定
static func throw_projectile(room: Dictionary, shooter: Dictionary, def: Dictionary) -> void:
	var kind: String = str(def.get("projectile", "grenade"))
	var fwd := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
	var speed: float = 17.0 if kind != "bolt" else float(def.get("projectileSpeed", 90.0))
	var pos := Vector3(shooter.pos.x, Player.eye_height(shooter) - 0.2, shooter.pos.z)
	var vel: Vector3
	if kind == "bolt":
		vel = fwd * speed
	else:
		vel = Vector3(
			fwd.x * speed + shooter.vel.x * 0.5,
			fwd.y * speed + 2.5,
			fwd.z * speed + shooter.vel.z * 0.5,
		)
	var id_str := "p%d" % room.nextProjId
	room.nextProjId += 1
	var fuse: float = 3.4
	match kind:
		"flash": fuse = 2.0
		"smoke": fuse = 2.2
		"fire": fuse = 2.4
		"decoy": fuse = 2.6
		"bolt": fuse = 12.0
	room.projectiles.append({
		"id": id_str, "owner": shooter.id, "pos": pos, "vel": vel,
		"fuse": fuse, "bounces": 0, "kind": kind, "weapon": str(def.get("id", "")),
		"damage": float(def.get("damage", 0)), "radius": float(def.get("radius", 8.0)),
	})
	room.broadcast.call({"type": "throw", "id": shooter.id, "pos": pos, "kind": kind})


# 兼容旧调用
static func throw_grenade(room: Dictionary, shooter: Dictionary) -> void:
	throw_projectile(room, shooter, WeaponData.BUILTIN_WEAPONS.thunder)
