class_name AIHeavenSession
extends RefCounted

## 天的天命/审判面具会话（记忆系统第二步：AI 接入）。
##
## 契约沿用「天=导演 / Godot=裁判」：
##   - AI 只产内容；数值、顺从判定、记忆落库全经 Godot 白名单校验
##   - oracle()：校验牌名∈22张 / directive∈枚举 / tone∈枚举；伏笔经 HeavenMemoryStore 落账
##   - judgment()：顺从判定由 GameManager.compute_compliance() 先算好（不交 AI 自评）；
##     memory_summary / attitude_profile_update / resolve_foreshadow_ids 经 HeavenMemoryStore 校验落库；
##     should_end_loop 仅在 current_day >= SOFT_END_DAY 才批准（硬上限 20 天的闸在 reset_loop 处，切片范围）
##   - AI 挂 / 超时 / 解析失败 → 回落路径，游戏照常可玩

const PLACES: Array = ["plaza", "treehouse_district", "stone_nest_tower"]   # 与 main.tscn 实际 area id 对齐
const NPCS: Array = ["soraya", "padwin", "cactus_bishop"]
const TONES: Array = ["gentle", "curious", "watching", "testing", "cold"]
const SOFT_END_DAY := 12
const REQUEST_TIMEOUT := 30.0
const JUDGMENT_FALLBACK := "午夜已至，石巢塔楼的方向传来钟声。今天的一切已被记下。"

const TAROT_PATH := "res://resources/tarot/major_arcana.json"
const SYSTEM_PROMPT_PATH := "res://ai/tian_system.txt"
const ORACLE_SCHEMA_PATH := "res://ai/oracle_schema.json"
const JUDGMENT_SCHEMA_PATH := "res://ai/judgment_schema.json"

const ORACLE_REQUIRED: Array = ["card_name", "prophecy", "tone", "internal_note"]
const JUDGMENT_REQUIRED: Array = ["day_summary", "tomorrow_seed", "should_end_loop", "internal_note"]

var _host: Node = null


## host 用于访问 autoload（RefCounted 无 get_tree）。测试可传入任意树内 Node。
func setup(host: Node) -> void:
	_host = host


# ============================================================
# 天命面具（早晨 · 出牌）
# ============================================================

## 返回 {ok, fell_back, card_name, prophecy, directive, tone, internal_note, foreshadow?}
## 副作用：写入 GameManager.heaven["daily_prophecy"]；plant_foreshadow 落伏笔账本。
func oracle() -> Dictionary:
	var gm := _autoload("GameManager")
	var bridge := _autoload("AIBridge")
	if gm == null or bridge == null:
		return _fallback_oracle(gm)
	var day := int(gm.current_day)
	var payload := _build_oracle_payload(gm, day)
	print("[AIHeavenSession] 天命面具请求 AI（第 %d 天）…" % day)
	var raw: String = await bridge.request_llm_with_guard(payload, REQUEST_TIMEOUT)
	if raw.begins_with("[API_ERROR]") or raw.begins_with("[BUSY]") or raw.begins_with("[DISABLED]"):
		print("[AIHeavenSession] oracle 失败回落：%s" % raw.left(60))
		return _fallback_oracle(gm)
	var r: Dictionary = AIJsonUtils.parse_response(raw, ORACLE_REQUIRED)
	if not bool(r.get("success", false)):
		print("[AIHeavenSession] oracle JSON 解析失败：%s" % str(r.get("error", "")))
		return _fallback_oracle(gm)
	var result := _validate_oracle(r.get("data", {}), day)
	_store_prophecy(gm, result)
	return result


