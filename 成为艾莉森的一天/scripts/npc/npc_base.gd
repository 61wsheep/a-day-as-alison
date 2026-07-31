extends CharacterBody2D
class_name NPCBase

## NPC 基类 — 交互检测 + 对话数据 + 交替对话流。
##
## 对话流：NPC 说一句 → 玩家按 E → 3 个选项出现
## → 玩家选一个 → NPC 说下一句 → 循环直到对话结束。

signal interaction_available(npc_id: String)

@export var npc_id: String = ""
@export var npc_name: String = ""
@export_multiline var npc_lines: Array[String] = []
@export_multiline var player_lines: Array[String] = []

var _player_in_range: bool = false
var _dialogue_active: bool = false
var _waiting_for_choice: bool = false
var _current_line: int = 0


func _ready() -> void:
	var zone = $InteractZone
	if zone:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	# Esc 随时退出对话（仅在对话激活时）
	if _dialogue_active and event.is_action_pressed("ui_cancel"):
		_end_dialogue()
		return
	if not _player_in_range:
		return
	if event.is_action_pressed("ui_accept"):
		if _dialogue_active and _waiting_for_choice:
			# 玩家按 E 但还在等选择 → 忽略
			return
		if _dialogue_active:
			# NPC 说完一句 → 显示选择
			_show_choices()
		else:
			# 开始对话
			_start_dialogue()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		interaction_available.emit(npc_id)
		get_node("/root/EventBus").interaction_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		get_node("/root/EventBus").interaction_hint_hide.emit()
		if _dialogue_active:
			_end_dialogue()


func _start_dialogue() -> void:
	if npc_lines.is_empty():
		return
	_dialogue_active = true
	_waiting_for_choice = false
	_current_line = 0
	get_node("/root/EventBus").interaction_hint_hide.emit()
	get_node("/root/EventBus").dialogue_started.emit(npc_id, npc_name, npc_lines[0])


func _show_choices() -> void:
	_waiting_for_choice = true
	var pre_written := ""
	if _current_line < player_lines.size():
		pre_written = player_lines[_current_line]
	get_node("/root/EventBus").dialogue_choices_show.emit(npc_id, npc_name, pre_written)


func on_choice_made(_npc_id: String, choice_index: int, reply_text: String) -> void:
	_waiting_for_choice = false

	# 短暂显示玩家回复
	get_node("/root/EventBus").player_reply_shown.emit(reply_text)

	# 推进到 NPC 下一句
	_current_line += 1
	if _current_line < npc_lines.size():
		await get_tree().create_timer(1.5).timeout
		get_node("/root/EventBus").dialogue_advanced.emit(npc_id, npc_lines[_current_line])
	else:
		await get_tree().create_timer(1.5).timeout
		_end_dialogue()


func _end_dialogue() -> void:
	_dialogue_active = false
	_waiting_for_choice = false
	_current_line = 0
	get_node("/root/EventBus").dialogue_ended.emit(npc_id)
