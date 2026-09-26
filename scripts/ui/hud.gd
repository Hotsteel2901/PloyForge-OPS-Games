class_name HUD
extends CanvasLayer

# (UI)
const CT_COLOR := Color("5a9dff")
const T_COLOR := Color("ff8b3d")
const ACCENT := Color("ffd83d")
const HP_LOW := Color("ff3d2e")
const HP_HIGH := Color("ffb03d")
const PANEL_BG := Color(0.02, 0.03, 0.05, 0.55)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.22)

var _root: Control
var _t: float = 0.0
var _dmg_flash: float = 0.0
var _local_name: String = ""
var _zombie_mode: bool = false
var _finale_pulse: bool = false
var _bomb_state: int = 0
var _bomb_site: String = ""
var _bomb_time: float = 0.0

var _hp_bar: Bar
var _armor_bar: Bar
var _hp_number: Label
var _armor_number: Label
var _money_label: Label
var _zombie_icon: Control
var _bl_hl: VBoxContainer

var _wpn_name: Label
var _ammo_mag: Label
var _ammo_res: Label
var _icon_code: Label
var _ads_hint: Label

var _timer_label: Label
var _score_ct: Label
var _score_t: Label
var _round_label: Label
var _phase_label: Label
var _bomb_label: Label
var _tc_box: VBoxContainer

var _msg_label: Label
var _msg_tween: Tween = null
var _banner: PanelContainer
var _banner_label: Label
var _banner_tween: Tween = null
var _use_panel: PanelContainer
var _use_label: Label
var _use_bar: Bar
var _respawn_label: Label

var _crosshair: Crosshair
var _scope: ScopeOverlay
var _dmg_vign: TextureRect
var _hp_vign: TextureRect
var _ads_vign: TextureRect
var _ads_vign_target: float = 0.0
var _feed: VBoxContainer


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_bottom_left()
	_build_bottom_right()
	_build_top_center()
	_build_center()
	_build_banner()
	_build_kill_feed()
	_build_crosshair()
	_build_vignettes()
	_root.visible = true


func _process(delta: float) -> void:
	_t += delta
	if _dmg_flash > 0.0:
		_dmg_flash = maxf(0.0, _dmg_flash - delta * 2.6)
	_dmg_vign.modulate.a = _dmg_flash
	var pulse: float = 0.0
	if _hp_vign.visible and _hp_bar != null:
		pulse = 0.22 + 0.14 * sin(_t * 6.0)
		_hp_vign.modulate.a = pulse
	if _bomb_state == 2 and _bomb_label.visible:
		_bomb_label.modulate.a = 0.65 + 0.35 * sin(_t * 8.0)
	# 布尔标志替代每帧字符串搜索
	if _finale_pulse:
		_phase_label.modulate.a = 0.6 + 0.4 * sin(_t * 5.0)
	else:
		_phase_label.modulate.a = 1.0
	if _ads_vign != null:
		var cur: float = _ads_vign.modulate.a
		var nxt: float = lerpf(cur, _ads_vign_target, minf(1.0, delta * 6.0))
		_ads_vign.modulate.a = nxt


func hide_ui() -> void:
	_root.visible = false


func show_ui() -> void:
	_root.visible = true


func get_crosshair_info() -> Dictionary:
	if _crosshair == null:
		return {"null": true}
	var sp: String = ""
	if _crosshair.get_script() != null:
		sp = str(_crosshair.get_script().resource_path)
	return {"script": sp, "visible": _crosshair.visible, "root_visible": _root.visible, "in_tree": _crosshair.is_inside_tree(), "size": _crosshair.size, "gap": _crosshair.gap, "spread": _crosshair.spread01, "ads": _crosshair.ads, "process": _crosshair.is_processing(),
		"timer": {"t": _timer_label.text, "vis": _timer_label.visible, "pos": _timer_label.position, "sz": _timer_label.size, "gsz": _timer_label.get_global_rect()},
		"phase": {"t": _phase_label.text, "vis": _phase_label.visible},
		"round": {"t": _round_label.text, "vis": _round_label.visible},
		"hp": {"t": _hp_number.text if _hp_number != null else "n/a"},
		"wpn": {"t": _wpn_name.text, "vis": _wpn_name.visible}}


