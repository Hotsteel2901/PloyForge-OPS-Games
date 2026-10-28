# 中继传输：客户端（或公网 Host）连到 relay 服务器。
# URL 形如 ws://relay.example.com:8080/ws?room=ABCD&role=host
# 服务器负责房间配对与转发，客户端之间零 NAT 依赖。
class_name RelayTransport
extends NetTransport

const PROTO_VERSION: int = 2

var _ws: WebSocketPeer = null
var _url: String = ""
var _room: String = ""
var _role: String = "client"
var _display_name: String = ""
var _reconnect_tries: int = 0
var _ping_sent_at: int = 0
var _ping_timer: float = 0.0
var _closed_by_user: bool = false


func connect_to(url: String, opts: Dictionary = {}) -> bool:
	_room = str(opts.get("room", "LOBBY"))
	_role = str(opts.get("role", "client"))
	_display_name = str(opts.get("name", "Player"))
	_closed_by_user = false
	_url = url
	if _url.ends_with("/"):
		_url = _url.substr(0, _url.length() - 1)
	if not _url.contains("/ws"):
		_url += "/ws"
	_url += "?room=%s&role=%s&name=%s&v=%d" % [_room.uri_encode(), _role, _display_name.uri_encode(), PROTO_VERSION]
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 512 * 1024
	_ws.outbound_buffer_size = 512 * 1024
	var err: int = _ws.connect_to_url(_url, TLSOptions.client())
	if err != OK:
		last_error = "连接失败 (%d)" % err
		return false
	is_host = _role == "host"
	return true


func poll() -> void:
	if _ws == null:
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	match st:
		WebSocketPeer.STATE_OPEN:
			if local_id < 0:
				# 服务器会先推 welcome 帧
				pass
			while _ws.get_available_packet_count() > 0:
				var pkt: PackedByteArray = _ws.get_packet()
				bytes_in += pkt.size()
				_handle_frame(pkt)
		WebSocketPeer.STATE_CLOSED:
			if not _closed_by_user:
				disconnected.emit("relay closed (%d)" % _ws.get_close_code())
			_ws = null


func _handle_frame(pkt: PackedByteArray) -> void:
	# 中继控制帧：0x10 + utf8 json
	if pkt.size() > 1 and pkt[0] == 0x10:
		var txt: String = pkt.slice(1).get_string_from_utf8()
		var obj: Variant = JSON.parse_string(txt)
		if obj is Dictionary:
			_handle_control(obj)
		return
	# 游戏帧：0x02 [u16 from] [payload]
	if pkt.size() > 3 and pkt[0] == 0x02:
		var from: int = pkt.decode_u16(1)
		var body: PackedByteArray = pkt.slice(3)
		packet.emit(from, body)
		return
	if pkt.size() >= 5:
		# 兼容直发（无信封）
		packet.emit(0, pkt)


func _handle_control(o: Dictionary) -> void:
	match str(o.get("t", "")):
		"welcome":
			local_id = int(o.get("id", 0))
			connected.emit()
			print("[Net] relay welcome id=%d room=%s" % [local_id, _room])
		"peer_join":
			peer_joined.emit(int(o.get("id", -1)), str(o.get("name", "")))
		"peer_leave":
			peer_left.emit(int(o.get("id", -1)), str(o.get("reason", "")))
		"error":
			last_error = str(o.get("msg", "relay error"))
			disconnected.emit(last_error)
		"pong":
			rtt_ms = Time.get_ticks_msec() - _ping_sent_at
		"room_state":
			pass


func ping() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ping_sent_at = Time.get_ticks_msec()
	send_control({"t": "ping"})


func send_control(o: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var buf := PackedByteArray()
	buf.append(0x10)
	buf.append_array(JSON.stringify(o).to_utf8_buffer())
	_ws.send(buf)


func send(id: int, data: PackedByteArray) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var out := PackedByteArray()
	out.append(0x01)
	var tb := PackedByteArray()
	tb.resize(2)
	tb.encode_u16(0, id)
	out.append_array(tb)
	out.append_array(data)
	_ws.send(out)
	bytes_out += out.size()


func broadcast(data: PackedByteArray, _except: int = -1) -> void:
	send(0xFFFF, data)


func close(reason: String = "") -> void:
	_closed_by_user = true
	if _ws != null:
		_ws.close(1000, reason)
		_ws = null
	disconnected.emit(reason)


func is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func state_text() -> String:
	if _ws == null:
		return "未连接"
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			return "连接中…"
		WebSocketPeer.STATE_OPEN:
			return "已连接"
		WebSocketPeer.STATE_CLOSING:
			return "断开中…"
		WebSocketPeer.STATE_CLOSED:
			return "已断开"
	return "未知"
