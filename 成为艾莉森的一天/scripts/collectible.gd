extends Area2D
class_name Collectible

## 可采集物品 — 玩家靠近自动拾取进背包（Inventory.add）。
## 拾取成功才消失；背包满（超 stack_max）拒收并保留，弹 toast 提示。
## 循环重置时通过 game.gd 的 _refresh_collectibles() 重新出现。

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")
const ItemDB := preload("res://scripts/systems/item_db.gd")

## 采到的物品 id（items.json 里的 id），替代原来的 gold_value 直加金币。
@export var item_id: String = "mushroom"


func _ready() -> void:
	add_to_group("collectible")
	body_entered.connect(_on_body_entered)
	_apply_icon()


## 图标从 ItemDB 切图（items.json 的 icon.region + 占位改色）；失败则程序红块兜底。
func _apply_icon() -> void:
	if not has_node("Icon") or $Icon is not Sprite2D:
		return
	var icon: Sprite2D = $Icon
	var tex := ItemDB.get_icon(item_id)
	if tex:
		icon.texture = tex
		icon.modulate = ItemDB.icon_tint(item_id)
		return
	var rect := ColorRect.new()
	rect.color = Color(0.75, 0.15, 0.15, 1.0)
	rect.size = Vector2(16, 16)
	rect.position = Vector2(-8, -8)
	add_child(rect)
	rect.owner = self


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var inv: Node = get_node("/root/Inventory")
	if inv.add(item_id):
		hide()
		# 禁用碰撞，防止重复拾取
		set_deferred("monitoring", false)
	else:
		get_node("/root/EventBus").toast.emit("背包满了！")
