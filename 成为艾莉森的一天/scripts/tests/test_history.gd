extends Node

## 历史对话（完整实录）端到端测试 — 装主场景 → 与帕德温推进 daily 台词 →
## 实录写入 DialogueLog → 靠近按 H 打开 HistoryPanel → 逐天分组展示 → Esc 关闭解锁。
## 复用 npc_base 真实输入路径（_start_dialogue + 合成 E 键推进）。
## daily 标记 ai:true，测试环境禁用 AIBridge 走 JSON 路径（确定性）。

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

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


## 读文件全文；不存在/打不开返回空串。
func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _press_e(npc: Node) -> void:
	npc._player_in_range = true
	npc._input(_make_e())


## 该条台词所挂的好感度变化量（找不到该行 / 该行无标注 → 0）。
func _aff_of(log: Node, npc_id: String, text: String) -> int:
	for e in log.for_npc(npc_id):
		if str(e.get("text", "")).contains(text):
			return int(e.get("affection", 0))
	return 0


## 该 NPC 实录里带好感标注的行数（验证标注只贴一次）。
func _aff_count(log: Node, npc_id: String) -> int:
	var n := 0
	for e in log.for_npc(npc_id):
		if int(e.get("affection", 0)) != 0:
			n += 1
	return n


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var gm: Node = get_node("/root/GameManager")
	var bus: Node = get_node("/root/EventBus")
	var log: Node = get_node("/root/DialogueLog")
	log.clear_all()   # 本轮纯内存实录，无盘可清，只清内存即可
	# 快照 user:// 默认实录文件（可能是旧版"自动落盘"在真机留下的）：新版实录纯内存，
	# 本轮不得新增/改动它 —— 若未来有人把自动落盘加回来，这里会 FAIL 拦住。
	var real_path := "user://dialogue_log.json"
	var real_before: String = _file_text(real_path)
	# 清掉旧版测试遗留的测试盘（旧代码 set_storage_path 会写穿它），确保下方
	# "本轮不写盘"断言确定性成立。
	if FileAccess.file_exists("user://dialogue_log.test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://dialogue_log.test.json"))

	# -- 装主场景 --
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
		get_tree().quit(1)
		return

	# -- 与帕德温走 L2 回落台词：met_padwin 置位 → 无委托时从 daily_a/b/c 池里轮选 --
	gm.set_flag("met_padwin")
	_check("对话选中 daily 池", str(padwin._select_dialogue().get("id", "")).begins_with("daily_"))
	padwin._start_dialogue()
	await _wait(0.2)
	for i in 6:   # 池中每条 2~3 行；对话一旦自然收尾即停，多出的 E 会重开对话（勿喂）
		if not bool(padwin._dialogue_active):
			break
		_press_e(padwin)
		await _wait(0.1)
	_check("daily 对话已结束", not bool(padwin._dialogue_active))

	# -- 实录写入校验 --
	# 断言下限跟着 L2 池走：池里大多是 2 行条目（padwin 14/15 条为 2 行），
	# 原来的 >=3 是按旧的三行 daily 写的，池落地当天就成了随机红。
	var entries: Array = log.for_npc("padwin")
	_check("padwin 实录非空", entries.size() >= 2)
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

	# -- 脚本固定对话的好感度标注：选项 effects.affection 必须落在它引出的那句回复上 --
	# _on_choice_made 的顺序是 apply_effects → _emit_line，所以标注跟在 NPC 回复行，
	# 不是玩家选的选项行（选项行先于结算记录，本就该无标注）。
	# 索拉雅 intro 第 3 个选项 effects.affection=+5（她初始 55）。
	var soraya: Node = scene.get_node_or_null("Areas/Plaza/Soraya")
	_check("找到索拉雅", soraya != null)
	if soraya != null:
		_check("索拉雅对话选中 intro", str(soraya._select_dialogue().get("id", "")) == "intro")
		soraya._start_dialogue()
		await _wait(0.2)
		_press_e(soraya)   # 第 2 行：旁白
		await _wait(0.1)
		_press_e(soraya)   # 第 3 行：玩家行 + 三选项 → 弹选项
		await _wait(0.1)
		_check("选项行已就绪待选", bool(soraya._waiting_for_choice))
		bus.dialogue_choice_made.emit(2)
		await _wait(0.2)
		_check("脚本选项的好感变化挂在其回复行上",
			_aff_of(log, "soraya", "每一个来到这里的人") == 5)
		_check("玩家选项行本身不带好感标注",
			_aff_of(log, "soraya", "我叫艾莉森") == 0)
		# 收场 end_effects(+5) 已无下文台词可挂：应随 dialogue_ended 清空，不得残留到后续行
		soraya._end_dialogue()
		await _wait(0.2)
		_check("脚本对话的好感标注行数=1（不重复贴）",
			_aff_count(log, "soraya") == 1)

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
	# 回归：正文必须有实际渲染高度——缺 fit_content 时 RichTextLabel 在 ScrollContainer
	# 内高度塌成 0（真机正文一片空白，headless get_parsed_text 却仍返回全文，测不出）。
	await get_tree().process_frame
	await get_tree().process_frame
	var body_min_h: float = hp._body.get_minimum_size().y
	var body_h: float = hp._body.size.y
	print("[HIST] body 渲染高度 min=%.0f actual=%.0f" % [body_min_h, body_h])
	_check("面板正文实际渲染高度>0（防塌陷）", body_min_h > 10.0 or body_h > 10.0)

	# -- Esc 关闭 → 解锁 --
	hp._unhandled_input(_make_esc())
	await _wait(0.2)
	_check("Esc 关闭面板", not bool(hp.is_open()))
	_check("关闭后解锁移动", not bool(player._movement_locked))

	# -- 回归：实录 = 本轮次纯内存，不落盘（无存档系统前不跨启动）--
	# 需求：历史只显示这一轮次玩过的内容，关游戏即清空；等存档系统落地后随档读写。
	# 模拟"下一次启动"：新建一份 DialogueLog（等价于新进程初始态）→ 应从空开始，
	# 上一进程内存里的 padwin 实录带不过来；且本轮全程不写任何盘。
	var fresh_log: Node = (load("res://scripts/autoload/dialogue_log.gd") as GDScript).new()
	_check("新一轮次实录从空开始（不跨启动）", fresh_log.for_npc("padwin").is_empty())
	_check("本轮实录不写盘（关游戏即清空）", not FileAccess.file_exists("user://dialogue_log.test.json"))
	_check("本轮不新增/改动默认实录文件", _file_text(real_path) == real_before)
	# 存档接入点仍可用：serialize 导出当前轮实录，deserialize 随档还原（未来随档读写）。
	var dumped: Dictionary = log.serialize()
	var in_dump: int = (dumped.get("padwin", []) as Array).size()
	_check("存档接口 serialize 可导出实录", in_dump >= 2)
	fresh_log.deserialize(dumped)
	_check("存档接口 deserialize 可还原实录", fresh_log.for_npc("padwin").size() >= 2)
	# 好感度标注是行的一部分，随档往返不能丢（否则读档后历史里看不到涨跌）
	_check("存档往返保留好感度标注字段",
		fresh_log.for_npc("padwin")[0].has("affection")
			and int(fresh_log.for_npc("padwin")[0]["affection"]) == int(log.for_npc("padwin")[0]["affection"]))
	fresh_log.free()
	log.clear_all()   # 收尾：清空本轮内存，模拟关闭游戏 → 下文空态提示

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
