# 内置 WebSocket 服务端传输（Host 侧直连）。
# 端口默认 7777。支持局域网与公网端口映射，无需额外服务进程。
class_name WsHostTransport
extends NetTransport

const MAX_PEERS: int = 16

var _tcp: TCPServer = null
var _port: int = 7777
var _peers: Dictionary = {}      # id -> WebSocketPeer
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func start_host(port: int) -> bool:
	close("")
	_port = port
	_tcp = TCPServer.new()
	var err: int = _tcp.listen(port, "0.0.0.0")
	if err != OK:
		last_error = "端口 %d 监听失败 (%d)" % [port, err]
		return false
	local_id = 0
	is_host = true
	_rng.randomize()
	print("[Net] WebSocket host on :%d" % port)
	connected.emit()
	return true


func poll() -> void:
	if _tcp == null:
		return
	# 接受新连接
	while _tcp.is_connection_available():
		var conn: StreamPeerTCP = _tcp.take_connection()
		if conn == null:
			break
		if _peers.size() >= MAX_PEERS:
			conn.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 256 * 1024
		ws.outbound_buffer_size = 256 * 1024
		var e: int = ws.accept_stream(conn)
		if e != OK:
			continue
		_peers[_next_id] = ws
		_next_id += 1
	# 轮询各 peer
	for id in _peers.keys():
		var ws: WebSocketPeer = _peers[id]
		ws.poll()
		var st: int = ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var pkt: PackedByteArray = ws.get_packet()
				bytes_in += pkt.size()
				packet.emit(int(id), pkt)
		elif st == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			peer_left.emit(int(id), "closed")
			ws.close()


func send(id: int, data: PackedByteArray) -> void:
	if not _peers.has(id):
		return
	var ws: WebSocketPeer = _peers[id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(data)
		bytes_out += data.size()


func broadcast(data: PackedByteArray, except: int = -1) -> void:
	for id in _peers:
		if int(id) == except:
			continue
		send(int(id), data)


func close(reason: String = "") -> void:
	for id in _peers:
		var ws: WebSocketPeer = _peers[id]
		ws.close(1000, reason)
	_peers.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	if is_host:
		disconnected.emit(reason)


func is_open() -> bool:
	return _port > 0 and _tcp != null


func peer_count() -> int:
	return _peers.size()


func peer_ids() -> Array:
	return _peers.keys()


func port() -> int:
	return _port


## 建议连接地址（供 UI 展示）
func advertise_urls() -> Array:
	var urls: Array = []
	var ips: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("127.") or a.begins_with("0.") or a.contains(":"):
			continue
		ips.append(a)
	for ip in ips:
		urls.append("ws://%s:%d" % [ip, _port])
	return urls
