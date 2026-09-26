extends Node

# 窗口模式特效高压测试：模拟 10 个丧尸 bot 高频近战（每帧多次 tracer/muzzle/blood/impact/explosion），
# 监控 effects 节点是否累积（卡死闪退的根源）。
# 用法: godot --path . res://tools/_fx_stress.tscn

var fx: Effects
var _t: float = 0.0
var _last_log: float = 0.0

func _ready() -> void:
	fx = Effects.new()
	fx.name = "Effects"
	add_child(fx)
	print("[FX] start")

func _process(delta: float) -> void:
	_t += delta
	# 模拟 10 个丧尸 bot 每帧攻击：每次近战 = 1 tracer + 1 muzzle + 1 impact + 0.5 blood
	for i in 10:
		var p := Vector3(randf_range(-20, 20), randf_range(0, 2), randf_range(-20, 20))
		fx.tracer(p, p + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		fx.muzzle_flash(p)
		fx.impact(p)
		if i % 2 == 0:
			fx.blood(p)
	# 偶尔手雷爆炸（生化模式投掷物少，但拆弹有）
	if int(_t * 2) % 10 == 0:
		fx.explosion(Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)), 8.0)
	# 每 10 秒打印节点状态
	if _t - _last_log >= 10.0:
		_last_log = _t
		print("[FX] t=%.0f children=%d trails=%d decals=%d casings=%d flash_lights=%d expl_lights=%d mem=%.1fMB" % [
			_t, fx.get_child_count(), fx._trail_nodes.size(), fx._decal_nodes.size(), fx._casings.size(),
			fx._flash_lights.size(), fx._explosion_lights.size(),
			float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)])
	if _t >= 90.0:
		print("[FX] DONE children=%d trails=%d decals=%d casings=%d expl_lights=%d" % [
			fx.get_child_count(), fx._trail_nodes.size(), fx._decal_nodes.size(), fx._casings.size(), fx._explosion_lights.size()])
		get_tree().quit()
