# 客户端：本地预测 + 服务器校正 + 远端插值。
# 对外暴露与 Room 同构的 state 字典，渲染层/HUD 无需区分单机或联机。
class_name NetClient
extends Node

signal joined(id: String, info: Dictionary)
signal kicked(reason: String)
signal chat_received(from: String, text: String)

var transport: NetTransport = null
var state: Dictionary = {}
var local_id: String = ""
var map_id: String = "cinder"
var mode: String = "defusal"
var connected: bool = false

var _input: Dictionary = {
	"mv": [0, 0, 0, 0], "j": false, "s": false, "c": false,
	"yaw": 0.0, "pitch": 0.0, "fire": false, "ads": false,
	"r": false, "sw": -1, "swd": 0, "u": false,
}
var _prev_snap: Dictionary = {}
var _cur_snap: Dictionary = {}
var _snap_time: float = 0.0
var _snap_interval: float = 1.0 / float(NetProtocol.SNAPSHOT_RATE)
var _interp_delay: float = 0.06
var _send_acc: float = 0.0
var _clock: float = 0.0
var _pending_events: Array = []
var _rng := RandomNumberGenerator.new()


## 轻量武器代理，让 HUD / viewmodel 代码无需改动
class WireWeapon:
	var def: Dictionary
	var ammo: float = 0.0
	var reserve: float = 0.0
	var state: String = "ready"
	func _init(d: Dictionary, a: int, r: int) -> void:
		def = d
		ammo = float(a)
		reserve = float(r)

	func can_fire(_t: float) -> bool:
		return true


func start(t: NetTransport, info: Dictionary) -> void:
	transport = t
	map_id = str(info.get("map", "cinder"))
	mode = str(info.get("mode", "defusal"))
	transport.packet.connect(_on_packet)
	transport.disconnected.connect(_on_disconnected)
	transport.connected.connect(_send_hello)
	state = {
		"mode": mode, "mapId": map_id, "map": MapData.get_map(map_id),
		"players": {}, "time": 0.0, "phase": "live", "roundNum": 0,
		"matchScore": {"CT": 0, "T": 0, "HUMAN": 0, "ZOMBIE": 0},
		"core": null, "bomb": Room.blank_bomb(), "projectiles": [],
		"smokes": [], "fires": [], "finaleActive": false, "buyUntil": 0.0,
		"ammoBoxes": [], "healthBoxes": [], "weapons": WeaponDB.all(),
	}
	connected = true


## 连上中继后立刻向房主打招呼（房主据此建立玩家对象）
func _send_hello() -> void:
	if transport == null:
		return
	transport.send(0, NetProtocol.encode(NetProtocol.Op.HELLO, {
		"v": NetProtocol.VERSION,
		"name": str(Settings.get_str("gameplay", "player_name")),
		"team": "random",
	}))


func poll(dt: float) -> void:
	if not connected or transport == null:
		return
	transport.poll()
	_clock += dt
	_interp_delay = clampf(float(Settings.get_int("network", "interp_ms")) / 1000.0, 0.0, 0.2)
	# 输入上行 30Hz
	_send_acc += dt
	var step: float = 1.0 / float(NetProtocol.TICK_RATE)
	while _send_acc >= step:
		_send_acc -= step
		_send_input()
		_predict(step)


func _send_input() -> void:
	if transport == null or not transport.is_open():
		return
	transport.send(0, NetProtocol.encode(NetProtocol.Op.INPUT, {
		"mv": _input.mv, "yaw": _input.yaw, "pitch": _input.pitch,
		"fire": _input.fire, "ads": _input.ads, "j": _input.j, "c": _input.c,
		"s": _input.s, "r": _input.r, "u": _input.u,
		"sw": _input.sw, "swd": _input.swd,
	}))
	# 边沿只发一次
	_input.sw = -1
	_input.swd = 0


func _predict(dt: float) -> void:
	var p: Dictionary = state.players.get(local_id, {})
	if p.is_empty() or not bool(p.alive):
		return
	var inp: Dictionary = {
		"mv": _input.mv, "j": _input.j, "c": _input.c, "s": _input.s,
		"yaw": _input.yaw, "pitch": _input.pitch,
	}
	p.yaw = _input.yaw
	p.pitch = _input.pitch
	p.crouch = _input.c
	SimPhysics.move_player(p, inp, dt, state.map.get("colliders", []))


func _on_packet(_peer: int, data: PackedByteArray) -> void:
	var msg: Dictionary = NetProtocol.decode(data)
	if msg.is_empty():
		return
	match int(msg.kind):
		NetProtocol.Op.WELCOME:
			local_id = str(msg.data.get("id", ""))
			map_id = str(msg.data.get("map", map_id))
			state["mapId"] = map_id
			state["map"] = MapData.get_map(map_id)
			joined.emit(local_id, msg.data)
		NetProtocol.Op.SNAPSHOT:
			_apply_snapshot(msg.data)
		NetProtocol.Op.EVENT:
			_pending_events.append(msg.data)
		NetProtocol.Op.REJECT:
			var reason: String = str(msg.data.get("reason", "unknown"))
			kicked.emit(str(NetProtocol.REJECT_TEXT.get(reason, reason)))
			connected = false
		NetProtocol.Op.PONG:
			pass


