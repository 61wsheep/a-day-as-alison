extends Node

## Mock AI 会话集成测试场景（真实场景树 + 帧循环）。
## 挂在 scenes/tests/ai_mock_test.tscn，由 headless 运行。
## 用法：godot --headless scenes/tests/ai_mock_test.tscn
##
## 注意：GDScript 闭包不按引用捕获局部变量，信号状态必须存成员变量或数组。

var _failures := 0
var _passes := 0
var _turn_counter := 0

# 信号状态（成员变量，闭包可修改）
var _ended := false
var _done := false
var _topics_seen: Array = []


func _ready() -> void:
	_run()


func _run() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		printerr("[MOCKTEST] 无 AIBridge autoload，跳过")
		get_tree().quit(1)
		return
	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_llm)
	var gm = get_node("/root/GameManager")
	gm.npc_affection["padwin"] = 50
	gm.clues_found.clear()

	await _run_s1_session()
	await _run_s2_sideline()
	await _run_failure_fallback()

	print("[MOCKTEST] 全部完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[MOCKTEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[MOCKTEST] FAIL  ", name)


func _mock_llm(payload: Dictionary) -> String:
	_turn_counter += 1
	var n := _turn_counter
	await get_tree().create_timer(0.02).timeout   # 模拟真实异步
	return JSON.stringify({
		"response_text": "（第%d轮回复）风的方向变了。" % n,
		"emotional_shift": -4 if n == 2 else 3,
		"memory_update": "第%d轮记忆摘要" % n,
		"hints_to_other_npcs": ["索拉雅机械重复的迎接" if n == 1 else "无关内容"],
		"should_end_conversation": n >= 3,
		"topic_suggestions": ["关于那座石塔", "今天的森林", "你昨天说的那句话"],
	})


func _run_s1_session() -> void:
	var gm = get_node("/root/GameManager")
	var session := AIDialogueSession.new()
	session.setup(self, "padwin")
	_ended = false
	_topics_seen = []
	session.session_finished.connect(func(): _ended = true)
	session.choices_ready.connect(func(topics): _topics_seen = topics)
	_turn_counter = 0

	session.begin()
	await get_tree().create_timer(0.3).timeout
	_check("S1 开场给出话题建议", _topics_seen.size() == 3)

	session.submit_topic(0)
	await get_tree().create_timer(0.3).timeout

	session.submit_free_text("那你呢？")
	await get_tree().create_timer(0.3).timeout

	_check("S1 会话结束（3 轮后 should_end）", _ended == true)
	# 3 轮：+3, -4×0.8=-3, +3 → 53
	_check("S1 好感度结算（负向×0.8）", gm.npc_affection["padwin"] == 53)
	_check("S1 hints 白名单线索", "clue_soraya_repeat" in gm.clues_found)


func _run_s2_sideline() -> void:
	var session := AIDialogueSession.new()
	session.setup(self, "padwin")
	_done = false
	session.sideline_done.connect(func(): _done = true)
	_turn_counter = 0

	session.free_input_turn("你相信命运吗？")
	await get_tree().create_timer(0.3).timeout

	_check("S2 旁路完成", _done == true)


func _run_failure_fallback() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	bridge.set_mock_responder(func(payload):
		await get_tree().create_timer(0.02).timeout
		return "[API_ERROR] 测试超时")
	# S2 旁路失败 → sideline_done（npc_base 收到后复原选项面板，等价回落）
	var session := AIDialogueSession.new()
	session.setup(self, "padwin")
	_done = false
	session.sideline_done.connect(func(): _done = true)
	_turn_counter = 0

	session.free_input_turn("测试失败回落")
	await get_tree().create_timer(0.3).timeout

	_check("S2 失败回落触发 sideline_done", _done == true)
	bridge.set_mock_responder(_mock_llm)
