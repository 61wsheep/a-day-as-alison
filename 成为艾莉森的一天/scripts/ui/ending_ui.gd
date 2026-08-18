extends CanvasLayer

## 结局 UI — 全屏展示结局塔罗牌面与文本，点击回到清晨开始新循环。

var _endings: Dictionary = {}
var _panel: PanelContainer
var _tarot_label: Label
var _title_label: Label
var _text_label: Label
var _progress_label: Label
var _btn: Button


func _ready() -> void:
	layer = 30
	_load_endings()
	_build_ui()


func _load_endings() -> void:
	var f := FileAccess.open("res://resources/endings/endings.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			_endings = data.get("endings", {})


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 420)
	_panel.offset_left = -280
	_panel.offset_top = -210
	_panel.offset_right = 280
	_panel.offset_bottom = 210
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	_tarot_label = Label.new()
	_tarot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tarot_label.add_theme_font_size_override("font_size", 16)
	_tarot_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
	vbox.add_child(_tarot_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(_title_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(520, 240)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_text_label)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_progress_label)

	_btn = Button.new()
	_btn.text = "—— 回到清晨 ——"
	_btn.pressed.connect(_on_confirm)
	vbox.add_child(_btn)

	_hide_all()


func _hide_all() -> void:
	get_node("Dim").hide()
	_panel.hide()


func show_ending(ending_id: String) -> void:
	if not _endings.has(ending_id):
		return
	var gm = get_node("/root/GameManager")
	gm.unlock_ending(ending_id)
	var e: Dictionary = _endings[ending_id]
	_tarot_label.text = str(e.get("tarot", ""))
	_title_label.text = "结局 · %s" % str(e.get("title", ""))
	_text_label.text = str(e.get("text", ""))
	_progress_label.text = "已收集结局 %d / 22 —— 只有「世界」能打破循环" % gm.endings_unlocked.size()
	get_node("Dim").show()
	_panel.show()
	get_node("/root/EventBus").dialogue_started.emit()
	get_node("/root/EventBus").ending_reached.emit(ending_id)


func _on_confirm() -> void:
	_hide_all()
	get_node("/root/EventBus").dialogue_ended.emit()
	get_node("/root/GameManager").reset_loop()