func _apply_snapshot(s: Dictionary) -> void:
	_prev_snap = _cur_snap
	_cur_snap = s
	_snap_time = _clock
	if s.has("m") and str(s.m) != map_id:
		map_id = str(s.m)
		state["mapId"] = map_id
		state["map"] = MapData.get_map(map_id)
	state["time"] = float(s.get("t", 0.0))
	state["phase"] = str(s.get("ph", "live"))
	state["roundNum"] = int(s.get("rn", 0))
	state["matchScore"] = s.get("sc", {})
	state["buyUntil"] = float(s.get("t", 0.0))
	state["core"] = {
		"state": "live", "time_left": float(s.get("tl", 0.0)),
		"bomb_planted": s.get("bomb") != null and int(s.bomb.get("planted", 0)) == 1,
		"bomb_time_left": float(s.get("bl", 0.0)),
	}
	# 炸弹
	var b: Variant = s.get("bomb")
	if b == null:
		state.bomb = Room.blank_bomb()
	elif int(b.get("planted", 0)) == 1:
		state.bomb = {"planted": true, "carried": false, "carrierId": null,
			"pos": Vector3(float(b.x), float(b.y), float(b.z)), "timeLeft": float(s.get("bl", 0.0))}
	elif int(b.get("carried", 0)) == 1:
		state.bomb = {"planted": false, "carried": true, "carrierId": str(b.get("carrierId", "")), "pos": null, "timeLeft": 0.0}
	else:
		state.bomb = {"planted": false, "carried": false, "carrierId": null,
			"pos": Vector3(float(b.x), float(b.y), float(b.z)), "timeLeft": 0.0}
	# 玩家
	var seen: Dictionary = {}
	for raw in s.get("p", []):
		var d: Dictionary = NetProtocol.unpack_player(raw)
		if d.is_empty():
			continue
		var pid: String = str(d.id)
		seen[pid] = true
		var p: Dictionary = state.players.get(pid, {})
		if p.is_empty():
			p = Player.create(pid, str(d.name))
			p.isRemote = pid != local_id
			p.history = null
			state.players[pid] = p
		p.name = str(d.name)
		p.team = int(d.team)
		p.hp = float(d.hp)
		p.maxHp = 100.0
		p.armor = int(d.armor)
		p.alive = bool(d.alive)
		p.crouch = bool(d.crouch)
		p.isZombie = bool(d.isZombie)
		p.kills = int(d.kills)
		p.deaths = int(d.deaths)
		p.score = int(d.score)
		p.money = int(d.get("money", 0))
		p.grenadeCount = int(d.get("grenades", 0))
		p.weaponLevel = int(d.get("weaponLevel", 0))
		p.target_pos = d.pos
		p.target_yaw = float(d.yaw)
		p.target_pitch = float(d.pitch)
		if pid == local_id:
			# 本地预测校正：小误差插值，大误差瞬移
			var err: float = p.pos.distance_to(d.pos)
			if err > 2.5 or not p.alive:
				p.pos = d.pos
				p.vel = Vector3.ZERO
			else:
				p.pos = p.pos.lerp(d.pos, 0.18)
			p.yaw = float(d.yaw)
			p.pitch = float(d.pitch)
		else:
			if not p.has("pos"):
				p.pos = d.pos
			p.yaw = float(d.yaw)
			p.pitch = float(d.pitch)
		# 武器代理
		var wdef: Dictionary = WeaponDB.get_def(str(d.get("weapon", "k9")))
		var ww = WireWeapon.new(wdef, int(d.get("ammo", 0)), int(d.get("reserve", 0)))
		p.weapons = {2: ww}
		p.activeSlot = 2
	# 移除消失的玩家
	for pid in state.players.keys():
		if not seen.has(pid):
			state.players.erase(pid)


## 每帧由外部调用：远端玩家位置插值
func interpolate(dt: float) -> void:
	var alpha: float = clampf(dt / maxf(0.001, _snap_interval), 0.0, 1.0)
	for pid in state.players:
		var p: Dictionary = state.players[pid]
		if pid == local_id:
			continue
		if p.has("target_pos"):
			p.pos = p.pos.lerp(p.target_pos, clampf(alpha * 1.6, 0.0, 1.0))


func get_events() -> Array:
	var out: Array = _pending_events.duplicate()
	_pending_events.clear()
	return out


func set_input(inp: Dictionary) -> void:
	_input.mv = inp.get("mv", [0, 0, 0, 0])
	_input.j = bool(inp.get("j", false))
	_input.c = bool(inp.get("c", false))
	_input.s = bool(inp.get("s", false))
	_input.yaw = float(inp.get("yaw", 0.0))
	_input.pitch = float(inp.get("pitch", 0.0))
	_input.fire = bool(inp.get("fire", false))
	_input.ads = bool(inp.get("ads", false))
	_input.r = bool(inp.get("r", false))
	_input.u = bool(inp.get("u", false))
	_input.sw = int(inp.get("sw", -1))
	_input.swd = int(inp.get("swd", 0))


func request_buy(item: String) -> void:
	if transport != null:
		transport.send(0, NetProtocol.encode(NetProtocol.Op.BUY, {"item": item}))


func send_chat(text: String) -> void:
	if transport != null:
		transport.send(0, NetProtocol.encode(NetProtocol.Op.CHAT, {"text": text, "name": str(Settings.get_str("gameplay", "player_name"))}))


func _on_disconnected(reason: String) -> void:
	connected = false
	kicked.emit(reason)


func latency() -> int:
	return int(transport.rtt_ms) if transport != null else 0
