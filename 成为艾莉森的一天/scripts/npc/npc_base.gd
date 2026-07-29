extends CharacterBody2D
class_name NPCBase

## NPC 基类 — 提供对话触发、交互区域检测、对话数据管理。

signal interaction_available(npc_id: String)

@export var npc_id: String = ""
@export var npc_name: String = ""
@export_multiline var dialogue_lines: Array[String] = []

var _player_in_range: bool = false
var _current_line: int = 0


func _ready() -> void:
	# 连接 InteractZone 的 body 进出信号
	var zone = $InteractZone
	if zone:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("ui_accept"):
		_start_dialogue()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		interaction_available.emit(npc_id)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _start_dialogue() -> void:
	if dialogue_lines.is_empty():
		return
	get_node("/root/EventBus").dialogue_started.emit(npc_id)
	_current_line = 0
	_show_current_line()


func _show_current_line() -> void:
	if _current_line < dialogue_lines.size():
		print("[%s]: %s" % [npc_name, dialogue_lines[_current_line]])


func advance_dialogue() -> void:
	_current_line += 1
	if _current_line < dialogue_lines.size():
		_show_current_line()
	else:
		_end_dialogue()


func _end_dialogue() -> void:
	get_node("/root/EventBus").dialogue_ended.emit(npc_id)
	_current_line = 0