# (UI)
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int, color: Color, parent: Node, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l


func _build_bottom_left() -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(20, -140)
	box.size = Vector2(260, 120)
	box.add_theme_stylebox_override("panel", _panel_style())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_bl_hl = VBoxContainer.new()
	_bl_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bl_hl.add_theme_constant_override("separation", 4)
	box.add_child(_bl_hl)

	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", 8)
	_bl_hl.add_child(hp_row)
	_hp_number = _label("100", 30, Color.WHITE, hp_row)
	_hp_bar = Bar.new()
	_hp_bar.color = HP_HIGH
	_hp_bar.custom_minimum_size = Vector2(150, 10)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_zombie_icon = ZombieIcon.new()
	_zombie_icon.custom_minimum_size = Vector2(22, 22)
	_zombie_icon.visible = false
	hp_row.add_child(_zombie_icon)

	var armor_row := HBoxContainer.new()
	armor_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armor_row.add_theme_constant_override("separation", 8)
	_bl_hl.add_child(armor_row)
	_armor_number = _label("0", 16, Color.WHITE, armor_row)
	_armor_number.custom_minimum_size = Vector2(34, 0)
	_armor_bar = Bar.new()
	_armor_bar.color = CT_COLOR
	_armor_bar.custom_minimum_size = Vector2(150, 8)
	_armor_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	armor_row.add_child(_armor_bar)

	_money_label = _label("$800", 20, ACCENT, _bl_hl)


func _build_bottom_right() -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-320, -118)
	box.size = Vector2(300, 98)
	box.add_theme_stylebox_override("panel", _panel_style())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var hl := HBoxContainer.new()
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.add_theme_constant_override("separation", 10)
	box.add_child(hl)

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(64, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.25, 0.3, 0.42, 0.5)
	isb.border_color = PANEL_BORDER
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(6)
	icon.add_theme_stylebox_override("panel", isb)
	hl.add_child(icon)
	_icon_code = Label.new()
	_icon_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_code.add_theme_font_size_override("font_size", 14)
	_icon_code.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.9))
	icon.add_child(_icon_code)

	var vl := VBoxContainer.new()
	vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vl.alignment = BoxContainer.ALIGNMENT_END
	hl.add_child(vl)
	_wpn_name = _label("", 14, Color(0.8, 0.84, 0.9), vl)
	var ammo_row := HBoxContainer.new()
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_row.add_theme_constant_override("separation", 6)
	vl.add_child(ammo_row)
	_ammo_mag = _label("0", 30, Color.WHITE, ammo_row)
	_ammo_res = _label("", 16, Color(0.62, 0.66, 0.72), ammo_row)
	_ammo_res.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_res.add_theme_constant_override("outline_size", 0)
	_ads_hint = _label("", 12, Color(0.6, 0.85, 1.0, 0.85), vl)


func _build_top_center() -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-320, 8)
	box.size = Vector2(640, 132)
	box.add_theme_stylebox_override("panel", _panel_style())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_tc_box = VBoxContainer.new()
	_tc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tc_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_tc_box)

	var score_row := HBoxContainer.new()
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 12)
	_tc_box.add_child(score_row)
	_score_ct = _label("0", 26, CT_COLOR, score_row)
	_score_t = _label("0", 26, T_COLOR, score_row)

	_timer_label = _label("00:00", 34, Color.WHITE, _tc_box)
	_round_label = _label("", 12, Color(0.7, 0.74, 0.8), _tc_box)
	_phase_label = _label("", 13, ACCENT, _tc_box)
	_bomb_label = _label("", 15, Color(1.0, 0.35, 0.3), _tc_box)


