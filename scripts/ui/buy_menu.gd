class_name BuyMenu
extends CanvasLayer

# 购买菜单：拆弹模式按武器购买/退货，生化模式只选主武器。

signal buy(item_id: String)
signal refund(item_id: String)
signal close_requested

const CARD_COLORS: Array = ["5a9dff", "ff8b3d", "ffd83d", "7ddc8f", "c08bff", "ff5a7d", "54d6d6", "ff9d5c"]
const PANEL_BG := Color(0.06, 0.07, 0.1, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.18)

var _root: Control
var _grid: VBoxContainer
var _money_label: Label
var _armor_label: Label
var _mode_label: Label
var _mode: String = "defusal"
var _money: int = 0
var _armor: int = 0
var _bought: Array = []
var _cards: Dictionary = {}


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1120, 560)
	var psb := StyleBoxFlat.new()
	psb.bg_color = PANEL_BG
	psb.border_color = BORDER
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(10)
	psb.content_margin_left = 24
	psb.content_margin_right = 24
	psb.content_margin_top = 18
	psb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", psb)
	_root.add_child(panel)

	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 14)
	panel.add_child(vl)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	vl.add_child(header)
	var title := _mk_label("购买菜单", 26, Color.WHITE, header)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_label = _mk_label("", 16, Color(0.75, 0.8, 0.88), header)
	_armor_label = _mk_label("", 16, Color("5a9dff"), header)
	_money_label = _mk_label("$0", 22, Color("ffd83d"), header)

	_grid = VBoxContainer.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("separation", 10)
	vl.add_child(_grid)

	var hint := _mk_label("按 B 或 Esc 关闭", 13, Color(0.55, 0.58, 0.64), vl)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.visible = false


func open(mode: String, money: int, armor: int, bought: Array) -> void:
	_mode = mode
	_money = money
	_armor = armor
	_bought = bought.duplicate()
	_rebuild()
	_root.visible = true


func hide_menu() -> void:
	if _root != null:
		_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func update_money(money: int, bought: Array) -> void:
	_money = money
	_bought = bought.duplicate()
	if not is_open():
		return
	_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_menu()
		close_requested.emit()
		get_viewport().set_input_as_handled()


# ---------- 构建 ----------
func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	if _mode == "zombie":
		_mode_label.text = "生化模式 · 选择主武器"
		_money_label.text = ""
		_armor_label.text = ""
		_add_row("主武器", _slot_weapons(2))
	else:
		_mode_label.text = "拆弹模式"
		_money_label.text = "$%d" % _money
		_armor_label.text = "护甲 %d" % _armor
		_add_row("手枪", _slot_weapons(1))
		_add_row("主武器", _slot_weapons(2))
		var gear: Array = [{"id": "armor", "cost": Economy.cost_of("armor", _armor) if Economy != null else 650}, {"id": "grenade", "cost": Economy.PRICES.get("grenade", 300) if Economy != null else 300}]
		_add_row("装备", gear)


func _slot_weapons(slot: int) -> Array:
	var out: Array = []
	if WeaponData == null:
		return out
	for id in WeaponData.BUILTIN_WEAPONS:
		var def: Dictionary = WeaponData.BUILTIN_WEAPONS.get(id, {})
		if int(def.get("slot", -1)) == slot and not def.get("melee", false):
			if id == "k9":
				continue  # K9 开局免费自带，购买菜单不重复售卖
			out.append({"id": id, "def": def})
	return out


func _add_row(title: String, items: Array) -> void:
	var row_label := _mk_label(title, 17, Color(0.85, 0.88, 0.95), _grid)
	row_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_child(row)
	for item in items:
		var id: String = str(item.get("id", ""))
		var def: Dictionary = item.get("def", {}) if item.has("def") else {}
		if id == "armor":
			def = {"id": "armor", "name": "防弹衣", "damage": 0, "falloffFar": 0, "magSize": 0, "cost": Economy.cost_of("armor", _armor)}
		elif id == "grenade":
			def = {"id": "grenade", "name": "破片手雷", "damage": 180, "falloffFar": 11, "magSize": 0}
		row.add_child(_make_card(id, def))


