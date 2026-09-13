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
	"last_compliance": "",
	"tomorrow_seed": "",
	"last_judgment": {},
	"loop_hard_cap": false,
}

## 循环硬上限（切片设计 §5.3）：第 20 天后无论如何强制终结。
const HARD_DAY_CAP := 20

## 当天开始时的好感度基线（reset_loop 时快照），供 apply_heaven_rules 算日差分。
var _affection_day_start: Dictionary = {}

## 线索显示名（用于提示）
## ⚠️ 必须与 resources/data/clues.json 的 name 逐字一致：状态面板把这里的名字与
## clues.json 的 desc 拼在一起显示，两套名字分叉就会出现"标题和描述不是一回事"。
## 另外这份名字会注入 AI 的 system 上下文，所以要写成**观察**（"挡脸的那只手"），
## 不要写成**结论**（"没有前世的记忆"）——给 AI 结论，它就会用结论的口吻说话。
const CLUE_NAMES := {
	"clue_padwin_no_memory": "帕德温挡脸的那只手",
	"clue_cactus_scar": "主教颈上的勒痕",
	"clue_burn_scar": "她背上的疤",
	"clue_soraya_repeat": "索拉雅递地图的折痕",
	"clue_forest_fake": "塔楼中的森林起源之书",
	"clue_id_card": "居留凭据",
	"clue_tower_roster": "塔楼阶下的名录",
}

## 线索描述层（文案同学交付）。状态面板与 AI 对话都从这里取 desc。
const CLUES_FILE := "res://resources/data/clues.json"
var _clue_desc_cache: Dictionary = {}


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


