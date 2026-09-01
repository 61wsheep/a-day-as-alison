extends CanvasLayer

## 售卖面板 — 索拉雅收购（M1 最简单的售卖出口）。
## 列出背包里可卖物品（forage 采集品），勾选 → 一口价卖出。
## 价格 = base_price × (1 + 0.2 × daily_luck)，整数化；塔罗吉凶影响售价。

const ItemDB := preload("res://scripts/systems/item_db.gd")

var _dim: ColorRect
var _panel: PanelContainer
var _rows: VBoxContainer
var _total_label: Label
var _checks: Dictionary = {}   # item_id -> CheckButton
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
	_panel.custom_minimum_size = Vector2(460, 380)
	_panel.offset_left = -230
	_panel.offset_top = -190
	_panel.offset_right = 230
	_panel.offset_bottom = 190
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
	scroll.custom_minimum_size = Vector2(420, 260)
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

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


## 列出背包中所有可卖物品（forage），每行：勾选框 + 图标 + 名称 + ×数量 + 单价。
func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_checks.clear()
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
		var check := CheckButton.new()
		check.text = "%s  ×%d    单价 %d G" % [ItemDB.name_of(id), count, unit]
		check.icon = ItemDB.get_icon(id)
		check.toggled.connect(func(_on: bool) -> void: _update_total())
		_checks[id] = check
		_rows.add_child(check)
	if not has_sellable:
		var empty := Label.new()
		empty.text = "（没有可卖的采集品）"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_rows.add_child(empty)
	_update_total()


func _update_total() -> void:
	var inv: Node = get_node("/root/Inventory")
	var luck: int = get_node("/root/GameManager").daily_luck
	var total := 0
	for id in _checks:
		if (_checks[id] as CheckButton).button_pressed:
			total += ItemDB.calc_sell_price(id, luck) * inv.count_of(id)
	_total_label.text = "合计：%d G" % total


## 一口价卖出所有勾选物品：扣背包 → 加金币 → 发 item_sold → 刷新面板。
func _on_sell() -> void:
	var inv: Node = get_node("/root/Inventory")
	var gm: Node = get_node("/root/GameManager")
	var luck: int = gm.daily_luck
	var bus := get_node("/root/EventBus")
	var total := 0
	var sold_any := false
	for id in _checks:
		if not (_checks[id] as CheckButton).button_pressed:
			continue
		var count: int = inv.count_of(id)
		if count <= 0:
			continue
		var price_total: int = ItemDB.calc_sell_price(id, luck) * count
		inv.remove(id, count)
		total += price_total
		bus.item_sold.emit(id, count, price_total)
		sold_any = true
	if not sold_any:
		bus.toast.emit("先勾选要卖的东西吧。")
		return
	gm.add_gold(total)
	bus.toast.emit("卖出了 %d G！" % total)
	_refresh()