func _build_center() -> void:
	_msg_label = _label("", 42, Color.WHITE, _root)
	_msg_label.set_anchors_preset(Control.PRESET_CENTER)
	_msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_msg_label.add_theme_constant_override("outline_size", 6)
	_msg_label.position.y -= 140


# 胜负大横幅：CS 风格居中大字 + 背景条 + 弹出动画（胜利金 / 失败红）
func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.position = Vector2(0, -170)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.74)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 52
	sb.content_margin_right = 52
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	_banner.add_theme_stylebox_override("panel", sb)
	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.add_theme_font_size_override("font_size", 84)
	_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_banner_label.add_theme_constant_override("outline_size", 18)
	_banner.add_child(_banner_label)
	_root.add_child(_banner)


func show_banner(text: String, win: bool) -> void:
	if _banner == null or _banner_label == null:
		show_message(text, 4.0)
		return
	if _banner_tween != null:
		_banner_tween.kill()
	if _msg_tween != null:
		_msg_tween.kill()
	_msg_label.text = ""
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", Color("ffd83d") if win else Color("ff5a4d"))
	_banner.visible = true
	_banner.reset_size()
	_banner.pivot_offset = _banner.size / 2.0
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(1.3, 1.3)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.12)
	_banner_tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(4.0)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)

	_use_panel = PanelContainer.new()
	_use_panel.set_anchors_preset(Control.PRESET_CENTER)
	_use_panel.position = Vector2(-190, 190)
	_use_panel.size = Vector2(380, 66)
	_use_panel.add_theme_stylebox_override("panel", _panel_style())
	_use_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_panel.visible = false
	_root.add_child(_use_panel)
	var uv := VBoxContainer.new()
	uv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uv.add_theme_constant_override("separation", 4)
	_use_panel.add_child(uv)
	_use_label = _label("", 16, Color.WHITE, uv)
	_use_bar = Bar.new()
	_use_bar.color = ACCENT
	_use_bar.custom_minimum_size = Vector2(340, 8)
	uv.add_child(_use_bar)

	_respawn_label = _label("", 34, Color(1.0, 0.85, 0.4), _root)
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_kill_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-360, 20)
	_feed.size = Vector2(340, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 4)
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_feed)


func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	_scope = ScopeOverlay.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scope)


func _build_vignettes() -> void:
	_dmg_vign = _make_vignette(Color(0.0, 0.0, 0.0, 0.0), Color(0.85, 0.12, 0.08, 0.55))
	_root.add_child(_dmg_vign)
	_hp_vign = _make_vignette(Color(0.0, 0.0, 0.0, 0.0), Color(0.85, 0.16, 0.08, 0.4))
	_hp_vign.visible = false
	_root.add_child(_hp_vign)
	_ads_vign = _make_vignette(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.55))
	_ads_vign.visible = true
	_ads_vign.modulate.a = 0.0
	_root.add_child(_ads_vign)


func _make_vignette(inner: Color, edge: Color) -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([inner, inner, edge])
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	return tr


# (UI) 每帧更新——脏检查缓存：文本/颜色/数值未变则跳过，
# 消除每帧 ~15 次 Label 格式化 + theme override 写入（Web 单线程敏感）
var _ulc_cache: Dictionary = {}


