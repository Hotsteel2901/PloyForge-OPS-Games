# 网络总管（autoload `Net`）：对上层暴露极简 API。
#   Net.host_local(7777, opts)     局域网 / 端口映射直连
#   Net.host_relay(url, room, opts) 公网中继托管
#   Net.join(url_or_code, opts)     连接（自动识别中继 URL / 直连 IP / 房间码）
extends Node

signal status_changed(status: int, detail: String)
signal room_list_updated(list: Array)
signal joined_game()
signal error_occurred(text: String)
signal chat_message(from: String, text: String)

enum Status { OFFLINE, CONNECTING, HOST, CLIENT }

var status: int = Status.OFFLINE
var server: NetServer = null
var client: NetClient = null
var transport: NetTransport = null
var lan: LanDiscovery = null
var room_code: String = ""
var relay_url: String = ""
var last_error: String = ""
var _opts: Dictionary = {}
var _http: HTTPRequest = null
var _lan_timer: float = 0.0
var _ping_warned: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	lan = LanDiscovery.new()
	relay_url = Settings.get_str("network", "relay_url")
	if relay_url == "":
		relay_url = "ws://127.0.0.1:8080"


func _process(delta: float) -> void:
	match status:
		Status.HOST:
			if server != null:
				server.poll(delta)
		Status.CLIENT:
			if client != null:
				client.poll(delta)
				client.interpolate(delta)
				_check_ping()
		Status.CONNECTING:
			# 握手阶段也必须轮询，否则 WebSocket 永远停在 CONNECTING
			if transport != null:
				transport.poll()
		_:
			pass
	if lan != null and Settings.get_bool("network", "lan_discovery"):
		_lan_timer += delta
		if _lan_timer > 0.5:
			_lan_timer = 0.0
			lan.poll(0.5)
	if transport != null and transport is RelayTransport:
		var rt: RelayTransport = transport
		rt._ping_timer += delta
		if rt._ping_timer >= 2.0:
			rt._ping_timer = 0.0
			rt.ping()


## 延迟上限警告（network/max_ping）：超过上限只提示一次，避免刷屏
func _check_ping() -> void:
	var cap: int = Settings.get_int("network", "max_ping")
	var ms: int = latency()
	if cap <= 0 or ms <= 0:
		return
	if ms > cap:
		if not _ping_warned:
			_ping_warned = true
			error_occurred.emit("当前延迟 %dms 已超过上限 %dms" % [ms, cap])
	else:
		_ping_warned = false


# ---------------- 查询 ----------------

func is_online() -> bool:
	return status == Status.HOST or status == Status.CLIENT


func is_host() -> bool:
	return status == Status.HOST


func can_play() -> bool:
	if status == Status.HOST:
		return server != null and server.room != null
	if status == Status.CLIENT:
		return client != null and client.connected
	return false


## 渲染层取状态：单机时由 game.gd 用自己的 Room，联机时取这里
func active_state() -> Dictionary:
	if status == Status.HOST and server != null and server.room != null:
		return server.room.state
	if status == Status.CLIENT and client != null:
		return client.state
	return {}


func local_id() -> String:
	if status == Status.HOST and server != null:
		return server.host_player_id
	if status == Status.CLIENT and client != null:
		return client.local_id
	return ""


func latency() -> int:
	if transport == null:
		return 0
	if transport is RelayTransport:
		return int(transport.rtt_ms)
	if status == Status.CLIENT and client != null:
		return client.latency()
	return 0


func players() -> Array:
	var out: Array = []
	if status == Status.HOST and server != null:
		for p in server.players_info():
			out.append(p)
	elif status == Status.CLIENT and client != null:
		for p in client.state.get("players", {}).values():
			out.append({"id": p.id, "name": p.name, "team": p.team, "bot": false, "ping": 0})
	return out


# ---------------- 开房 ----------------

func host_local(port: int, opts: Dictionary) -> bool:
	leave()
	var t := WsHostTransport.new()
	if not t.start_host(port):
		last_error = t.last_error
		_set_status(Status.OFFLINE, last_error)
		error_occurred.emit(last_error)
		return false
	transport = t
	server = NetServer.new()
	add_child(server)
	server.start(t, opts)
	_opts = opts
	room_code = "LAN"
	_set_status(Status.HOST, "端口 %d" % port)
	if Settings.get_bool("network", "lan_discovery"):
		lan.start_advertise({"room": "LAN-%d" % port, "port": port, "mode": str(opts.get("mode", "")), "map": str(opts.get("mapId", "")), "players": server.room.state.players.size()})
	joined_game.emit()
	return true


func host_relay(url: String, room: String, opts: Dictionary) -> bool:
	leave()
	relay_url = url
	var t := RelayTransport.new()
	var code: String = room if room != "" else _gen_code()
	if not t.connect_to(url, {"room": code, "role": "host", "name": str(opts.get("name", "Host"))}):
		last_error = t.last_error
		error_occurred.emit(last_error)
		return false
	transport = t
	server = NetServer.new()
	add_child(server)
	server.start(t, opts)
	_opts = opts
	room_code = code
	_set_status(Status.HOST, "中继房间 %s" % code)
	joined_game.emit()
	return true


