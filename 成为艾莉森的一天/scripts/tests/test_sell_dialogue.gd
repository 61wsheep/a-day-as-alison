extends Node

## 售卖入口测试（玩家主动，#3/#4）—— 携带采集品时不再自动触发收购对话；
## 对话内出现「卖点东西」入口（_can_sell_here），按下 → sell_requested → SellPanel 打开。

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[SELLDLG] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[SELLDLG] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[SELLDLG] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var inv: Node = get_node("/root/Inventory")
	var gm: Node = get_node("/root/GameManager")

	inv.add("mushroom", 2)
	gm.set_flag("met_soraya")   # 正常流程：见过索拉雅后
	_check("背包有蘑菇", inv.has("mushroom"))

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)

	# 翻完开场旁白（播放期间玩家锁着）；塔罗已挪进艾莉森小屋，开局不再自动弹
	await TestHelpers.dismiss_opening(scene)
	gm.daily_luck = 1

	var soraya: Node = scene.get_node_or_null("Areas/Plaza/Soraya")
	_check("找到索拉雅", soraya != null)
	if soraya == null:
		get_tree().quit(1)
		return

	var player := get_tree().get_first_node_in_group("player")
	soraya._on_body_entered(player)
	soraya._start_dialogue()
	await _wait(0.3)

	# 移除自动收购对话后：即使背包有采集品，选中的也是日常对话而非 sell
	var selected: Dictionary = soraya._select_dialogue()
	_check("不再自动触发收购对话（回落到 daily 池）", str(selected.get("id", "")).begins_with("daily_"))

	# 对话 UI 提供「卖点东西」入口
	var dlg_ui: Node = scene.get_node("DialogueUI")
	_check("对话内提供卖点入口", dlg_ui._can_sell_here())

	# 按下卖点 → sell_requested → 结束对话 → SellPanel 打开
	get_node("/root/EventBus").sell_requested.emit()
	await _wait(0.5)
	var sell: Node = scene.get_node_or_null("SellPanel")
	_check("SellPanel 已打开", sell != null and bool(sell._open))
	if sell and sell._open:
		_check("面板列出蘑菇", sell._rows.has("mushroom"))
		_check("蘑菇行有数量选择框", sell._rows["mushroom"].get("spin", null) != null)
		(sell as Node)._close()

	# 无采集品时卖点入口消失
	var n: int = inv.count_of("mushroom")
	if n > 0:
		inv.remove("mushroom", n)
	_check("清空后无卖点入口", not dlg_ui._can_sell_here())

	scene.queue_free()
	await _wait(0.3)

	print("[SELLDLG] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
