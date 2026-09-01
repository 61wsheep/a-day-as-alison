extends Node

## 采集→售卖全流程测试 — 拾取进背包、售卖价公式（daily_luck 系数）、
## 金币/物品/信号正确、对话 has_kind 条件。
## 驱动真实 SellPanel（主场景实例化），非只测纯函数。
## 用法：godot --headless scenes/tests/test_forage_sell.tscn

const ItemDB := preload("res://scripts/systems/item_db.gd")

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[SELL] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[SELL] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[SELL] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)
	var inv: Node = get_node("/root/Inventory")
	var gm: Node = get_node("/root/GameManager")

	# -- 定价公式（纯函数，daily_luck 系数生效）--
	_check("luck=1 蘑菇=12", ItemDB.calc_sell_price("mushroom", 1) == 12)
	_check("luck=0 蘑菇=10", ItemDB.calc_sell_price("mushroom", 0) == 10)
	_check("luck=-1 蘑菇=8", ItemDB.calc_sell_price("mushroom", -1) == 8)
	_check("luck=1 浆果=7（四舍五入）", ItemDB.calc_sell_price("berry", 1) == 7)

	# -- 模拟采集：进背包，不直接加钱 --
	var gold_before: int = gm.gold
	_check("拾取蘑菇×3", inv.add("mushroom", 3))
	_check("拾取浆果×2", inv.add("berry", 2))
	_check("采集不改金币（进背包而非加钱）", gm.gold == gold_before)

	# -- 加载主场景，驱动真实 SellPanel --
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)
	# 关掉晨间塔罗（它抽牌会覆盖 daily_luck 与 dialogue_started）
	var tarot: Node = scene.get_node_or_null("TarotUI")
	if tarot and tarot.has_method("_on_action"):
		tarot._on_action()
		await _wait(0.3)
		tarot._on_action()
		await _wait(0.3)

	# 塔罗抽完后再定吉凶，锁死 luck=1 供定价断言
	gm.daily_luck = 1

	var sell: Node = scene.get_node_or_null("SellPanel")
	_check("SellPanel 已挂入主场景", sell != null)
	if sell == null:
		get_tree().quit(1)
		return

	var sold_events: Array = []
	get_node("/root/EventBus").item_sold.connect(
		func(id: String, count: int, price: int) -> void:
			sold_events.append({"id": id, "count": count, "price": price}))

	sell.open()
	_check("面板列出 2 种可卖品", sell._rows.size() == 2)
	# 每行都有数量 SpinBox，默认=持有数（勾选即卖整类，兼容旧行为）
	var berry_row: Dictionary = sell._rows.get("berry", {})
	var berry_spin: SpinBox = berry_row.get("spin", null) as SpinBox
	_check("浆果行有数量选择框", berry_spin != null)
	if berry_spin:
		_check("数量默认=持有数 2", int(berry_spin.value) == 2)
		_check("数量上限=持有数 2", int(berry_spin.max_value) == 2)

	# -- 部分卖出：勾选浆果，只卖 1 颗 --
	(berry_row["check"] as CheckButton).button_pressed = true
	berry_spin.value = 1
	sell._on_sell()
	_check("部分卖出后浆果剩 1", inv.count_of("berry") == 1)
	_check("蘑菇未动仍 3", inv.count_of("mushroom") == 3)
	_check("金币 +7（1×7）", gm.gold == gold_before + 7)

	# -- 全选（默认整类）→ 卖出剩余 --
	for row in sell._rows.values():
		(row["check"] as CheckButton).button_pressed = true
	sell._on_sell()
	_check("卖出后蘑菇清空", not inv.has("mushroom"))
	_check("卖出后浆果清空", not inv.has("berry"))
	_check("金币累计 +50（7 + 3×12 + 1×7）", gm.gold == gold_before + 50)
	_check("item_sold 发 3 次", sold_events.size() == 3)
	var total_price := 0
	for ev in sold_events:
		total_price += int(ev["price"])
	_check("item_sold 合计=50", total_price == 50)
	_check("卖空后 has_kind 条件失效", not gm.conditions_met({"has_kind": ["forage"]}))

	# -- 真实采集路径：靠近（body_entered）→ 按 E（_try_collect）→ 进背包 --
	var pool: Node = scene.get_node_or_null("Areas/Plaza/Mushrooms")
	if pool and pool.get_child_count() > 0:
		var collect: Node = pool.get_child(0)
		var target_id: String = str(collect.item_id)
		var before: int = inv.count_of(target_id)
		collect.show()
		collect.monitoring = true
		collect._on_body_entered(get_tree().get_first_node_in_group("player"))
		collect._try_collect()
		_check("collectible 按 E 采集进背包", inv.count_of(target_id) == before + 1)
		_check("采集后隐藏消失", not collect.visible)
	else:
		_check("collectible 按 E 采集进背包", false)

	# -- 背包面板：开合 + 移动锁定 --
	var inv_panel: Node = scene.get_node_or_null("InventoryPanel")
	_check("InventoryPanel 已挂入主场景", inv_panel != null)
	if inv_panel:
		var player: Node = get_tree().get_first_node_in_group("player")
		inv_panel._toggle()
		await _wait(0.2)
		_check("背包面板打开", inv_panel._open)
		_check("打开时锁定玩家移动", player != null and bool(player._movement_locked))
		inv_panel._toggle()
		await _wait(0.2)
		_check("背包面板关闭", not inv_panel._open)
		_check("关闭后解锁移动", player != null and not bool(player._movement_locked))

	sell._close()
	scene.queue_free()
	await _wait(0.3)

	print("[SELL] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
