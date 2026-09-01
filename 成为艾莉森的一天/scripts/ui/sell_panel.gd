extends CanvasLayer

## 售卖面板 — 索拉雅收购（玩家主动进入）。
## 每个可卖品类一行：勾选 + 数量选择（SpinBox，默认全部）+ 单价。
## 只卖勾选品类里所选数量，不再一口价清空整类。
## 价格 = base_price × (1 + 0.2 × daily_luck)，整数化；塔罗吉凶影响售价。

const ItemDB := preload("res://scripts/systems/item_db.gd")

var _dim: ColorRect
var _panel: PanelContainer
var _rows_box: VBoxContainer
var _total_label: Label
var _rows: Dictionary = {}   # item_id -> {check, spin, count}
var _open := false


func _ready() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(540, 420)
	_panel.offset_left = -270
	_panel.offset_top = -210
	_panel.offset_right = 270
	_panel.offset_bottom = 210
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "—— 索拉雅的收购 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 280)
	vbox.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)

	var hint := Label.new()
	hint.text = "勾选品类，用数字框选择卖出数量"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)

	_total_label = Label.new()
	_total_label.text = "合计：0 G"
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total_label.add_theme_font_size_override("font_size", 18)
	_total_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(_total_label)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btns)

	var sell_btn := Button.new()
	sell_btn.text = "卖出选中"
	sell_btn.pressed.connect(_on_sell)
	btns.add_child(sell_btn)

	var leave_btn := Button.new()
	leave_btn.text = "离开"
	leave_btn.pressed.connect(_close)
	btns.add_child(leave_btn)

	_dim.hide()
	_panel.hide()


func open() -> void:
	_refresh()
	_dim.show()
	_panel.show()
	_open = true
	get_node("/root/EventBus").dialogue_started.emit()   # 锁定玩家移动，防 Tab/I 干扰


func _close() -> void:
	if not _open:
		return
	_dim.hide()
	_panel.hide()
	_open = false
	get_node("/root/EventBus").dialogue_ended.emit()


## 每行：勾选 + 图标 + 名称 × 持有 + 数量 SpinBox + 单价。
## SpinBox 默认 = 持有数量（勾选即卖整类），可下调卖部分。
func _refresh() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	_rows.clear()
	var inv: Node = get_node("/root/Inventory")
	var luck: int = get_node("/root/GameManager").daily_luck
	var snapshot: Dictionary = inv.all_items()
	var has_sellable := false
	var ids: Array = snapshot.keys()
	ids.sort()
	for id in ids:
		if ItemDB.kind_of(id) != "forage":
			continue
		has_sellable = true
		var count: int = int(snapshot[id])
		var unit: int = ItemDB.calc_sell_price(id, luck)
		_rows_box.add_child(_make_row(id, count, unit))
	if not has_sellable:
		var empty := Label.new()
		empty.text = "（没有可卖的采集品）"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_rows_box.add_child(empty)
	_update_total()


func _make_row(id: String, count: int, unit: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var check := CheckButton.new()
	check.toggled.connect(func(_on: bool) -> void: _update_total())
	row.add_child(check)

	var icon := TextureRect.new()
	icon.texture = ItemDB.get_icon(id)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s ×%d" % [ItemDB.name_of(id), count]
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.add_theme_font_size_override("font_size", 14)
	row.add_child(name_label)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = count
	spin.value = count
	spin.custom_minimum_size = Vector2(76, 0)
	spin.value_changed.connect(func(_v: float) -> void: _update_total())
	row.add_child(spin)

	var price_label := Label.new()
	price_label.text = "× %d G" % unit
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	row.add_child(price_label)

	_rows[id] = {"check": check, "spin": spin, "count": count}
	return row


func _update_total() -> void:
	var luck: int = get_node("/root/GameManager").daily_luck
	var total := 0
	for id in _rows:
		var row: Dictionary = _rows[id]
		if (row["check"] as CheckButton).button_pressed:
			total += ItemDB.calc_sell_price(id, luck) * int((row["spin"] as SpinBox).value)
	_total_label.text = "合计：%d G" % total


## 卖出所有勾选品类所选数量：扣背包 → 加金币 → 发 item_sold → 刷新面板。
func _on_sell() -> void:
	var inv: Node = get_node("/root/Inventory")
	var gm: Node = get_node("/root/GameManager")
	var luck: int = gm.daily_luck
	var bus := get_node("/root/EventBus")
	var total := 0
	var sold_any := false
	for id in _rows:
		var row: Dictionary = _rows[id]
		if not (row["check"] as CheckButton).button_pressed:
			continue
		var qty: int = int((row["spin"] as SpinBox).value)
		if qty <= 0:
			continue
		var count: int = inv.count_of(id)
		qty = min(qty, count)
		if qty <= 0:
			continue
		var price_total: int = ItemDB.calc_sell_price(id, luck) * qty
		inv.remove(id, qty)
		total += price_total
		bus.item_sold.emit(id, qty, price_total)
		sold_any = true
	if not sold_any:
		bus.toast.emit("先勾选要卖的东西吧。")
		return
	gm.add_gold(total)
	bus.toast.emit("卖出了 %d G！" % total)
	_refresh()