func _build_oracle_payload(gm: Node, day: int) -> Dictionary:
	var heaven: Dictionary = gm.heaven
	var user := "【天命面具 —— 晨间出牌】\n\n"
	user += "第 %d 天。你的状态：善意 %.2f / 兴趣 %.2f / 玩家真相理解 %.2f / 累计反抗 %d 次。\n\n" % [
		day, float(heaven.get("benevolence", 0.0)), float(heaven.get("engagement", 0.3)),
		float(heaven.get("truth_proximity", 0.0)), int(heaven.get("prophecy_resistance", 0)),
	]
	var seed := str(heaven.get("tomorrow_seed", ""))
	if not seed.is_empty():
		user += "你昨夜埋下的明日种子：%s\n\n" % seed

	# 昨日顺从在 reset_loop 时已归档到 last_compliance（daily_* 是当天的，勿混用）
	var last_compliance := str(heaven.get("last_compliance", ""))
	var memory_block := MemoryQuery.assemble(MemoryQuery.MASK_ORACLE, {
		"current_day": day,
		"last_compliance": last_compliance,
	})
	if not memory_block.is_empty():
		user += "你的记忆：\n%s\n\n" % memory_block

	user += "可用枚举：\n地点：%s\nNPC：%s\n22 张大阿尔卡那：%s\n\n" % [
		", ".join(PLACES), ", ".join(NPCS), ", ".join(_load_card_names()),
	]
	user += "任务：\n"
	user += "- 选一张牌（card_name 必须与清单完全一致）\n"
	user += "- 写 2-4 句预言诗：模糊、留白、可多种应验、可被违背\n"
	user += "- 可选：设 directive（玩家看不到，仅用于判定顺从/反抗）；今日不想设局就给 null\n"
	user += "- 可选：plant_foreshadow 埋一条你真打算应验的伏笔；不埋给 null\n"
	user += "- tone 与 internal_note 必填\n"
	user += "\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
	user += "```json\n%s\n```\n" % _read_file(ORACLE_SCHEMA_PATH)
	user += "请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"
	return {"system": _read_file(SYSTEM_PROMPT_PATH), "user": user}


func _validate_oracle(parsed: Dictionary, day: int) -> Dictionary:
	var card_names := _load_card_names()
	var card_name := str(parsed.get("card_name", ""))
	if card_name not in card_names and card_names.size() > 0:
		# 牌名不在 22 张内：用随机数据牌牌名兜底，预言仍用 AI 文本
		card_name = str(card_names[randi() % card_names.size()])

	# directive 枚举校验：不合法则丢弃（当天不设局），其余字段保留
	var directive: Variant = null
	var raw_directive: Variant = parsed.get("directive")
	if raw_directive is Dictionary:
		var dtype := str(raw_directive.get("type", ""))
		var target := str(raw_directive.get("target", ""))
		if (dtype == "visit" and target in PLACES) or (dtype == "talk" and target in NPCS):
			directive = {"type": dtype, "target": target}

	var tone := str(parsed.get("tone", ""))
	if tone not in TONES:
		tone = "watching"

	var result := {
		"ok": true,
		"fell_back": false,
		"card_name": card_name,
		"prophecy": str(parsed.get("prophecy", "")),
		"directive": directive,
		"tone": tone,
		"internal_note": str(parsed.get("internal_note", "")),
	}

	# 伏笔落账（白名单：文本非空 + due_in_days >= 1）
	var raw_fs: Variant = parsed.get("plant_foreshadow")
	if raw_fs is Dictionary:
		var fs_text := str(raw_fs.get("text", "")).strip_edges()
		var due := int(raw_fs.get("due_in_days", 0))
		if not fs_text.is_empty() and due >= 1:
			result["foreshadow"] = HeavenMemoryStore.plant_foreshadow(fs_text, day, due)
	return result


func _fallback_oracle(gm: Node) -> Dictionary:
	var cards := _load_cards()
	var card: Dictionary = {"name": "？？？", "reading": "牌面被雾遮住了。"}
	if cards.size() > 0:
		card = cards[randi() % cards.size()]
	var result := {
		"ok": false,
		"fell_back": true,
		"card_name": str(card.get("name", "？？？")),
		"prophecy": str(card.get("reading", "")),
		"directive": null,
		"tone": "watching",
		"internal_note": "",
	}
	_store_prophecy(gm, result)
	return result