func update_local_player(p: Dictionary) -> void:
	if p.is_empty() or _root == null:
		return
	var hp: float = float(p.get("h", p.get("hp", 100.0)))
	var max_hp: float = float(p.get("mx", p.get("maxHp", 100.0)))
	var armor: float = float(p.get("a", p.get("armor", 0)))
	var money: int = int(p.get("mo", p.get("money", 0)))
	var alive: bool = true
	if p.has("al"):
		alive = int(p.get("al", 1)) != 0
	elif p.has("alive"):
		alive = bool(p.get("alive", true))
	var zombie: bool = int(p.get("zb", 0)) != 0 or bool(p.get("isZombie", false))
	_local_name = str(p.get("n", _local_name))
	var wpn_id: String = _read_weapon_id(p)
	var ammo: int = int(p.get("am", p.get("ammo", 0)))
	var reserve: int = int(p.get("rs", p.get("reserve", 0)))
	var ads: bool = false
	var inp: Variant = p.get("input", null)
	if inp is Dictionary:
		ads = bool(inp.get("ads", false))

	var frac: float = 1.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)
	var hp_color: Color = HP_LOW.lerp(HP_HIGH, frac)
	var hp_int: int = int(ceil(hp))
	if _ulc_cache.get("hp", -1) != hp_int or _ulc_cache.get("alive", false) != alive:
		_ulc_cache["hp"] = hp_int
		_ulc_cache["alive"] = alive
		_hp_number.text = str(hp_int if alive else 0)
		_hp_number.add_theme_color_override("font_color", hp_color)
		_hp_bar.value = frac
		_hp_bar.color = hp_color
	if _ulc_cache.get("armor", -1) != int(armor) or _ulc_cache.get("zombie", false) != zombie:
		_ulc_cache["armor"] = int(armor)
		_ulc_cache["zombie"] = zombie
		_armor_number.text = str(int(armor))
		_armor_bar.value = clampf(armor / 100.0, 0.0, 1.0)
		_armor_bar.visible = not zombie
		_armor_number.visible = not zombie
		_money_label.visible = not zombie
		_zombie_icon.visible = zombie
		_hp_number.add_theme_font_size_override("font_size", 40 if zombie else 30)
	if _ulc_cache.get("money", -999999) != money:
		_ulc_cache["money"] = money
		_money_label.text = "$%d" % money

	var wdef: Dictionary = WeaponData.BUILTIN_WEAPONS.get(wpn_id, {})
	var wpn_name: String = str(wdef.get("name", wpn_id))
	if _ulc_cache.get("wpn", "") != wpn_id or _ulc_cache.get("alive2", false) != alive:
		_ulc_cache["wpn"] = wpn_id
		_ulc_cache["alive2"] = alive
		_wpn_name.text = wpn_name
		_wpn_name.visible = alive
		_icon_code.text = str(wpn_id).to_upper().substr(0, 3)
		_icon_code.visible = alive
		_ammo_mag.visible = alive
		_ammo_res.visible = alive
		_ads_hint.visible = alive
	if _ulc_cache.get("ammo", -2) != ammo or _ulc_cache.get("reserve", -2) != reserve:
		_ulc_cache["ammo"] = ammo
		_ulc_cache["reserve"] = reserve
		if ammo < 0 or bool(wdef.get("melee", false)):
			_ammo_mag.text = "∞"
			_ammo_res.text = ""
		else:
			_ammo_mag.text = str(ammo)
			_ammo_res.text = "/ %d" % reserve
	if _ulc_cache.get("ads", false) != ads:
		_ulc_cache["ads"] = ads
		_ads_hint.text = "ADS" if ads else ""
	if _ulc_cache.get("lowhp", false) != (hp < 25.0 and alive and not zombie):
		_ulc_cache["lowhp"] = hp < 25.0 and alive and not zombie
		_hp_vign.visible = hp < 25.0 and alive and not zombie
		if not _hp_vign.visible:
			_hp_vign.modulate.a = 0.0


func _read_weapon_id(p: Dictionary) -> String:
	if p.has("w"):
		return str(p.get("w", ""))
	var ws: Variant = p.get("weapons", null)
	if ws is Dictionary:
		var slot: int = int(p.get("activeSlot", 1))
		var w: Variant = ws.get(slot, null)
		if w != null and not (w is Dictionary) and w.def != null:
			return str(w.def.get("id", ""))
	return ""


var _uri_cache: Dictionary = {}


