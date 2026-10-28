# 硬核模式 · Hardcore
#
# 这是「自定义游戏模式」的最小示例：
#   - 注册一个新模式 id（hardcore）
#   - 继承 ModeBase，自己决定出生、计分、胜负
#   - 用 modc 打包后，主菜单会自动多出一个「硬核死斗」按钮
#
# 打包： python3 tools/modc/modc.py build mods_examples/hardcore
extends ModBase


func setup(ctx: ModContext) -> void:
	ctx.add_mode({
		"id": "hardcore",
		"label": "硬核死斗",
		"short": "HC",
		"desc": "一滴血、无护甲、武器随机。谁先到 15 杀谁赢。",
		"min": 2, "max": 12, "color": "ff3d5a", "tag": "MOD",
	}, func() -> ModeBase:
		return HardcoreMode.new()
	)
	ctx.log("hardcore mode registered")


## 模式实现。注意：内部类不能带 class_name，直接 extends ModeBase。
class HardcoreMode extends ModeBase:
	func _init() -> void:
		id = "hardcore"
		label = "硬核死斗"
		short = "HC"
		desc = "一滴血、无护甲、武器随机。"
		team_based = false
		respawn = true
		respawn_delay = 1.5
		round_time = 300.0
		score_limit = 15
		uses_money = false
		needs_sites = false
		columns = ["kills", "deaths", "score"]

	func setup(room) -> void:
		room.state.core = Room.RoundCore.new(round_time, 0.0)

	func start_round(room) -> void:
		for p in room.state.players.values():
			p.team = Constants.TEAM_NONE
			p.isZombie = false
			p.kills = 0
			p.deaths = 0
			p.score = 0
		room.spawn_all()
		if room.state.core != null:
			room.state.core.begin(round_time)

	## 每次出生：1 血、无甲、随机主武器
	func on_player_spawn(room, p: Dictionary) -> void:
		p.hp = 1.0
		p.maxHp = 1.0
		p.armor = 0
		var pool: Array = ["vx9", "arc17", "warden", "longshot", "sf"]
		var wid: String = str(pool[randi() % pool.size()])
		var def: Dictionary = WeaponDB.get_def(wid)
		if def.is_empty():
			return
		p.weapons.clear()
		p.weapons[2] = WeaponData.WeaponRuntime.new(def)
		p.activeSlot = 2

	func on_kill(room, victim: Dictionary, killer: Variant, _info: Dictionary) -> bool:
		if killer != null and killer != victim:
			killer.score += 10
			if int(killer.kills) >= score_limit:
				if room.state.core != null:
					room.state.core.end_round(str(killer.team), "score_limit")
		victim.respawnAt = room.state.time + respawn_delay
		return true

	func on_tick(room, dt: float) -> void:
		var core = room.state.core
		if core == null or core.state != "live":
			return
		core.time_left -= dt
		if core.time_left <= 0.0:
			core.end_round("DRAW", "timeout")

	func award_round(room, winner: String, reason: String) -> void:
		room.finish_round(winner, reason, true, 6.0)