func _store_prophecy(gm: Node, result: Dictionary) -> void:
	if gm == null:
		return
	gm.heaven["daily_prophecy"] = {
		"card_name": result.get("card_name", ""),
		"prophecy": result.get("prophecy", ""),
		"directive": result.get("directive"),
		"tone": result.get("tone", "watching"),
		"internal_note": result.get("internal_note", ""),
	}


# ============================================================
# 审判面具（午夜 · 复盘）
# ============================================================

## 返回 {ok, fell_back, day_summary, tomorrow_seed, should_end_proposed, should_end_approved, compliance}
## 副作用：日结摘要/态度画像/伏笔应验落库；写 heaven["daily_compliance"/"tomorrow_seed"/"last_judgment"]。
func judgment() -> Dictionary:
	var gm := _autoload("GameManager")
	var bridge := _autoload("AIBridge")
	if gm == null:
		return {"ok": false, "fell_back": true, "day_summary": JUDGMENT_FALLBACK,
			"tomorrow_seed": "", "should_end_proposed": false, "should_end_approved": false, "compliance": ""}
	var day := int(gm.current_day)
	# Godot 裁判先算顺从/反抗（事实判定，不交 AI 自评）
	var compliance: String = gm.compute_compliance()
	gm.heaven["daily_compliance"] = compliance

	if bridge == null:
		return _fallback_judgment(gm, compliance)
	var payload := _build_judgment_payload(gm, day, compliance)
	print("[AIHeavenSession] 审判面具请求 AI（第 %d 天）…" % day)
	var raw: String = await bridge.request_llm_with_guard(payload, REQUEST_TIMEOUT)
	if raw.begins_with("[API_ERROR]") or raw.begins_with("[BUSY]") or raw.begins_with("[DISABLED]"):
		print("[AIHeavenSession] judgment 失败回落：%s" % raw.left(60))
		return _fallback_judgment(gm, compliance)
	var r: Dictionary = AIJsonUtils.parse_response(raw, JUDGMENT_REQUIRED)
	if not bool(r.get("success", false)):
		print("[AIHeavenSession] judgment JSON 解析失败：%s" % str(r.get("error", "")))
		return _fallback_judgment(gm, compliance)
	return _apply_judgment(gm, r.get("data", {}), day, compliance)


func _build_judgment_payload(gm: Node, day: int, compliance: String) -> Dictionary:
	var heaven: Dictionary = gm.heaven
	var user := "【审判面具 —— 午夜复盘】\n\n"
	user += "第 %d 天。你的状态：善意 %.2f / 兴趣 %.2f / 玩家真相理解 %.2f / 累计反抗 %d 次。\n\n" % [
		day, float(heaven.get("benevolence", 0.0)), float(heaven.get("engagement", 0.3)),
		float(heaven.get("truth_proximity", 0.0)), int(heaven.get("prophecy_resistance", 0)),
	]
	var prophecy: Variant = heaven.get("daily_prophecy")
	if prophecy is Dictionary:
		user += "你今日的预言：%s（牌：%s）\n\n" % [
			str(prophecy.get("prophecy", "")), str(prophecy.get("card_name", "")),
		]
	else:
		user += "今日你未设局。\n\n"

	var memory_block := MemoryQuery.assemble(MemoryQuery.MASK_JUDGMENT, {
		"current_day": day,
		"compliance": compliance,
	})
	if not memory_block.is_empty():
		user += "%s\n\n" % memory_block

	user += "任务：\n"
	user += "- day_summary：写给玩家的回顾叙事（200-400 字），你态度的稳定窗口\n"
	user += "- tomorrow_seed：明日走向种子（1-2 句），明早的你会收到它\n"
	user += "- memory_summary：压缩后的今日记忆（≤150 字），给未来的你看\n"
	user += "- key_event_ids：从上面今日事件清单挑关键 id（只能选清单中存在的）\n"
	user += "- attitude_profile_update：若玩家表现让你态度有实质变化，重写画像（≤150 字）；否则 null\n"
	user += "- resolve_foreshadow_ids：今日应验的伏笔 id（只能选 open 清单中的）\n"
	user += "- should_end_loop：仅当你真觉得该终结时 true（第 %d 天前 Godot 不会批准）\n" % SOFT_END_DAY
	user += "\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
	user += "```json\n%s\n```\n" % _read_file(JUDGMENT_SCHEMA_PATH)
	user += "请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"
	return {"system": _read_file(SYSTEM_PROMPT_PATH), "user": user}


