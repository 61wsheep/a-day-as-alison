extends CanvasLayer

## 背包面板 — I 键开合。
## 左侧物品网格（图标 + 数量），右侧详情（名称/描述/单价）。
## 打开期间锁定玩家移动；对话进行中不可打开；打开/关闭发 EventBus 信号。

const ItemDB := preload("res://scripts/systems/item_db.gd")

const GRID_COLS := 5

var _dim: ColorRect
var _panel: PanelContainer
var _grid: GridContainer
var _detail_name: Label
var _detail_desc: Label
var _detail_price: Label
var _selected: String = ""
var _open := false
var _dlg_active := false


func _ready() -> void:
	layer = 12
	_build_ui()
	var bus = get_node("/root/EventBus")
	bus.dialogue_started.connect(func():
		_dlg_active = true
		_close())
	bus.dialogue_ended.connect(func(): _dlg_active = false)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("open_inventory") and not _dlg_active:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 360)
	_panel.offset_left = -280
	_panel.offset_top = -180
	_panel.offset_right = 280
	_panel.offset_bottom = 180
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	_panel.add_child(hbox)

	# 左侧：滚动网格
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 320)
	hbox.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	# 右侧：详情
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(190, 320)
	detail.add_theme_constant_override("separation", 8)
	hbox.add_child(detail)

	var title := Label.new()
	title.text = "—— 背包 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	detail.add_child(title)

	_detail_name = Label.new()
	_detail_name.text = "（未选择物品）"
	_detail_name.add_theme_font_size_override("font_size", 17)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_name)

	_detail_price = Label.new()
	_detail_price.text = ""
	_detail_price.add_theme_font_size_override("font_size", 14)
	_detail_price.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	detail.add_child(_detail_price)

	_detail_desc = Label.new()
	_detail_desc.text = ""
	_detail_desc.add_theme_font_size_override("font_size", 13)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(180, 120)
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_detail_desc)

	var hint := Label.new()
	hint.text = "[I] 关闭"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	detail.add_child(hint)

	_dim.hide()
	_panel.hide()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_refresh()
		_dim.show()
		_panel.show()
		_open = true
		_set_player_locked(true)
		get_node("/root/EventBus").inventory_opened.emit()


func _close() -> void:
	if not _open:
		return
	_dim.hide()
	_panel.hide()
	_open = false
	_set_player_locked(false)
	get_node("/root/EventBus").inventory_closed.emit()


func _set_player_locked(locked: bool) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and "_movement_locked" in p:
		p._movement_locked = locked


## 从 Inventory 快照重建网格。物品用按钮呈现（图标 + ×N），点击看详情。
func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_selected = ""
	_detail_name.text = "（未选择物品）"
	_detail_price.text = ""
	_detail_desc.text = ""
	var inv: Node = get_node("/root/Inventory")
	var snapshot: Dictionary = inv.all_items()
	if snapshot.is_empty():
		var empty := Label.new()
		empty.text = "（背包空空如也）"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_grid.add_child(empty)
		return
	var ids: Array = snapshot.keys()
	ids.sort()
	for id in ids:
		var count: int = int(snapshot[id])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 56)
		btn.icon = ItemDB.get_icon(id)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.text = "×%d" % count
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.pressed.connect(_show_detail.bind(id))
		_grid.add_child(btn)


func _show_detail(item_id: String) -> void:
	_selected = item_id
	_detail_name.text = ItemDB.name_of(item_id)
	_detail_price.text = "单价 %d G" % ItemDB.base_price(item_id)
	_detail_desc.text = ItemDB.desc_of(item_id)
