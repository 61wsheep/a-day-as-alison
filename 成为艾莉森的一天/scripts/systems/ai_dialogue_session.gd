class_name AIDialogueSession
extends RefCounted

## AI 对话会话 —— S1（每日 AI 会话）与 S2（JSON 对话里的自由输入旁路）共用。
##
## 状态契约：AI 只输出"表现"，一切数值/线索/flag 变更经 Godot 校验。
##   - emotional_shift → 校验 clampi(-10,15) → 负向×0.8 → GameManager.change_affection()
##   - hints_to_other_npcs → AIHintWhitelist → GameManager.discover_clue()
##   - AI 永远不能直接改 flags
##
## 信号（给 npc_base 转发到 EventBus）：
##   thinking_changed(active)  line_ready(speaker, text, emotion)
##   choices_ready(topics)     sideline_done()          session_finished()

signal thinking_changed(active: bool)
signal line_ready(speaker: String, text: String, emotion: String)
signal choices_ready(topics: Array)
signal sideline_done()
signal session_finished()   # 自然判停（AI 决定结束）→ npc_base 显示告别提示后退出
signal session_aborted()    # 失败/异常中断 → 立即退出，不显示告别

const MAX_TURNS := 8            # 单次会话轮数上限（对齐 Python MAX_TURNS，收敛到游戏内）
const MIN_TURNS := 2            # 前 N 轮 AI 不能主动结束
const MEMORY_WINDOW := 5        # 保留最近 N 轮上下文（提速：输入小一点 → prefill 快；长程靠 memory_update）
const DIALOGUE_MAX_TOKENS := 512   # 提速：单轮输出上限（防啰嗦失控；截断会整轮回落，故留足余量，靠提示词压短而非硬砍）
const TOPIC_COUNT := 3

var _npc_base: Node = null
var _npc_id := ""
var _turn := 0
var _in_flight := false
var _sideline := false           # true = S2 旁路（JSON 对话里一次自由输入）
var _ended := false

var _memory_updates: Array = []
var _total_turns := 0
var _history: Array = []         # [{player, npc, emotional_shift, internal_note, memory_update}]

const _REQUIRED_FIELDS := ["response_text", "emotional_shift", "memory_update"]
const _SYSTEM_PROMPT_PATH := "res://ai/tian_system.txt"
const _SCHEMA_PATH := "res://ai/dialogue_schema.json"


func setup(npc_base: Node, npc_id: String) -> void:
	_npc_base = npc_base
	_npc_id = npc_id
	var mem := AIMemoryStore.load(npc_id)
	_memory_updates = mem.get("memory_updates", [])
	_total_turns = int(mem.get("total_turns", 0))
	# 把上次对话最后几轮带进上下文
	var recent: Array = mem.get("recent_history", [])
	for h in recent:
		if h is Dictionary:
			_history.append({
				"player": str(h.get("player", "")),
				"npc": str(h.get("npc", "")),
			})


## S1 入口：整段 AI 会话。
func begin() -> void:
	_turn = 1   # 开场即第 1 轮
	_record_talk_event()
	_build_and_request(true)


## S2 入口：JSON 对话里的一次自由输入旁路。
func free_input_turn(text: String) -> void:
	_sideline = true
	_record_talk_event()
	_submit(text)


## talk 事件打点（切片设计：顺从判定与 NPC 记忆的事实来源）。
## owner = 该 NPC（私密记忆：别的 NPC 检索不到这次对话内容）。
func _record_talk_event() -> void:
	var gm := _autoload("GameManager")
	if gm and gm.has_method("record_heaven_event"):
		gm.record_heaven_event("talk", "玩家与 %s 交谈" % _npc_id,
			[_npc_id, str(gm.current_area)], _npc_id)


## 玩家点击话题建议按钮。
func submit_topic(choice_index: int) -> void:
	if _in_flight or _ended:
		return
	var topics := _last_topics
	if choice_index < 0 or choice_index >= topics.size():
		return
	_submit(str(topics[choice_index]))


