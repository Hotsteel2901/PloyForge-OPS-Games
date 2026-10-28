# 网络传输抽象层。
# 所有传输共享同一套二进制协议：WS 帧 = [u8 kind][payload(var_to_bytes)]。
# Host 侧既可以直接开内置 WebSocket 服务端（局域网/公网直连），
# 也可以反向连到中继服务器（房间模式，穿透一切 NAT/防火墙）。
class_name NetTransport
extends RefCounted

signal connected()
signal disconnected(reason: String)
signal peer_joined(id: int, name: String)
signal peer_left(id: int, reason: String)
signal packet(id: int, data: PackedByteArray)

var local_id: int = -1
var is_host: bool = false
var rtt_ms: int = 0
var last_error: String = ""
var bytes_in: int = 0
var bytes_out: int = 0


func start_host(_port: int) -> bool:
	return false


func connect_to(_url: String, _opts: Dictionary = {}) -> bool:
	return false


func poll() -> void:
	pass


func send(_id: int, _data: PackedByteArray) -> void:
	pass


func broadcast(_data: PackedByteArray, _except: int = -1) -> void:
	pass


func close(_reason: String = "") -> void:
	pass


func is_open() -> bool:
	return false


func peer_count() -> int:
	return 0


# ---------------- 编码工具 ----------------

static func pack(kind: int, payload: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(kind)
	var body: PackedByteArray = var_to_bytes(payload)
	var lenb := PackedByteArray()
	lenb.resize(4)
	lenb.encode_u32(0, body.size())
	out.append_array(lenb)
	out.append_array(body)
	return out


static func unpack(data: PackedByteArray) -> Dictionary:
	if data.size() < 5:
		return {}
	var kind: int = data[0]
	var n: int = data.decode_u32(1)
	if data.size() < 5 + n:
		return {}
	var body: Variant = bytes_to_var(data.slice(5, 5 + n))
	if body == null or not (body is Dictionary):
		return {}
	return {"kind": kind, "data": body}
