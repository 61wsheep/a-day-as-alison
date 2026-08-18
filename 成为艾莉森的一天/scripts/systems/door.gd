extends Area2D
class_name Door

## 场景切换门 — 玩家走入即切换到目标区域的指定出生点。

@export var target_area: String = ""
@export var target_spawn: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		print("[door] ", name, " -> ", target_area, "/", target_spawn)
		get_node("/root/EventBus").door_entered.emit(target_area, target_spawn)