## 玩家提交自由输入文本（S1 会话内）。
func submit_free_text(text: String) -> void:
	if _in_flight or _ended:
		return
	_submit(text)


## 结束会话：保存记忆 + 清理在途请求。
func end_session() -> void:
	_ended = true
	if _in_flight:
		var bridge := _autoload("AIBridge")
		if bridge:
			bridge.cancel_current()
	_flush_memory()
	_history.clear()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

var _last_topics: Array = []


## RefCounted 无 get_tree，借传入的 NPC 节点引用访问 autoload。
func _autoload(name: String) -> Node:
	if _npc_base == null:
		return null
	return _npc_base.get_node_or_null("/root/%s" % name)


func _submit(player_input: String) -> void:
	if _ended or _in_flight:
		return
	_turn += 1
	_last_player_input = player_input
	_build_and_request(false, player_input)


func _build_and_request(is_opening: bool, player_input: String = "") -> void:
	var payload := _build_payload(is_opening, player_input)
	thinking_changed.emit(true)
	_in_flight = true
	var bridge := _autoload("AIBridge")
	var raw := ""
	if bridge:
		print("[AIDialogueSession] 请求 AI（%s 第 %d 轮）…" % [_npc_id, _turn])
		raw = await bridge.request_llm_with_guard(payload, 30.0)
	_in_flight = false
	thinking_changed.emit(false)
	if _ended:
		return   # 会话已被玩家结束（Esc 退出），丢弃迟到的结果

	if raw.begins_with("[API_ERROR]") or raw.begins_with("[BUSY]") or raw.begins_with("[DISABLED]"):
		_handle_failure(raw)
		return
	_handle_response(raw)


