extends Area2D

## 广场委托板（交互触发器）— 玩家靠近显示「[E] 查看委托板」，按 E 打开 QuestBoardUI。
## 复用 EventBus 的 board_hint_show/hide（dialogue_ui 渲染在右下角提示位）。
## 仿 collectible 的 _in_range + _player_locked + _unhandled_input(ui_accept) 模式。

var _in_range := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = true
	get_node("/root/EventBus").board_hint_show.emit()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = false
	get_node("/root/EventBus").board_hint_hide.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _in_range or not visible:
		return
	if _player_locked():
		return
	if event.is_action_pressed("ui_accept"):
		_open_board()
		get_viewport().set_input_as_handled()


func _player_locked() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	return p != null and bool(p._movement_locked)


func _open_board() -> void:
	var ui := get_node_or_null("/root/Main/QuestBoardUI")
	if ui == null:
		ui = get_tree().get_first_node_in_group("quest_board_ui")
	if ui == null or not ui.has_method("open"):
		return
	ui.open()
