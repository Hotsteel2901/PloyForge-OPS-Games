# 局域网发现：UDP 广播房主信息（无需中继即可在局域网内互见）。
class_name LanDiscovery
extends RefCounted

const PORT: int = 7778
const MAGIC: String = "PF2LAN"

var _udp: PacketPeerUDP = null
var _broadcast_timer: float = 0.0
var _rooms: Dictionary = {}
var _serving: bool = false
var _info: Dictionary = {}


func start_advertise(info: Dictionary) -> void:
	stop()
	_info = info
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_serving = true
	print("[LAN] advertising on %d" % PORT)


func start_listen() -> void:
	stop()
	_udp = PacketPeerUDP.new()
	var err: int = _udp.bind(PORT, "0.0.0.0")
	if err != OK:
		push_warning("[LAN] bind failed %d" % err)
	_serving = false


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	_rooms.clear()


func poll(dt: float) -> void:
	if _udp == null:
		return
	if _serving:
		_broadcast_timer += dt
		if _broadcast_timer >= 1.0:
			_broadcast_timer = 0.0
			var msg: Dictionary = _info.duplicate()
			msg["magic"] = MAGIC
			msg["t"] = Time.get_ticks_msec()
			_udp.set_dest_address("255.255.255.255", PORT)
			_udp.put_packet(JSON.stringify(msg).to_utf8_buffer())
	while _udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _udp.get_packet()
		var ip: String = _udp.get_packet_ip()
		var obj: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not (obj is Dictionary) or str(obj.get("magic", "")) != MAGIC:
			continue
		obj["ip"] = ip
		obj["seen"] = Time.get_ticks_msec()
		_rooms[str(obj.get("room", ip))] = obj


func rooms() -> Array:
	var now: int = Time.get_ticks_msec()
	var out: Array = []
	for k in _rooms.keys():
		var r: Dictionary = _rooms[k]
		if now - int(r.seen) > 4000:
			_rooms.erase(k)
			continue
		out.append(r)
	return out
