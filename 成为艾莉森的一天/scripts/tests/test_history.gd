extends Node

## 历史对话（完整实录）端到端测试 — 装主场景 → 与帕德温推进 daily 台词 →
## 实录写入 DialogueLog → 靠近按 H 打开 HistoryPanel → 逐天分组展示 → Esc 关闭解锁。
## 复用 npc_base 真实输入路径（_start_dialogue + 合成 E 键推进）。
## daily 标记 ai:true，测试环境禁用 AIBridge 走 JSON 路径（确定性）。

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		printerr("[HIST] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[HIST] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[HIST] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _make_e() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	return ev


func _make_h() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_H
	ev.pressed = true
	return ev


func _make_esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _press_e(npc: Node) -> void:
	npc._player_in_range = true
	npc._input(_make_e())


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var gm: Node = get_node("/root/GameManager")
	var log: Node = get_node("/root/DialogueLog")
	log.set_storage_path("user://dialogue_log.test.json")   # 测试隔离盘，不碰真机历史
	log.clear_all()

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

	var padwin: Node = scene.get_node_or_null("Areas/TreehouseDistrict/Padwin")
	var hp: Node = scene.get_node_or_null("HistoryPanel")
	_check("找到帕德温", padwin != null)
	_check("HistoryPanel 挂入主场景", hp != null)
	if padwin == null or hp == null:
		get_tree().quit(1)
		return

	# -- 与帕德温走 daily 台词：met_padwin 置位 → 无委托时选中 daily --
	gm.set_flag("met_padwin")
	_check("对话选中 daily", str(padwin._select_dialogue().get("id", "")) == "daily")
	padwin._start_dialogue()
	await _wait(0.2)
	for i in 6:   # daily 3 行；对话一旦自然收尾即停，多出的 E 会重开对话（勿喂）
		if not bool(padwin._dialogue_active):
			break
		_press_e(padwin)
		await _wait(0.1)
	_check("daily 对话已结束", not bool(padwin._dialogue_active))

	# -- 实录写入校验 --
	var entries: Array = log.for_npc("padwin")
	_check("padwin 实录非空", entries.size() >= 3)
	var has_npc_line := false
	var has_player_line := false
	var has_day := true
	for e in entries:
		if str(e.get("speaker", "")) == "player":
			has_player_line = true
			_check("player 行显示名=艾莉森", str(e.get("display", "")) == "艾莉森")
		else:
			has_npc_line = true
		_check("每行带天数", int(e.get("day", -1)) >= 1)
		if str(e.get("text", "")).strip_edges() == "":
			has_day = false
	_check("含 NPC 台词行", has_npc_line)
	_check("含艾莉森台词行", has_player_line)
	_check("无空文本行", has_day)
	# 分 NPC：从未对话的索拉雅应为空
	_check("索拉雅实录为空（分 NPC 隔离）", log.for_npc("soraya").is_empty())

	# -- 靠近按 H → HistoryPanel 打开（走 event_bus history_requested 真实路径）--
	hp._close()
	_check("打开前面板关闭", not bool(hp.is_open()))
	padwin._player_in_range = true
	var player := get_tree().get_first_node_in_group("player")
	player._movement_locked = false
	padwin._input(_make_h())
	await _wait(0.2)
	_check("H 打开历史面板", bool(hp.is_open()))
	_check("面板标题含帕德温", str(hp._title.text).contains("帕德温"))
	var body_text := str(hp._body.get_parsed_text())
	_check("面板含第 N 天分组", body_text.contains("第"))
	_check("面板含实际台词", body_text.contains("租金") or body_text.contains("帕德温"))
	_check("打开时锁定玩家移动", bool(player._movement_locked))

	# -- Esc 关闭 → 解锁 --
	hp._unhandled_input(_make_esc())
	await _wait(0.2)
	_check("Esc 关闭面板", not bool(hp.is_open()))
	_check("关闭后解锁移动", not bool(player._movement_locked))

	# -- 回归：跨进程持久化（根因：实录曾是纯内存态，重开游戏后 H 面板永远空白）--
	# 实录已随每次 append 写穿到测试盘。模拟"重开游戏"：清空内存 → 从磁盘 reload
	#（等价于新进程 _ready 的 _load）→ 历史应原样恢复。
	var log3: Node = get_node("/root/DialogueLog")
	_check("实录已写穿到磁盘", FileAccess.file_exists("user://dialogue_log.test.json"))
	var before_reload: int = log3.for_npc("padwin").size()
	log3.logs.clear()   # 只清内存，不清盘
	_check("模拟重启：内存实录已空", log3.for_npc("padwin").is_empty())
	log3.reload()
	_check("重启后从磁盘恢复实录",
		log3.for_npc("padwin").size() >= before_reload and log3.for_npc("padwin").size() >= 3)
	log3.clear_all()   # 收尾：清空测试盘，避免残留影响下次运行

	# 收尾后 H 打开 → 面板显示"尚无记录"空态提示，而不是白屏/崩溃
	player._movement_locked = false
	padwin._player_in_range = true
	padwin._input(_make_h())
	await _wait(0.2)
	_check("空历史时面板显示提示文案", str(hp._body.get_parsed_text()).contains("还没有与"))
	hp._unhandled_input(_make_esc())
	await _wait(0.2)

	scene.queue_free()
	await _wait(0.3)

	print("[HIST] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
