extends CharacterBody2D
class_name NPCBase

## NPC 基类 — 提供对话触发、交互区域检测、对话数据管理。
##
## 通过 EventBus 信号驱动对话 UI，不再使用 print。

signal interaction_available(npc_id: String)

@export var npc_id: String = ""
@export var npc_name: String = ""
@export_multiline var dialogue_lines: Array[String] = []

var _player_in_range: bool = false
var _dialogue_active: bool = false
var _current_line: int = 0


func _ready() -> void:
	var zone = $InteractZone
	if zone:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if event.is_action_pressed("ui_accept"):
		if _dialogue_active:
			advance_dialogue()
		else:
			_start_dialogue()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		interaction_available.emit(npc_id)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _dialogue_active:
			_end_dialogue()


func _start_dialogue() -> void:
	if dialogue_lines.is_empty():
		return
	_dialogue_active = true
	_current_line = 0
	get_node("/root/EventBus").dialogue_started.emit(npc_id, npc_name, dialogue_lines[0])


func advance_dialogue() -> void:
	_current_line += 1
	if _current_line < dialogue_lines.size():
		get_node("/root/EventBus").dialogue_advanced.emit(npc_id, dialogue_lines[_current_line])
	else:
		_end_dialogue()


func _end_dialogue() -> void:
	_dialogue_active = false
	_current_line = 0
	get_node("/root/EventBus").dialogue_ended.emit(npc_id)
