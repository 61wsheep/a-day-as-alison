extends Node

## 背包 autoload —— Dictionary[item_id] = count。
## 跨 loop_reset 保留，重启不保留（v0.1，存档另行排期）。

const ItemDB := preload("res://scripts/systems/item_db.gd")

signal changed(item_id: String, new_count: int)

var items: Dictionary = {}


## 加入 count 个物品。返回 false = 超 stack_max 拒收（或物品不存在）。
func add(item_id: String, count: int = 1) -> bool:
	if count <= 0 or not ItemDB.has_item(item_id):
		return false
	var cur := int(items.get(item_id, 0))
	var stack_max := ItemDB.stack_max(item_id)
	if cur + count > stack_max:
		return false
	items[item_id] = cur + count
	changed.emit(item_id, int(items[item_id]))
	return true


## 移除 count 个物品。返回 false = 数量不足。
func remove(item_id: String, count: int = 1) -> bool:
	var cur := int(items.get(item_id, 0))
	if cur < count:
		return false
	var left := cur - count
	if left <= 0:
		items.erase(item_id)
	else:
		items[item_id] = left
	changed.emit(item_id, left)
	return true


func count_of(item_id: String) -> int:
	return int(items.get(item_id, 0))


func has(item_id: String) -> bool:
	return count_of(item_id) > 0


## 背包里是否有某一类物品（forage / herb / potion / quest）。
func has_kind(kind: String) -> bool:
	for id in items:
		if ItemDB.kind_of(id) == kind:
			return true
	return false


## 某一类物品的总数量（跨种类累加）。
func count_of_kind(kind: String) -> int:
	var total := 0
	for id in items:
		if ItemDB.kind_of(id) == kind:
			total += count_of(id)
	return total


## 背包快照（UI 用，避免外部直接改内部 Dictionary）。
func all_items() -> Dictionary:
	return items.duplicate()
