class_name AIMemoryStore
extends RefCounted

## NPC 跨天 AI 记忆存储。存 user://ai_memory/<npc_id>.json。
## 结构对齐 ai_verify/memories/<npc>.json：
##   {
##     "npc_id": "...",
##     "last_saved": "...",
##     "day": N,                     # 信息性
##     "affection": N,               # 信息性（真实好感度以 GameManager 为准）
##     "memory_updates": [...],      # 最多 20 条
##     "total_turns": N,
##     "recent_history": [...],      # 最多 3 轮 {player, npc}
##   }

const MAX_MEMORY_UPDATES := 20
const MAX_RECENT_HISTORY := 3


## 读取 NPC 记忆。文件不存在/损坏时返回空结构。
static func load(npc_id: String) -> Dictionary:
	var path := _path(npc_id)
	if not FileAccess.file_exists(path):
		return {
			"npc_id": npc_id,
			"memory_updates": [],
			"total_turns": 0,
			"recent_history": [],
		}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"npc_id": npc_id,
			"memory_updates": [],
			"total_turns": 0,
			"recent_history": [],
		}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		var m: Dictionary = parsed
		m["memory_updates"] = m.get("memory_updates", []) if m.get("memory_updates") is Array else []
		m["recent_history"] = m.get("recent_history", []) if m.get("recent_history") is Array else []
		m["total_turns"] = int(m.get("total_turns", 0))
		return m
	return {
		"npc_id": npc_id,
		"memory_updates": [],
		"total_turns": 0,
		"recent_history": [],
	}


## 写入 NPC 记忆。affection/day 为信息性字段（以 GameManager 为准，调用方传入）。
static func save(npc_id: String, memory_updates: Array, total_turns: int,
		recent_history: Array, affection: int = 0, day: int = 0) -> void:
	var dir := "user://ai_memory"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var data := {
		"npc_id": npc_id,
		"last_saved": Time.get_datetime_string_from_system(),
		"day": day,
		"affection": affection,
		"memory_updates": memory_updates.slice(max(0, memory_updates.size() - MAX_MEMORY_UPDATES)),
		"total_turns": total_turns,
		"recent_history": recent_history.slice(max(0, recent_history.size() - MAX_RECENT_HISTORY)),
	}
	var f := FileAccess.open(_path(npc_id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


static func _path(npc_id: String) -> String:
	return "user://ai_memory/%s.json" % npc_id
