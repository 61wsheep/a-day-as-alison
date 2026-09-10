extends Node

## 采集刷新优化测试 — 蘑菇/浆果只在草坪（非路面）出现、浆果当天固定点位再结。
## 用 SceneLayout.is_grass_tile（td.terrain==2 草地）判定，复用主场景真实采集路径。

const SceneLayout := preload("res://scripts/systems/scene_layout.gd")

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[FORAGE] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[FORAGE] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[FORAGE] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var inv: Node = get_node("/root/Inventory")
	# 清空以便确定性计数
	for id in ["berry", "mushroom"]:
		if inv.has(id):
			inv.remove(id, inv.count_of(id))

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)
	# 翻完开场旁白（播放期间玩家锁着）；塔罗已挪进艾莉森小屋，开局不再自动弹
	await TestHelpers.dismiss_opening(scene)

	var ground: TileMapLayer = scene.get_node_or_null("Areas/Plaza/Ground")
	_check("找到广场地面", ground != null)
	if ground == null:
		get_tree().quit(1)
		return

	# -- 初始落点都在草坪 --
	var initial_spots := [
		["Mushroom1", "Areas/Plaza/Mushrooms/Mushroom1"],
		["Mushroom2", "Areas/Plaza/Mushrooms/Mushroom2"],
		["Mushroom3", "Areas/Plaza/Mushrooms/Mushroom3"],
		["Berry1", "Areas/Plaza/Berries/Berry1"],
		["Berry2", "Areas/Plaza/Berries/Berry2"],
		["Berry3", "Areas/Plaza/Berries/Berry3"],
		["Berry4", "Areas/Plaza/Berries/Berry4"],
	]
	for pair in initial_spots:
		var node: Node2D = scene.get_node_or_null(pair[1])
		var on_grass := node != null and SceneLayout.is_grass_tile(ground, node.global_position)
		_check("%s 落在草坪" % pair[0], on_grass)

	# -- 蘑菇随机草坪刷：多次采样全在草 --
	var all_grass := true
	for i in 25:
		var p: Vector2 = scene._random_grass_pos()
		if not SceneLayout.is_grass_tile(ground, p):
			all_grass = false
			printerr("[FORAGE] 非草坪采样点 ", p)
	_check("蘑菇随机采样 25 次均在草坪", all_grass)

	# -- 路面点必须被判为非草（对拍：主路中心应为 false）--
	_check("主路中心非草坪", not SceneLayout.is_grass_tile(ground, Vector2(640, 384)))

	# -- 浆果当天再结：采集后隐藏，约 regrow 时间后原位重新出现可再采 --
	var berry: Node = scene.get_node_or_null("Areas/Plaza/Berries/Berry1")
	_check("找到浆果丛", berry != null and berry is Area2D)
	if berry == null:
		get_tree().quit(1)
		return
	berry.regrow_seconds = 0.1   # 测试加速：正常为 25s
	berry.show()
	berry.monitoring = true
	var cnt_before: int = inv.count_of("berry")
	berry._try_collect()
	var got_after: int = inv.count_of("berry")
	var collected := got_after == cnt_before + 1
	_check("采集浆果进背包", collected)
	_check("采集后隐藏", not berry.visible)
	if collected:
		await _wait(0.6)   # 0.1×(0.8~1.2) 秒后应再结
		_check("浆果在原位再结（重新可见）", berry.visible)
		_check("再结后可再采集（monitoring 恢复）", bool(berry.monitoring))
		var cnt2: int = inv.count_of("berry")
		berry._try_collect()
		_check("再结后能再次采到", inv.count_of("berry") == cnt2 + 1)
	else:
		_check("浆果在原位再结（重新可见）", false)
		_check("再结后可再采集（monitoring 恢复）", false)

	scene.queue_free()
	await _wait(0.3)

	print("[FORAGE] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