func update_round_info(round_num: int, time_left: float, scores: Dictionary, phase: String, buy_time: float) -> void:
	if _root == null:
		return
	_zombie_mode = scores.has("HUMAN") or scores.has("ZOMBIE")
	var clamped: int = max(0, int(time_left))
	var mm: int = clamped / 60
	var ss: int = clamped % 60
	var timer_str: String = "%02d:%02d" % [mm, ss]
	if _uri_cache.get("timer", "") != timer_str:
		_uri_cache["timer"] = timer_str
		_timer_label.text = timer_str
	var ct_score: int = int(scores.get("HUMAN", scores.get("human", scores.get("CT", scores.get("ct", 0)))))
	var t_score: int = int(scores.get("ZOMBIE", scores.get("zombie", scores.get("T", scores.get("t", 0)))))
	if _uri_cache.get("scores", "") != "%d|%d|%s" % [ct_score, t_score, str(_zombie_mode)]:
		_uri_cache["scores"] = "%d|%d|%s" % [ct_score, t_score, str(_zombie_mode)]
		_score_ct.text = str(ct_score)
		_score_t.text = str(t_score)
		if _zombie_mode:
			_score_ct.add_theme_color_override("font_color", Color("54d6d6"))
			_score_t.add_theme_color_override("font_color", Color("7d5a2f"))
		else:
			_score_ct.add_theme_color_override("font_color", CT_COLOR)
			_score_t.add_theme_color_override("font_color", T_COLOR)
	var phase_text: String = str(phase).to_upper()
	var round_str: String = "Round %d - %s" % [round_num, phase_text]
	if _uri_cache.get("round", "") != round_str:
		_uri_cache["round"] = round_str
		_round_label.text = round_str
	var phase_label_str: String = ""
	var phase_col: Color = Color.WHITE
	match str(phase):
		"buy":
			phase_label_str = "购买阶段 %ds" % max(0, int(buy_time))
			phase_col = ACCENT
		"finale":
			phase_label_str = "!! 琉璃决战 !!"
			phase_col = Color(1.0, 0.3, 0.2)
		"over":
			phase_label_str = "比赛结束"
			phase_col = Color(0.7, 0.7, 0.7)
		_:
			phase_label_str = "战斗中"
	_finale_pulse = str(phase) == "finale"
	if _uri_cache.get("phase", "") != phase_label_str or _uri_cache.get("phase_col", "") != phase_col.to_html():
		_uri_cache["phase"] = phase_label_str
		_uri_cache["phase_col"] = phase_col.to_html()
		_phase_label.text = phase_label_str
		_phase_label.add_theme_color_override("font_color", phase_col)


func update_bomb(state_int: int, label_text: String = "", label_color: Color = Color.WHITE, timer: float = 0.0) -> void:
	_bomb_state = state_int
	_bomb_time = timer
	if _root == null:
		return
	_bomb_label.modulate.a = 1.0
	if state_int == 0 or label_text == "":
		_bomb_label.text = ""
		return
	_bomb_label.text = label_text
	_bomb_label.add_theme_color_override("font_color", label_color)
	if state_int == 2 and timer > 0.0:
		_bomb_label.text = "%s  %02d:%02d" % [label_text, int(timer) / 60, int(timer) % 60]


func add_kill_feed(killer: String, victim: String, weapon: String, headshot: bool) -> void:
	if _feed == null:
		return
	var entry := PanelContainer.new()
	var sb := _panel_style()
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	entry.add_theme_stylebox_override("panel", sb)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.scroll_active = false
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_theme_font_size_override("normal_font_size", 14)
	var k_col: String = "#ffd83d" if killer == _local_name else "#ffffff"
	var v_col: String = "#ffd83d" if victim == _local_name else "#ffffff"
	var head: String = "[爆头] " if headshot else ""
	txt.text = "[color=%s]%s[/color]  [color=#8fa4c8]%s[/color]  [color=%s]%s[/color]%s" \
		% [k_col, killer, str(weapon).to_upper(), v_col, victim, head]
	entry.add_child(txt)
	_feed.add_child(entry)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(entry, "modulate:a", 0.0, 0.5)
	tw.tween_callback(entry.queue_free)


