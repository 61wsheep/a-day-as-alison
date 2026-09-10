extends Node

## 状态面板（Tab）回归测试 —— 开合、内容快照、对话中禁开、移动锁定。
## 用法：godot --headless scenes/tests/test_status_panel.tscn

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[PANEL] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[PANEL] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[PANEL] FAIL  ", check_name)


func _press_tab() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_TAB
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _run() -> void:
	var bridge: Node = get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var gm: Node = get_node("/root/GameManager")

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)

	# 翻完开场旁白（播放期间玩家锁着）；塔罗已挪进艾莉森小屋，开局不再自动弹
	await TestHelpers.dismiss_opening(scene)

	var panel: Node = scene.get_node_or_null("StatusPanel")
	_check("StatusPanel 已挂入主场景", panel != null)
	if panel == null:
		get_tree().quit(1)
		return

	# 造数据：一条线索 + 好感度变化
	gm.discover_clue("clue_padwin_no_memory")
	gm.change_affection("padwin", 20)
	await _wait(0.2)

	_check("初始关闭", not panel.is_open())
	_press_tab()
	await _wait(0.3)
	_check("Tab 打开面板", panel.is_open())

	var player: Node = get_tree().get_first_node_in_group("player")
	_check("打开时锁定玩家移动", player != null and bool(player._movement_locked))

	# 内容快照包含线索与好感度
	_texts = ""
	_collect_text(panel)
	_check("面板显示线索名", "帕德温没有前世的记忆" in _texts)
	_check("面板显示好感度数值", "70/100" in _texts)

	_press_tab()
	await _wait(0.3)
	_check("Tab 再按关闭", not panel.is_open())
	_check("关闭后解锁移动", player != null and not bool(player._movement_locked))

	# 对话中禁开
	var bus: Node = get_node("/root/EventBus")
	bus.dialogue_started.emit()
	await _wait(0.2)
	_press_tab()
	await _wait(0.3)
	_check("对话中 Tab 不打开", not panel.is_open())
	bus.dialogue_ended.emit()

	print("[PANEL] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


var _texts := ""


func _collect_text(node: Node) -> void:
	if node is Label:
		_texts += node.text + "\n"
	for c in node.get_children():
		_collect_text(c)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
