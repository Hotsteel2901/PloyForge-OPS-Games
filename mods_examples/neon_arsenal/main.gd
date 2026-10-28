# neon_arsenal 主入口。
# 这里只演示 API 的 5%：完整参考见 docs/MODDING.md。
extends ModBase


func setup(ctx: ModContext) -> void:
	ctx.log("hello from neon_arsenal")

	# 1) 注册一把武器（字段可只写必要项，其余走默认值）
	ctx.add_weapon(ctx.quick_weapon("spark", "Spark 电浆枪", 34.0, 700, {
		"magSize": 24, "reserve": 96, "spread": 0.022, "adsSpread": 0.006,
		"recoil": 0.018, "cost": 3100, "category": "rifle",
		"desc": "模组示例武器：稳定的三连发。",
	}))

	# 2) 事件钩子：每次有人出生，回满护甲
	ctx.on("player_spawn", func(payload: Dictionary) -> void:
		var id: String = str(payload.get("id", ""))
		print("[neon_arsenal] spawn ", id)
	)

	# 3) 每回合开始做点事
	ctx.on("round_start", func(_info: Dictionary) -> void:
		ctx.log("round start")
	)


func teardown() -> void:
	pass
