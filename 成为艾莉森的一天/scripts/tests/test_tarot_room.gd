extends Node

## 魔法桌 + 出门锁 冒烟测试 —— 验证塔罗从「开局自动弹」搬到「回小屋按 E 抽」。
## 用法：godot --headless scenes/tests/test_tarot_room.tscn
##
## 覆盖：
##   1. 第 1 天：抽不了牌（还没搬进小屋）
##   2. 第 2 天 + 已租房：循环重置后在小屋 WakeUp 醒来
##   3. 小屋里有魔法桌，走近出提示「[E] 抽今天的牌」
##   4. 没抽牌走到门口 → 出不去（门锁），弹提示
##   5. 桌前按 E → 开塔罗 → 抽牌 → tarot_drawn_today
##   6. 抽完再走到门口 → 正常出门

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 25.0
	guard.timeout.connect(func():
		printerr("[TAROTROOM] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TAROTROOM] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[TAROTROOM] FAIL  ", check_name)


func _finish() -> void:
	print("[TAROTROOM] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	var bridge: Node = get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)   # 离线：塔罗走数据牌，快速且确定性

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(0.3)

	var gm: Node = get_node("/root/GameManager")
	var tarot: Node = scene.get_node_or_null("TarotUI")
	var tarot_panel: Control = tarot.get("_panel") if tarot else null
	var player: Node = scene.get_node_or_null("Player")
	var room: Node = scene.get_node_or_null("Areas/AlisonRoom")
	var door: Node = room.get_node_or_null("DoorOut") if room else null
	var table: Node = room.get_node_or_null("MagicTable") if room else null
	var dlg: Node = scene.get_node_or_null("DialogueUI")
	var hint: Control = dlg.get("_interact_hint") if dlg else null

	_check("场景核心节点齐全", tarot != null and player != null and room != null
		and door != null and table != null)

	# 先把第一轮开场旁白翻完，免得它锁着玩家干扰后续
	var opening: Node = scene.get_node_or_null("OpeningUI")
	if opening and opening.is_playing():
		for i in 8:
			if not opening.is_playing():
				break
			opening._advance()
			await get_tree().process_frame
	_check("开场旁白已收屏（前置）", opening == null or not opening.is_playing())

	# ---- 1. 第 1 天抽不了牌 ----
	_check("第 1 天 current_day == 1", int(gm.current_day) == 1)
	if tarot:
		tarot.open()
		await get_tree().process_frame
	_check("第 1 天开不了塔罗", tarot_panel != null and not tarot_panel.visible)

	# ---- 2. 第 2 天 + 已租房 → 在小屋醒来 ----
	# switch_area 有 0.5s 门冷却（开局那一下会设上），冷却期内重置会被静默吞掉
	await _wait(0.6)
	gm.treehouse_rented = true
	gm.reset_loop()
	await get_tree().process_frame
	_check("第 2 天", int(gm.current_day) == 2)
	_check("当前区域是小屋", str(gm.current_area) == "alison_room")

	# 循环开场旁白是自动收的，翻掉它再验位置与交互
	if opening and opening.is_playing():
		for i in 8:
			if not opening.is_playing():
				break
			opening._advance()
			await get_tree().process_frame
	await _wait(0.6)   # 顺便等 switch_area 的 0.5s 门冷却过期

	var wake: Node2D = room.get_node_or_null("WakeUp")
	_check("出生在 WakeUp", wake != null
		and player.global_position.distance_to(wake.global_position) < 8.0)
	_check("魔法桌摆进了房间地板内",
		table != null and absf(table.global_position.x - 200.0) < 1.0
		and absf(table.global_position.y - 45.0) < 1.0)

	# ---- 3. 走近魔法桌出提示 ----
	player.global_position = table.global_position + Vector2(0, 30)
	await _wait(0.3)
	_check("桌前提示可见", hint != null and hint.visible)
	_check("提示文案正确", hint != null and hint.text == "[E] 抽今天的牌")

	# ---- 4. 没抽牌出不了门 ----
	player.global_position = door.global_position
	await _wait(0.4)
	_check("没抽牌出不了门", str(gm.current_area) == "alison_room")
	_check("离开桌前提示已收起", hint != null and not hint.visible)

	# ---- 5. 桌前按 E 抽牌 ----
	player.global_position = table.global_position + Vector2(0, 30)
	await _wait(0.4)
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	table._input(ev)
	await get_tree().process_frame
	_check("按 E 打开塔罗", tarot_panel != null and tarot_panel.visible)

	tarot._on_action()          # 抽牌（AI 已关 → 数据牌）
	await _wait(0.3)
	_check("抽牌后 tarot_drawn_today", bool(gm.tarot_drawn_today))
	_check("抽牌拿到牌名", str(gm.daily_tarot_card) != "")

	tarot._on_action()          # 收起面板
	await _wait(0.3)
	_check("面板已收起", tarot_panel != null and not tarot_panel.visible)

	# 抽完再按 E 不该重新弹（每天只弹一次）
	table._input(ev)
	await get_tree().process_frame
	_check("抽过当天不再弹塔罗", tarot_panel != null and not tarot_panel.visible)

	# ---- 6. 抽完可以出门 ----
	player.global_position = door.global_position
	await _wait(0.6)
	_check("抽牌后可以出门", str(gm.current_area) == "treehouse_district")

	_finish()
