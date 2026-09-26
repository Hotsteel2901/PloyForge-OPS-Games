extends Node

# 超长时生化模式模拟：跑 20 分钟游戏时间（多回合+换图），用日志检测死循环/卡死。
# 用法: godot --headless --path . res://tools/_zombie_long.tscn

func _ready() -> void:
	var room := Room.new({
		"id": "test",
		"mode": Constants.MODE_ZOMBIE,
		"mapId": "containment",
		"botCount": 10,
		"maxPlayers": 12,
	})
	room.start()
	var last_log: int = 0
	var total_ticks: int = 30 * 60 * 20  # 20 分钟
	for tick in range(total_ticks):
		room.tick()
		if tick - last_log >= 30 * 30:
			last_log = tick
			var t: float = room.state.time
			var p_count: int = room.state.players.size()
			var alive: int = 0
			var zombies: int = 0
			for p in room.state.players.values():
				if p.alive:
					alive += 1
					if p.isZombie:
						zombies += 1
			var core_s: String = room.state.core.state if room.state.core != null else "null"
			var map: String = room.state.mapId
			print("[ZL] t=%.0f map=%s round=%d phase=%s core=%s alive=%d zombie=%d players=%d projs=%d" % [
				t, map, room.state.roundNum, room.state.phase, core_s, alive, zombies, p_count, room.state.projectiles.size()])
	print("[ZL] DONE rounds=", room.state.roundNum, " map=", room.state.mapId, " score=", room.state.matchScore)
	get_tree().quit()
