class_name ItemDB
extends Object

## 物品数据库 —— 从 resources/data/items.json 读取物品元数据（静态类）。
## 用法：ItemDB.get_item("mushroom") / get_icon(id) / calc_sell_price(id, luck)。
## 与 SceneLayout 同构：静态方法、惰性加载、可无实例调用。

const ITEMS_PATH := "res://resources/data/items.json"
const ATLAS_PATH := "res://assets/tilesets/forest_plaza.png"

## 程序占位改色（正式图标到位后删除本表，直接走 items.json 原图）。
const ICON_TINT := {
	"berry": Color(0.85, 0.25, 0.25),
	"herb_moonleaf": Color(0.5, 0.65, 0.95),
	"potion_blank": Color(0.7, 0.8, 0.9),
}

static var _items: Dictionary = {}
static var _icons: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		push_warning("[ItemDB] 无法打开 items.json")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_warning("[ItemDB] items.json 解析失败")
		return
	for it in data.get("items", []):
		if it is Dictionary:
			_items[str(it.get("id", ""))] = it


static func all() -> Array:
	_ensure()
	return _items.values()


static func get_item(item_id: String) -> Dictionary:
	_ensure()
	return _items.get(item_id, {})


static func has_item(item_id: String) -> bool:
	_ensure()
	return _items.has(item_id)


static func kind_of(item_id: String) -> String:
	return str(get_item(item_id).get("kind", ""))


static func base_price(item_id: String) -> int:
	return int(get_item(item_id).get("base_price", 0))


static func stack_max(item_id: String) -> int:
	return int(get_item(item_id).get("stack_max", 99))


static func name_of(item_id: String) -> String:
	return str(get_item(item_id).get("name", item_id))


static func desc_of(item_id: String) -> String:
	return str(get_item(item_id).get("desc", ""))


## 物品图标：按 items.json 的 icon.region 程序切图（AtlasTexture），带缓存。
static func get_icon(item_id: String) -> Texture2D:
	_ensure()
	if _icons.has(item_id):
		return _icons[item_id]
	var meta := get_item(item_id)
	var region_arr: Array = meta.get("icon", {}).get("region", [])
	if region_arr.size() != 4:
		_icons[item_id] = null
		return null
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS_PATH) as Texture2D
	at.region = Rect2(float(region_arr[0]), float(region_arr[1]), float(region_arr[2]), float(region_arr[3]))
	_icons[item_id] = at
	return at


static func icon_tint(item_id: String) -> Color:
	return ICON_TINT.get(item_id, Color.WHITE)


## 售卖价：base_price × (1 + 0.2 × daily_luck)，整数化。
## 与 tarot_ui 的「吉 ×1.2 / 凶 ×0.8」文案一致。
static func calc_sell_price(item_id: String, daily_luck: int) -> int:
	return roundi(base_price(item_id) * (1.0 + 0.2 * daily_luck))
