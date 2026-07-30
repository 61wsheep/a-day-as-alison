extends CanvasLayer

## 对话 UI — 显示 NPC 名称、对话文本、"按 E 继续"提示。
##
## 监听 EventBus 信号：dialogue_started / dialogue_advanced / dialogue_ended

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var text_label: Label = $Panel/VBoxContainer/TextLabel
@onready var hint_label: Label = $Panel/VBoxContainer/HintLabel


func _ready() -> void:
	hide()
	get_node("/root/EventBus").dialogue_started.connect(_on_dialogue_started)
	get_node("/root/EventBus").dialogue_advanced.connect(_on_dialogue_advanced)
	get_node("/root/EventBus").dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started(npc_id: String, npc_name: String, text: String) -> void:
	name_label.text = npc_name
	text_label.text = text
	hint_label.text = "[E] 继续"
	show()


func _on_dialogue_advanced(_npc_id: String, text: String) -> void:
	text_label.text = text


func _on_dialogue_ended(_npc_id: String) -> void:
	hide()
