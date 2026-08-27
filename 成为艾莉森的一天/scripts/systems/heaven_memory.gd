class_name HeavenMemoryStore
extends RefCounted

## 天的记忆系统 —— 事实层与存储层（第一切片：纯程序地基，无 AI 参与）。
##
## 设计依据：《记忆系统_调研与构建方案》v0.1
##   - 第1层 事件流 events.jsonl（append-only，程序写入客观事实）
##   - 第2层 日结摘要 day_summaries.json（字段先留位，AI 在第二步行审面具接入后写入）
##   - 第3层 长期记忆：attitude_profile.json / relation_cards.json / foreshadows.json
##
## 契约：本模块只被 Godot 侧调用。AI 产出的文本（summary/impression 等）
## 一律走 apply_*_ai() 入口，经白名单校验后才落库——AI 不是状态写入者。
##
## 与既有 ai_memory.gd 的关系：
##   AIMemoryStore 管"NPC 和玩家聊了什么"（对话侧记忆）；
##   HeavenMemoryStore 管"世界发生了什么、天如何看待"（观测/博弈侧记忆）。两者并存互补。

const OWNER_HEAVEN := "heaven"   # 天全知可见的事件层；NPC 检索时仅能命中与其相关的子集

## 重要性打分规则表（Godot 计算，AI 不参与）。数值为 v0.1 初值，待测试校准。
const IMPORTANCE_RULES := {
	"obey": 7,               # 顺从预言
	"defy": 7,               # 反抗预言
	"clue": 8,               # 发现新线索
	"truth_tier_up": 9,      # 真相理解跨档
	"affection_tier_up": 6,  # NPC 好感跨档上升
	"affection_tier_down": 6,
	"foreshadow_touched": 8, # 玩家触及天埋下的伏笔
	"talk": 3,               # 普通对话
	"visit": 2,              # 普通访问
	"gift": 4,
}
const DEFAULT_IMPORTANCE := 2

## 检索评分常数（Generative Agents 简化版：重要性 + 近期性指数衰减 + 标签命中）
const W_IMPORTANCE := 2.0
const W_RECENCY := 10.0
const RECENCY_DECAY := 0.3    # score_recency = W_RECENCY * exp(-DECAY * 距今天数)
const W_TAG_HIT := 5.0

## AI 文本字段长度白名单（超长截断，防 prompt 膨胀）
const MAX_ATTITUDE_PROFILE_CHARS := 150
const MAX_IMPRESSION_CHARS := 80
const MAX_UNRESOLVED_CHARS := 80
const MAX_DAY_SUMMARY_CHARS := 400

## 存储目录（测试可覆盖为 user://memory_test）
static var _base_dir := "user://memory"
static var _events_cache: Array = []
static var _cache_loaded := false
static var _evt_counter := 0


# ============================================================
# 第 1 层：事件流
# ============================================================

## 记录一条事件。importance_override < 0 时按规则表打分。
## owner: "heaven"（天全知）或具体 npc_id（该 NPC 亲历的私密事件）。
## 返回写入的事件 Dictionary。
static func record_event(type: String, owner: String, tags: Array, fact: String,
		day: int, importance_override: int = -1) -> Dictionary:
	_ensure_events_loaded()
	_evt_counter += 1
	var importance := importance_override
	if importance < 0:
		importance = int(IMPORTANCE_RULES.get(type, DEFAULT_IMPORTANCE))
	var evt := {
		"id": "evt_%05d" % _evt_counter,
		"day": day,
		"owner": owner,
		"type": type,
		"tags": tags.duplicate(),
		"fact": fact,
		"importance": importance,
		"created_day": day,
		"last_recalled_day": 0,
	}
	_events_cache.append(evt)
	_append_jsonl(_events_path(), evt)
	return evt


## 全部事件（按写入顺序）。
static func all_events() -> Array:
	_ensure_events_loaded()
	return _events_cache.duplicate()


## 某天的事件。
static func events_for_day(day: int) -> Array:
	_ensure_events_loaded()
	var out: Array = []
	for evt in _events_cache:
		if int(evt.get("day", -1)) == day:
			out.append(evt)
	return out


