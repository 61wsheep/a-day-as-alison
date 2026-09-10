extends Area2D
class_name TreehouseDoor

## 树屋门 — 已租下后它就是"前门"，与三个外景的门一致：走到门口（body_entered）
## 直接走进 alison_room，不按 E。未租时树屋是别人的家不能进，按 E 打开租赁界面。
## D13：无论租的是 oak/cedar/willow 哪一间，都通向同一间艾莉森的小屋。

@export var house_id: String = ""

var _player_in_range: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("ui_accept"):
		if get_node("/root/GameManager").treehouse_rented:
			# 兜底：租完 UI 关掉时人还站在门口，body_entered 不会重触发，此时按 E 也一样进门
			_enter_room()
		else:
			get_node("/root/EventBus").game_action.emit("rental:" + house_id)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if get_node("/root/GameManager").treehouse_rented:
			# 已租：走到门口即自动走进小屋（同外景 Door 的 body_entered 切换语义）
			_enter_room()
			return
		get_node("/root/EventBus").interaction_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		get_node("/root/EventBus").interaction_hint_hide.emit()


func _enter_room() -> void:
	_player_in_range = false
	get_node("/root/EventBus").interaction_hint_hide.emit()
	get_node("/root/EventBus").door_entered.emit("alison_room", "BedroomDoorIn")
