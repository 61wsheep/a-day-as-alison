extends CanvasLayer

## 塔罗占卜 UI — 每天清晨抽一张大阿尔卡那，影响当日蘑菇售价。

var _cards: Array = []
var _panel: PanelContainer
var _title_label: Label
var _card_name: Label
var _reading: Label
var _action_btn: Button
var _drawn: bool = false


func _ready() -> void:
	layer = 20
	_load_cards()
	_build_ui()


func _load_cards() -> void:
	var f := FileAccess.open("res://resources/tarot/major_arcana.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			_cards = data.get("cards", [])


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 260)
	_panel.offset_left = -210
	_panel.offset_top = -130
	_panel.offset_right = 210
	_panel.offset_bottom = 130
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "—— 晨间占卜 ——"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	_card_name = Label.new()
	_card_name.text = "？？？"
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.add_theme_font_size_override("font_size", 26)
	_card_name.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(_card_name)

	_reading = Label.new()
	_reading.text = "在魔法桌前坐下，抽一张属于今天的牌。"
	_reading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reading.custom_minimum_size = Vector2(380, 90)
	_reading.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_reading)

	_action_btn = Button.new()
	_action_btn.text = "抽牌"
	_action_btn.pressed.connect(_on_action)
	vbox.add_child(_action_btn)

	_hide_all()


func _hide_all() -> void:
	get_node("Dim").hide()
	_panel.hide()


func open() -> void:
	var gm = get_node("/root/GameManager")
	if gm.tarot_drawn_today:
		return
	_drawn = false
	_card_name.text = "？？？"
	_reading.text = "在魔法桌前坐下，抽一张属于今天的牌。"
	_action_btn.text = "抽牌"
	get_node("Dim").show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()


func _on_action() -> void:
	if not _drawn:
		_draw_card()
	else:
		_close()


func _draw_card() -> void:
	if _cards.is_empty():
		_close()
		return
	var gm = get_node("/root/GameManager")
	var card: Dictionary = _cards[randi() % _cards.size()]
	gm.tarot_drawn_today = true
	gm.daily_tarot_card = str(card.get("name", ""))
	gm.daily_luck = int(card.get("luck", 0))
	_drawn = true
	_card_name.text = gm.daily_tarot_card
	var luck_text := ""
	match gm.daily_luck:
		1: luck_text = "\n\n（吉兆：今日蘑菇售价 ×1.5）"
		-1: luck_text = "\n\n（凶兆：今日蘑菇售价 ×0.5）"
	_reading.text = str(card.get("reading", "")) + luck_text
	_action_btn.text = "开始今天"
	get_node("/root/EventBus").tarot_drawn.emit(card)


func _close() -> void:
	_hide_all()
	get_node("/root/EventBus").dialogue_ended.emit()
