# 纯数学工具：射线、碰撞、护甲、伤害衰减。移植自 shared/math.js
extends Node

const EPS: float = 1e-6


static func clampf(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


static func lerpf(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func clamp_angle(a: float) -> float:
	while a > PI:
		a -= PI * 2.0
	while a < -PI:
		a += PI * 2.0
	return a


static func ang_lerp(a: float, b: float, t: float) -> float:
	return a + clamp_angle(b - a) * t


# 射线 vs 球体
static func ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var ox: float = origin.x - center.x
	var oy: float = origin.y - center.y
	var oz: float = origin.z - center.z
	var b: float = ox * dir.x + oy * dir.y + oz * dir.z
	var c: float = ox * ox + oy * oy + oz * oz - radius * radius
	var disc: float = b * b - c
	if disc < 0:
		return INF
	var sq: float = sqrt(disc)
	var t: float = -b - sq
	if t < 0:
		t = -b + sq
	return INF if t < 0 else t


# 射线 vs AABB
static func ray_aabb(origin: Vector3, dir: Vector3, b_min: Vector3, b_max: Vector3) -> float:
	var tmin: float = 0.0
	var tmax: float = INF
	for i in range(3):
		var o: float = origin[i]
		var d: float = dir[i]
		var lo: float = b_min[i]
		var hi: float = b_max[i]
		if absf(d) < EPS:
			if o < lo or o > hi:
				return INF
		else:
			var t1: float = (lo - o) / d
			var t2: float = (hi - o) / d
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			tmin = max(tmin, t1)
			tmax = min(tmax, t2)
			if tmin > tmax:
				return INF
	return tmin


static func aabb_overlap(a_min: Vector3, a_max: Vector3, b_min: Vector3, b_max: Vector3) -> bool:
	return a_min.x < b_max.x and a_max.x > b_min.x and \
		   a_min.y < b_max.y and a_max.y > b_min.y and \
		   a_min.z < b_max.z and a_max.z > b_min.z


# 只做重叠解算、不做位置积分。按最小穿透轴把玩家推出 box。
# pos 是脚底位置；返回 {grounded}
static func resolve_overlap(pos: Vector3, vel: Vector3, half: float, height: float, box_min: Vector3, box_max: Vector3) -> Dictionary:
	var p_min := Vector3(pos.x - half, pos.y, pos.z - half)
	var p_max := Vector3(pos.x + half, pos.y + height, pos.z + half)
	if not aabb_overlap(p_min, p_max, box_min, box_max):
		return {"grounded": false, "pos": pos, "vel": vel}
	# 脚底接近箱体顶面时优先纵向解算
	if pos.y >= box_max.y - 0.06:
		pos.y = box_max.y
		vel.y = 0.0
		return {"grounded": true, "pos": pos, "vel": vel}
	var pen_x: float = min(p_max.x - box_min.x, box_max.x - p_min.x)
	var pen_y: float = min(p_max.y - box_min.y, box_max.y - p_min.y)
	var pen_z: float = min(p_max.z - box_min.z, box_max.z - p_min.z)
	var grounded: bool = false
	if pen_y <= pen_x and pen_y <= pen_z:
		var above: bool = pos.y + height / 2.0 > (box_min.y + box_max.y) / 2.0
		if above:
			pos.y = box_max.y
			grounded = true
		else:
			pos.y = box_min.y - height
		vel.y = 0.0
	elif pen_x <= pen_z:
		pos.x = box_max.x + half if pos.x > (box_min.x + box_max.x) / 2.0 else box_min.x - half
		vel.x = 0.0
	else:
		pos.z = box_max.z + half if pos.z > (box_min.z + box_max.z) / 2.0 else box_min.z - half
		vel.z = 0.0
	return {"grounded": grounded, "pos": pos, "vel": vel}


static func apply_armor(damage: int, armor: int) -> Dictionary:
	var absorbed: int = min(armor, int(damage * 0.5))
	return {"damage": max(0, damage - absorbed), "armor": max(0, armor - absorbed)}


static func damage_falloff(damage: float, dist: float, near: float, far: float, min_mult: float = 0.5) -> float:
	if dist <= near:
		return damage
	if dist >= far:
		return damage * min_mult
	var t: float = (dist - near) / (far - near)
	return damage * (1.0 - t * (1.0 - min_mult))


static func distance3(a: Vector3, b: Vector3) -> float:
	return (a - b).length()


static func direction_from_angles(yaw: float, pitch: float) -> Vector3:
	var cp: float = cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


# 在方向锥内随机扰动
static func random_in_cone(dir: Vector3, angle: float) -> Vector3:
	var a: float = randf() * PI * 2.0
	var r: float = sqrt(randf()) * angle
	var ox: float = cos(a) * r
	var oy: float = sin(a) * r
	var n: Vector3 = dir.normalized()
	var t := Vector3(1, 0, 0)
	if absf(n.x) > 0.9:
		t = Vector3(0, 0, 1)
	var b: Vector3 = Vector3(n.y * t.z - n.z * t.y, n.z * t.x - n.x * t.z, n.x * t.y - n.y * t.x)
	var bl: float = b.length()
	if bl < EPS:
		bl = 1.0
	b /= bl
	var c: Vector3 = Vector3(t.y * b.z - t.z * b.y, t.z * b.x - t.x * b.z, t.x * b.y - t.y * b.x)
	return n + b * ox + c * oy