func _build_payload(is_opening: bool, player_input: String) -> Dictionary:
	var gm := _autoload("GameManager")
	var day := 1
	var affection := 50
	var today_reading := ""
	var time_id := ""
	var known_clues: Array = []
	if gm:
		day = int(gm.current_day)
		affection = int(gm.npc_affection.get(_npc_id, 50))
		today_reading = str(gm.daily_tarot_card)
		time_id = str(gm.current_time)
		known_clues = gm.clues_found

	var system_text := _read_file(_SYSTEM_PROMPT_PATH)
	var card_path := "res://ai/npc_%s.txt" % _npc_id
	var card_text := _read_file(card_path)
	var schema_text := _read_file(_SCHEMA_PATH)

	# ---- 门控挡刀：玩家已知线索注入（AI 只在这个信息范围内说话）----
	var clue_names: Array = []
	if gm and gm.CLUE_NAMES is Dictionary:
		for cid in known_clues:
			clue_names.append("%s" % gm.CLUE_NAMES.get(cid, cid))

	# ---- 跨天记忆 ----
	var cross_day := "（尚无跨天记忆 —— 今天是你们第一次见面）"
	if not _memory_updates.is_empty():
		var lines: Array = []
		var tail: Array = _memory_updates.slice(max(0, _memory_updates.size() - 5))
		for m in tail:
			lines.append("- %s" % m)
		cross_day = "\n".join(lines)

	# ---- 本轮历史 ----
	var history_block := "（第一次对话）"
	if not _history.is_empty():
		var recent := _history.slice(max(0, _history.size() - MEMORY_WINDOW))
		var lines: Array = []
		for h in recent:
			lines.append("玩家: %s\n%s: %s" % [h.get("player", ""), _npc_id, h.get("npc", "")])
		history_block = "\n".join(lines)

	# ---- 组装 user 消息 ----
	var user := ""
	if is_opening:
		user += "【化身面具 —— 正在扮演 %s】\n\n" % _npc_id
		user += "第 %d 天。%s。%s 对玩家的好感度: %d/100。\n\n" % [day, time_id, _npc_id, affection]
		user += "今日塔罗: %s\n\n" % (today_reading if today_reading != "" else "（今日未抽牌）")
		user += "玩家已知线索: %s\n\n" % (", ".join(clue_names) if not clue_names.is_empty() else "（尚未获得线索）")
		user += "跨天记忆（之前几天的对话摘要 —— NPC 可能隐隐约约有印象，但不一定主动提起）:\n%s\n\n" % cross_day
		user += _heaven_injection(gm, day)
		user += "这是 %s 今天与艾莉森的第一次见面。请以他的身份开口问候，并以玩家艾莉森的第一人称口吻给出 3 条她可能接的话（topic_suggestions——是玩家视角的回复选项，不是你自己的话）。问候语 1-2 句即可，简短自然，别长篇自我介绍。\n\n" % _npc_id
	else:
		user += "第 %d 天 %s。%s 对玩家的好感度: %d/100。\n\n" % [day, time_id, _npc_id, affection]
		user += "跨天记忆:\n%s\n\n" % cross_day
		user += "本轮对话历史:\n%s\n\n" % history_block
		user += "玩家刚才说: [%s]\n\n" % player_input
		user += "以 %s 的身份回应（JSON）。记住:\n" % _npc_id
		user += "- 你是 %s —— 用你的性格、经历、语气说话，你不是 AI 助手\n" % _npc_id
		user += "- 无论玩家用什么风格输入，你都要保持 %s 自己的口吻和动作尺度，不要模仿玩家的文风\n" % _npc_id
		user += "- 这是今天第 %d 轮对话，如果感觉对话该结束了，设 should_end_conversation=true\n" % _turn
		user += "- 回复要精炼：response_text 一般 1-2 句、别超 3 句；topic_suggestions 每条 6-12 个字即可\n"
		if not is_opening:
			user += "- 请同时以玩家艾莉森的第一人称口吻给出 3 条她下一步可能说的话（topic_suggestions——玩家视角的回复选项，让对话能继续下去）\n"

	# ---- schema 注入（非 Claude 路径，与 Python call_llm_structured 一致）----
	user += "\n\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
	user += "```json\n%s\n```\n" % schema_text
	user += "请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"

	return {
		"system": "%s\n\n%s" % [system_text, card_text],
		"user": user,
		"max_tokens": DIALOGUE_MAX_TOKENS,   # 对话单轮独立限幅（提速，不拖累天命/审判面具的长输出）
	}


func _handle_response(raw: String) -> void:
	var r := AIJsonUtils.parse_response(raw, _REQUIRED_FIELDS)
	if not r.get("success", false):
		_handle_failure("JSON 解析失败: %s" % r.get("error", ""))
		return
	var parsed: Dictionary = r.get("data", {})
	_apply_turn(parsed)
	if _sideline:
		sideline_done.emit()
		_ended = true
		_flush_memory()
		return
	# S1：显示回复（+ 未结束才给话题按钮）。
	var text := str(parsed.get("response_text", ""))
	var emo := str(parsed.get("emotion", ""))
	line_ready.emit(_npc_id, text, emo)
	# 结束判定（先算：判停/到轮数上限的那一轮不再弹话题与输入框——否则 AI 最后
	# 一句刚显示就被盖在选项面板下，且那些按钮点了也无效，观感"最后一句话没显示"）
	var should_end := bool(parsed.get("should_end_conversation", false))
	if should_end and _turn <= MIN_TURNS:
		should_end = false
	if should_end or _turn >= MAX_TURNS:
		_ended = true   # 先置位：收尾停留期间忽略玩家后续提交
		session_finished.emit()
		return
	_last_topics = parsed.get("topic_suggestions", []) if parsed.get("topic_suggestions") is Array else []
	choices_ready.emit(_last_topics)


