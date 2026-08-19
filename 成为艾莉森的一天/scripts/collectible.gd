extends Area2D
class_name Collectible

## 可采集物品 — 玩家靠近自动拾取，加金币后消失。
## 循环重置时通过 game.gd 的 _refresh_collectibles() 重新出现。

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")

@export var gold_value: int = 10
@export var item_name: String = "蘑菇"


func _ready() -> void:
	add_to_group("collectible")
	body_entered.connect(_on_body_entered)
	# 用 Cainos 灌木丛作为蘑菇的视觉（蘑菇藏在草丛里）
	if not has_node("Icon") or $Icon is not Sprite2D:
		return
	var icon: Sprite2D = $Icon
	if icon.texture == null:
		var tex := load("res://assets/tilesets/cainos/plant.png") as Texture2D
		if tex:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = SceneLayout.MUSHROOM_ICON_REGION
			icon.texture = at
			return
		var rect = ColorRect.new()
		rect.color = Color(0.75, 0.15, 0.15, 1.0)
		rect.size = Vector2(16, 16)
		rect.position = Vector2(-8, -8)
		add_child(rect)
		rect.owner = self


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var gm = get_node("/root/GameManager")
		# 塔罗运势影响售价：吉 ×1.5 / 平 ×1 / 凶 ×0.5
		var mult := 1.0
		if gm.daily_luck > 0:
			mult = 1.5
		elif gm.daily_luck < 0:
			mult = 0.5
		gm.add_gold(int(gold_value * mult))
		hide()
		# 禁用碰撞，防止重复拾取
		set_deferred("monitoring", false)
