# ADS scope overlay drawn with CanvasItem primitives.
# Per-weapon reticles: pistols/none, SMGs simple ring, rifles cross,
# shotguns open circle, LMG front post, snipers heavy mil-dot cross.
class_name ScopeOverlay
extends Control

var _weapon_id: String = ""
var _ads: bool = false
var _ads_t: float = 0.0
var _color: Color = Color(0.18, 0.95, 0.35, 0.92)
var _dim: Color = Color(0.08, 0.4, 0.14, 0.7)

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func set_scope(weapon_id: String, ads: bool) -> void:
	# 脏检查：武器/ADS 状态未变则不重绘（消除每帧全屏 queue_redraw）
	if _weapon_id == weapon_id and _ads == ads:
		return
	_weapon_id = weapon_id
	_ads = ads
	queue_redraw()


func _process(delta: float) -> void:
	var target: float = 1.0 if _ads and _weapon_id != "" and not _no_scope() else 0.0
	if absf(_ads_t - target) > 0.001:
		_ads_t = lerpf(_ads_t, target, minf(1.0, delta * 10.0))
		queue_redraw()


func _no_scope() -> bool:
	# pistols, knife, grenade, zombie claws have no scope frame
	match _weapon_id:
		"fang", "pc", "pf", "thunder", "zclaw":
			return true
	return false


func _draw() -> void:
	if _ads_t < 0.01:
		return
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var base: float = minf(size.x, size.y) * 0.006
	var alpha: float = _ads_t
	var c: Color = Color(_color.r, _color.g, _color.b, _color.a * alpha)
	var dim: Color = Color(_dim.r, _dim.g, _dim.b, _dim.a * alpha)

	match _weapon_id:
		"longshot", "sm", "sr":
			_draw_sniper(cx, cy, base, c, dim)
		"warden":
			_draw_aug(cx, cy, base, c, dim)
		"bruiser":
			_draw_lmg(cx, cy, base, c, dim)
		"sa", "sp":
			_draw_shotgun(cx, cy, base, c, dim)
		"k9", "sc", "sf":
			_draw_smg(cx, cy, base, c, dim)
		"vx9", "arc17", "ra", "rb":
			_draw_rifle(cx, cy, base, c, dim)
		_:
			_draw_rifle(cx, cy, base, c, dim)


func _draw_sniper(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# thick crosshair with mil-dot marks and a thin outer ring
	var lw: float = maxf(1.5, base * 0.55)
	var gap: float = base * 5.0
	var r: float = minf(size.x, size.y) * 0.18
	var inner: float = r * 0.45
	_draw_cross(cx, cy, gap, lw, c)
	# outer thin ring
	draw_arc(Vector2(cx, cy), r, 0.0, TAU, 64, Color(c.r, c.g, c.b, c.a * 0.45), 1.2, true)
	# mil dots
	for i in range(1, 4):
		var off: float = gap + base * 5.0 * i
		draw_circle(Vector2(cx + off, cy), base * 0.45, c)
		draw_circle(Vector2(cx - off, cy), base * 0.45, c)
		draw_circle(Vector2(cx, cy + off), base * 0.45, c)
		draw_circle(Vector2(cx, cy - off), base * 0.45, c)
	# center dot
	draw_circle(Vector2(cx, cy), base * 0.6, Color(1.0, 1.0, 1.0, c.a * 0.95))


func _draw_aug(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# AUG already has a scope tube in viewmodel, keep overlay minimal
	var gap: float = base * 4.0
	_draw_cross(cx, cy, gap, maxf(1.2, base * 0.4), c)
	var r: float = minf(size.x, size.y) * 0.12
	draw_arc(Vector2(cx, cy), r, 0.0, TAU, 48, Color(c.r, c.g, c.b, c.a * 0.35), 1.0, true)


func _draw_lmg(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# iron sight style: top horizontal post + small center dot
	var lw: float = maxf(1.5, base * 0.5)
	var gap: float = base * 3.5
	var w: float = base * 18.0
	draw_line(Vector2(cx - w, cy - gap), Vector2(cx + w, cy - gap), c, lw)
	draw_line(Vector2(cx, cy - gap), Vector2(cx, cy - gap - base * 5.0), c, lw)
	draw_circle(Vector2(cx, cy), base * 0.5, c)


func _draw_shotgun(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# open circle with cross
	var r: float = minf(size.x, size.y) * 0.06
	draw_arc(Vector2(cx, cy), r, 0.0, TAU, 48, c, maxf(1.2, base * 0.4), true)
	_draw_cross(cx, cy, base * 3.0, maxf(1.2, base * 0.4), c)


func _draw_smg(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# simple ring + dot
	var r: float = minf(size.x, size.y) * 0.05
	draw_arc(Vector2(cx, cy), r, 0.0, TAU, 40, c, maxf(1.2, base * 0.4), true)
	draw_circle(Vector2(cx, cy), base * 0.55, c)


func _draw_rifle(cx: float, cy: float, base: float, c: Color, dim: Color) -> void:
	# cross with small hash marks
	var lw: float = maxf(1.2, base * 0.4)
	var gap: float = base * 3.0
	_draw_cross(cx, cy, gap, lw, c)
	# hash marks
	var mark: float = base * 3.0
	for side in [-1, 1]:
		draw_line(Vector2(cx + side * (gap + mark), cy - base), Vector2(cx + side * (gap + mark), cy + base), c, lw)
		draw_line(Vector2(cx - base, cy + side * (gap + mark)), Vector2(cx + base, cy + side * (gap + mark)), c, lw)


func _draw_cross(cx: float, cy: float, gap: float, lw: float, c: Color) -> void:
	var arm: float = minf(size.x, size.y) * 0.12
	draw_line(Vector2(cx - arm, cy), Vector2(cx - gap, cy), c, lw)
	draw_line(Vector2(cx + gap, cy), Vector2(cx + arm, cy), c, lw)
	draw_line(Vector2(cx, cy - arm), Vector2(cx, cy - gap), c, lw)
	draw_line(Vector2(cx, cy + gap), Vector2(cx, cy + arm), c, lw)
