extends CanvasLayer

## 塔罗占卜 UI（委托链路的 NPC 占卜）— 与晨间 TarotUI 完全隔离：
## 不写 gm.tarot_drawn_today / daily_luck / HUD tarot_drawn，晨间售价机制不受影响。
## 数据段：抽大阿尔卡那 → 牌面对人解读 → 「把牌交给他」→ QuestManager.report 完成任务 → ack → 关闭。
## 解读文案优先级：card.npc_readings[npc] → reading_to_person → reading（通用回落，可单测）。

var _cards: Array = []
var _npc_id := ""
var _quest_id := ""
var _drawn := false
var _done := false

var _dim: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _question_label: Label
var _card_name: Label
var _reading_label: Label
var _action_btn: Button
var _open := false


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
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(480, 360)
	_panel.offset_left = -240
	_panel.offset_top = -180
	_panel.offset_right = 240
	_panel.offset_bottom = 180
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "—— 塔罗占卜 ——"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(_title_label)

	_question_label = Label.new()
	_question_label.text = ""
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.add_theme_font_size_override("font_size", 13)
	_question_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.84))
	vbox.add_child(_question_label)

	_card_name = Label.new()
	_card_name.text = "？？？"
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.add_theme_font_size_override("font_size", 26)
	_card_name.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(_card_name)

	_reading_label = Label.new()
	_reading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reading_label.custom_minimum_size = Vector2(440, 130)
	_reading_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_reading_label)

	_action_btn = Button.new()
	_action_btn.text = "抽牌"
	_action_btn.pressed.connect(_on_action)
	vbox.add_child(_action_btn)

	_dim.hide()
	_panel.hide()


## 占卜面板入口（game.gd 对话结束分发 divine:* 调用）。npc_id 有活动 tarot 委托才开。
func open(npc_id: String) -> void:
	var qm = get_node("/root/QuestManager")
	var qid: String = qm.pending_reading_for(npc_id)
	if qid == "":
		get_node("/root/EventBus").toast.emit("（现在没有人需要占卜……）")
		return
	_npc_id = npc_id
	_quest_id = qid
	var q: Dictionary = qm.get_quest(qid)
	_drawn = false
	_done = false
	_open = true
	_title_label.text = "—— 为 %s 占卜 ——" % qm.display_name(npc_id)
	var steps: Array = q.get("steps", [])
	var question := ""
	if not steps.is_empty():
		question = str(steps[0].get("question", ""))
	_question_label.text = "委托：%s\n%s" % [str(q.get("title", "")), question]
	_card_name.text = "？？？"
	_reading_label.text = "牌背朝上。集中精神——替 %s 问出那个藏了很久的问题。" % qm.display_name(npc_id)
	_action_btn.text = "抽一张牌"
	_dim.show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()   # 锁玩家移动


func is_open() -> bool:
	return _open


func _on_action() -> void:
	if _done:
		_close()
	elif not _drawn:
		_draw()
	else:
		_hand_over()


## 抽牌：随机大阿尔卡那（数据段，与晨间 AI/随机路径无关）。
func _draw() -> void:
	if _cards.is_empty():
		_close()
		return
	_present(_cards[randi() % _cards.size()])


## 测试注入单张牌后仍可走同一状态机：set _cards=[card]; _drawn=false; _draw()
func _present(card: Dictionary) -> void:
	_drawn = true
	_card_name.text = str(card.get("name", "？？？"))
	_reading_label.text = reading_for(card, _npc_id)
	_action_btn.text = "把牌交给他"


## 解读文案三分支（纯函数，供单测）：npc_readings[npc] → reading_to_person → reading。
func reading_for(card: Dictionary, npc_id: String) -> String:
	var by_npc: Dictionary = card.get("npc_readings", {})
	if by_npc.has(npc_id):
		return str(by_npc[npc_id])
	if card.has("reading_to_person"):
		return str(card.get("reading_to_person", ""))
	return str(card.get("reading", ""))


## 把牌交给他：QuestManager.report 完成任务（奖励 toast 由 quest_manager 发），面板切 ack。
func _hand_over() -> void:
	_done = true
	var qm = get_node("/root/QuestManager")
	var q: Dictionary = qm.get_quest(_quest_id)
	qm.report({"type": "tarot_reading_for", "npc": _npc_id})
	var ack := str(q.get("ack", "他凝视牌面良久，没有说话。"))
	var hint := str(q.get("complete_hint", ""))
	_card_name.text = "—— 牌已收下 ——"
	_reading_label.text = ack if hint == "" else "%s\n\n%s" % [ack, hint]
	_action_btn.text = "离开"


func _close() -> void:
	if not _open:
		return
	_open = false
	_dim.hide()
	_panel.hide()
	get_node("/root/EventBus").dialogue_ended.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