func join(url_or_code: String, opts: Dictionary) -> bool:
	leave()
	var target: String = url_or_code.strip_edges()
	if target == "":
		error_occurred.emit("请输入房间码或地址")
		return false
	var t: NetTransport = null
	if target.contains("://"):
		t = RelayTransport.new()
		var room: String = str(opts.get("room", "LOBBY"))
		if not (t as RelayTransport).connect_to(target, {"room": room, "role": "client", "name": str(opts.get("name", "Player"))}):
			last_error = t.last_error
			error_occurred.emit(last_error)
			return false
		relay_url = target
	else:
		# 纯房间码 → 优先局域网直连（P2P），失败再走中继
		if target.length() <= 8 and not target.contains(".") and not target.contains(":"):
			if Settings.get_bool("network", "prefer_p2p"):
				var lan_ip: String = _find_lan_host(target)
				if lan_ip != "":
					var pu: String = "ws://%s:%d/ws?room=%s&role=client&name=%s&v=%d" % [
						lan_ip, NetProtocol.PORT, target, str(opts.get("name", "Player")).uri_encode(), NetProtocol.VERSION]
					t = RelayTransport.new()
					if (t as RelayTransport).connect_to(pu, {"room": target, "role": "client", "name": str(opts.get("name", "Player"))}):
						room_code = target
						transport = t
						client = NetClient.new()
						add_child(client)
						client.kicked.connect(_on_kicked)
						client.joined.connect(func(id, info):
							_set_status(Status.CLIENT, "已连接（局域网直连）")
							joined_game.emit()
						)
						client.start(t, opts)
						_set_status(Status.CONNECTING, "局域网直连中…")
						return true
			t = RelayTransport.new()
			if not (t as RelayTransport).connect_to(relay_url, {"room": target, "role": "client", "name": str(opts.get("name", "Player"))}):
				last_error = t.last_error
				error_occurred.emit(last_error)
				return false
			room_code = target
		else:
			# IP[:port] → 直连 Host 的内置 WS 服务
			var host: String = target
			var port: int = NetProtocol.PORT
			if target.contains(":"):
				host = target.get_slice(":", 0)
				port = int(target.get_slice(":", 1))
			t = RelayTransport.new()
			var u: String = "ws://%s:%d/ws?room=direct&role=client&name=%s&v=%d" % [host, port, str(opts.get("name", "Player")).uri_encode(), NetProtocol.VERSION]
			if not (t as RelayTransport).connect_to(u, {"room": "direct", "role": "client", "name": str(opts.get("name", "Player"))}):
				last_error = t.last_error
				error_occurred.emit(last_error)
				return false
	transport = t
	client = NetClient.new()
	add_child(client)
	client.kicked.connect(_on_kicked)
	client.joined.connect(func(id, info):
		_set_status(Status.CLIENT, "已连接")
		joined_game.emit()
	)
	client.start(t, opts)
	_set_status(Status.CONNECTING, "连接中…")
	return true


## 局域网里找同房间号的 host（P2P 优先用）
func _find_lan_host(code: String) -> String:
	if lan == null:
		return ""
	for r in lan.rooms():
		if str(r.get("room", "")) == code and str(r.get("ip", "")) != "":
			return str(r.get("ip"))
	return ""


## 设置变更后重读网络参数（中继地址 / 局域网发现开关）
func reload_settings() -> void:
	var url: String = Settings.get_str("network", "relay_url")
	relay_url = url if url != "" else "ws://127.0.0.1:8080"
	if Settings.get_bool("network", "lan_discovery"):
		if lan != null and status == Status.OFFLINE:
			lan.start_listen()
	elif lan != null:
		lan.stop()


func leave() -> void:
	if server != null:
		server.stop()
		server.queue_free()
		server = null
	if client != null:
		client.queue_free()
		client = null
	if transport != null:
		transport.close("left")
		transport = null
	if lan != null:
		lan.stop()
	_set_status(Status.OFFLINE, "")


func _on_kicked(reason: String) -> void:
	last_error = reason
	error_occurred.emit(reason)
	leave()


func _set_status(s: int, detail: String) -> void:
	status = s
	status_changed.emit(s, detail)
	Bus.net_status_changed.emit(s, detail)


func _gen_code() -> String:
	const CH: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s: String = ""
	for i in 4:
		s += CH[randi() % CH.length()]
	return s


# ---------------- 中继房间列表（HTTP） ----------------

func fetch_rooms() -> void:
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_rooms)
	var base: String = relay_url
	if base.begins_with("ws://"):
		base = "http://" + base.substr(5)
	elif base.begins_with("wss://"):
		base = "https://" + base.substr(6)
	var url: String = base.get_slice("/ws", 0) + "/rooms"
	_http.request(url)


func _on_rooms(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var arr: Variant = JSON.parse_string(body.get_string_from_utf8())
	if arr is Array:
		room_list_updated.emit(arr)


func send_chat(text: String) -> void:
	if client != null:
		client.send_chat(text)
	elif server != null:
		server._broadcast_event({"type": "chat", "from": str(Settings.get_str("gameplay", "player_name")), "text": text})


# ---------------- 兼容层：给 game.gd 用 ----------------

func apply_local_input(inp: Dictionary) -> void:
	if client != null:
		client.set_input(inp)


func buy(item: String) -> void:
	if client != null:
		client.request_buy(item)


func drain_events() -> Array:
	if client != null:
		return client.get_events()
	return []
