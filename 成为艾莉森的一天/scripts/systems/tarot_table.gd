extends Area2D
class_name TarotTable

## 魔法桌 — 艾莉森小屋里的塔罗占卜点。
## 晨间塔罗从「每天开局自动弹」改成「回自己房间、走到桌前按 E 抽」：
## 玩家掌握节奏，抽不抽、什么时候抽都由自己决定。
##
## 触发约定与门/树屋门一致：进范围显示提示，按 E 触发。
## 「没抽牌不能出门」不在这里把关——那是 DoorOut 的事（door.gd 的 require_tarot），
## 这里只负责「能不能抽」和「把抽牌动作发给 game.gd 路由」。

var _player_in_range: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 抽完立刻收提示，免得玩家站在桌前还被催
	get_node("/root/EventBus").tarot_drawn.connect(func(_card: Dictionary) -> void:
		get_node("/root/EventBus").tarot_hint_hide.emit())


## 今天还能不能抽：第 1 天还没搬进小屋，没有牌可抽；抽过当天就不再触发。
func can_draw() -> bool:
	var gm = get_node("/root/GameManager")
	return gm.current_day >= 2 and not gm.tarot_drawn_today


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if not event.is_action_pressed("ui_accept"):
		return
	# 循环开场旁白/任何面板正开着时玩家是被锁住的，这时按 E 不该捅开塔罗
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "_movement_locked" in player and player._movement_locked:
		return
	if can_draw():
		# 路由到 game.gd（与 rental:/divine: 同一入口），避免这里直接抓 TarotUI 节点
		get_node("/root/EventBus").game_action.emit("tarot")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if can_draw():
		get_node("/root/EventBus").tarot_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	get_node("/root/EventBus").tarot_hint_hide.emit()
