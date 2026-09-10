extends CharacterBody2D
class_name NPCBase

## NPC 基类 — JSON 数据驱动的对话引擎。
##
## 对话数据：res://resources/dialogues/<npc>.json
## 流程：E 开始 → 逐行推进（E）→ 遇到 choices 行弹出选项
## → 选择后应用 effects，可选 reply → 继续/跳转/结束。

signal interaction_available(npc_id: String)

@export var npc_id: String = ""
@export var dialogue_file: String = ""

var _data: Dictionary = {}
var _lines: Array = []
var _end_effects: Dictionary = {}
var _line_idx: int = 0
var _dialogue_active: bool = false
var _waiting_for_choice: bool = false
var _showing_reply: bool = false
var _pending_end: bool = false
var _pending_end_effects: Dictionary = {}
var _player_in_range: bool = false

# -- AI 对话状态（S1 会话 + S2 旁路） --
var _ai_mode := false
var _ai_thinking := false
var _ai_free_input_enabled := false
var _ai_session: AIDialogueSession = null
var _last_topics: Array = []   # AI 本轮给的话题建议（供玩家点击后记入实录）


func _ready() -> void:
	var zone = get_node_or_null("InteractZone")
	if zone:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)
	_load_dialogue_data()
	var bus = get_node("/root/EventBus")
	bus.dialogue_choice_made.connect(_on_choice_made)
	bus.dialogue_free_input.connect(_on_free_input)
	bus.dialogue_exit_requested.connect(_request_exit)


