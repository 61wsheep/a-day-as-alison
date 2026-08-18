extends CharacterBody2D
class_name NPCBase

## NPC 基类 — JSON 数据驱动的对话引擎。
##
## 对话数据：res://resources/dialogues/<npc>.json
## 流程：E 开始 → 逐行推进（E）→ 遇到 choices 行弹出选项
## → 选择后应用 effects，可选 reply → 继续/跳转/结束。

signal interaction_available(npc_id: String)

@export var npc_id: String = ""
@export var dialogue_file: String = ""

var _data: Dictionary = {}
var _lines: Array = []
var _end_effects: Dictionary = {}
var _line_idx: int = 0
var _dialogue_active: bool = false
var _waiting_for_choice: bool = false
var _showing_reply: bool = false
var _pending_end: bool = false
var _pending_end_effects: Dictionary = {}
var _player_in_range: bool = false


func _ready() -> void:
	var zone = get_node_or_null("InteractZone")
	if zone:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)
	_load_dialogue_data()
	get_node("/root/EventBus").dialogue_choice_made.connect(_on_choice_made)


func _load_dialogue_data() -> void:
	if dialogue_file.is_empty() or not FileAccess.file_exists(dialogue_file):
		return
	var f := FileAccess.open(dialogue_file, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_data = parsed


func _input(event: InputEvent) -> void:
	if _dialogue_active and event.is_action_pressed("ui_cancel"):
		_end_dialogue()
		return
	if not _player_in_range:
		return
	if event.is_action_pressed("ui_accept"):
		if _waiting_for_choice:
			return
		if _dialogue_active:
			if _showing_reply:
				_showing_reply = false
				if _pending_end:
					_end_dialogue()
					return
				_line_idx += 1
				_advance()
			else:
				_line_idx += 1
				_advance()
		else:
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


# ---------------------------------------------------------------------------
# 对话选择与推进
# ---------------------------------------------------------------------------
func _start_dialogue() -> void:
	var dlg := _select_dialogue()
	if dlg.is_empty():
		return
	_lines = dlg.get("lines", [])
	_end_effects = dlg.get("end_effects", {})
	if _lines.is_empty():
		return
	_dialogue_active = true
	_waiting_for_choice = false
	_showing_reply = false
	_pending_end = false
	_pending_end_effects = {}
	_line_idx = 0
	get_node("/root/EventBus").interaction_hint_hide.emit()
	get_node("/root/EventBus").dialogue_started.emit()
	_advance()


func _select_dialogue() -> Dictionary:
	var gm = get_node("/root/GameManager")
	var best: Dictionary = {}
	var best_priority := -1
	for dlg in _data.get("dialogues", []):
		if gm.conditions_met(dlg.get("conditions", {})):
			var p := int(dlg.get("priority", 0))
			if p > best_priority:
				best_priority = p
				best = dlg
	return best


func _advance() -> void:
	var gm = get_node("/root/GameManager")
	var bus = get_node("/root/EventBus")
	while _line_idx < _lines.size():
		var line: Dictionary = _lines[_line_idx]
		if line.has("conditions") and not gm.conditions_met(line["conditions"]):
			_line_idx += 1
			continue
		if line.has("choices"):
			var valid: Array = []
			for choice in line["choices"]:
				if gm.conditions_met(choice.get("conditions", {})):
					valid.append(choice)
			if valid.is_empty():
				_line_idx += 1
				continue
			_waiting_for_choice = true
			var labels: Array = []
			for c in valid:
				labels.append(str(c.get("text", "……")))
			bus.dialogue_choices.emit(labels)
			# 同时显示该行文本作为选项前的铺垫
			if str(line.get("text", "")) != "":
				_emit_line(line)
			return
		_emit_line(line)
		return
	_end_dialogue()


func _emit_line(line: Dictionary) -> void:
	var speaker := str(line.get("speaker", npc_id))
	var display := _display_name(speaker)
	get_node("/root/EventBus").dialogue_line.emit(
		speaker, display, str(line.get("text", "")), str(line.get("emotion", "")))


func _display_name(speaker: String) -> String:
	if speaker == "player":
		return "艾莉森"
	if speaker == "narrator":
		return ""
	return str(_data.get("display_name", speaker))


func _on_choice_made(choice_index: int) -> void:
	if not _dialogue_active or not _waiting_for_choice:
		return
	_waiting_for_choice = false
	var gm = get_node("/root/GameManager")
	var line: Dictionary = _lines[_line_idx]
	var valid: Array = []
	for choice in line["choices"]:
		if gm.conditions_met(choice.get("conditions", {})):
			valid.append(choice)
	if choice_index < 0 or choice_index >= valid.size():
		return
	var chosen: Dictionary = valid[choice_index]

	gm.apply_effects(chosen.get("effects", {}))
	_pending_end_effects = chosen.get("end_effects", {})
	_pending_end = bool(chosen.get("end", false))

	var reply := str(chosen.get("reply", ""))
	if reply != "":
		_showing_reply = true
		_emit_line({
			"speaker": npc_id,
			"text": reply,
			"emotion": str(chosen.get("reply_emotion", "")),
		})
		return

	if _pending_end:
		_end_dialogue()
		return
	if chosen.has("goto"):
		_line_idx = int(chosen["goto"])
	else:
		_line_idx += 1
	_advance()


func _end_dialogue() -> void:
	if not _dialogue_active:
		return
	_dialogue_active = false
	_waiting_for_choice = false
	_showing_reply = false
	var gm = get_node("/root/GameManager")
	gm.apply_effects(_pending_end_effects)
	gm.apply_effects(_end_effects)
	_pending_end_effects = {}
	get_node("/root/EventBus").dialogue_ended.emit()