## 线索描述（clues.json 的 desc）。首次调用时懒加载并缓存。
## 文案同学还没交付的描述写成"（待补…）"占位，那样的返回空串——宁可什么都不给，
## 也不要把"待补"两个字塞进 AI 的上下文。
func clue_description(clue_id: String) -> String:
	if _clue_desc_cache.is_empty():
		var f := FileAccess.open(CLUES_FILE, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.get("clues") is Dictionary:
				_clue_desc_cache = parsed["clues"]
			f.close()
	var entry: Variant = _clue_desc_cache.get(clue_id, {})
	var desc: String = str(entry.get("desc", "")) if entry is Dictionary else ""
	if desc.begins_with("（待补"):
		return ""
	return desc


## 供 AI 对话注入用的一行式线索摘要：名字 —— 描述。
## 已获得的线索必须带描述进 prompt，否则 AI 只知道"她发现了什么名字"，
## 不知道她**看见了什么**，回话就会发虚、只会复述名字。
func clue_brief(clue_id: String) -> String:
	var nm: String = CLUE_NAMES.get(clue_id, clue_id)
	var desc := clue_description(clue_id)
	return nm if desc == "" else "%s —— %s" % [nm, desc]


## 天记忆事件打点（记忆系统第一步地基）。
## owner 默认 "heaven"（天全知可见）；NPC 私密事件传具体 npc_id。
## fact 必须是程序生成的客观描述，不接受 AI 文本。
func record_heaven_event(type: String, fact: String, tags: Array = [], owner: String = "heaven") -> void:
	HeavenMemoryStore.record_event(type, owner, tags, fact, current_day)


func set_flag(flag_id: String) -> void:
	flags[flag_id] = true


func has_flag(flag_id: String) -> bool:
	return flags.get(flag_id, false)


## 好感度变更（唯一入口，AI 结算/剧本 effects/委托奖励都走这里）。
## 实际有变化才广播 affection_changed —— delta=0 或已触顶/触底时不提示，
## 免得 AI 每轮给 0 时对话里一直闪「+0」。
func change_affection(npc_id: String, delta: int) -> void:
	if not npc_affection.has(npc_id):
		return
	var old_value: int = int(npc_affection[npc_id])
	var new_value: int = clampi(old_value + delta, 0, 100)
	if new_value == old_value:
		return
	npc_affection[npc_id] = new_value
	get_node("/root/EventBus").affection_changed.emit(
		npc_id, new_value - old_value, old_value, new_value)


func get_affection_tier(npc_id: String) -> String:
	return affection_tier_of(int(npc_affection.get(npc_id, 0)))


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
	if cond.has("day_max") and current_day > int(cond["day_max"]):
		return false
	if cond.has("time") and current_time != str(cond["time"]):
		return false
	if cond.has("rented") and treehouse_rented != bool(cond["rented"]):
		return false
	# -- 背包条件（对话选项用，如索拉雅「卖点东西」需背包有 forage） --
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null:
		for i in cond.get("has_item", []):
			if inv.count_of(str(i)) <= 0:
				return false
		for k in cond.get("has_kind", []):
			if not inv.has_kind(str(k)):
				return false
	return true


## 重置循环，进入新的一天。
##
## from_ending: 是否由结局「回到清晨」触发。它只影响一件事 —— 循环开场那行旁白
## （opening.json 的 loop_condensed）只在结局那条链路播；午夜入睡是常规推进，
## 玩家刚从自己床上醒来，再演一遍「她在苔上睁眼」既重复又打断节奏。
## 默认 false：入睡、测试、模拟一律走不播的分支。
func reset_loop(from_ending: bool = false) -> void:
	# 归档昨日顺从判定（供次日天命面具/化身面具注入"呼应昨天"）
	heaven["last_compliance"] = str(heaven.get("daily_compliance", ""))
	# 天的单日字段随循环重置（tomorrow_seed 跨天保留，供次日天命面具注入）
	heaven["daily_prophecy"] = null
	heaven["daily_compliance"] = ""
	if current_day >= HARD_DAY_CAP:
		# 硬上限闸（切片设计 §5.3）：第 20 天后循环必须终结。
		# TODO(终局裁决切片)：此处应进入「世界」结局流程；当前夹住天数、其余重置照常，
		# 玩家可继续行动但时间永远停在第 20 天。
		heaven["loop_hard_cap"] = true
		get_node("/root/EventBus").toast.emit("第 20 天。天不再允许时间前进。")
	else:
		current_day += 1
	# 新的一天开始：快照好感度基线（供午夜规则表算日差分）
	_affection_day_start = npc_affection.duplicate()
	current_time = "morning"
	tarot_drawn_today = false
	daily_tarot_card = ""
	daily_luck = 0
	get_node("/root/EventBus").loop_reset.emit(from_ending)
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


## 天的态度平移规则表（切片设计 §3.4）。午夜入睡结算时由 game.gd 调用。
## 输入为当天客观观测（记忆事件流 + 好感度日差分），AI 不参与数值计算。
## ⚠ 表中数值为 v0.1 初值，待测试迭代校准。
func apply_heaven_rules() -> void:
	var events: Array = HeavenMemoryStore.events_for_day(current_day)

	# -- 顺从/反抗 --
	var compliance := str(heaven.get("daily_compliance", ""))
	match compliance:
		"obey":
			_shift("benevolence", 0.04)
			_shift("engagement", -0.02)
			record_heaven_event("obey", "玩家顺从了今日的预言")
		"defy":
			_shift("benevolence", -0.04)
			_shift("engagement", 0.08)
			heaven["prophecy_resistance"] = int(heaven.get("prophecy_resistance", 0)) + 1
			record_heaven_event("defy", "玩家反抗了今日的预言")
		_:
			_shift("engagement", 0.01)   # 中性/未设局：天仍在看

	# -- 发现新线索（每条）+ 真相理解跨档记入事件流 --
	var clue_count := 0
	var talked_npcs: Array = []
	for evt in events:
		var etype := str(evt.get("type", ""))
		if etype == "clue":
			clue_count += 1
		elif etype == "talk":
			var owner := str(evt.get("owner", ""))
			if owner != HeavenMemoryStore.OWNER_HEAVEN and owner not in talked_npcs:
				talked_npcs.append(owner)
	if clue_count > 0:
		var truth_before := float(heaven.get("truth_proximity", 0.0))
		_shift("engagement", 0.03 * clue_count)
		_shift("truth_proximity", 0.06 * clue_count)
		if int(truth_before / 0.3) < int(float(heaven.get("truth_proximity", 0.0)) / 0.3):
			record_heaven_event("truth_tier_up", "玩家对循环真相的理解加深了一档")

	# -- NPC 好感日差分（相对当天早晨基线）+ 跨档记入事件流 --
	var total_delta := 0
	for npc_id in npc_affection:
		var start_val := int(_affection_day_start.get(npc_id, npc_affection[npc_id]))
		var now_val := int(npc_affection[npc_id])
		total_delta += now_val - start_val
		var tier_before := affection_tier_of(start_val)
		var tier_after := affection_tier_of(now_val)
		if tier_before != tier_after:
			var evt_type := "affection_tier_up" if now_val > start_val else "affection_tier_down"
			record_heaven_event(evt_type, "玩家与 %s 的关系从 %s 变为 %s" % [npc_id, tier_before, tier_after], [npc_id], npc_id)
	if total_delta > 0:
		_shift("benevolence", 0.02)
	elif total_delta < 0:
		_shift("benevolence", -0.02)
		_shift("engagement", 0.02)

	# -- 当天与 ≥2 个 NPC 对话 --
	if talked_npcs.size() >= 2:
		_shift("engagement", 0.02)


## 态度字段平移 + clamp 到定义域（benevolence [-1,1]，其余 [0,1]）。
func _shift(field: String, delta: float) -> void:
	var lo := -1.0 if field == "benevolence" else 0.0
	heaven[field] = clampf(float(heaven.get(field, 0.0)) + delta, lo, 1.0)


## 好感度档位（按数值判定；get_affection_tier 也走这里，阈值只此一处）。
func affection_tier_of(val: int) -> String:
	if val < 20: return "hostile"
	elif val < 40: return "cold"
	elif val < 60: return "neutral"
	elif val < 80: return "friendly"
	else: return "intimate"


## 设置时段并广播（时间推进由 TimeManager 调用）。
func set_time(time_id: String) -> void:
	current_time = time_id
	get_node("/root/EventBus").time_changed.emit(time_id)
	if time_id == "midnight":
		get_node("/root/EventBus").midnight_reached.emit()
