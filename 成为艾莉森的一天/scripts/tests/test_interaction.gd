extends Node

## 交互反馈测试（#1/#2）—— 浆果点 item_id 正确、采集提示 show/hide、
## E 键采集进背包、按键帮助面板（K）开关与移动锁定。

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[INT] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[INT] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[INT] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var inv: Node = get_node("/root/Inventory")

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)

	var tarot: Node = scene.get_node_or_null("TarotUI")
	if tarot and tarot.has_method("_on_action"):
		tarot._on_action()
		await _wait(0.3)
		tarot._on_action()
		await _wait(0.3)

	var plaza: Node = scene.get_node("Areas/Plaza")
	var dlg_ui: Node = scene.get_node("DialogueUI")
	var player := get_tree().get_first_node_in_group("player")

	# -- 1. 浆果点/蘑菇点 item_id 正确（修复 #1 的核心）--
	var berry: Node = plaza.get_node("Berries/Berry1")
	var mushroom: Node = plaza.get_node("Mushrooms/Mushroom1")
	_check("浆果点 item_id=berry", str(berry.item_id) == "berry")
	_check("蘑菇点 item_id=mushroom", str(mushroom.item_id) == "mushroom")

	# -- 2. 靠近浆果 → 右下角采集提示；离开 → 隐藏 --
	berry.show()
	berry.monitoring = true
	berry._on_body_entered(player)
	await _wait(0.1)
	_check("靠近浆果显示采集提示", dlg_ui._collect_hint.visible)
	_check("提示文本含浆果名", str(dlg_ui._collect_hint.text).contains("红浆果"))
	berry._on_body_exited(player)
	await _wait(0.1)
	_check("离开后采集提示隐藏", not dlg_ui._collect_hint.visible)

	# -- 3. E 键采集：靠近 + 按 E（_unhandled_input）→ 进背包且消失 --
	var before: int = inv.count_of("berry")
	berry.show()
	berry.monitoring = true
	berry._on_body_entered(player)
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.physical_keycode = KEY_E
	ev.pressed = true
	berry._unhandled_input(ev)
	_check("按 E 采集进背包", inv.count_of("berry") == before + 1)
	_check("采集后隐藏消失", not berry.visible)
	# 已采集的浆果不再响应
	berry._unhandled_input(ev)
	_check("采集后再次按 E 不重复", inv.count_of("berry") == before + 1)

	# -- 4. 按键帮助面板：K 开关 + 移动锁定 --
	var kp: Node = scene.get_node_or_null("KeybindPanel")
	_check("KeybindPanel 已挂入主场景", kp != null)
	if kp == null:
		get_tree().quit(1)
		return
	_check("右上角按键提示存在", kp._chip != null and bool(kp._chip.visible))
	kp._toggle()
	await _wait(0.2)
	_check("按键面板打开", kp.is_open())
	_check("打开时锁定玩家移动", bool(player._movement_locked))
	_check("面板列出移动/背包等条目", kp._rows.get_child_count() >= 5)
	kp._toggle()
	await _wait(0.2)
	_check("按键面板关闭", not kp.is_open())
	_check("关闭后解锁移动", not bool(player._movement_locked))

	scene.queue_free()
	await _wait(0.3)

	print("[INT] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
