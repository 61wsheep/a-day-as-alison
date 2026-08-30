extends Node

## 入睡门控回归测试 —— 验证「只有租了树屋才能入睡」。
## 用法：godot --headless scenes/tests/test_sleep_no_house.tscn
##
## 覆盖：
##   1. 未租房到午夜 → 面板弹出但入睡按钮禁用，_do_sleep 不生效（天数不变）
##   2. 午夜面板被对话顶掉后，对话结束自动补回
##   3. 午夜现场租房 → 面板刷新、按钮解锁 → 两阶段入睡进入次日

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 25.0
	guard.timeout.connect(func():
		printerr("[SLEEP] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[SLEEP] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[SLEEP] FAIL  ", check_name)


func _run() -> void:
	var bridge: Node = get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)   # 离线：审判走回落文案，快速且确定性
	var gm: Node = get_node("/root/GameManager")
	gm.treehouse_rented = false
	gm.treehouse = ""

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)

	# 关掉晨间塔罗（抽牌 → 开始今天），避免遮挡午夜面板
	var tarot: Node = scene.get_node_or_null("TarotUI")
	if tarot and tarot.has_method("_on_action"):
		tarot._on_action()
		await _wait(0.3)
		tarot._on_action()
		await _wait(0.3)

	_check("初始未租房", not gm.treehouse_rented)
	_check("初始为第 1 天", int(gm.current_day) == 1)

	# ---- 阶段 1：未租房到午夜 → 不能入睡 ----
	get_node("/root/TimeManager").skip_to_midnight()
	await _wait(0.5)
	var panel: CanvasLayer = scene.get("_midnight_panel")
	var btn: Button = scene.get("_midnight_btn")
	_check("未租房午夜面板弹出", panel != null and panel.visible)
	_check("未租房入睡按钮禁用", btn != null and btn.disabled)
	scene._do_sleep()   # 兜底路径也不应生效
	await _wait(0.3)
	_check("未租房 _do_sleep 不生效（仍为第 1 天）", int(gm.current_day) == 1)

	# ---- 阶段 2：面板被对话顶掉 → 对话结束自动补回 ----
	var bus: Node = get_node("/root/EventBus")
	bus.dialogue_started.emit()
	await _wait(0.2)
	_check("对话顶掉入睡面板", not panel.visible)
	bus.dialogue_ended.emit()
	await _wait(0.2)
	_check("对话结束后面板自动补回", panel.visible)
	_check("补回后按钮仍禁用（未租房）", btn.disabled)

	# ---- 阶段 3：午夜现场租房 → 解锁入睡 ----
	gm.treehouse_rented = true
	gm.treehouse = "oak"
	bus.dialogue_started.emit()   # 模拟打开/关闭租赁界面
	await _wait(0.2)
	bus.dialogue_ended.emit()
	await _wait(0.2)
	_check("租房后面板补回且按钮解锁", panel.visible and not btn.disabled)

	scene._do_sleep()   # 第一次：审判复盘（AI 关闭 → 立即回落）
	await _wait(0.8)
	_check("审判复盘已展示", bool(scene.get("_judgment_shown")))
	scene._do_sleep()   # 第二次：真正入睡
	await _wait(0.8)
	_check("租房后可入睡进入第 2 天", int(gm.current_day) == 2)

	print("[SLEEP] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
