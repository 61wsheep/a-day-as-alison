extends Node

## 自动化回归测试 — 驱动完整游戏流程并截图。
## 运行方式：godot scenes/autotest.tscn
## 截图输出到 D:/AIGameBuild/_preview/shots/

const SHOT_DIR := "D:/AIGameBuild/_preview/shots/"

var _player: Node2D
var _bus: Node
var _gm: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_bus = get_node("/root/EventBus")
	_gm = get_node("/root/GameManager")
	_player = get_tree().get_first_node_in_group("player")
	await get_tree().create_timer(1.5).timeout
	_run()


func _press_e() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_E
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + shot_name + ".png")
	print("[AUTOTEST] shot: ", shot_name)


func _find_npc(id: String) -> NPCBase:
	for n in get_tree().root.find_children("*", "NPCBase", true, false):
		if n.npc_id == id:
			return n
	return null


func _find_by_name(sub: String) -> Node:
	for n in get_tree().root.find_children("*", "Node", true, false):
		if sub in n.name:
			return n
	return null


func _goto(pos: Vector2) -> void:
	_player.global_position = pos
	await get_tree().create_timer(0.6).timeout
	print("[AUTOTEST] goto", pos, " -> player@", _player.global_position, " area=", _gm.current_area)


## 与一个 NPC 完成整段对话；choices 为依次要选的选项下标。
## shot_name 非空时，在对话第一行出现后截图。
func _talk(npc: NPCBase, picks: Array, shot_name: String = "") -> void:
	if npc == null:
		print("[AUTOTEST][FAIL] NPC 不存在")
		return
	await _press_e()
	await get_tree().create_timer(0.5).timeout
	if not npc._dialogue_active:
		print("[AUTOTEST][FAIL] 对话未开始: ", npc.npc_id)
		return
	if shot_name != "":
		await _shot(shot_name)
	var pick_idx := 0
	var guard := 0
	while npc._dialogue_active and guard < 80:
		if npc._waiting_for_choice:
			var pick: int = picks[min(pick_idx, picks.size() - 1)]
			pick_idx += 1
			_bus.dialogue_choice_made.emit(pick)
			await get_tree().create_timer(0.4).timeout
		else:
			await _press_e()
			await get_tree().create_timer(0.3).timeout
		guard += 1
	if npc._dialogue_active:
		print("[AUTOTEST][FAIL] 对话未能结束: ", npc.npc_id)
	print("[AUTOTEST] flags=", _gm.flags, " clues=", _gm.clues_found)


func _run() -> void:
	# 1. 塔罗开场
	await _shot("01_tarot_open")
	var tarot := _find_by_name("Tarot")
	if tarot and tarot.has_method("_on_action"):
		tarot._on_action()  # 抽牌
		await get_tree().create_timer(0.4).timeout
		await _shot("02_tarot_card")
		tarot._on_action()  # 开始今天
		await get_tree().create_timer(0.4).timeout
	else:
		print("[AUTOTEST][FAIL] 找不到 TarotUI")
	print("[AUTOTEST] tarot=", _gm.daily_tarot_card, " luck=", _gm.daily_luck)
	await _shot("03_plaza")

	# 2. 索拉雅对话
	await _goto(Vector2(640, 350))
	await _talk(_find_npc("soraya"), [0], "04_soraya_dialogue")
	await _shot("05_after_soraya")

	# 3. 东门 → 树屋区
	await _goto(Vector2(1246, 384))
	await get_tree().create_timer(0.6).timeout
	print("[AUTOTEST] area=", _gm.current_area, " (期望 treehouse_district)")
	await _shot("06_treehouse")

	# 4. 帕德温对话
	await _goto(Vector2(500, 450))
	await _talk(_find_npc("padwin"), [0], "07_padwin_dialogue")

	# 5. 卡克特斯主教对话
	await _goto(Vector2(820, 440))
	await _talk(_find_npc("cactus_bishop"), [0], "08_cactus_dialogue")

	# 6. 租房（给足金币）
	_gm.gold = 300
	await _goto(Vector2(300, 330))
	await _press_e()
	await get_tree().create_timer(0.5).timeout
	await _shot("09_rental_ui")
	var rental := _find_by_name("Rental")
	if rental and rental.has_method("_on_rent"):
		rental._on_rent()
		await get_tree().create_timer(0.4).timeout
		print("[AUTOTEST] rented=", _gm.treehouse_rented, " house=", _gm.treehouse, " gold=", _gm.gold)
	else:
		print("[AUTOTEST][FAIL] 找不到 RentalUI")
	if rental and rental.has_method("_close"):
		rental._close()

	# 7. 快进到午夜
	get_node("/root/TimeManager").skip_to_midnight()
	await get_tree().create_timer(0.8).timeout
	await _shot("10_midnight")
	var main := _find_by_name("Main")
	if main and main.has_method("_do_sleep"):
		pass  # 不入睡——去塔楼触发结局

	# 8. 回广场 → 西门 → 塔楼
	await _goto(Vector2(22, 416))  # 树屋区西门回广场
	await get_tree().create_timer(0.6).timeout
	await _goto(Vector2(22, 384))  # 广场西门进塔楼
	await get_tree().create_timer(0.6).timeout
	print("[AUTOTEST] area=", _gm.current_area, " (期望 stone_nest_tower)")
	await _shot("11_tower")

	# 9. 祭坛问答 → 结局
	await _goto(Vector2(640, 300))
	await _talk(_find_npc("tian"), [0], "12_tower_qa")
	await get_tree().create_timer(1.0).timeout
	await _shot("13_ending")

	# 10. 确认结局 → 循环重置到 Day 2
	var ending := _find_by_name("Ending")
	if ending and ending.has_method("_on_confirm"):
		ending._on_confirm()
		await get_tree().create_timer(1.0).timeout
		print("[AUTOTEST] day=", _gm.current_day, " (期望 2)")
		await _shot("14_day2")
	else:
		print("[AUTOTEST][FAIL] 找不到 EndingUI")

	print("[AUTOTEST] DONE endings=", _gm.endings_unlocked)
	get_tree().quit()