func _make_card(id: String, def: Dictionary) -> Button:
	var owned: bool = _bought.has(id)
	var name: String = str(def.get("name", id))
	var price: int = 0
	if _mode != "zombie":
		price = int(def.get("cost", Economy.PRICES.get(id, 800))) if def.has("cost") else int(Economy.PRICES.get(id, 800))
	var card := Button.new()
	card.custom_minimum_size = Vector2(150, 172)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var color_idx: int = abs(id.hash()) % CARD_COLORS.size()
	var accent: Color = Color(CARD_COLORS[color_idx])
	if owned:
		accent = Color("7ddc8f")
	elif _mode == "defusal" and _money < price:
		accent = Color(0.45, 0.48, 0.55)
		card.disabled = true
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.19, 0.85)
	normal.border_color = Color(accent, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.19, 0.26, 0.95)
	hover.border_color = Color(accent, 0.95)
	var pressed_sb := hover.duplicate()
	pressed_sb.bg_color = Color(0.2, 0.24, 0.32, 0.95)
	var disabled_sb := normal.duplicate()
	disabled_sb.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	disabled_sb.border_color = Color(0.3, 0.32, 0.38, 0.6)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", pressed_sb)
	card.add_theme_stylebox_override("disabled", disabled_sb)

	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 5)
	card.add_child(vl)

	var top := HBoxContainer.new()
	vl.add_child(top)
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(44, 26)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(accent, 0.28)
	isb.border_color = Color(accent, 0.8)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(5)
	icon.add_theme_stylebox_override("panel", isb)
	top.add_child(icon)
	var code := Label.new()
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 13)
	code.add_theme_color_override("font_color", Color(accent, 1.0))
	code.text = str(id).to_upper().substr(0, 3)
	icon.add_child(code)
	var price_label := _mk_label("$%d" % price if _mode == "defusal" else "免费", 15, Color("ffd83d"), top)
	price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var name_label := _mk_label(name, 16, Color.WHITE, vl)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 3)
	vl.add_child(stats)
	_add_stat(stats, "伤害", float(def.get("damage", 0)) / 120.0)
	_add_stat(stats, "射程", float(def.get("falloffFar", 30)) / 200.0)
	_add_stat(stats, "弹药", clampf(float(def.get("magSize", 30)) / 100.0, 0.0, 1.0))

	if owned and _mode == "defusal":
		var bottom := HBoxContainer.new()
		vl.add_child(bottom)
		var owned_label := _mk_label("已购买", 14, Color("7ddc8f"), bottom)
		owned_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var refund_btn := Button.new()
		refund_btn.text = "退货"
		refund_btn.custom_minimum_size = Vector2(52, 26)
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0.75, 0.3, 0.2, 0.85)
		rsb.set_corner_radius_all(5)
		refund_btn.add_theme_stylebox_override("normal", rsb)
		var rsb_h := rsb.duplicate()
		rsb_h.bg_color = Color(0.9, 0.4, 0.25, 0.95)
		refund_btn.add_theme_stylebox_override("hover", rsb_h)
		refund_btn.add_theme_stylebox_override("pressed", rsb_h)
		refund_btn.add_theme_color_override("font_color", Color.WHITE)
		refund_btn.add_theme_font_size_override("font_size", 13)
		refund_btn.pressed.connect(func(): refund.emit(id))
		bottom.add_child(refund_btn)
	elif owned and _mode == "zombie":
		var sel := _mk_label("已选择", 14, Color("7ddc8f"), vl)
		sel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.pressed.connect(func(): buy.emit(id))
	elif not owned:
		card.pressed.connect(func(): buy.emit(id))
	_cards[id] = card
	return card


func _add_stat(parent: Node, label: String, ratio: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l := _mk_label(label, 11, Color(0.62, 0.66, 0.74), row)
	l.custom_minimum_size = Vector2(28, 0)
	var bar := StatBar.new()
	bar.value = ratio
	bar.custom_minimum_size = Vector2(70, 5)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)


func _mk_label(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


class StatBar extends Control:
	var value: float = 0.0

	func _draw() -> void:
		if size.x <= 1.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.92, 0.98, 0.18))
		var w: float = size.x * clampf(value, 0.0, 1.0)
		if w > 1.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, size.y)), Color(0.9, 0.92, 0.98, 0.85))
