extends CanvasLayer

## 历史对话面板 — 贴近 NPC 按 H 打开（DialogueLog 完整实录），滚动回看。
## layer 15：在对话 UI(10) 之上、占卜/委托板等弹窗(20)之下；open/close 沿用
## dialogue_started/ended 锁玩家，Esc/点遮罩关闭。

const NPC_NAMES := {
	"padwin": "帕德温", "soraya": "索拉雅",
	"cactus_bishop": "卡克特斯主教", "tian": "？？？",
}

var _npc_id := ""
var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _open := false


func _ready() -> void:
	layer = 15
	_build_ui()
	get_node("/root/EventBus").history_requested.connect(open)


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.offset_left = -310
	_panel.offset_top = -240
	_panel.offset_right = 310
	_panel.offset_bottom = 240
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true   # 关键：否则 ScrollContainer 内 RichTextLabel 高度塌成 0，正文渲染空白
	_body.scroll_following = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(580, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 15)
	scroll.add_child(_body)

	var hint := Label.new()
	hint.text = "[Esc] / 点击空白关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)

	_dim.hide()
	_panel.hide()


func open(npc_id: String) -> void:
	_npc_id = npc_id
	var log := get_node("/root/DialogueLog")
	var entries: Array = log.for_npc(npc_id)
	_title.text = "—— 与 %s 的对话 ——" % _npc_display_name(npc_id)
	_body.clear()
	if entries.is_empty():
		_body.append_text("还没有与 %s 的对话记录。" % _npc_display_name(npc_id))
	else:
		var last_day := -1
		for e in entries:
			var day := int(e.get("day", 0))
			if day != last_day:
				last_day = day
				_body.append_text("\n[center][color=#9a9aa0]—— 第 %d 天 ——[/color][/center]\n" % day)
			var name := str(e.get("display", ""))
			var text := str(e.get("text", ""))
			var color := "#d9d9de"
			match str(e.get("speaker", "")):
				"player":
					color = "#a8d8a8"
				"narrator":
					color = "#9a9aa0"
			_body.append_text("[color=%s]%s：[/color]%s\n" % [color, name, text])
		_body.scroll_to_line(_body.get_line_count() - 1)
	_open = true
	_dim.show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()   # 锁玩家移动


func is_open() -> bool:
	return _open


func _npc_display_name(npc_id: String) -> String:
	return NPC_NAMES.get(npc_id, npc_id)


func _close() -> void:
	if not _open:
		return
	_open = false
	_dim.hide()
	_panel.hide()
	get_node("/root/EventBus").dialogue_ended.emit()   # 解锁玩家移动


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
