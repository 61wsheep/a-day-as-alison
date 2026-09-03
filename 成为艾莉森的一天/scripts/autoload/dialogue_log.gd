extends Node

## 历史对话实录（autoload）— 按 NPC 记录实际发生过的每一句对白
## （脚本台词 + AI 会话行 + narrator/player 行），供「贴近 NPC 按 H 查看历史对话」回看。
## 记录由 npc_base._emit_line / _on_free_input 上报。
##
## 作用域 = 本轮次（本次启动）：纯内存，刻意不落盘 —— 关游戏即清空，
## 下一次启动从零开始。现状没有存档系统，跨启动保留与"只显示这一轮玩过的
## 内容"冲突；等存档系统落地后，由存档层调 serialize()/deserialize() 把实录
## 随档读写，历史便只显示所载档的内容。
## （对照：NPC 的 ai_memory / 天的 heaven_memory 是"角色记得"的设定，仍跨
##  会话持久，与"玩家可回看的实录按轮清空"是两条线，互不影响。）

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


## 存档接入点：导出当前轮实录（随档保存用）。存档系统落地后把返回值写进存档文件。
func serialize() -> Dictionary:
	return logs.duplicate(true)


## 存档接入点：从存档数据恢复本轮实录（随档加载用）。传入 serialize() 的产物可原样还原。
func deserialize(data: Dictionary) -> void:
	logs.clear()
	for npc_id in data:
		var raw: Array = data[npc_id] if data[npc_id] is Array else []
		var list: Array = []
		for e in raw:
			if not (e is Dictionary):
				continue
			list.append({
				"day": int(e.get("day", 0)),
				"speaker": str(e.get("speaker", "")),
				"display": str(e.get("display", "")),
				"text": str(e.get("text", "")),
			})
		while list.size() > MAX_PER_NPC:
			list.pop_front()
		if not list.is_empty():
			logs[str(npc_id)] = list


func _display_fallback(speaker: String) -> String:
	if speaker == "player":
		return "艾莉森"
	if speaker == "narrator":
		return "旁白"
	return speaker
