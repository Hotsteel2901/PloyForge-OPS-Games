class_name Scoreboard
extends CanvasLayer

# Tab 计分板：CT/T 双列，K/D、血量、金钱；按帧更新但数据未变时跳过重建。

const CT_COLOR := Color("5a9dff")
const T_COLOR := Color("ff8b3d")
const HUM_COLOR := Color("54d6d6")
const ZOM_COLOR := Color("b05a2a")
const BORDER := Color(1.0, 1.0, 1.0, 0.18)

var _root: Control
var _mode_label: Label
var _score_label: Label
var _map_label: Label
var _ct_header: Label
var _t_header: Label
var _ct_col: VBoxContainer
var _t_col: VBoxContainer
var _cache_key: String = ""


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(940, 560)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	psb.border_color = BORDER
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(10)
	psb.content_margin_left = 28
	psb.content_margin_right = 28
	psb.content_margin_top = 20
	psb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", psb)
	_root.add_child(panel)

	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 12)
	panel.add_child(vl)

	_map_label = _mk_label("POLYFORGE: OPS", 22, Color.WHITE, vl)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label = _mk_label("0 : 0", 44, Color.WHITE, vl)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label = _mk_label("", 15, Color(0.7, 0.74, 0.82), vl)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	vl.add_child(cols)

	var ct_box := VBoxContainer.new()
	ct_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(ct_box)
	_ct_header = _mk_label("反恐精英 (CT)", 17, CT_COLOR, ct_box)
	_ct_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ct_col = VBoxContainer.new()
	_ct_col.add_theme_constant_override("separation", 3)
	ct_box.add_child(_ct_col)

	var t_box := VBoxContainer.new()
	t_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(t_box)
	_t_header = _mk_label("恐怖分子 (T)", 17, T_COLOR, t_box)
	_t_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_t_col = VBoxContainer.new()
	_t_col.add_theme_constant_override("separation", 3)
	t_box.add_child(_t_col)


func update(players: Array, scores: Dictionary, mode: String) -> void:
	if _root == null:
		return
	var key: String = _make_key(players, scores, mode)
	if key == _cache_key:
		return
	_cache_key = key
	_rebuild(players, scores, mode)


func show_scoreboard() -> void:
	if _root != null:
		_root.visible = true


func hide_scoreboard() -> void:
	if _root != null:
		_root.visible = false


func is_panel_visible() -> bool:
	return _root != null and _root.visible


# ---------- 内部 ----------
func _make_key(players: Array, scores: Dictionary, mode: String) -> String:
	var parts: PackedStringArray = []
	parts.append(mode)
	parts.append(str(scores.get("CT", scores.get("ct", 0))))
	parts.append(str(scores.get("T", scores.get("t", 0))))
	parts.append(str(scores.get("HUMAN", scores.get("human", 0))))
	parts.append(str(scores.get("ZOMBIE", scores.get("zombie", 0))))
	for p in players:
		if p is Dictionary:
			parts.append("%s|%s|%s|%s|%s|%s|%s" % [
				str(p.get("i", "")), p.get("k", "-"), p.get("d", "-"),
				p.get("h", "-"), p.get("mo", "-"), p.get("al", "-"), p.get("t", "-")])
	return "\n".join(parts)


func _rebuild(players: Array, scores: Dictionary, mode: String) -> void:
	_mode_label.text = str(Constants.MODE_LABEL.get(mode, mode)) if Constants != null else mode
	var zombie_mode: bool = scores.has("HUMAN") or scores.has("ZOMBIE")
	var team_a: int = Constants.TEAM_HUMAN if zombie_mode else Constants.TEAM_CT
	var team_b: int = Constants.TEAM_ZOMBIE if zombie_mode else Constants.TEAM_T
	if zombie_mode:
		_ct_header.text = "人类"
		_t_header.text = "僵尸"
		_ct_header.add_theme_color_override("font_color", HUM_COLOR)
		_t_header.add_theme_color_override("font_color", ZOM_COLOR)
	else:
		_ct_header.text = "反恐精英 (CT)"
		_t_header.text = "恐怖分子 (T)"
		_ct_header.add_theme_color_override("font_color", CT_COLOR)
		_t_header.add_theme_color_override("font_color", T_COLOR)
	var sa: String = str(int(scores.get("HUMAN" if zombie_mode else "CT", scores.get("human" if zombie_mode else "ct", 0))))
	var sb: String = str(int(scores.get("ZOMBIE" if zombie_mode else "T", scores.get("zombie" if zombie_mode else "t", 0))))
	_score_label.text = "%s : %s" % [sa, sb]

	_clear_col(_ct_col)
	_clear_col(_t_col)
	_add_header_row(_ct_col, CT_COLOR if not zombie_mode else HUM_COLOR)
	_add_header_row(_t_col, T_COLOR if not zombie_mode else ZOM_COLOR)
	var list_a: Array = []
	var list_b: Array = []
	for p in players:
		if not (p is Dictionary):
			continue
		var team: int = int(p.get("t", p.get("team", 0)))
		if team == team_a:
			list_a.append(p)
		elif team == team_b:
			list_b.append(p)
	list_a.sort_custom(func(a, b): return int(a.get("k", 0)) > int(b.get("k", 0)))
	list_b.sort_custom(func(a, b): return int(a.get("k", 0)) > int(b.get("k", 0)))
	for p in list_a:
		_add_row(_ct_col, p)
	for p in list_b:
		_add_row(_t_col, p)


func _clear_col(col: VBoxContainer) -> void:
	for c in col.get_children():
		c.queue_free()


func _add_header_row(col: VBoxContainer, color: Color) -> void:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 2)
	col.add_child(g)
	for t in ["玩家", "K", "D", "HP", "资金"]:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", color)
		l.custom_minimum_size = Vector2(86, 22)
		g.add_child(l)


func _add_row(col: VBoxContainer, p: Dictionary) -> void:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 2)
	col.add_child(g)
	var alive: bool = int(p.get("al", p.get("alive", 1))) != 0
	var dim: Color = Color(1.0, 1.0, 1.0, 0.38 if alive else 0.16)
	var name_l := Label.new()
	name_l.text = str(p.get("n", p.get("name", "?")))
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", Color.WHITE if alive else Color(0.6, 0.62, 0.68))
	name_l.custom_minimum_size = Vector2(86, 24)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	g.add_child(name_l)
	_add_cell(g, str(p.get("k", p.get("kills", "-"))), dim)
	_add_cell(g, str(p.get("d", p.get("deaths", "-"))), dim)
	var hp: Variant = p.get("h", null)
	if hp == null:
		hp = p.get("hp", "-")
	_add_cell(g, str(hp) if alive else "阵亡", dim)
	_add_cell(g, "$" + str(p.get("mo", p.get("money", 0))), dim)


func _add_cell(g: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(86, 24)
	g.add_child(l)


func _mk_label(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
