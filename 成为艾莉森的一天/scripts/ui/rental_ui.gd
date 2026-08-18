extends CanvasLayer

## 树屋租赁 UI — 租房 / 回家休息。

const HOUSES := {
	"oak": {
		"name": "橡树屋",
		"price": 100,
		"desc": "靠近广场的朴素树屋，阳光充足，下楼就能采蘑菇。",
	},
	"cedar": {
		"name": "杉树屋",
		"price": 150,
		"desc": "距离森林大学最近的树屋，索拉雅就住在附近，夜里能听见书页声。",
	},
	"willow": {
		"name": "柳树屋",
		"price": 120,
		"desc": "悬在溪面上的安静树屋，据说住在这里的人更容易梦见过去的事。",
	},
}

var _house_id: String = ""
var _panel: PanelContainer
var _title: Label
var _desc: Label
var _btn_box: VBoxContainer


func _ready() -> void:
	layer = 20
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(400, 200)
	_panel.offset_left = -200
	_panel.offset_top = -110
	_panel.offset_right = 200
	_panel.offset_bottom = 110
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(360, 60)
	_desc.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_desc)

	_btn_box = VBoxContainer.new()
	_btn_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_btn_box)

	_hide_all()


func _hide_all() -> void:
	get_node("Dim").hide()
	_panel.hide()


func open(house_id: String) -> void:
	if not HOUSES.has(house_id):
		return
	_house_id = house_id
	var gm = get_node("/root/GameManager")
	var house: Dictionary = HOUSES[house_id]

	for child in _btn_box.get_children():
		child.queue_free()

	if gm.treehouse_rented and gm.treehouse == house_id:
		_title.text = "%s —— 你的家" % house["name"]
		_desc.text = "树屋里的一切都让你感到熟悉。床头柜上放着一张身份证——姓名、生日、照片，全都是你。"
		_add_button("睡到午夜", _on_rest)
		_add_button("离开", _close)
	elif gm.treehouse_rented:
		_title.text = str(house["name"])
		_desc.text = "你已经租下了别的树屋。这里不属于你。"
		_add_button("离开", _close)
	else:
		_title.text = "%s —— 月租 %d G" % [house["name"], int(house["price"])]
		_desc.text = str(house["desc"])
		if gm.gold >= int(house["price"]):
			_add_button("租住（%d G）" % int(house["price"]), _on_rent)
		else:
			_desc.text += "\n\n（金币不足——去广场采蘑菇换钱吧。）"
		_add_button("再想想", _close)

	get_node("Dim").show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()


func _add_button(text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	_btn_box.add_child(btn)


func _on_rent() -> void:
	var gm = get_node("/root/GameManager")
	var house: Dictionary = HOUSES[_house_id]
	if gm.spend_gold(int(house["price"])):
		gm.treehouse_rented = true
		gm.treehouse = _house_id
		gm.discover_clue("clue_id_card")
		get_node("/root/EventBus").toast.emit("你租下了%s！" % house["name"])
	_close()


func _on_rest() -> void:
	get_node("/root/TimeManager").skip_to_midnight()
	_close()


func _close() -> void:
	_hide_all()
	get_node("/root/EventBus").dialogue_ended.emit()
