extends CanvasLayer

## 塔罗占卜 UI — 每天清晨抽一张大阿尔卡那，影响当日蘑菇售价。
## AI 可用时走天命面具（AI 选牌 + 预言诗）；不可用/失败回落数据牌（原有随机逻辑）。

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const HeavenSession := preload("res://scripts/systems/ai_heaven_session.gd")

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


## 打开抽牌面板。现在由魔法桌按 E 触发（不再开局自动弹），所以这里要挡三种情况：
## 第 1 天（还没搬进小屋，没有牌可抽）、今天已经抽过、面板本来就开着。
## 面板已开时直接返回，顺便让「在桌前连按 E」变成空操作，不会把已翻开的牌重置回「？？？」。
func open() -> void:
	var gm = get_node("/root/GameManager")
	if _panel.visible or gm.tarot_drawn_today or gm.current_day < 2:
		return
	_drawn = false
	_card_name.text = "？？？"
	_reading.text = "在魔法桌前坐下，抽一张属于今天的牌。"
	_action_btn.text = "抽牌"
	get_node("Dim").show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()


func _on_action() -> void:
	# 面板没开就什么都不做：塔罗不再开局自动弹出后，外部（含各测试的防御式收尾）
	# 那句 _on_action() 会变成「凭空抽一张牌」，静默改掉 tarot_drawn_today / daily_luck。
	if not _panel.visible:
		return
	if not _drawn:
		_draw_card()
	else:
		_close()


func _draw_card() -> void:
	if _cards.is_empty():
		_close()
		return
	var bridge: Node = get_node_or_null("/root/AIBridge")
	if bridge != null and bridge.is_available():
		_draw_card_ai()
	else:
		_draw_card_fallback()


## 天命面具路径：AI 选牌 + 预言诗（带加载态；session 内部已含校验与回落）。
func _draw_card_ai() -> void:
	_card_name.text = "？？？"
	_reading.text = "天正凝视牌面……"
	_action_btn.disabled = true
	var session := HeavenSession.new()
	session.setup(self)
	var result: Dictionary = await session.oracle()
	_action_btn.disabled = false
	_present_result(result)


## 数据牌路径：AI 关闭时的完整回落（原有随机抽牌逻辑）。
func _draw_card_fallback() -> void:
	var card: Dictionary = _cards[randi() % _cards.size()]
	_present_result({
		"card_name": str(card.get("name", "")),
		"prophecy": str(card.get("reading", "")),
	})


## 统一展示：写入 GameManager 当日牌面 + 运气（蘑菇售价机制不变），发 tarot_drawn 信号。
func _present_result(result: Dictionary) -> void:
	var gm = get_node("/root/GameManager")
	gm.tarot_drawn_today = true
	gm.daily_tarot_card = str(result.get("card_name", ""))
	gm.daily_luck = _luck_for(gm.daily_tarot_card)
	_drawn = true
	_card_name.text = gm.daily_tarot_card
	var luck_text := ""
	match gm.daily_luck:
		1: luck_text = "\n\n（吉兆：今日采集品售价 ×1.2）"
		-1: luck_text = "\n\n（凶兆：今日采集品售价 ×0.8）"
	_reading.text = str(result.get("prophecy", "")) + luck_text
	_action_btn.text = "开始今天"
	get_node("/root/EventBus").tarot_drawn.emit({"name": gm.daily_tarot_card, "luck": gm.daily_luck})


## 按牌名从数据牌查 luck 值（AI 选的牌也要保住售价机制）；查不到按 0。
func _luck_for(card_name: String) -> int:
	for card in _cards:
		if str(card.get("name", "")) == card_name:
			return int(card.get("luck", 0))
	return 0


func _close() -> void:
	_hide_all()
	get_node("/root/EventBus").dialogue_ended.emit()
