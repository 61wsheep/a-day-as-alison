extends CanvasLayer

## 委托板 — 广场告示牌打开（rental_ui/sell_panel 范式）。
## 三区：可接受（解锁且未接）→ 进行中 → 已完成。每次 open 全量刷新。

var _dim: ColorRect
var _panel: PanelContainer
var _scroll_box: VBoxContainer
var _open := false


func _ready() -> void:
	layer = 20
	add_to_group("quest_board_ui")   # 世界委托板（notice_board）经此查找 UI
	_build_ui()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(480, 420)
	_panel.offset_left = -240
	_panel.offset_top = -210
	_panel.offset_right = 240
	_panel.offset_bottom = 210
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "—— 广场委托板 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_scroll_box = VBoxContainer.new()
	_scroll_box.add_theme_constant_override("separation", 8)
	_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_scroll_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var leave := Button.new()
	leave.text = "离开"
	leave.pressed.connect(_close)
	btn_row.add_child(leave)

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


func toggle() -> void:
	if _open:
		_close()
	else:
		open()


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _scroll_box.get_children():
		child.queue_free()
	var qm = get_node("/root/QuestManager")

	_add_section("可接受的委托")
	var avail: Array = qm.available_quests()
	if avail.is_empty():
		_add_line("（目前没有可接受的委托。每天去看看，说不定有新字条。）", Color(0.7, 0.7, 0.75))
	for q in avail:
		_add_quest_card(q, true)

	_add_section("进行中")
	var active: Array = qm.active_quests()
	if active.is_empty():
		_add_line("（没有进行中的委托。）", Color(0.7, 0.7, 0.75))
	for q in active:
		_add_quest_card(q, false)

	_add_section("已完成")
	var done: Array = qm.completed_quests()
	if done.is_empty():
		_add_line("（尚未完成任何委托。）", Color(0.7, 0.7, 0.75))
	for q in done:
		var row := Label.new()
		row.text = "✓  %s" % q.get("title", "")
		row.add_theme_color_override("font_color", Color(0.65, 0.85, 0.65))
		_scroll_box.add_child(row)


func _add_section(text: String) -> void:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	_scroll_box.add_child(sep)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_scroll_box.add_child(label)


func _add_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll_box.add_child(label)


## 一条委托：标题 + 简介 + 奖励行（进行中显示下一步目标；可接受时带「接受」按钮）。
func _add_quest_card(q: Dictionary, can_accept: bool) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	_scroll_box.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	var title := Label.new()
	title.text = str(q.get("title", ""))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	vb.add_child(title)

	var brief := Label.new()
	brief.text = str(q.get("brief", ""))
	brief.add_theme_font_size_override("font_size", 12)
	brief.add_theme_color_override("font_color", Color(0.8, 0.8, 0.82))
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(brief)

	if can_accept:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var reward := Label.new()
		reward.text = "奖励：%s" % get_node("/root/QuestManager").reward_text(q.get("rewards", {}))
		reward.add_theme_font_size_override("font_size", 12)
		reward.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		row.add_child(reward)
		var accept := Button.new()
		accept.text = "接受"
		accept.add_theme_font_size_override("font_size", 13)
		accept.pressed.connect(func() -> void:
			get_node("/root/QuestManager").accept(str(q.get("id", "")))
			_refresh())
		row.add_child(accept)
	else:
		var target := Label.new()
		target.text = _step_target(q)
		target.add_theme_font_size_override("font_size", 12)
		target.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
		target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(target)


## 进行中委托的下一步目标文案（v0.1 只认 tarot_reading_for；其余回落「查看委托细节」）。
func _step_target(q: Dictionary) -> String:
	var steps: Array = q.get("steps", [])
	var qm: Node = get_node("/root/QuestManager")
	var idx: int = qm.step_index_of(str(q.get("id", "")))
	if idx >= steps.size():
		return "……委托书上的字迹模糊了。"
	var step: Dictionary = steps[idx]
	match str(step.get("type", "")):
		"tarot_reading_for":
			return "→ 去找 %s，他有一件事想请你占卜。" % qm.display_name(str(step.get("npc", "")))
		_:
			return "→ 按委托书上的要求准备（后续开放）。"


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.15, 0.18, 0.92)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