func _load_dialogue_data() -> void:
	if dialogue_file.is_empty() or not FileAccess.file_exists(dialogue_file):
		return
	var f := FileAccess.open(dialogue_file, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_data = parsed


func _input(event: InputEvent) -> void:
	# Esc 退出对话 —— 无论是否在自由输入框聚焦、无论 AI/JSON 模式，都生效
	if _ai_mode and event.is_action_pressed("ui_cancel"):
		print("[NPC:%s] Esc 到达 _input（AI 模式），强制结束对话" % npc_id)
		var bridge = get_node_or_null("/root/AIBridge")
		if bridge:
			bridge.cancel_current()   # 取消在途请求（可能立刻恢复，也可能不）
		_end_dialogue()               # 无论如何立即结束对话，不依赖 await 恢复
		return
	if _dialogue_active and event.is_action_pressed("ui_cancel"):
		_end_dialogue()
		return
	if _ai_mode and _is_text_focus_owner():
		return                     # 自由输入框聚焦时，E 不旁路给对话
	if not _player_in_range:
		return
	# H：靠近 NPC 时查看与该角色的历史对话（非对话中、玩家未锁、不在输入框里才响应）
	if not _dialogue_active and not _movement_locked() and not _is_text_focus_owner() \
			and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_H:
		get_node("/root/EventBus").history_requested.emit(npc_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		if _ai_mode:               # S1 里 E 无推进作用，忽略
			return
		if _waiting_for_choice:
			return
		if _dialogue_active:
			if _showing_reply:
				_showing_reply = false
				if _pending_end:
					_end_dialogue()
					return
				_line_idx += 1
				_advance()
			else:
				_line_idx += 1
				_advance()
		else:
			# 弹窗/其他对话开着（玩家移动被锁）时不重开对话——否则对话结束连按 E
			# 会把 NPC 对话重新叠到占卜/售卖等面板上（M2 占卜弹窗被打断的根因）。
			if _movement_locked():
				return
			_start_dialogue()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		interaction_available.emit(npc_id)
		get_node("/root/EventBus").interaction_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		get_node("/root/EventBus").interaction_hint_hide.emit()
		if _dialogue_active:
			_end_dialogue()


# ---------------------------------------------------------------------------
# 对话选择与推进
# ---------------------------------------------------------------------------
func _start_dialogue() -> void:
	var dlg := _select_dialogue()
	if dlg.is_empty():
		return
	var bus = get_node("/root/EventBus")
	_dialogue_active = true
	_ai_mode = false
	_ai_session = null

	# S1：入口标记 ai:true 且 AI 可用 → 整段进入 AI 会话
	if bool(dlg.get("ai", false)) and _ai_supported():
		_begin_ai_session(dlg)
		return

	# —— 以下为原有 JSON 路径 ——
	_lines = dlg.get("lines", [])
	_end_effects = dlg.get("end_effects", {})
	if _lines.is_empty():
		return
	# S2：JSON 对话里允许自由输入暗门（有角色卡且 AI 可用）
	_ai_free_input_enabled = _ai_supported()
	bus.dialogue_ai_meta.emit(npc_id, false, _ai_free_input_enabled)
	_waiting_for_choice = false
	_showing_reply = false
	_pending_end = false
	_pending_end_effects = {}
	_line_idx = 0
	bus.interaction_hint_hide.emit()
	bus.dialogue_started.emit()
	_advance()


func _ai_supported() -> bool:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		return false
	return bridge.is_available() and bridge.has_role_card(npc_id)


func _begin_ai_session(dlg: Dictionary) -> void:
	_ai_mode = true
	_ai_free_input_enabled = true
	_end_effects = dlg.get("end_effects", {})
	var bus = get_node("/root/EventBus")
	bus.dialogue_ai_meta.emit(npc_id, true, true)
	bus.interaction_hint_hide.emit()
	bus.dialogue_started.emit()
	_ai_session = AIDialogueSession.new()
	_ai_session.setup(self, npc_id)
	_ai_session.thinking_changed.connect(_on_ai_thinking)
	_ai_session.line_delta.connect(_on_ai_line_delta)
	_ai_session.line_ready.connect(_on_ai_line)
	_ai_session.choices_ready.connect(_on_ai_choices)
	_ai_session.sideline_done.connect(_on_ai_sideline_done)
	_ai_session.session_finished.connect(_on_ai_session_finished)
	_ai_session.session_aborted.connect(_end_dialogue)
	_ai_session.begin()


func _select_dialogue() -> Dictionary:
	var gm = get_node("/root/GameManager")
	var best_priority := -1
	var matches: Array = []
	for dlg in _data.get("dialogues", []):
		if gm.conditions_met(dlg.get("conditions", {})):
			var p := int(dlg.get("priority", 0))
			if p > best_priority:
				best_priority = p
				matches = [dlg]
			elif p == best_priority:
				matches.append(dlg)
	if matches.is_empty():
		return {}
	if matches.size() == 1:
		return matches[0]
	# 同优先级多条命中：仅当都是 L2 回落变奏（rotate:true）时按天轮换，
	# 避免离线连玩复读同一段；脚本剧情条目（无 rotate）保持取数组首个的旧行为。
	var has_rotate := false
	for m in matches:
		if bool(m.get("rotate", false)):
			has_rotate = true
	if not has_rotate:
		return matches[0]
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	var day := 1
	if gm:
		day = int(gm.current_day)
	# 轮换基准对齐到本组匹配的最小起始天：A/B/C 分档条目按档位各自开场，
	# 否则全局 (day-1)%n 会让 day3 落到 b3、day7(C 档首日)落到 c2，档内叙事顺序被打乱。
	# 无 day_min 的纯轮换池退化为以 day1 为基准的旧行为。
	var base_day := -1
	for m in matches:
		var dm := int(m.get("conditions", {}).get("day_min", -1))
		if dm > 0 and (base_day < 0 or dm < base_day):
			base_day = dm
	if base_day < 0:
		base_day = 1
	return matches[(day - base_day) % matches.size()]


func _advance() -> void:
	var gm = get_node("/root/GameManager")
	var bus = get_node("/root/EventBus")
	while _line_idx < _lines.size():
		var line: Dictionary = _lines[_line_idx]
		if line.has("conditions") and not gm.conditions_met(line["conditions"]):
			_line_idx += 1
			continue
		if line.has("choices"):
			var valid: Array = []
			for choice in line["choices"]:
				if gm.conditions_met(choice.get("conditions", {})):
					valid.append(choice)
			if valid.is_empty():
				_line_idx += 1
				continue
			_waiting_for_choice = true
			var labels: Array = []
			for c in valid:
				labels.append(str(c.get("text", "……")))
			# 先播该行文本作选项前的铺垫，再弹选项。
			# 顺序不能反：dialogue_line 处理器会把刚弹出的选项面板隐藏（见 dialogue_ui._on_dialogue_line），
			# 反了玩家就看不到选项——真机占卜 divine_offer / intro 带文本+选项的行按钮全隐形，抽牌面板永远触不发。
			if str(line.get("text", "")) != "":
				_emit_line(line)
			bus.dialogue_choices.emit(labels)
			return
		_emit_line(line)
		return
	_end_dialogue()


func _emit_line(line: Dictionary) -> void:
	var speaker := str(line.get("speaker", npc_id))
	var display := _display_name(speaker)
	var text := str(line.get("text", ""))
	get_node("/root/EventBus").dialogue_line.emit(
		speaker, display, text, str(line.get("emotion", "")))
	# 实录上报：脚本台词 + AI 会话行 + narrator/player 行都记录，供「历史对话」回看
	if text != "":
		var log := get_node_or_null("/root/DialogueLog")
		if log:
			log.append(npc_id, speaker, display, text,
				int(get_node("/root/GameManager").current_day))


func _display_name(speaker: String) -> String:
	if speaker == "player":
		return "艾莉森"
	if speaker == "narrator":
		return ""
	return str(_data.get("display_name", speaker))


func _on_choice_made(choice_index: int) -> void:
	if not _dialogue_active:
		return
	if _ai_mode:
		# 点话题建议 = 艾莉森开口说的话，与自由输入一致记入实录（否则 AI 对话里
		# 玩家的话只剩 NPC 行，按 H 看不到自己说过什么）。
		if choice_index >= 0 and choice_index < _last_topics.size():
			_log_player_line(str(_last_topics[choice_index]))
		if _ai_session:
			_ai_session.submit_topic(choice_index)   # 话题按钮 → 当作玩家输入推进
		return
	if not _waiting_for_choice:
		return
	_waiting_for_choice = false
	var gm = get_node("/root/GameManager")
	var line: Dictionary = _lines[_line_idx]
	var valid: Array = []
	for choice in line["choices"]:
		if gm.conditions_met(choice.get("conditions", {})):
			valid.append(choice)
	if choice_index < 0 or choice_index >= valid.size():
		return
	var chosen: Dictionary = valid[choice_index]

	gm.apply_effects(chosen.get("effects", {}))
	_pending_end_effects = chosen.get("end_effects", {})
	_pending_end = bool(chosen.get("end", false))

	var reply := str(chosen.get("reply", ""))
	if reply != "":
		_showing_reply = true
		_emit_line({
			"speaker": npc_id,
			"text": reply,
			"emotion": str(chosen.get("reply_emotion", "")),
		})
		return

	if _pending_end:
		_end_dialogue()
		return
	if chosen.has("goto"):
		_line_idx = int(chosen["goto"])
	else:
		_line_idx += 1
	_advance()


func _end_dialogue() -> void:
	if not _dialogue_active:
		return
	_dialogue_active = false
	if _ai_session:
		_ai_session.end_session()   # 内部 flush 记忆 + cancel 在途请求
		_ai_session = null
	_ai_mode = false
	_waiting_for_choice = false
	_showing_reply = false
	if _ai_thinking:
		_ai_thinking = false
		get_node("/root/EventBus").ai_thinking.emit(false)   # 收起「在思考」标签
	var gm = get_node("/root/GameManager")
	gm.apply_effects(_pending_end_effects)
	gm.apply_effects(_end_effects)
	_pending_end_effects = {}
	get_node("/root/EventBus").dialogue_ended.emit()
	# 清除 UI 的「AI 对话中」标记
	get_node("/root/EventBus").dialogue_ai_meta.emit(npc_id, false, false)


# ---------------------------------------------------------------------------
# AI 对话相关（S1 会话 / S2 旁路）
# ---------------------------------------------------------------------------
func _on_free_input(text: String) -> void:
	if not _dialogue_active:
		return
	_log_player_line(text)   # 玩家自由输入 / 不回答（沉默）也进实录
	if _ai_mode:
		if _ai_session:
			_ai_session.submit_free_text(text)
		return
	if not _waiting_for_choice:
		return
	# S2：懒创建会话做一次旁路回复
	if _ai_session == null:
		_ai_session = AIDialogueSession.new()
		_ai_session.setup(self, npc_id)
		_ai_session.line_delta.connect(_on_ai_line_delta)
		_ai_session.line_ready.connect(_on_ai_line)
		_ai_session.sideline_done.connect(_on_ai_sideline_done)
		_ai_session.thinking_changed.connect(_on_ai_thinking)
	_ai_session.free_input_turn(text)


## 玩家发言以"艾莉森行"显示在对话面板上，并进实录（历史回看也要含你说过的话）。
## 覆盖：自由输入框打字 / 不回答（沉默） / 点击 AI 话题建议按钮。
## 走 _emit_line：一次调用同时完成 ①bus.dialogue_line 渲染"艾莉森：…"到 UI
## ②DialogueLog 记录。此前玩家自由输入只在后台提交给 AI，UI 从不显示自己的话，
## 看起来就像只弹"（NPC 在想着什么…）"或 NPC 回复——这里把玩家的话显出来。
func _log_player_line(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	_emit_line({"speaker": "player", "text": t})


func _request_exit() -> void:
	if _dialogue_active:
		_end_dialogue()


func _on_ai_thinking(active: bool) -> void:
	_ai_thinking = active
	get_node("/root/EventBus").ai_thinking.emit(active)


## AI 自然判停（should_end_conversation）：把 AI 自己说的最后一句留在面板上，
## 停留片刻再退出，避免对话"无声无息地消失"。
## 注意：不在此处用"[XX 似乎不想再聊下去了。]"覆盖正文——那会瞬间盖掉 AI 真正
## 的告别句（真机表现为"NPC 说的最后一句话没显示出来"）。收场提示改走顶部 toast，
## 正文保持 AI 最后一句可见直到对话关闭。
func _on_ai_session_finished() -> void:
	if not _dialogue_active:
		return
	var bus := get_node("/root/EventBus")
	if bus:
		bus.toast.emit("（%s 似乎不想再聊下去了…）" % _display_name(npc_id))
	await get_tree().create_timer(2.5).timeout
	if _dialogue_active:
		_end_dialogue()


func _on_ai_line(speaker: String, text: String, emotion: String) -> void:
	if not _dialogue_active:
		return   # 对话已结束（如 Esc 退出），丢弃迟到的 AI 回复
	_emit_line({"speaker": speaker, "text": text, "emotion": emotion})


## 流式增量：只转发给 UI 覆盖显示，**不走 _emit_line**——那条路径会写 DialogueLog，
## 逐帧写入会把实录撑爆（同一句话记几十遍）。
func _on_ai_line_delta(speaker: String, text: String) -> void:
	if not _dialogue_active:
		return
	get_node("/root/EventBus").dialogue_line_delta.emit(speaker, _display_name(speaker), text, "")


func _on_ai_choices(topics: Array) -> void:
	_last_topics = topics   # 缓存：玩家点话题按钮时据此记实录、取文本
	if _ai_mode:
		get_node("/root/EventBus").dialogue_choices.emit(topics)


func _on_ai_sideline_done() -> void:
	# S2：AI 旁路回复结束，重发当前 JSON 选项让面板复原
	_emit_current_choices()


func _emit_current_choices() -> void:
	if _lines.is_empty() or _line_idx >= _lines.size():
		return
	var line: Dictionary = _lines[_line_idx]
	if not line.has("choices"):
		return
	var labels: Array = []
	var gm = get_node("/root/GameManager")
	for c in line["choices"]:
		if gm.conditions_met(c.get("conditions", {})):
			labels.append(str(c.get("text", "……")))
	if labels.is_empty():
		return
	get_node("/root/EventBus").dialogue_choices.emit(labels)


func _is_text_focus_owner() -> bool:
	var c := get_viewport().gui_get_focus_owner()
	return c is LineEdit


## 玩家当前是否被锁（对话/弹窗打开）。开场新对话前必须检查——否则结束连按 E 会把
## 对话叠到占卜/售卖等面板上。
func _movement_locked() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	return p != null and bool(p._movement_locked)
