extends Node

## 全局游戏管理器
## 管理跨循环保留的数据：金币、线索、结局、好感度、剧情标记。

var gold: int = 100
var endings_unlocked: Array[String] = []
var clues_found: Array[String] = []
var flags: Dictionary = {}
var npc_affection: Dictionary = {
	"soraya": 55,
	"padwin": 50,
	"cactus_bishop": 25,
}
var current_day: int = 1
var current_time: String = "morning"
var current_area: String = "plaza"
var tarot_drawn_today: bool = false
var daily_tarot_card: String = ""
var daily_luck: int = 0
var treehouse: String = ""
var treehouse_rented: bool = false

## 天的状态层（记忆系统第二步）。
## 持久字段（跨天）：benevolence/engagement/truth_proximity/prophecy_resistance。
## 单日字段（reset_loop 重置）：daily_prophecy/daily_compliance。
## v0.1 只存内存；user:// 持久化随存档系统排期。
var heaven: Dictionary = {
	"benevolence": 0.0,
	"engagement": 0.3,
	"truth_proximity": 0.0,
	"prophecy_resistance": 0,
	"daily_prophecy": null,
	"daily_compliance": "",
	"tomorrow_seed": "",
	"last_judgment": {},
}

## 线索显示名（用于提示）
const CLUE_NAMES := {
	"clue_padwin_no_memory": "帕德温没有前世的记忆",
	"clue_cactus_scar": "主教颈上的勒痕",
	"clue_burn_scar": "自己背上的烧伤疤痕",
	"clue_soraya_repeat": "索拉雅机械重复的迎接",
	"clue_forest_fake": "塔楼中的森林起源之书",
	"clue_id_card": "树屋里与自己完全相符的身份证",
}


func add_gold(amount: int) -> void:
	gold += amount
	gold = max(gold, 0)
	get_node("/root/EventBus").gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		get_node("/root/EventBus").gold_changed.emit(gold)
		return true
	return false


func unlock_ending(ending_id: String) -> void:
	if ending_id not in endings_unlocked:
		endings_unlocked.append(ending_id)


func discover_clue(clue_id: String) -> void:
	if clue_id not in clues_found:
		clues_found.append(clue_id)
		get_node("/root/EventBus").clue_found.emit(clue_id)
		var display: String = CLUE_NAMES.get(clue_id, clue_id)
		get_node("/root/EventBus").toast.emit("获得线索：%s" % display)
		record_heaven_event("clue", "玩家发现线索：%s" % display, [clue_id, current_area])


## 天记忆事件打点（记忆系统第一步地基）。
## owner 默认 "heaven"（天全知可见）；NPC 私密事件传具体 npc_id。
## fact 必须是程序生成的客观描述，不接受 AI 文本。
func record_heaven_event(type: String, fact: String, tags: Array = [], owner: String = "heaven") -> void:
	HeavenMemoryStore.record_event(type, owner, tags, fact, current_day)


func set_flag(flag_id: String) -> void:
	flags[flag_id] = true


func has_flag(flag_id: String) -> bool:
	return flags.get(flag_id, false)


func change_affection(npc_id: String, delta: int) -> void:
	if npc_affection.has(npc_id):
		npc_affection[npc_id] = clamp(npc_affection[npc_id] + delta, 0, 100)


func get_affection_tier(npc_id: String) -> String:
	var val = npc_affection.get(npc_id, 0)
	if val < 20: return "hostile"
	elif val < 40: return "cold"
	elif val < 60: return "neutral"
	elif val < 80: return "friendly"
	else: return "intimate"


## 统一处理剧情 effects（对话 JSON 中的效果块）
func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	for f in effects.get("set_flag", []):
		set_flag(f)
	for c in effects.get("discover_clue", []):
		discover_clue(c)
	var aff: Dictionary = effects.get("affection", {})
	for npc_id in aff:
		change_affection(npc_id, int(aff[npc_id]))
	if effects.has("gold"):
		add_gold(int(effects["gold"]))
	if effects.has("action"):
		get_node("/root/EventBus").game_action.emit(str(effects["action"]))


## 条件判定（对话选择 / 对话线 / 对话入口共用）
func conditions_met(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	for f in cond.get("flag", []):
		if not has_flag(f):
			return false
	for f in cond.get("flag_not", []):
		if has_flag(f):
			return false
	for c in cond.get("clue", []):
		if c not in clues_found:
			return false
	for c in cond.get("clue_not", []):
		if c in clues_found:
			return false
	if cond.has("day_min") and current_day < int(cond["day_min"]):
		return false
	if cond.has("time") and current_time != str(cond["time"]):
		return false
	if cond.has("rented") and treehouse_rented != bool(cond["rented"]):
		return false
	return true


func reset_loop() -> void:
	current_day += 1
	current_time = "morning"
	tarot_drawn_today = false
	daily_tarot_card = ""
	daily_luck = 0
	# 天的单日字段随循环重置（tomorrow_seed 跨天保留，供次日天命面具注入）
	heaven["daily_prophecy"] = null
	heaven["daily_compliance"] = ""
	get_node("/root/EventBus").loop_reset.emit()
	get_node("/root/EventBus").day_started.emit(current_day)


## 顺从/反抗三态判定（切片设计 §3.5，Godot 裁判，不交 AI 自评）。
## 事实来源：天记忆事件流（HeavenMemoryStore.events_for_day）。
## 返回 "obey" / "defy" / "neutral"；当天未设局返回 ""。
func compute_compliance() -> String:
	var prophecy: Variant = heaven.get("daily_prophecy")
	if not (prophecy is Dictionary):
		return ""
	var directive: Variant = prophecy.get("directive")
	if not (directive is Dictionary):
		return ""
	var dtype := str(directive.get("type", ""))
	var target := str(directive.get("target", ""))
	if target.is_empty():
		return ""
	var events: Array = HeavenMemoryStore.events_for_day(current_day)

	if dtype == "visit":
		# obey：day_log 记录了访问 A
		# defy：访问了另一地点 B，且在 B 有 ≥1 次有效交互（对话/线索）
		var visited_target := false
		var other_places: Array = []
		for evt in events:
			if str(evt.get("type", "")) != "visit":
				continue
			var tags: Array = evt.get("tags", [])
			if target in tags:
				visited_target = true
			else:
				for t in tags:
					if t not in other_places:
						other_places.append(t)
		if visited_target:
			return "obey"
		for evt in events:
			var etype := str(evt.get("type", ""))
			if etype != "talk" and etype != "clue":
				continue
			for t in evt.get("tags", []):
				if t in other_places:
					return "defy"
		return "neutral"

	if dtype == "talk":
		# obey：与 N 有过对话
		# defy：与 N 之外的其他 NPC 合计对话 ≥2 次，且与 N 对话 0 次
		var talked_target := false
		var other_talks := 0
		for evt in events:
			if str(evt.get("type", "")) != "talk":
				continue
			if target in evt.get("tags", []):
				talked_target = true
			else:
				other_talks += 1
		if talked_target:
			return "obey"
		if other_talks >= 2:
			return "defy"
		return "neutral"

	return ""


func set_time(time_id: String) -> void:
	current_time = time_id
	get_node("/root/EventBus").time_changed.emit(time_id)
	if time_id == "midnight":
		get_node("/root/EventBus").midnight_reached.emit()
