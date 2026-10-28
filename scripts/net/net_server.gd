# 权威服务端（Listen Server / 专用服务器共用）。
# 持有 Room，接收客户端输入，按 20Hz 下发快照。
class_name NetServer
extends Node

signal player_joined(peer_id: int, player_id: String)
signal player_left(peer_id: int, player_id: String)

const INPUT_TIMEOUT: float = 12.0
const MAX_INPUTS_PER_SEC: int = 90

var transport: NetTransport = null
var room: Room = null
var host_player_id: String = ""
var peer_to_player: Dictionary = {}
var player_to_peer: Dictionary = {}
var _last_input: Dictionary = {}
var _input_budget: Dictionary = {}
var _snap_acc: float = 0.0
var _tick_acc: float = 0.0
var _running: bool = false
var _host_name: String = "Host"
var _opts: Dictionary = {}


func start(t: NetTransport, opts: Dictionary) -> void:
	transport = t
	_opts = opts
	_running = true
	transport.packet.connect(_on_packet)
	transport.peer_left.connect(_on_peer_left)
	room = Room.new({
		"id": "net",
		"mode": str(opts.get("mode", "defusal")),
		"mapId": str(opts.get("mapId", "cinder")),
		"botCount": int(opts.get("botCount", 6)),
		"maxPlayers": int(opts.get("maxPlayers", Constants.MAX_PLAYERS)),
		"localOnly": true,
	})
	room._local_only = true     # 快照由 NetServer 自己发，避免重复
	_hook_room_output()
	var p: Dictionary = room.add_local_player(str(opts.get("name", "Host")), str(opts.get("team", "random")))
	if not p.is_empty():
		host_player_id = str(p.id)
		room.spawn_joiner(p)
	room.start()
	room.spawn_joiner(p) if not p.is_empty() and not p.alive else null
	print("[NetServer] hosting mode=%s map=%s" % [room.state.mode, room.state.mapId])


func _hook_room_output() -> void:
	var local_broadcast := func(msg: Dictionary) -> void:
		# 本地 Host 玩家的 UI 消息
		if host_player_id != "" and room.state.players.has(host_player_id):
			var hp: Dictionary = room.state.players[host_player_id]
			if hp.has("pendingMessages"):
				hp.pendingMessages.append(msg)
		_broadcast_event(msg)
	var local_send := func(pid: String, msg: Dictionary) -> void:
		if pid == host_player_id:
			if room.state.players.has(pid):
				room.state.players[pid].pendingMessages.append(msg)
			return
		if player_to_peer.has(pid):
			_send_event(int(player_to_peer[pid]), msg)
	room.broadcast = local_broadcast
	room.state.broadcast = local_broadcast
	room.send_to = local_send
	room.state.sendTo = local_send


func _broadcast_event(msg: Dictionary) -> void:
	if transport == null:
		return
	var data: PackedByteArray = NetProtocol.encode(NetProtocol.Op.EVENT, msg)
	for peer in peer_to_player.keys():
		transport.send(int(peer), data)


func _send_event(peer: int, msg: Dictionary) -> void:
	if transport == null:
		return
	transport.send(peer, NetProtocol.encode(NetProtocol.Op.EVENT, msg))


func poll(dt: float) -> void:
	if not _running or transport == null:
		return
	transport.poll()
	_tick_acc += dt
	var step: float = 1.0 / float(NetProtocol.TICK_RATE)
	var guard: int = 0
	while _tick_acc >= step and guard < 6:
		_tick_acc -= step
		room.tick()
		guard += 1
	# 超时踢人
	for pid in _last_input.keys():
		if room.state.time - float(_last_input[pid]) > INPUT_TIMEOUT:
			var peer: int = -1
			for k in peer_to_player:
				if str(peer_to_player[k]) == str(pid):
					peer = int(k)
					break
			if peer >= 0:
				_kick(peer, "timeout")
	_snap_acc += dt
	if _snap_acc >= 1.0 / float(NetProtocol.SNAPSHOT_RATE):
		_snap_acc = 0.0
		_send_snapshot()


func _send_snapshot() -> void:
	if transport == null or room == null:
		return
	var players: Array = []
	for p in room.state.players.values():
		p.ping = int(transport.rtt_ms) if p.id == host_player_id else int(p.get("ping", 0))
		players.append(NetProtocol.pack_player(p))
	var snap: Dictionary = {
		"t": room.state.time,
		"p": players,
		"m": room.state.mapId,
		"mode": room.state.mode,
		"ph": room.state.phase,
		"rn": room.state.roundNum,
		"tl": float(room.state.core.time_left) if room.state.core != null else 0.0,
		"sc": room.state.matchScore,
		"bomb": room._bomb_snapshot(),
		"proj": room._proj_snapshot(),
		"smokes": room.state.smokes.size(),
		"extra": room.mode.snapshot_extra(room),
		"host": host_player_id,
	}
	var data: PackedByteArray = NetProtocol.encode(NetProtocol.Op.SNAPSHOT, snap)
	for peer in peer_to_player.keys():
		transport.send(int(peer), data)


