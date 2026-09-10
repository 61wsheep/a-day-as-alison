extends Node

## 历史实录 · AI 自由对话的玩家发言（回归测试，零网络）。
## 需求：按 H 回看时，AI 对话环节里艾莉森说过的话也要能看到——
##   1) 自由输入框打字（dialogue_free_input → npc_base._on_free_input）
##   2) 点击话题建议按钮（dialogue_choice_made → npc_base._on_choice_made AI 分支）
## 用 mock LLM 走真实 npc_base + AIDialogueSession（S1），断言两种玩家发言都进 DialogueLog、
## HistoryPanel 能渲染出来。之前只记 NPC 行、不记玩家点的话题按钮——本测试拦回归。

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0
var _turn := 0
var _topics_seen: Array = []
var _ui_lines: Array = []   # 对话面板实际显示的行（bus.dialogue_line 捕获：玩家/AI/旁白）


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 40.0
	guard.timeout.connect(func():
		printerr("[HAI] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[HAI] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[HAI] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


## 脚本化 LLM 响应：轮次 → JSON（字段须满足 dialogue_schema 要求）。
## 第 1 轮=AI 开场（给话题）；之后每轮都返回话题；n>=3 判停。
func _mock_llm(_payload: Dictionary) -> String:
	_turn += 1
	var n := _turn
	return JSON.stringify({
		"response_text": "（第%d轮回复）风从东边的林子来。" % n,
		"emotional_shift": 1,
		"memory_update": "第%d轮记忆摘要" % n,
		"internal_note": "（内心%d）" % n,
		"hints_to_other_npcs": [],
		"should_end_conversation": n >= 3,
		"topic_suggestions": ["你昨天说的那句话", "关于那座石塔", "谢谢，改天再聊"],
	})


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	var log: Node = get_node("/root/DialogueLog")
	var bus: Node = get_node("/root/EventBus")
	var gm: Node = get_node("/root/GameManager")
	log.clear_all()
	if bridge == null:
		printerr("[HAI] 无 AIBridge autoload，跳过")
		get_tree().quit(1)
		return
	# 强制 mock（不依赖真 key）；跑完恢复关闭态
	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_llm)

	bus.dialogue_choices.connect(func(topics: Array): _topics_seen = topics)
	bus.dialogue_line.connect(func(speaker: String, _d: String, text: String, _e: String):
		_ui_lines.append([speaker, text]))

	# -- 装主场景，关晨间塔罗 --
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)
	# 翻完开场旁白（播放期间玩家锁着）；塔罗已挪进艾莉森小屋，开局不再自动弹
	await TestHelpers.dismiss_opening(scene)

	var padwin: Node = scene.get_node_or_null("Areas/TreehouseDistrict/Padwin")
	var hp: Node = scene.get_node_or_null("HistoryPanel")
	_check("找到帕德温", padwin != null)
	_check("HistoryPanel 挂入主场景", hp != null)
	if padwin == null or hp == null:
		# 复位 mock 后退出
		bridge.set_mock_responder(Callable())
		bridge.set_enabled(false)
		get_tree().quit(1)
		return

	# -- 置 met_padwin → daily（ai:true）→ 走 S1 真 AI 会话 --
	gm.set_flag("met_padwin")
	_check("对话选中 daily(AI)", str(padwin._select_dialogue().get("id", "")) == "daily")
	_check("角色卡存在（AI 可用前置）", bridge.has_role_card("padwin"))
	padwin._start_dialogue()
	await _wait(0.6)
	_check("进入 S1 AI 模式", bool(padwin._ai_mode) and bool(padwin._dialogue_active))
	_check("AI 开场给了话题建议", _topics_seen.size() == 3)
	_check("AI 开场 NPC 行已入实录", _has_speaker(log, "padwin", "padwin"))

	# -- 玩家自由输入打字 → 实录 + 推进第 2 轮 --
	var typed := "我今天想多了解你"
	bus.dialogue_free_input.emit(typed)
	await _wait(0.6)
	_check("自由输入玩家行入实录", _has_text(log, "padwin", "player", typed))
	_check("NPC 对自由输入的回复已入实录", _has_speaker_after(log, "padwin", "padwin", typed))
	_check("UI 面板显示自由输入玩家话", _ui_has_player(typed))

	# -- 点击话题建议按钮（第 2 轮回复给的话题）→ 实录 + UI 显示 + 推进第 3 轮 --
	_check("第 2 轮后仍有话题建议", _topics_seen.size() == 3)
	var topic := str(_topics_seen[0])
	bus.dialogue_choice_made.emit(0)
	await _wait(0.6)
	_check("点击的话题按钮文字已入实录", _has_text(log, "padwin", "player", topic))
	_check("UI 面板显示点击话题玩家话", _ui_has_player(topic))
	# 第 3 轮 mock 判停 → 收场契约：AI 最后一句留在正文（不被"[… 不想再聊]"系统行覆盖）
	_check("AI 最后一句未被子系统告别行覆盖", _ui_last_contains("风从东边的林子来"))
	_check("收场无系统告别正文行", not _ui_text_has("不想再聊"))

	# -- 面板能回看到两种玩家发言 --
	hp._close()
	hp.open("padwin")
	await _wait(0.3)
	var body := str(hp._body.get_parsed_text())
	_check("面板含自由输入玩家话", body.contains(typed))
	_check("面板含点击话题玩家话", body.contains(topic))
	hp._close()

	# -- 收尾：结束对话，复位 mock --
	if bool(padwin._dialogue_active):
		padwin._end_dialogue()
		await _wait(0.3)
	bridge.set_mock_responder(Callable())
	bridge.set_enabled(false)
	log.clear_all()

	scene.queue_free()
	await _wait(0.3)
	print("[HAI] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _has_speaker(log: Node, npc_id: String, speaker: String) -> bool:
	for e in log.for_npc(npc_id):
		if str(e.get("speaker", "")) == speaker:
			return true
	return false


func _has_text(log: Node, npc_id: String, speaker: String, text: String) -> bool:
	for e in log.for_npc(npc_id):
		if str(e.get("speaker", "")) == speaker and str(e.get("text", "")).contains(text):
			return true
	return false


## typed 出现之后，必须还有一条 NPC 发言（证明 typed 被真正提交并得到回复）。
func _has_speaker_after(log: Node, npc_id: String, speaker: String, after_text: String) -> bool:
	var found_after := false
	for e in log.for_npc(npc_id):
		if found_after and str(e.get("speaker", "")) == speaker:
			return true
		if str(e.get("text", "")).contains(after_text):
			found_after = true
	return false


## UI（bus.dialogue_line）是否出现过艾莉森的这条发言。
func _ui_has_player(text: String) -> bool:
	for row in _ui_lines:
		if str(row[0]) == "player" and str(row[1]).contains(text):
			return true
	return false


## UI 当前/最后一行正文是否包含 text（收场时 AI 最后一句应保持在最后）。
func _ui_last_contains(text: String) -> bool:
	if _ui_lines.is_empty():
		return false
	return str(_ui_lines[-1][1]).contains(text)


## UI 全程是否出现过包含 text 的行（用于断言没有系统告别正文行）。
func _ui_text_has(text: String) -> bool:
	for row in _ui_lines:
		if str(row[1]).contains(text):
			return true
	return false
