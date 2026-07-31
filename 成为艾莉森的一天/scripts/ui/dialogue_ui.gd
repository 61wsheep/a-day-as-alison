extends CanvasLayer

## 对话 UI — 对话面板 + 交互提示 + 三选一回复面板
##
## 监听 EventBus 信号驱动所有显示。

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var text_label: Label = $Panel/VBoxContainer/TextLabel
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel
@onready var interact_hint: Panel = $InteractHint
@onready var choice_panel: Panel = $ChoicePanel
@onready var choice_pre_btn: Button = $ChoicePanel/VBoxContainer/PreWriteBtn
@onready var choice_silent_btn: Button = $ChoicePanel/VBoxContainer/SilentBtn
@onready var choice_free_input: LineEdit = $ChoicePanel/VBoxContainer/FreeInput


func _ready() -> void:
	panel.hide()
	interact_hint.hide()
	choice_panel.hide()

	# 信号连接
	get_node("/root/EventBus").interaction_hint_show.connect(_show_hint)
	get_node("/root/EventBus").interaction_hint_hide.connect(_hide_hint)
	get_node("/root/EventBus").dialogue_started.connect(_on_dialogue_started)
	get_node("/root/EventBus").dialogue_advanced.connect(_on_dialogue_advanced)
	get_node("/root/EventBus").dialogue_ended.connect(_on_dialogue_ended)
	get_node("/root/EventBus").dialogue_choices_show.connect(_on_choices_show)
	get_node("/root/EventBus").player_reply_shown.connect(_on_player_reply)

	# 按钮事件
	choice_pre_btn.pressed.connect(_on_pre_written)
	choice_silent_btn.pressed.connect(_on_silent)
	choice_free_input.text_submitted.connect(_on_free_input_submitted)


func _show_hint() -> void:
	interact_hint.show()


func _hide_hint() -> void:
	interact_hint.hide()


func _on_dialogue_started(_npc_id: String, npc_name: String, text: String) -> void:
	name_label.text = npc_name
	text_label.text = text
	hint_label.text = "[E] 继续对话"
	choice_panel.hide()
	panel.show()


func _on_dialogue_advanced(_npc_id: String, text: String) -> void:
	name_label.text = "帕德温"
	text_label.text = text
	hint_label.text = "[E] 继续对话"
	choice_panel.hide()
	panel.show()


func _on_dialogue_ended(_npc_id: String) -> void:
	panel.hide()
	choice_panel.hide()


func _on_choices_show(_npc_id: String, _npc_name: String, pre_written: String) -> void:
	choice_pre_btn.text = pre_written if pre_written != "" else "..."
	choice_free_input.text = ""
	choice_panel.show()
	hint_label.text = ""


func _on_pre_written() -> void:
	choice_panel.hide()
	get_node("/root/EventBus").dialogue_choice_made.emit("padwin", 0, choice_pre_btn.text)


func _on_silent() -> void:
	choice_panel.hide()
	get_node("/root/EventBus").dialogue_choice_made.emit("padwin", 1, "（沉默不语）")


func _on_free_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	choice_panel.hide()
	get_node("/root/EventBus").dialogue_choice_made.emit("padwin", 2, text)


func _on_player_reply(text: String) -> void:
	name_label.text = "艾莉森"
	text_label.text = text
	hint_label.text = ""
	panel.show()
