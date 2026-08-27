class_name MemoryQuery
extends RefCounted

## 记忆检索器 —— 把 HeavenMemoryStore 的三层记忆组装成各面具 prompt 的注入块。
##
## 设计依据：《记忆系统_调研与构建方案》§2.4。
## 不用向量库：20 天一局的数据量，"重要性 + 近期性衰减 + 标签命中"足够。
##
## 各面具的注入策略与隔离规则：
##   天命面具(oracle)  : 天的态度画像 + 近3天日结 + Top5事件(owner=heaven) + open伏笔×3 + 昨日顺从
##   审判面具(judgment): 今日全部事件 + 今日compliance + 态度画像 + open伏笔/烂尾提醒
##   化身面具(npc)     : 该NPC关系卡 + Top5事件(owner∈[npc, heaven]且heaven事件须含该npc标签)

const MASK_ORACLE := "oracle"
const MASK_JUDGMENT := "judgment"
const MASK_NPC := "npc"

const TOP_K_EVENTS := 5
const MAX_OPEN_FORESHADOWS := 3
const RECENT_SUMMARY_DAYS := 3

const HeavenMemory := preload("res://scripts/systems/heaven_memory.gd")


## 组装记忆注入块。context 字段按面具而异：
##   通用：current_day:int
##   oracle：last_compliance:String（"obey"/"defy"/"neutral"/""）
##   judgment：compliance:String
##   npc：npc_id:String、directive:Dictionary（可空）
## 返回可直接拼进 prompt 的中文文本块；无记忆时返回空串。
static func assemble(mask: String, context: Dictionary) -> String:
	var current_day := int(context.get("current_day", 1))
	match mask:
		MASK_ORACLE:
			return _assemble_oracle(current_day, str(context.get("last_compliance", "")))
		MASK_JUDGMENT:
			return _assemble_judgment(current_day, str(context.get("compliance", "")))
		MASK_NPC:
			return _assemble_npc(current_day, str(context.get("npc_id", "")))
	return ""


# ============================================================
# 天命面具
# ============================================================

static func _assemble_oracle(current_day: int, last_compliance: String) -> String:
	var lines: PackedStringArray = []
	var profile: Dictionary = HeavenMemory.get_attitude_profile()
	if not str(profile.get("text", "")).is_empty():
		lines.append("你对玩家的态度：%s" % profile["text"])

	if not last_compliance.is_empty():
		var label: String = {"obey": "顺从", "defy": "反抗", "neutral": "未理会"}.get(last_compliance, last_compliance)
		lines.append("昨日玩家%s了你的预言。" % label)

	var summaries := HeavenMemory.recent_day_summaries(current_day, RECENT_SUMMARY_DAYS)
	if summaries.size() > 0:
		lines.append("近日回顾：")
		for s in summaries:
			lines.append("  第%d天：%s" % [int(s.get("day", 0)), str(s.get("summary", ""))])

	var events := HeavenMemory.top_events(current_day, [], [HeavenMemoryStore.OWNER_HEAVEN], TOP_K_EVENTS)
	if events.size() > 0:
		lines.append("你记得的事：")
		for evt in events:
			lines.append("  第%d天：%s" % [int(evt.get("day", 0)), str(evt.get("fact", ""))])

	var foreshadows := HeavenMemory.open_foreshadows().slice(0, MAX_OPEN_FORESHADOWS)
	if foreshadows.size() > 0:
		lines.append("你埋下且未应验的伏笔：")
		for fs in foreshadows:
			lines.append("  （第%d天埋，限第%d天前）%s" % [int(fs["planted_day"]), int(fs["due_by_day"]), str(fs["text"])])

	return "\n".join(lines)


# ============================================================
# 审判面具
# ============================================================

static func _assemble_judgment(current_day: int, compliance: String) -> String:
	var lines: PackedStringArray = []
	var today := HeavenMemory.events_for_day(current_day)
	if today.size() > 0:
		lines.append("今日发生（[id] 供 key_event_ids 挑选）：")
		for evt in today:
			lines.append("  [%s] %s" % [str(evt.get("id", "")), str(evt.get("fact", ""))])
	else:
		lines.append("今日无有效观测。")

	if not compliance.is_empty():
		var label: String = {"obey": "顺从", "defy": "反抗", "neutral": "未理会"}.get(compliance, compliance)
		lines.append("今日玩家对预言：%s。" % label)

	var profile: Dictionary = HeavenMemory.get_attitude_profile()
	if not str(profile.get("text", "")).is_empty():
		lines.append("你此前对玩家的态度：%s" % profile["text"])

	var open_fs := HeavenMemory.open_foreshadows()
	if open_fs.size() > 0:
		lines.append("尚未应验的伏笔（(id) 供 resolve_foreshadow_ids 挑选）：%s" % "；".join(
			open_fs.map(func(fs): return "(%s) %s" % [str(fs.get("id", "")), str(fs.get("text", ""))])))
	var expired := HeavenMemory.expire_foreshadows(current_day)
	if expired.size() > 0:
		lines.append("⚠ 你有 %d 条伏笔烂尾了，今夜须圆场或放弃。" % expired.size())

	return "\n".join(lines)


# ============================================================
# 化身面具（NPC 对话）—— 严格 owner 隔离
# ============================================================

static func _assemble_npc(current_day: int, npc_id: String) -> String:
	if npc_id.is_empty():
		return ""
	var lines: PackedStringArray = []

	var card := HeavenMemory.get_relation_card(npc_id)
	if not card.is_empty():
		var parts: PackedStringArray = []
		parts.append("你见过他 %d 次" % int(card.get("met_count", 0)))
		if not str(card.get("impression", "")).is_empty():
			parts.append("你对他的印象：%s" % card["impression"])
		if not str(card.get("unresolved", "")).is_empty():
			parts.append("未了之事：%s" % card["unresolved"])
		lines.append("你与玩家的过往：%s。" % "；".join(parts))

	# 隔离规则：本人的私密事件 + 天层事件中与本人相关的子集（tags 含 npc_id）
	var mine := HeavenMemory.top_events(current_day, [npc_id], [npc_id], TOP_K_EVENTS)
	var shared := HeavenMemory.top_events(current_day, [npc_id], [HeavenMemoryStore.OWNER_HEAVEN], TOP_K_EVENTS) \
		.filter(func(evt): return npc_id in evt.get("tags", []))
	var merged := mine + shared
	merged.sort_custom(func(a, b): return int(a.get("day", 0)) > int(b.get("day", 0)))
	if merged.size() > 0:
		lines.append("你记得：")
		for evt in merged.slice(0, TOP_K_EVENTS):
			lines.append("  第%d天：%s" % [int(evt.get("day", 0)), str(evt.get("fact", ""))])

	return "\n".join(lines)
