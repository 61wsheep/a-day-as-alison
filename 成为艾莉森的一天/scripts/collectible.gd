extends Area2D
class_name Collectible

## 可采集物品 — 玩家靠近自动拾取，加金币后消失。
## 循环重置时通过 game.gd 的 _refresh_collectibles() 重新出现。

@export var gold_value: int = 10
@export var item_name: String = "蘑菇"


func _ready() -> void:
	add_to_group("collectible")
	body_entered.connect(_on_body_entered)
	# 自动生成占位可视化: 红色小方块
	if not has_node("Icon") or $Icon is not Sprite2D:
		return
	var icon: Sprite2D = $Icon
	if icon.texture == null:
		var rect = ColorRect.new()
		rect.color = Color(0.75, 0.15, 0.15, 1.0)
		rect.size = Vector2(16, 16)
		rect.position = Vector2(-8, -8)
		add_child(rect)
		rect.owner = self


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var gm = get_node("/root/GameManager")
		gm.add_gold(gold_value)
		hide()
		# 禁用碰撞，防止重复拾取
		set_deferred("monitoring", false)
