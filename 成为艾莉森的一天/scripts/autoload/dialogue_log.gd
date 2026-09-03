extends Node

## 历史对话实录（autoload）— 按 NPC 记录实际发生过的每一句对白
## （脚本台词 + AI 会话行 + narrator/player 行），供「贴近 NPC 按 H 查看历史对话」回看。
## 记录由 npc_base._emit_line / _on_free_input 上报。
##
## 持久化：写穿到 user://dialogue_log.json，跨进程保留 —— 与 AI 记忆(ai_memory)
## / 天的记忆(heaven_memory) 同一套"跨天/跨会话都记得"的设定。否则重开游戏后
## 历史归零，按 H 面板永远空白（真机 bug 根因）。
##   - 仅非 headless（真机/窗口运行）默认落盘；headless 测试跑 JSON 无盘污染。
##   - 测试可 set_storage_path() 显式指定测试盘以验证持久化（会强制开启落盘）。

const MAX_PER_NPC := 400   # 每 NPC 上限，超出丢最旧
const DEFAULT_PATH := "user://dialogue_log.json"

## npc_id → Array[{day:int, speaker:String, display:String, text:String}]（旧→新）
var logs: Dictionary = {}

var _storage_path := DEFAULT_PATH
var _persist := false      # 是否落盘（默认仅真机；测试 set_storage_path 后强制开）


func _ready() -> void:
	_persist = DisplayServer.get_name() != "headless"
	if _persist:
		_load()


## 测试隔离：改用独立存储文件并强制落盘，避免污染/依赖真机 user:// 历史。
func set_storage_path(path: String) -> void:
	_storage_path = path
	_persist = true


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
	if _persist:
		_save()


## 该 NPC 的实录副本（旧→新；最新在后）。
func for_npc(npc_id: String) -> Array:
	var list: Array = logs.get(npc_id, [])
	return list.duplicate()


func clear_npc(npc_id: String) -> void:
	logs.erase(npc_id)
	if _persist:
		_save()


func clear_all() -> void:
	logs.clear()
	if _persist:
		_save()


## 从磁盘重载（模拟"重新打开游戏"后 _ready 的加载路径；测试用它验证跨进程持久化）。
func reload() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(_storage_path):
		return
	var f := FileAccess.open(_storage_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var loaded: Dictionary = {}
	for npc_id in parsed:
		var raw: Array = parsed[npc_id] if parsed[npc_id] is Array else []
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
			loaded[str(npc_id)] = list
	logs = loaded


func _save() -> void:
	var f := FileAccess.open(_storage_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(logs, "\t"))
		f.close()


func _display_fallback(speaker: String) -> String:
	if speaker == "player":
		return "艾莉森"
	if speaker == "narrator":
		return "旁白"
	return speaker
