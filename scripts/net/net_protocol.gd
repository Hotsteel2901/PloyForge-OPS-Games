# 网络协议定义（v2）。所有消息 = [u8 op][u32 len][var_to_bytes(dict)]
class_name NetProtocol
extends RefCounted

const VERSION: int = 2
const PORT: int = 7777
const TICK_RATE: int = 30
const SNAPSHOT_RATE: int = 20

enum Op {
	HELLO = 1,
	WELCOME = 2,
	REJECT = 3,
	INPUT = 4,
	SNAPSHOT = 5,
	EVENT = 6,
	CHAT = 7,
	PING = 8,
	PONG = 9,
	BUY = 10,
	CMD = 11,
	LEAVE = 12,
	PONG_CLOCK = 13,
	SELECT_TEAM = 14,
}

const REJECT_TEXT: Dictionary = {
	"full": "房间已满",
	"version": "客户端版本不匹配",
	"banned": "你已被移出房间",
	"starting": "比赛正在开始",
}


static func encode(op: int, payload: Dictionary) -> PackedByteArray:
	return NetTransport.pack(op, payload)


static func decode(data: PackedByteArray) -> Dictionary:
	return NetTransport.unpack(data)


## 玩家状态压缩：只传变化量大的字段，快照体积约为 JSON 的 1/3
static func pack_player(p: Dictionary) -> Array:
	var w: Variant = p.weapons.get(int(p.activeSlot), null)
	return [
		str(p.get("id", "")), str(p.get("name", "")), int(p.get("team", 0)),
		snappedf(p.pos.x, 0.01), snappedf(p.pos.y, 0.01), snappedf(p.pos.z, 0.01),
		snappedf(float(p.yaw), 0.001), snappedf(float(p.pitch), 0.001),
		int(ceil(float(p.hp))), 1 if p.alive else 0, 1 if p.crouch else 0,
		1 if p.isZombie else 0, int(p.armor), int(p.kills), int(p.deaths), int(p.score),
		str(w.def.id) if w != null else "k9",
		int(w.ammo) if w != null else 0,
		int(w.reserve) if w != null else 0,
		int(p.money), int(p.grenadeCount), int(p.get("weaponLevel", 0)),
	]


static func unpack_player(a: Array) -> Dictionary:
	if a.size() < 16:
		return {}
	return {
		"id": str(a[0]), "name": str(a[1]), "team": int(a[2]),
		"pos": Vector3(float(a[3]), float(a[4]), float(a[5])),
		"yaw": float(a[6]), "pitch": float(a[7]),
		"hp": int(a[8]), "alive": int(a[9]) == 1, "crouch": int(a[10]) == 1,
		"isZombie": int(a[11]) == 1, "armor": int(a[12]),
		"kills": int(a[13]), "deaths": int(a[14]), "score": int(a[15]),
		"weapon": str(a[16]) if a.size() > 16 else "k9",
		"ammo": int(a[17]) if a.size() > 17 else 0,
		"reserve": int(a[18]) if a.size() > 18 else 0,
		"money": int(a[19]) if a.size() > 19 else 0,
		"grenades": int(a[20]) if a.size() > 20 else 0,
		"weaponLevel": int(a[21]) if a.size() > 21 else 0,
	}
