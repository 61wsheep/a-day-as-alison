extends SceneTree

## AIDialogueSession 的 mock 集成测试（零网络）。
## 运行：godot --headless -s res://scripts/tests/test_ai_session_mock.gd --quit
## 注入脚本化 LLM 响应，验证：
##   - S1 会话循环（开场→话题→回复→结束）
##   - emotional_shift 结算（负向×0.8、clamp、进 GameManager）
##   - hints 命中白名单 → discover_clue
##   - S2 旁路 + 失败回落

const AIDialogueSession := preload("res://scripts/systems/ai_dialogue_session.gd")

var _failures := 0
var _passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # 等场景树就绪
	var bridge = root.get_node_or_null("AIBridge")
	if bridge == null:
		printerr("[MOCKTEST] 无 AIBridge autoload，跳过")
		quit(1)
		return

	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_llm)

	var base := Node.new()
	root.add_child(base)

	var gm = root.get_node_or_null("GameManager")
	if gm:
		gm.npc_affection["padwin"] = 50
		gm.clues_found.clear()

	await _run_s1_session(base, gm)
	await _run_s2_sideline(base)
	await _run_failure_fallback(base)

	print("[MOCKTEST] AI 会话 mock 测试: %d 通过, %d 失败" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[MOCKTEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[MOCKTEST] FAIL  ", name)


## 脚本化 LLM 响应：轮次 → 脚本化 JSON。
var _turn_counter := 0
func _mock_llm(payload: Dictionary) -> String:
	_turn_counter += 1
	var n := _turn_counter
	var json_data := {
		"response_text": "（第%d轮回复）风的方向变了。" % n,
		"emotional_shift": -4 if n == 2 else 3,
		"memory_update": "第%d轮记忆摘要" % n,
		"internal_note": "（内心想法%d）" % n,
		"hints_to_other_npcs": ["索拉雅机械重复的迎接" if n == 1 else "无关内容"],
		"should_end_conversation": n >= 3,
		"topic_suggestions": ["关于那座石塔", "今天的森林", "你昨天说的那句话"],
	}
	return JSON.stringify(json_data)


func _run_s1_session(base: Node, gm: Node) -> void:
	var session := AIDialogueSession.new()
	session.setup(base, "padwin")
	var ended := false
	session.session_finished.connect(func(): ended = true)
	var topics_seen: Array = []
	session.choices_ready.connect(func(topics): topics_seen = topics)
	_turn_counter = 0

	# 开场
	session.begin()
	await _wait_frames(3)
	_check("S1 开场给出话题建议", topics_seen.size() == 3)

	# 点话题推进第 2 轮
	session.submit_topic(0)
	await _wait_frames(3)

	# 自由输入推进第 3 轮（should_end=true 结束）
	session.submit_free_text("那你呢？")
	await _wait_frames(3)

	_check("S1 会话结束（3 轮后 should_end）", ended == true)
	if gm:
		# 3 轮：+3, -4×0.8=-3, +3 → 50+3-3+3=53
		_check("S1 好感度结算（负向×0.8）", gm.npc_affection["padwin"] == 53)
		_check("S1 hints 白名单线索", "clue_soraya_repeat" in gm.clues_found)


func _run_s2_sideline(base: Node) -> void:
	var session := AIDialogueSession.new()
	session.setup(base, "padwin")
	var done := false
	session.sideline_done.connect(func(): done = true)
	_turn_counter = 0

	session.free_input_turn("你相信命运吗？")
	await _wait_frames(3)

	_check("S2 旁路完成", done == true)


func _run_failure_fallback(base: Node) -> void:
	var bridge = root.get_node_or_null("AIBridge")
	bridge.set_mock_responder(func(payload): return "[API_ERROR] 测试超时")
	var session := AIDialogueSession.new()
	session.setup(base, "padwin")
	var ended := false
	session.session_finished.connect(func(): ended = true)
	_turn_counter = 0

	session.free_input_turn("测试失败回落")
	await _wait_frames(3)

	_check("失败回落触发 session_finished", ended == true)
	bridge.set_mock_responder(_mock_llm)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame
