extends Area2D
class_name TreehouseDoor

## 树屋门 — 玩家靠近按 E 打开租赁/休息界面。

@export var house_id: String = ""

var _player_in_range: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("ui_accept"):
		# 已租下树屋：按 E 走进自己的小屋（D13：任何一间树屋门都通向同一间艾莉森的小屋）
		if get_node("/root/GameManager").treehouse_rented:
			get_node("/root/EventBus").door_entered.emit("alison_room", "BedroomDoorIn")
		else:
			get_node("/root/EventBus").game_action.emit("rental:" + house_id)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		get_node("/root/EventBus").interaction_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		get_node("/root/EventBus").interaction_hint_hide.emit()
