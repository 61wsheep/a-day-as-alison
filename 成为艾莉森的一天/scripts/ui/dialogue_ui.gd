extends CanvasLayer

## 对话 UI — 对话面板 + 交互提示
##
## 监听 EventBus 信号驱动显示。

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var text_label: Label = $Panel/VBoxContainer/TextLabel
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel
@onready var interact_hint: Panel = $InteractHint


func _ready() -> void:
	panel.hide()
	interact_hint.hide()
	get_node("/root/EventBus").interaction_hint_show.connect(_show_hint)
	get_node("/root/EventBus").interaction_hint_hide.connect(_hide_hint)
	get_node("/root/EventBus").dialogue_started.connect(_on_dialogue_started)
	get_node("/root/EventBus").dialogue_advanced.connect(_on_dialogue_advanced)
	get_node("/root/EventBus").dialogue_ended.connect(_on_dialogue_ended)


func _show_hint() -> void:
	interact_hint.show()


func _hide_hint() -> void:
	interact_hint.hide()


func _on_dialogue_started(_npc_id: String, npc_name: String, text: String) -> void:
	name_label.text = npc_name
	text_label.text = text
	hint_label.text = "[E] Continue"
	panel.show()


func _on_dialogue_advanced(_npc_id: String, text: String) -> void:
	text_label.text = text


func _on_dialogue_ended(_npc_id: String) -> void:
	panel.hide()
