extends Node

## M2 帕德温占卜支线端到端测试 — 委托板接单 → 与帕德温对话触发占卜 →
## 抽牌解读（数据段）→ 完成任务发奖 → 故事回放（resolved 只播一次）。
## 复用 npc_base 真实输入路径（_start_dialogue + 合成 E 键推进 + 选选项）。
## 与晨间 TarotUI 隔离：本流程不写 gm.tarot_drawn_today / daily_luck。

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		printerr("[TAROTQ] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TAROTQ] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[TAROTQ] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _make_e() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	return ev


func _press_e(npc: Node) -> void:
	npc._player_in_range = true   # _input 推进对话前有范围守卫
	npc._input(_make_e())


func _find_button_by_text(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and c.text == text:
			return c
		var r := _find_button_by_text(c, text)
		if r != null:
			return r
	return null


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var gm: Node = get_node("/root/GameManager")
	var qm: Node = get_node("/root/QuestManager")

	# -- 装主场景 --
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)
	# 关掉晨间塔罗（两次点击：抽牌 → 关闭）
	var tarot: Node = scene.get_node_or_null("TarotUI")
	if tarot and tarot.has_method("_on_action"):
		tarot._on_action()
		await _wait(0.3)
		tarot._on_action()
		await _wait(0.3)
	gm.current_day = 3   # quest unlock day_min=3

	# -- M2 节点挂入主场景 --
	var notice: Node = scene.get_node_or_null("Areas/Plaza/NoticeBoard")
	var qboard: Node = scene.get_node_or_null("QuestBoardUI")
	var div: Node = scene.get_node_or_null("TarotDivinationUI")
	var padwin: Node = scene.get_node_or_null("Areas/TreehouseDistrict/Padwin")
	_check("NoticeBoard 挂入", notice != null)
	_check("QuestBoardUI 挂入", qboard != null)
	_check("TarotDivinationUI 挂入", div != null)
	_check("找到帕德温", padwin != null)
	if notice == null or qboard == null or div == null or padwin == null:
		get_tree().quit(1)
		return

	# -- 委托板：靠近 → 按 E 打开 → 按「接受」接单 --
	var player := get_tree().get_first_node_in_group("player")
	notice._on_body_entered(player)
	notice._unhandled_input(_make_e())
	await _wait(0.2)
	_check("委托板打开", qboard.has_method("is_open") and bool(qboard.is_open()))
	var accept_btn := _find_button_by_text(qboard, "接受")
	_check("委托板列出可接受的委托（接受按钮存在）", accept_btn != null)
	if accept_btn:
		accept_btn.pressed.emit()
		await _wait(0.2)
		_check("接单后任务 active", qm.is_active("tarot_padwin_01"))
	qboard._close()
	await _wait(0.2)
	_check("委托板已关闭", not bool(qboard.is_open()))

	# -- 与帕德温对话：应选中 divine_offer --
	gm.set_flag("met_padwin")
	_check("对话选中 divine_offer", str(padwin._select_dialogue().get("id", "")) == "divine_offer")
	padwin._start_dialogue()
	await _wait(0.2)
	var guard_n := 0
	while bool(padwin._dialogue_active) and not bool(padwin._waiting_for_choice) and guard_n < 8:
		_press_e(padwin)
		guard_n += 1
		await _wait(0.1)
	_check("推进到占卜选择点", bool(padwin._waiting_for_choice))

	# 选「好，我来为你抽一张牌。」（divine_offer 选项 0）→ action divine:padwin
	get_node("/root/EventBus").dialogue_choice_made.emit(0)
	await _wait(0.2)
	_check("等待确认 reply", bool(padwin._showing_reply))
	_press_e(padwin)   # 确认 → 结束对话 → game 分发 divine → 占卜面板打开
	await _wait(0.3)

	_check("占卜面板打开", div != null and bool(div._open))
	_check("占卜对象 = padwin", str(div._npc_id) == "padwin")
	_check("对应委托 id", str(div._quest_id) == "tarot_padwin_01")

	# -- 回归 #3：占卜面板打开后再连按一次 E，不得把 NPC 对话重新叠到弹窗上 --
	_press_e(padwin)   # 额外一次 E（复现文件证实修复前会 padwin._dialogue_active=true）
	await _wait(0.2)
	_check("弹窗下连按 E 不重开对话", not bool(padwin._dialogue_active))
	_check("占卜面板仍在", div != null and bool(div._open))

	# -- 解读文案三分支（纯函数）--
	_check("npc 专属解读命中",
		div.reading_for({"npc_readings": {"padwin": "A"}, "reading_to_person": "B", "reading": "C"}, "padwin") == "A")
	_check("对人物解读回落",
		div.reading_for({"reading_to_person": "B", "reading": "C"}, "padwin") == "B")
	_check("兜底原 reading",
		div.reading_for({"reading": "C"}, "padwin") == "C")

	# -- 注入单张牌，确定性抽牌 → 解读展示 --
	div._cards = [{
		"id": "crafted", "name": "XIX · 测试日",
		"npc_readings": {"padwin": "MARKER 专属：怀表停在黄昏。"},
		"reading_to_person": "fallback-B", "reading": "fallback-C",
	}]
	div._draw()
	await _wait(0.2)
	_check("抽牌展示牌名", div._card_name.text == "XIX · 测试日")
	_check("解读用 padwin 专属文案", div._reading_label.text == "MARKER 专属：怀表停在黄昏。")
	_check("进入把牌交给他态", bool(div._drawn) and div._action_btn.text == "把牌交给他")

	# -- 把牌交给他 → 任务完成 + 奖励落地 --
	var gold_before: int = gm.gold
	div._hand_over()
	await _wait(0.3)
	_check("任务完成", qm.is_completed("tarot_padwin_01"))
	_check("不再 active", not qm.is_active("tarot_padwin_01"))
	_check("金币 +30", gm.gold == gold_before + 30)
	_check("帕德温好感 50→60", int(gm.npc_affection.get("padwin", 0)) == 60)
	_check("故事解锁 flag", gm.has_flag("padwin_watch_resolved"))
	_check("active flag 清除", not gm.has_flag("quest_active_tarot_padwin_01"))
	_check("面板进入 ack 态", bool(div._done))
	div._close()
	await _wait(0.3)
	_check("占卜面板关闭", not bool(div._open))

	# -- 完成后再对话 → resolved 故事块（只播一次）--
	_check("完成后选中 resolved", str(padwin._select_dialogue().get("id", "")) == "resolved")
	padwin._start_dialogue()
	await _wait(0.2)
	for i in 4:   # resolved 4 行，播完自动收尾（end_effects 置 padwin_watch_spoken）
		_press_e(padwin)
		await _wait(0.1)
	_check("resolved 回放后 spoken 置位", gm.has_flag("padwin_watch_spoken"))
	_check("再对话回落 daily", str(padwin._select_dialogue().get("id", "")) == "daily")

	scene.queue_free()
	await _wait(0.3)

	print("[TAROTQ] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