func on_damage() -> void:
	if _root == null:
		return
	_dmg_flash = 1.0


func on_hit_marker() -> void:
	if _crosshair != null:
		_crosshair.flash()


func show_message(text: String, duration: float) -> void:
	if _msg_label == null:
		return
	if text == "" or duration <= 0.0:
		_msg_label.text = ""
		_msg_label.modulate.a = 1.0
		if _msg_tween != null:
			_msg_tween.kill()
			_msg_tween = null
		return
	# 杀掉上一个未完成的 tween：否则旧 tween 的淡出会覆盖/提前隐藏新消息
	# （round_end 与 match_end 同帧到达时，后者会被前者的 tween 提前淡掉）
	if _msg_tween != null:
		_msg_tween.kill()
	_msg_label.text = text
	_msg_label.modulate.a = 1.0
	_msg_label.pivot_offset = _msg_label.size / 2.0
	_msg_tween = create_tween()
	if duration < 9999.0:
		_msg_tween.tween_interval(maxf(0.2, duration - 0.5))
		_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.5)
	else:
		_msg_tween.tween_interval(duration)


func update_use_progress(action: String, progress: float) -> void:
	if _use_panel == null:
		return
	if action == "" or progress <= 0.0:
		_use_panel.visible = false
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	_use_panel.visible = true
	_use_bar.value = clamped
	_use_label.text = "%d%%  %s" % [int(clamped * 100.0), "正在安装炸弹..." if action == "plant" else "正在拆除炸弹..."]


func update_respawn(t: float) -> void:
	if _respawn_label == null:
		return
	if t <= 0.0:
		_respawn_label.text = ""
		return
	_respawn_label.text = "复活倒计时 %.1fs" % t


func set_crosshair(spread01: float, ads: bool) -> void:
	if _crosshair != null:
		_crosshair.set_spread(spread01, ads)


func set_ads_vignette(alpha: float) -> void:
	_ads_vign_target = clampf(alpha, 0.0, 1.0)


func set_scope(weapon_id: String, ads: bool) -> void:
	if _scope != null:
		_scope.set_scope(weapon_id, ads)


func update_money(money: int) -> void:
	if _money_label != null:
		_money_label.text = "$%d" % money


# (UI)
class Bar extends Control:
	var value: float = 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color: Color = Color.WHITE:
		set(c):
			color = c
			queue_redraw()
	var radius: int = 4
	var _bg: StyleBoxFlat
	var _fg: StyleBoxFlat

	func _init() -> void:
		_bg = StyleBoxFlat.new()
		_bg.bg_color = Color(0.0, 0.0, 0.0, 0.35)
		_bg.set_corner_radius_all(radius)
		_fg = StyleBoxFlat.new()
		_fg.set_corner_radius_all(radius)

	func _draw() -> void:
		if size.x <= 1.0:
			return
		draw_style_box(_bg, Rect2(Vector2.ZERO, size))
		var w: float = (size.x - 2.0) * clampf(value, 0.0, 1.0)
		if w > 1.0:
			_fg.bg_color = color
			draw_style_box(_fg, Rect2(Vector2(1.0, 1.0), Vector2(w, size.y - 2.0)))





class ZombieIcon extends Control:


	func _draw() -> void:


		var c: Vector2 = size / 2.0


		draw_circle(c, 9.0, Color(0.72, 0.12, 0.1, 0.95))


		draw_circle(c, 4.0, Color(0.35, 0.04, 0.03))


		draw_circle(Vector2(c.x, c.y - 11.0), 2.5, Color(0.72, 0.12, 0.1, 0.95))


		draw_circle(Vector2(c.x - 9.0, c.y + 5.0), 2.5, Color(0.72, 0.12, 0.1, 0.95))


		draw_circle(Vector2(c.x + 9.0, c.y + 5.0), 2.5, Color(0.72, 0.12, 0.1, 0.95))