## 事件检索评分。query_tags 命中数计入相关性。
static func score_event(evt: Dictionary, current_day: int, query_tags: Array) -> float:
	var s := float(evt.get("importance", DEFAULT_IMPORTANCE)) * W_IMPORTANCE
	var age: int = maxi(0, current_day - int(evt.get("day", current_day)))
	s += W_RECENCY * exp(-RECENCY_DECAY * float(age))
	var evt_tags: Array = evt.get("tags", [])
	var hits := 0
	for t in query_tags:
		if t in evt_tags:
			hits += 1
	s += W_TAG_HIT * float(hits)
	return s


## Top-K 检索。allowed_owners 限定可见 owner（记忆隔离的核心）。
## query_tags 用于相关性加分。返回按分数降序的事件数组。
static func top_events(current_day: int, query_tags: Array, allowed_owners: Array, k: int) -> Array:
	_ensure_events_loaded()
	var scored: Array = []
	for evt in _events_cache:
		if str(evt.get("owner", "")) not in allowed_owners:
			continue
		scored.append({"evt": evt, "score": score_event(evt, current_day, query_tags)})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array = []
	for i in range(min(k, scored.size())):
		var evt: Dictionary = scored[i]["evt"]
		evt["last_recalled_day"] = current_day
		out.append(evt)
	return out


# ============================================================
# 第 2 层：日结摘要（第二步由审判面具 AI 产出，本层只负责校验落库）
# ============================================================

## AI 产出的日结摘要落库。key_event_ids 必须存在于事件流，否则剔除（白名单校验）。
static func apply_day_summary_ai(day: int, summary: String, key_event_ids: Array, mood_shift: String) -> Dictionary:
	_ensure_events_loaded()
	var valid_ids: Array = []
	for eid in key_event_ids:
		if _find_event(str(eid)) != null:
			valid_ids.append(str(eid))
	var entry := {
		"day": day,
		"summary": summary.left(MAX_DAY_SUMMARY_CHARS),
		"key_events": valid_ids,
		"mood_shift": mood_shift,
	}
	var all := get_day_summaries()
	all = all.filter(func(e): return int(e.get("day", -1)) != day)   # 同一天覆盖写
	all.append(entry)
	_write_json(_day_summaries_path(), all)
	return entry


static func get_day_summaries() -> Array:
	var parsed: Variant = _read_json(_day_summaries_path(), [])
	return parsed if parsed is Array else []


static func recent_day_summaries(current_day: int, n: int) -> Array:
	var out: Array = []
	for e in get_day_summaries():
		if int(e.get("day", 0)) < current_day:
			out.append(e)
	out.sort_custom(func(a, b): return int(a["day"]) > int(b["day"]))
	return out.slice(0, n)


# ============================================================
# 第 3 层 a：天的态度画像（每晚由审判面具提议重写，校验字数后落库）
# ============================================================

static func apply_attitude_profile_ai(text: String, day: int) -> void:
	_write_json(_attitude_profile_path(), {
		"text": text.left(MAX_ATTITUDE_PROFILE_CHARS),
		"updated_day": day,
	})


static func get_attitude_profile() -> Dictionary:
	var parsed: Variant = _read_json(_attitude_profile_path(), {})
	return parsed if parsed is Dictionary else {}


# ============================================================
# 第 3 层 b：NPC 关系卡（程序字段 Godot 写；叙述字段 AI 提议、校验后落库）
# ============================================================

## 程序字段更新（好感度/见面次数等）。字段以 GameManager 为权威源，此处为记忆侧快照。
static func update_relation_card_stats(npc_id: String, affinity: int, met_count: int) -> void:
	var cards := _load_relation_cards()
	var card: Dictionary = cards.get(npc_id, {
		"npc_id": npc_id, "affinity": 0, "met_count": 0, "impression": "", "unresolved": "",
	})
	card["affinity"] = affinity
	card["met_count"] = met_count
	cards[npc_id] = card
	_write_json(_relation_cards_path(), cards)


## AI 叙述字段更新（impression/unresolved），长度白名单校验。
static func apply_relation_card_ai(npc_id: String, impression: String, unresolved: String) -> void:
	var cards := _load_relation_cards()
	var card: Dictionary = cards.get(npc_id, {
		"npc_id": npc_id, "affinity": 0, "met_count": 0, "impression": "", "unresolved": "",
	})
	card["impression"] = impression.left(MAX_IMPRESSION_CHARS)
	card["unresolved"] = unresolved.left(MAX_UNRESOLVED_CHARS)
	cards[npc_id] = card
	_write_json(_relation_cards_path(), cards)