func _apply_judgment(gm: Node, parsed: Dictionary, day: int, compliance: String) -> Dictionary:
	# 日结摘要落库（key_event_ids 白名单校验在 apply_day_summary_ai 内）
	var memory_summary := str(parsed.get("memory_summary", "")).strip_edges()
	if memory_summary.is_empty():
		memory_summary = str(parsed.get("day_summary", ""))
	var key_ids: Array = []
	if parsed.get("key_event_ids") is Array:
		key_ids = parsed.get("key_event_ids")
	HeavenMemoryStore.apply_day_summary_ai(day, memory_summary, key_ids, str(parsed.get("mood_shift", "")))

	# 态度画像重写（null/空 = 态度不变）
	var profile_update: Variant = parsed.get("attitude_profile_update")
	if profile_update is String and not str(profile_update).strip_edges().is_empty():
		HeavenMemoryStore.apply_attitude_profile_ai(str(profile_update).strip_edges(), day)

	# 伏笔应验（id 校验在 resolve_foreshadow 内：非 open 直接拒绝）
	if parsed.get("resolve_foreshadow_ids") is Array:
		for fid in parsed.get("resolve_foreshadow_ids"):
			HeavenMemoryStore.resolve_foreshadow(str(fid), day)

	var tomorrow_seed := str(parsed.get("tomorrow_seed", ""))
	gm.heaven["tomorrow_seed"] = tomorrow_seed

	# 终结提议：Godot 只在软限窗口批准，永不越权
	var proposed := bool(parsed.get("should_end_loop", false))
	var approved := proposed and day >= SOFT_END_DAY

	gm.heaven["last_judgment"] = {
		"day_summary": str(parsed.get("day_summary", "")),
		"tomorrow_seed": tomorrow_seed,
		"internal_note": str(parsed.get("internal_note", "")),
	}
	return {
		"ok": true,
		"fell_back": false,
		"day_summary": str(parsed.get("day_summary", "")),
		"tomorrow_seed": tomorrow_seed,
		"should_end_proposed": proposed,
		"should_end_approved": approved,
		"compliance": compliance,
	}


func _fallback_judgment(gm: Node, compliance: String) -> Dictionary:
	if gm != null:
		gm.heaven["tomorrow_seed"] = ""
		gm.heaven["last_judgment"] = {"day_summary": JUDGMENT_FALLBACK, "tomorrow_seed": "", "internal_note": ""}
	return {
		"ok": false,
		"fell_back": true,
		"day_summary": JUDGMENT_FALLBACK,
		"tomorrow_seed": "",
		"should_end_proposed": false,
		"should_end_approved": false,
		"compliance": compliance,
	}


# ============================================================
# 工具
# ============================================================

func _autoload(autoload_name: String) -> Node:
	if _host == null:
		return null
	return _host.get_node_or_null("/root/%s" % autoload_name)


func _load_cards() -> Array:
	var text := _read_file(TAROT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var cards: Variant = parsed.get("cards", [])
		if cards is Array:
			return cards
	return []


func _load_card_names() -> Array:
	var names: Array = []
	for card in _load_cards():
		if card is Dictionary:
			names.append(str(card.get("name", "")))
	return names


func _read_file(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	return ""
