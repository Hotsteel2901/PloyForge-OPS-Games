# 玩家移动积分：服务端权威 + 客户端预测共用。移植自 shared/physics.js
class_name SimPhysics
extends RefCounted

const PHYS = Constants.PHYS


# p: Player（含 pos:Vector3, vel:Vector3, yaw, pitch, grounded, crouch, isZombie,
#    weaponMoveMult, speedOverride, slowTicks, boostUntil）
# input: { mv=[fwd,back,left,right], j=bool, s=bool(sprint), c=bool(crouch) }
# colliders: Array<Dictionary{min:Vector3, max:Vector3}>
static func move_player(p: Dictionary, input: Dictionary, dt: float, colliders: Array) -> void:
	var speed_override = p.get("speedOverride", null)
	var base_speed: float = speed_override if speed_override != null else (
		PHYS.ZOMBIE_SPEED if p.isZombie else PHYS.SPEED * float(p.get("weaponMoveMult", 1.0))
	)
	var speed: float = base_speed
	if p.isZombie and int(p.get("slowTicks", 0)) > 0:
		speed *= PHYS.ZOMBIE_SLOW_MULT
	if input.get("s", false) and not p.isZombie and not p.crouch and input.mv[0]:
		speed *= PHYS.SPRINT_MULT
	if p.crouch and not p.isZombie:
		speed *= PHYS.CROUCH_MULT

	var f_val: int = (1 if input.mv[0] else 0) - (1 if input.mv[1] else 0)
	var s_val: int = (1 if input.mv[3] else 0) - (1 if input.mv[2] else 0)
	var fx: float = -sin(p.yaw)
	var fz: float = -cos(p.yaw)
	var rx: float = -fz
	var rz: float = fx
	var wx: float = fx * f_val + rx * s_val
	var wz: float = fz * f_val + rz * s_val
	var wl: float = sqrt(wx * wx + wz * wz)
	if wl > 0.0:
		wx = (wx / wl) * speed
		wz = (wz / wl) * speed

	var accel: float = min(1.0, dt * (14.0 if p.isZombie else 11.0))
	p.vel.x += (wx - p.vel.x) * accel
	p.vel.z += (wz - p.vel.z) * accel

	# 垂直：接地且未跳跃时速度归零；跳跃立刻离地；只有空中才受重力
	# 跳跃=边沿触发（CS2 语义）：人类玩家按住空格只在着地瞬间起跳，防无限 bhop；
	# bot 的 input.j 是每 tick 重置的单帧指令，直接执行。
	if p.grounded:
		if input.get("j", false):
			var jump_now: bool = bool(p.get("isBot", false)) or not bool(p.get("prevJump", false))
			p.prevJump = true
			if jump_now:
				p.vel.y = PHYS.ZOMBIE_JUMP if p.isZombie else PHYS.JUMP
				p.grounded = false
		else:
			p.prevJump = false
			p.vel.y = 0.0
	else:
		p.vel.y += PHYS.GRAVITY * dt
	if p.vel.y < PHYS.TERMINAL:
		p.vel.y = PHYS.TERMINAL

	var height: float = PHYS.CROUCH_H if p.crouch else PHYS.STAND_H

	# 位置积分
	p.pos.x += p.vel.x * dt
	p.pos.y += p.vel.y * dt
	p.pos.z += p.vel.z * dt

	# 自动台阶：积分后脚底被 0.4m 以下障碍挡住，但抬高后可通行时自动上台阶
	if p.grounded and (abs(p.vel.x) > 0.5 or abs(p.vel.z) > 0.5):
		var STEP: float = 0.4
		var half: float = PHYS.HALF
		var cur_min := Vector3(p.pos.x - half, p.pos.y, p.pos.z - half)
		var cur_max := Vector3(p.pos.x + half, p.pos.y + height, p.pos.z + half)
		var new_min := Vector3(p.pos.x - half, p.pos.y + STEP, p.pos.z - half)
		var new_max := Vector3(p.pos.x + half, p.pos.y + STEP + height, p.pos.z + half)
		var cur_blocked := false
		var new_blocked := false
		for box in colliders:
			if _overlap_tol(cur_min, cur_max, box.min, box.max):
				cur_blocked = true
			if _overlap_tol(new_min, new_max, box.min, box.max):
				new_blocked = true
		if cur_blocked and not new_blocked:
			p.pos.y += STEP

	var grounded := false
	var half := PHYS.HALF
	for _pass in range(2):
		for box in colliders:
			var r := MathUtil.resolve_overlap(p.pos, p.vel, half, height, box.min, box.max)
			p.pos = r.pos
			p.vel = r.vel
			if r.grounded:
				grounded = true
			# 支撑检测：脚底贴合碰撞体顶面视为站立
			if abs(p.pos.y - box.max.y) < 0.06 and \
			   p.pos.x + half > box.min.x and p.pos.x - half < box.max.x and \
			   p.pos.z + half > box.min.z and p.pos.z - half < box.max.z:
				grounded = true
	# 地图地面安全网
	if p.pos.y <= 0.0 and p.vel.y <= 0.0:
		p.pos.y = 0.0
		p.vel.y = 0.0
		grounded = true
	p.grounded = grounded


# 2cm 容差重叠判定（避免 0.4 累加的浮点误差把"刚好站上台阶"误判为撞墙）
static func _overlap_tol(a_min: Vector3, a_max: Vector3, b_min: Vector3, b_max: Vector3) -> bool:
	return a_min.x < b_max.x - 0.02 and a_max.x > b_min.x + 0.02 and \
		   a_min.y < b_max.y - 0.02 and a_max.y > b_min.y + 0.02 and \
		   a_min.z < b_max.z - 0.02 and a_max.z > b_min.z + 0.02