static func get_relation_card(npc_id: String) -> Dictionary:
	return _load_relation_cards().get(npc_id, {})


# ============================================================
# 第 3 层 c：伏笔账本（天"说话算话"的根基）
# ============================================================

## 埋一条伏笔（第二步由天命面具 plant_foreshadow 字段触发，本函数为落库入口）。
static func plant_foreshadow(text: String, planted_day: int, due_in_days: int) -> Dictionary:
	var all := get_foreshadows()
	var fs := {
		"id": "fs_%03d" % (all.size() + 1),
		"planted_day": planted_day,
		"text": text,
		"status": "open",
		"due_by_day": planted_day + max(1, due_in_days),
		"resolved_day": 0,
	}
	all.append(fs)
	_write_json(_foreshadows_path(), all)
	return fs


## 标记应验（审判面具 resolve_foreshadow_ids 触发，校验 id 存在且 open）。
static func resolve_foreshadow(fs_id: String, day: int) -> bool:
	var all := get_foreshadows()
	for fs in all:
		if fs.get("id") == fs_id and fs.get("status") == "open":
			fs["status"] = "resolved"
			fs["resolved_day"] = day
			_write_json(_foreshadows_path(), all)
			return true
	return false


## 过期检查：超过 due_by_day 的 open 伏笔自动转 expired。返回新过期的伏笔（供审判面具提示"烂尾"）。
static func expire_foreshadows(current_day: int) -> Array:
	var all := get_foreshadows()
	var expired: Array = []
	var dirty := false
	for fs in all:
		if fs.get("status") == "open" and current_day > int(fs.get("due_by_day", 0)):
			fs["status"] = "expired"
			expired.append(fs)
			dirty = true
	if dirty:
		_write_json(_foreshadows_path(), all)
	return expired


static func get_foreshadows() -> Array:
	var parsed: Variant = _read_json(_foreshadows_path(), [])
	return parsed if parsed is Array else []


static func open_foreshadows() -> Array:
	var out: Array = []
	for fs in get_foreshadows():
		if fs.get("status") == "open":
			out.append(fs)
	return out


# ============================================================
# 持久化与内部工具
# ============================================================

## 测试用：切换存储目录并清空缓存。
static func set_storage_dir(dir: String) -> void:
	_base_dir = dir
	_events_cache = []
	_cache_loaded = false
	_evt_counter = 0


static func _events_path() -> String: return _base_dir + "/events.jsonl"
static func _day_summaries_path() -> String: return _base_dir + "/day_summaries.json"
static func _attitude_profile_path() -> String: return _base_dir + "/attitude_profile.json"
static func _relation_cards_path() -> String: return _base_dir + "/relation_cards.json"
static func _foreshadows_path() -> String: return _base_dir + "/foreshadows.json"


static func _find_event(evt_id: String) -> Variant:
	for evt in _events_cache:
		if evt.get("id") == evt_id:
			return evt
	return null


static func _load_relation_cards() -> Dictionary:
	var parsed: Variant = _read_json(_relation_cards_path(), {})
	return parsed if parsed is Dictionary else {}


static func _ensure_events_loaded() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	_events_cache = []
	if not FileAccess.file_exists(_events_path()):
		return
	var f := FileAccess.open(_events_path(), FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			_events_cache.append(parsed)
	f.close()
	# 恢复计数器，保证重启后 id 不重号
	for evt in _events_cache:
		var num := str(evt.get("id", "")).trim_prefix("evt_").to_int()
		_evt_counter = max(_evt_counter, num)


static func _append_jsonl(path: String, data: Dictionary) -> void:
	_ensure_dir()
	# 注意：FileAccess.READ_WRITE 不会创建不存在的文件（会返回 null），
	# 首次写入（events.jsonl 还不存在）必须用 WRITE 建文件，后续再追加。
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(JSON.stringify(data))
	f.close()


static func _read_json(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed != null else fallback


static func _write_json(path: String, data: Variant) -> void:
	_ensure_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_dir))