func _on_packet(peer: int, data: PackedByteArray) -> void:
	var msg: Dictionary = NetProtocol.decode(data)
	if msg.is_empty():
		return
	var op: int = int(msg.kind)
	var d: Dictionary = msg.data
	match op:
		NetProtocol.Op.HELLO:
			_handle_hello(peer, d)
		NetProtocol.Op.INPUT:
			_handle_input(peer, d)
		NetProtocol.Op.BUY:
			_handle_buy(peer, d)
		NetProtocol.Op.CHAT:
			_broadcast_event({"type": "chat", "from": str(d.get("name", "")), "text": str(d.get("text", "")).substr(0, 200)})
		NetProtocol.Op.PING:
			transport.send(peer, NetProtocol.encode(NetProtocol.Op.PONG, {"t": d.get("t", 0)}))
		NetProtocol.Op.SELECT_TEAM:
			_on_select_team(peer, str(d.get("team", "random")))
		NetProtocol.Op.LEAVE:
			_kick(peer, "left")


func _handle_hello(peer: int, d: Dictionary) -> void:
	if int(d.get("v", 0)) != NetProtocol.VERSION:
		transport.send(peer, NetProtocol.encode(NetProtocol.Op.REJECT, {"reason": "version"}))
		return
	if peer_to_player.has(peer):
		return
	if room.state.players.size() >= room.state.maxPlayers:
		transport.send(peer, NetProtocol.encode(NetProtocol.Op.REJECT, {"reason": "full"}))
		return
	var name: String = str(d.get("name", "Player")).substr(0, 16)
	var pid: String = "n%d" % peer
	var p: Dictionary = room.add_remote_player(pid, name, str(d.get("team", "random")))
	if p.is_empty():
		transport.send(peer, NetProtocol.encode(NetProtocol.Op.REJECT, {"reason": "full"}))
		return
	peer_to_player[peer] = pid
	player_to_peer[pid] = peer
	_last_input[pid] = room.state.time
	room.spawn_joiner(p)
	transport.send(peer, NetProtocol.encode(NetProtocol.Op.WELCOME, {
		"id": pid, "v": NetProtocol.VERSION,
		"map": room.state.mapId, "mode": room.state.mode,
		"tick": NetProtocol.TICK_RATE,
		"host": host_player_id,
	}))
	player_joined.emit(peer, pid)
	_broadcast_event({"type": "net_join", "name": name, "id": pid})
	print("[NetServer] peer %d joined as %s" % [peer, pid])


func _handle_input(peer: int, d: Dictionary) -> void:
	if not peer_to_player.has(peer):
		return
	var pid: String = str(peer_to_player[peer])
	if not room.state.players.has(pid):
		return
	var p: Dictionary = room.state.players[pid]
	if not p.alive and room.state.phase != "buy":
		return
	_last_input[pid] = room.state.time
	p.connected = true
	p.ping = int(transport.rtt_ms)
	var mv: Array = d.get("mv", [0, 0, 0, 0])
	var inp: Dictionary = p.input
	inp.mv = [
		1 if int(mv[0]) == 1 else 0, 1 if int(mv[1]) == 1 else 0,
		1 if int(mv[2]) == 1 else 0, 1 if int(mv[3]) == 1 else 0,
	]
	inp.yaw = clampf(float(d.get("yaw", 0.0)), -100.0, 100.0)
	inp.pitch = clampf(float(d.get("pitch", 0.0)), -1.55, 1.55)
	inp.fire = bool(d.get("fire", false))
	inp.ads = bool(d.get("ads", false))
	inp.j = bool(d.get("j", false))
	inp.c = bool(d.get("c", false))
	inp.s = bool(d.get("s", false))
	inp.r = bool(d.get("r", false))
	inp.u = bool(d.get("u", false))
	# 边沿事件（只取一次，由 Room 消费后置回 -1/false）
	var sw: int = int(d.get("sw", -1))
	if sw >= 0:
		p.edge.sw = sw
	var swd: int = int(d.get("swd", 0))
	if swd != 0:
		p.edge.swd = swd
	if bool(d.get("j", false)):
		p.edge.j = true
	if bool(d.get("r", false)):
		p.edge.r = true


func _handle_buy(peer: int, d: Dictionary) -> void:
	if not peer_to_player.has(peer):
		return
	var p: Dictionary = room.state.players.get(str(peer_to_player[peer]), {})
	if p.is_empty():
		return
	var item: String = str(d.get("item", ""))
	var r: Dictionary = room.handle_buy(p, item)
	if not bool(r.get("ok", false)):
		transport.send(peer, NetProtocol.encode(NetProtocol.Op.EVENT, {"type": "buy_fail", "item": item, "reason": str(r.get("reason", ""))}))


func _on_select_team(peer: int, team: String) -> void:
	if not peer_to_player.has(peer):
		return
	var p: Dictionary = room.state.players.get(str(peer_to_player[peer]), {})
	if p.is_empty():
		return
	p.teamPref = team if team in ["ct", "t"] else "random"


func _on_peer_left(peer: int, reason: String) -> void:
	if not peer_to_player.has(peer):
		return
	var pid: String = str(peer_to_player[peer])
	_broadcast_event({"type": "net_leave", "id": pid, "reason": reason})
	room.remove_player(pid)
	peer_to_player.erase(peer)
	player_to_peer.erase(pid)
	_last_input.erase(pid)
	player_left.emit(peer, pid)


func _kick(peer: int, reason: String) -> void:
	if transport != null:
		transport.send(peer, NetProtocol.encode(NetProtocol.Op.REJECT, {"reason": reason}))
	_on_peer_left(peer, reason)


func stop() -> void:
	_running = false
	if transport != null:
		transport.close("server closed")
	room = null


func players_info() -> Array:
	var out: Array = []
	if room == null:
		return out
	for p in room.state.players.values():
		out.append({"id": p.id, "name": p.name, "team": p.team, "bot": p.isBot, "ping": p.get("ping", 0)})
	return out
