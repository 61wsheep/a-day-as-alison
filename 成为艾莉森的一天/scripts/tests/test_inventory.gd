extends Node

## 背包系统单测 — add/remove/stack_max/满组拒收/kind 过滤/changed 信号/快照。
## 用法：godot --headless scenes/tests/test_inventory.tscn

const ItemDB := preload("res://scripts/systems/item_db.gd")

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[INV] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[INV] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[INV] FAIL  ", check_name)


func _run() -> void:
	var inv: Node = get_node("/root/Inventory")

	# -- ItemDB 数据 --
	_check("items.json 加载", ItemDB.has_item("mushroom"))
	_check("mushroom kind=forage", ItemDB.kind_of("mushroom") == "forage")
	_check("berry kind=forage", ItemDB.kind_of("berry") == "forage")
	_check("herb_moonleaf kind=herb", ItemDB.kind_of("herb_moonleaf") == "herb")
	_check("mushroom base_price=10", ItemDB.base_price("mushroom") == 10)
	_check("berry stack_max=30", ItemDB.stack_max("berry") == 30)

	# -- add --
	_check("初始为空", inv.all_items().is_empty())
	_check("add 蘑菇×5", inv.add("mushroom", 5))
	_check("数量=5", inv.count_of("mushroom") == 5)
	_check("add 蘑菇×15 到上限", inv.add("mushroom", 15))
	_check("数量=20", inv.count_of("mushroom") == 20)
	_check("满组拒收", not inv.add("mushroom", 1))
	_check("数量仍=20", inv.count_of("mushroom") == 20)
	_check("不存在物品拒收", not inv.add("nonexistent_item"))
	_check("count<=0 拒收", not inv.add("mushroom", 0))

	# -- remove --
	_check("remove 蘑菇×8", inv.remove("mushroom", 8))
	_check("数量=12", inv.count_of("mushroom") == 12)
	_check("remove 超量拒绝", not inv.remove("mushroom", 99))
	_check("remove 清空", inv.remove("mushroom", 12))
	_check("清空后 erase", not inv.has("mushroom"))
	_check("再 remove 空物品拒绝", not inv.remove("mushroom"))

	# -- kind 过滤 --
	inv.add("berry", 2)
	_check("has_kind forage", inv.has_kind("forage"))
	_check("count_of_kind=2", inv.count_of_kind("forage") == 2)
	inv.add("herb_moonleaf", 1)
	_check("加 herb 不影响 forage 统计", inv.count_of_kind("forage") == 2)
	_check("has_kind herb", inv.has_kind("herb"))

	# -- changed 信号 --
	var last := {"id": "", "n": -1}
	inv.changed.connect(func(id: String, n: int) -> void:
		last["id"] = id
		last["n"] = n)
	inv.add("berry", 1)
	_check("changed 信号触发", last.get("id") == "berry" and last.get("n") == 3)

	# -- all_items 快照不可变 --
	var snap: Dictionary = inv.all_items()
	snap["mushroom"] = 999
	_check("快照修改不影响本体", inv.count_of("mushroom") == 0 and inv.count_of("berry") == 3)

	print("[INV] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
