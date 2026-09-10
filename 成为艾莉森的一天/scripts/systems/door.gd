extends Area2D
class_name Door

## 场景切换门 — 玩家走入即切换到目标区域的指定出生点。

@export var target_area: String = ""
@export var target_spawn: String = ""
## 出门锁：勾上后，当天还没抽塔罗就出不去（艾莉森小屋专用）。
## 第 1 天豁免——那时玩家还没搬进小屋，本来就没有牌可抽。
@export var require_tarot: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if require_tarot and not _tarot_done():
		get_node("/root/EventBus").toast.emit("今天的牌还没看。先去魔法桌前抽一张。")
		return
	print("[door] ", name, " -> ", target_area, "/", target_spawn)
	get_node("/root/EventBus").door_entered.emit(target_area, target_spawn)


func _tarot_done() -> bool:
	var gm = get_node("/root/GameManager")
	return gm.current_day < 2 or gm.tarot_drawn_today
