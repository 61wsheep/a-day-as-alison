extends Node

## 测试 AI 判停收场（新契约）：
##   S1 自然判停（should_end）→ 不覆盖 AI 最后一句正文；发告别 toast；停留 2.5s 后自动退出
##   + _ended 置位后收尾期间提交被忽略
##   + 失败路径 session_aborted → 立即退出、无告别 toast
## 场景运行：godot --headless scenes/tests/test_ai_farewell.tscn

var _turn := 0
var _lines: Array = []
var _toasts: Array = []
var _ended := false


func _ready() -> void:
	_run()


## 每轮递增计数；第 3 轮返回 should_end_conversation=true。
func _mock_llm(_payload: Dictionary) -> String:
	_turn += 1
	return JSON.stringify({
		"response_text": "（第%d轮回复）风的方向变了。" % _turn,
		"emotional_shift": 0,
		"memory_update": "第%d轮记忆" % _turn,
		"should_end_conversation": _turn >= 3,
		"topic_suggestions": [],
	})


func _run() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		printerr("[FAREWELL] 无 AIBridge autoload")
		get_tree().quit(1)
		return
	var bus = get_node("/root/EventBus")

	# ---------- 场景 1：自然判停 → 告别 toast + 延迟退出 ----------
	bridge.set_mock_responder(_mock_llm)
	_turn = 0
	_lines.clear()
	_toasts.clear()
	_ended = false
	bus.dialogue_line.connect(_lines_append)
	bus.toast.connect(_toast_append)
	bus.dialogue_ended.connect(_on_dlg_ended)

	var npc = preload("res://scripts/npc/npc_base.gd").new()
	add_child(npc)
	npc.npc_id = "padwin"
	npc._data = {"display_name": "帕德温"}
	npc._ai_mode = true
	npc._dialogue_active = true

	var session = preload("res://scripts/systems/ai_dialogue_session.gd").new()
	npc._ai_session = session
	session.setup(npc, "padwin")
	session.line_ready.connect(npc._on_ai_line)
	session.choices_ready.connect(npc._on_ai_choices)
	session.sideline_done.connect(npc._on_ai_sideline_done)
	session.session_finished.connect(npc._on_ai_session_finished)
	session.session_aborted.connect(npc._end_dialogue)

	session.begin()
	await get_tree().create_timer(0.25).timeout   # 第 1 轮
	session.submit_free_text("在吗？")
	await get_tree().create_timer(0.25).timeout   # 第 2 轮
	session.submit_free_text("继续说")
	await get_tree().create_timer(0.25).timeout   # 第 3 轮 → should_end → 告别

	# AI 最后一句（第 3 轮回复）必须还在正文行里（不被系统行覆盖）
	var last_reply_in_body := false
	for l in _lines:
		if "风的方向变了" in l:
			last_reply_in_body = true
	# 收场以 toast 提示，不占正文行
	var farewell_toast := ""
	for t in _toasts:
		if "不想再聊" in t:
			farewell_toast = t
	print("[FAREWELL] 最后一句在正文=%s 告别toast=%s  对话仍激活=%s"
		% [last_reply_in_body, farewell_toast, npc._dialogue_active])
	var farewell_ok: bool = last_reply_in_body and farewell_toast != "" and npc._dialogue_active

	# _ended 置位：告别停留期间提交被忽略
	var lines_before := _lines.size()
	session.submit_free_text("别走")
	await get_tree().create_timer(0.25).timeout
	var guard_ok := _lines.size() == lines_before
	print("[FAREWELL] 告别期间提交被忽略=%s（行数 %d → %d）" % [guard_ok, lines_before, _lines.size()])

	# 2.5s 停留后自动退出
	await get_tree().create_timer(3.0).timeout
	print("[FAREWELL] 延迟后自动退出: dialogue_active=%s ended=%s" % [npc._dialogue_active, _ended])
	var exit_ok: bool = not npc._dialogue_active and _ended

	# 清场，避免干扰场景 2
	npc.queue_free()
	bus.dialogue_line.disconnect(_lines_append)
	bus.toast.disconnect(_toast_append)
	bus.dialogue_ended.disconnect(_on_dlg_ended)

	# ---------- 场景 2：失败 → session_aborted 立即退出、无告别 toast ----------
	bridge.set_mock_responder(func(_p): return "[API_ERROR] 测试断网")
	_turn = 0
	_lines.clear()
	_toasts.clear()
	_ended = false
	bus.dialogue_line.connect(_lines_append)
	bus.toast.connect(_toast_append)
	bus.dialogue_ended.connect(_on_dlg_ended)

	var npc2 = preload("res://scripts/npc/npc_base.gd").new()
	add_child(npc2)
	npc2.npc_id = "padwin"
	npc2._data = {"display_name": "帕德温"}
	npc2._ai_mode = true
	npc2._dialogue_active = true

	var s2 = preload("res://scripts/systems/ai_dialogue_session.gd").new()
	npc2._ai_session = s2
	s2.setup(npc2, "padwin")
	s2.line_ready.connect(npc2._on_ai_line)
	s2.choices_ready.connect(npc2._on_ai_choices)
	s2.sideline_done.connect(npc2._on_ai_sideline_done)
	s2.session_finished.connect(npc2._on_ai_session_finished)
	s2.session_aborted.connect(npc2._end_dialogue)

	s2.begin()
	await get_tree().create_timer(0.4).timeout   # 请求失败 → session_aborted
	var farewell_toast2 := false
	for t in _toasts:
		if "不想再聊" in t:
			farewell_toast2 = true
	# 失败路径会发"AI 暂时无法回复"toast（既有），但绝不该有"告别"toast/正文
	var abort_ok: bool = not npc2._dialogue_active and _ended \
		and _lines.is_empty() and not farewell_toast2
	print("[FAREWELL] 失败立即退出=%s（dialogue_active=%s ended=%s 行数=%d toast数=%d）"
		% [abort_ok, npc2._dialogue_active, _ended, _lines.size(), _toasts.size()])

	var all_ok: bool = farewell_ok and guard_ok and exit_ok and abort_ok
	print("[FAREWELL] %s" % ("PASS 收尾toast+最后一句保留+守卫+延迟退出+失败立即退出" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)


func _lines_append(_s, _d, text, _e) -> void:
	_lines.append(text)


func _toast_append(text: String) -> void:
	_toasts.append(text)


func _on_dlg_ended() -> void:
	_ended = true
