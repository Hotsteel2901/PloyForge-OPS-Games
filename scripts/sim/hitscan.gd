# 命中判定：世界射线 + 玩家（身体/头部球体）+ 近战判定。移植自 host/hitscan.js
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


# 倒带：用快照获取每个玩家在 time 时刻的状态
static func rewind_players(room: Dictionary, shooter: Dictionary, time: float) -> Dictionary:
	var rewound := {}
	for p in room.players.values():
		if p == shooter:
			continue
		var snap: Variant = p.history.get_at(time) if p.history != null else null
		if snap == null:
			snap = {
				"pos": p.pos,
				"yaw": p.yaw,
				"pitch": p.pitch,
				"crouch": p.crouch,
				"alive": p.alive,
			}
		rewound[p.id] = snap
	return rewound


# 玩家射线检测：返回 {player, headshot, t} 或 null
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


# 执行一次射击（含近战 / 投掷物 / 穿透）。返回命中结果列表。
static func perform_shot(room: Dictionary, shooter: Dictionary, def: Dictionary, opts: Dictionary = {}) -> Array:
	if not shooter.alive:
		return []
	var results: Array = []
	var rewound: Variant = null
	if opts.has("rewindTime"):
		rewound = rewind_players(room, shooter, float(opts.rewindTime))

	if def.get("melee", false):
		var origin := Vector3(shooter.pos.x, Player.eye_height(shooter), shooter.pos.z)
		var fwd := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
		var best := {"t": INF, "target": null}
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
				best = {"t": dist, "target": p}
		if best.target != null:
			var dmg: int = WeaponData.compute_shot_damage(def, false, best.t)
			var r: Variant = Player.damage_player(room, shooter, best.target, float(dmg), {"weapon": def.id, "headshot": false, "dist": best.t})
			if r != null:
				results.append(r)
		return results

	if def.get("projectile", "") == "grenade":
		throw_grenade(room, shooter)
		return results

	var pellets: int = int(def.get("pellets", 1))
	var origin := Vector3(shooter.pos.x, Player.eye_height(shooter), shooter.pos.z)
	for i in range(pellets):
		var base := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
		var angle: float = WeaponData.apply_spread(def, bool(shooter.input.ads))
		var dir: Vector3 = MathUtil.random_in_cone(base, angle) if angle > 0.0 else base
		var t_world: float = trace_world(room.map, origin, dir)
		var hit := raycast_players(room, shooter, origin, dir, t_world, rewound)
		if hit.is_empty():
			continue
		var dist: float = hit.t
		var dmg: int = WeaponData.compute_shot_damage(def, hit.headshot, dist)
		var r: Variant = Player.damage_player(room, shooter, hit.player, float(dmg), {"weapon": def.id, "headshot": hit.headshot, "dist": dist})
		if r != null:
			r["pos"] = Vector3(origin.x + dir.x * dist, origin.y + dir.y * dist, origin.z + dir.z * dist)
			results.append(r)
		# 穿透：沿直线命中后续目标（仍被墙体阻挡）
		if def.get("pierce", false):
			var skip := {hit.player.id: true}
			for _hop in range(5):
				var next_hit := raycast_players(room, shooter, origin, dir, t_world, rewound, skip)
				if next_hit.is_empty() or next_hit.t >= t_world - 0.01:
					break
				skip[next_hit.player.id] = true
				var d2: int = WeaponData.compute_shot_damage(def, next_hit.headshot, next_hit.t)
				var r2: Variant = Player.damage_player(room, shooter, next_hit.player, float(d2), {"weapon": def.id, "headshot": next_hit.headshot, "dist": next_hit.t})
				if r2 != null:
					r2["pos"] = Vector3(origin.x + dir.x * next_hit.t, origin.y + dir.y * next_hit.t, origin.z + dir.z * next_hit.t)
					results.append(r2)
	return results


static func throw_grenade(room: Dictionary, shooter: Dictionary) -> void:
	var fwd := MathUtil.direction_from_angles(shooter.yaw, shooter.pitch)
	var speed: float = 17.0
	var pos := Vector3(shooter.pos.x, Player.eye_height(shooter) - 0.2, shooter.pos.z)
	var vel := Vector3(
		fwd.x * speed + shooter.vel.x * 0.5,
		fwd.y * speed + 2.5,
		fwd.z * speed + shooter.vel.z * 0.5,
	)
	var id_str := "p%d" % room.nextProjId
	room.nextProjId += 1
	room.projectiles.append({
		"id": id_str,
		"owner": shooter.id,
		"pos": pos,
		"vel": vel,
		"fuse": 3.4,
		"bounces": 0,
		"kind": "grenade",
	})
	room.broadcast.call({"type": "throw", "id": shooter.id, "pos": pos})
