extends Node

## 历史对话实录（autoload）— 按 NPC 记录本局实际发生过的每一句对白
## （脚本台词 + AI 会话行 + narrator/player 行），供「贴近 NPC 按 H 查看历史对话」回看。
## 记录由 npc_base._emit_line / _on_free_input 上报；内存态，跨天保留，随会话结束清空。

const MAX_PER_NPC := 400   # 每 NPC 上限，超出丢最旧

## npc_id → Array[{day:int, speaker:String, display:String, text:String}]（旧→新）
var logs: Dictionary = {}


func append(npc_id: String, speaker: String, display: String, text: String, day: int) -> void:
	if npc_id == "" or text == "":
		return
	var list: Array = logs.get(npc_id, [])
	list.append({
		"day": day,
		"speaker": speaker,
		"display": display if display != "" else _display_fallback(speaker),
		"text": text,
	})
	while list.size() > MAX_PER_NPC:
		list.pop_front()
	logs[npc_id] = list


## 该 NPC 的实录副本（旧→新；最新在后）。
func for_npc(npc_id: String) -> Array:
	var list: Array = logs.get(npc_id, [])
	return list.duplicate()


func clear_npc(npc_id: String) -> void:
	logs.erase(npc_id)


func clear_all() -> void:
	logs.clear()


func _display_fallback(speaker: String) -> String:
	if speaker == "player":
		return "艾莉森"
	if speaker == "narrator":
		return "旁白"
	return speaker
