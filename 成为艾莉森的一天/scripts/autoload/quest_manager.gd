extends Node

## 订单/任务管理器（M2 底座）— quests.json 数据驱动。
## v0.1：塔罗占卜委托（kind=tarot_reading），机制通用，后续 NPC/建房任务加数据即可。
## 状态全内存：跨 loop_reset 保留，重启不保留（无存档系统，v0.1 约定）。
##
## 与对话系统的桥（利用既有 conditions 词汇表）：
##   accept   → GameManager.set_flag("quest_active_<id>")
##              → NPC 对话 JSON 用 flag:["quest_active_<id>"] 命中「占卜请求」块
##   complete → 清除该 flag + 奖励 flag 落地（rewards.set_flag）
##              → 对话 JSON 用 flag 命中「故事回放」块

const QUESTS_PATH := "res://resources/data/quests.json"

## NPC 显示名（奖励 toast / 委托板文案共用）
const NPC_DISPLAY := {
	"padwin": "帕德温",
	"soraya": "索拉雅",
	"cactus_bishop": "卡克特斯主教",
}

signal quest_accepted(quest_id: String)
signal quest_completed(quest_id: String)

var _data: Dictionary = {}
var _active: Dictionary = {}        # quest_id -> {"step_index": int}
var _completed: Array[String] = []


func _ready() -> void:
	_load()


func _load() -> void:
	if FileAccess.file_exists(QUESTS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
		if parsed is Dictionary:
			_data = parsed


func quests() -> Array:
	return _data.get("quests", [])


func get_quest(quest_id: String) -> Dictionary:
	for q in quests():
		if str(q.get("id", "")) == quest_id:
			return q
	return {}


func is_completed(quest_id: String) -> bool:
	return quest_id in _completed


func is_active(quest_id: String) -> bool:
	return _active.has(quest_id)


## 活动任务当前 step 下标（委托板渲染「下一步目标」文案用；未进行/已完成返回 0）。
func step_index_of(quest_id: String) -> int:
	if not is_active(quest_id):
		return 0
	return int(_active[quest_id].get("step_index", 0))


func active_flag_of(quest_id: String) -> String:
	return "quest_active_%s" % quest_id


## 解锁条件求值（对话/委托板共用，读 GameManager 状态）。
## 支持 unlock: {day_min, affection_min{npc:val}, flag:[], flag_not:[], rented}
func unlock_met(quest_id: String) -> bool:
	var q := get_quest(quest_id)
	if q.is_empty():
		return false
	var u: Dictionary = q.get("unlock", {})
	var gm = get_node("/root/GameManager")
	if u.has("day_min") and gm.current_day < int(u["day_min"]):
		return false
	if u.has("affection_min"):
		var am: Dictionary = u["affection_min"]
		for npc_id in am:
			if int(gm.npc_affection.get(npc_id, 0)) < int(am[npc_id]):
				return false
	for f in u.get("flag", []):
		if not gm.has_flag(str(f)):
			return false
	for f in u.get("flag_not", []):
		if gm.has_flag(str(f)):
			return false
	if u.has("rented") and gm.treehouse_rented != bool(u["rented"]):
		return false
	return true


## NPC 显示名（委托板/占卜面板文案用）
func display_name(npc_id: String) -> String:
	return NPC_DISPLAY.get(npc_id, npc_id)


## 委托板上可接受的委托：解锁条件满足、未进行、未完成。
func available_quests() -> Array:
	var out: Array = []
	for q in quests():
		var qid := str(q.get("id", ""))
		if qid == "":
			continue
		if is_active(qid) or is_completed(qid):
			continue
		if unlock_met(qid):
			out.append(q)
	return out


## 进行中委托（含进度），供委托板「进行中」区渲染。
func active_quests() -> Array:
	var out: Array = []
	for qid in _active:
		var q := get_quest(qid)
		if not q.is_empty():
			out.append(q)
	return out


## 已完成委托列表，供委托板归档区渲染。
func completed_quests() -> Array:
	var out: Array = []
	for qid in _completed:
		var q := get_quest(qid)
		if not q.is_empty():
			out.append(q)
	return out


func accept(quest_id: String) -> void:
	if is_active(quest_id) or is_completed(quest_id):
		return
	if get_quest(quest_id).is_empty():
		return
	_active[quest_id] = {"step_index": 0}
	var gm = get_node("/root/GameManager")
	gm.set_flag(active_flag_of(quest_id))
	quest_accepted.emit(quest_id)
	get_node("/root/EventBus").toast.emit("接受了委托：%s" % get_quest(quest_id).get("title", quest_id))


## 各系统上报事件推进任务（v0.1 只有 tarot_reading_for）：
##   QuestManager.report({"type":"tarot_reading_for","npc":"padwin"})
## 匹配活动任务当前 step（type + npc），单步任务直接完成。
func report(event: Dictionary) -> void:
	var etype := str(event.get("type", ""))
	for qid in _active:
		var q := get_quest(qid)
		var steps: Array = q.get("steps", [])
		var idx := int(_active[qid].get("step_index", 0))
		if idx >= steps.size():
			continue
		var step: Dictionary = steps[idx]
		if str(step.get("type", "")) != etype:
			continue
		if step.has("npc") and str(event.get("npc", "")) != str(step.get("npc", "")):
			continue
		_complete(qid)
		return


func _complete(quest_id: String) -> void:
	var q := get_quest(quest_id)
	var gm = get_node("/root/GameManager")
	# 奖励落地复用 GameManager.apply_effects（gold/affection/set_flag）
	gm.apply_effects(q.get("rewards", {}))
	_completed.append(quest_id)
	_active.erase(quest_id)
	gm.flags[active_flag_of(quest_id)] = false   # GameManager 无 clear_flag，直接置 false
	var bus := get_node("/root/EventBus")
	bus.toast.emit("委托完成！%s（%s）" % [q.get("title", quest_id), reward_text(q.get("rewards", {}))])
	quest_completed.emit(quest_id)


## 奖励摘要文案：{gold:30, affection:{padwin:10}} → 「金币 +30 · 帕德温 好感 +10」
func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("gold"):
		parts.append("金币 +%d" % int(r["gold"]))
	var aff: Dictionary = r.get("affection", {})
	for npc_id in aff:
		parts.append("%s 好感 +%d" % [NPC_DISPLAY.get(npc_id, npc_id), int(aff[npc_id])])
	return " · ".join(parts)


## 该 NPC 名下是否有「在等他来占卜」的活动任务（占卜面板入口判断）。
## 返回任务 id，无则 ""。
func pending_reading_for(npc_id: String) -> String:
	for qid in _active:
		var q := get_quest(qid)
		var steps: Array = q.get("steps", [])
		var idx := int(_active[qid].get("step_index", 0))
		if idx >= steps.size():
			continue
		var step: Dictionary = steps[idx]
		if str(step.get("type", "")) == "tarot_reading_for" and str(step.get("npc", "")) == npc_id:
			return qid
	return ""