func _apply_turn(parsed: Dictionary) -> void:
	var gm := _autoload("GameManager")
	var text := str(parsed.get("response_text", ""))
	var shift := int(parsed.get("emotional_shift", 0))
	shift = clampi(shift, -10, 15)
	if shift < 0:
		shift = int(round(shift * 0.8))
	if gm:
		gm.change_affection(_npc_id, shift)
	# 线索白名单
	var hints: Array = parsed.get("hints_to_other_npcs", []) if parsed.get("hints_to_other_npcs") is Array else []
	for h in hints:
		var cid := AIHintWhitelist.resolve(str(h))
		if cid != "" and gm:
			gm.discover_clue(cid)
	# 记忆
	var mu := str(parsed.get("memory_update", ""))
	if mu != "":
		_memory_updates.append(mu)
	# 历史（S2 旁路也记，便于上下文连续）
	var internal_note := str(parsed.get("internal_note", ""))
	_history.append({
		"player": _last_player_input,
		"npc": text,
		"emotional_shift": shift,
		"internal_note": internal_note,
		"memory_update": mu,
	})


func _handle_failure(reason: String) -> void:
	print("[AIDialogueSession] %s" % reason)
	_toast("AI 暂时无法回复，已切回固定对话")
	if _sideline:
		sideline_done.emit()
		_ended = true
		_flush_memory()
	else:
		_ended = true
		session_aborted.emit()  # npc_base 收到后回落该入口 JSON lines（不显示告别）


## 游戏内提示（借 NPC 节点拿 EventBus，避免重复 get_node("/root/EventBus")）。
func _toast(message: String) -> void:
	if _npc_base == null:
		return
	var bus: Node = _npc_base.get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("toast"):
		bus.emit_signal("toast", message)


func _flush_memory() -> void:
	var gm := _autoload("GameManager")
	var affection := 0
	var day := 0
	if gm:
		affection = int(gm.npc_affection.get(_npc_id, 0))
		day = int(gm.current_day)
	var recent: Array = []
	for h in _history.slice(max(0, _history.size() - 3)):
		recent.append({"player": h.get("player", ""), "npc": h.get("npc", "")})
	_total_turns += _history.size()
	AIMemoryStore.save(_npc_id, _memory_updates, _total_turns, recent, affection, day)
	# 关系卡程序字段同步（好感度/见面次数快照；叙述字段由审判面具 AI 侧更新）
	if gm:
		var prev_card: Dictionary = HeavenMemoryStore.get_relation_card(_npc_id)
		HeavenMemoryStore.update_relation_card_stats(_npc_id, affection,
			int(prev_card.get("met_count", 0)) + 1)


var _last_player_input := ""


func _read_file(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	return ""


## 天的注视注入（切片设计 §6.2）：昨日顺从 + 今日基调 + 明日种子 + 该 NPC 的关系卡与记忆。
## 这是"被注视的回应感"在白天的主体通道。无可用信息时返回空串。
func _heaven_injection(gm: Node, day: int) -> String:
	if gm == null:
		return ""
	var heaven: Dictionary = gm.heaven
	var parts: Array = []

	var compliance := str(heaven.get("last_compliance", ""))
	if not compliance.is_empty():
		var label := str({"obey": "顺从", "defy": "反抗", "neutral": "未理会"}.get(compliance, compliance))
		parts.append("昨天：玩家%s了天的预言" % label)

	var prophecy: Variant = heaven.get("daily_prophecy")
	if prophecy is Dictionary:
		var tone := str(prophecy.get("tone", ""))
		if not tone.is_empty():
			parts.append("天今日基调：%s" % tone)

	var seed := str(heaven.get("tomorrow_seed", ""))
	if not seed.is_empty():
		parts.append("近日伏笔：%s" % seed)

	# 该 NPC 的关系卡 + 记忆检索（owner 隔离：看不到别的 NPC 的私密事件）
	var mem_block := MemoryQuery.assemble(MemoryQuery.MASK_NPC, {
		"current_day": day,
		"npc_id": _npc_id,
	})
	if not mem_block.is_empty():
		parts.append(mem_block)

	if parts.is_empty():
		return ""
	return "天的注视（自然流露，不要生硬复述）：\n%s\n\n" % "\n".join(parts)
