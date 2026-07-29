extends Node

## 时间管理器 — 事件驱动的时间推进。

enum TimeOfDay {
	MORNING,
	AFTERNOON,
	EVENING,
	NIGHT,
	MIDNIGHT,
}

const TIME_ORDER = [
	"morning",
	"afternoon",
	"evening",
	"night",
	"midnight",
]

var _current_index: int = 0


func advance_time() -> String:
	if _current_index < TIME_ORDER.size() - 1:
		_current_index += 1
		var new_time = TIME_ORDER[_current_index]
		get_node("/root/GameManager").set_time(new_time)
		return new_time
	return "midnight"


func can_advance_to(target_time: String) -> bool:
	var target_idx = _get_index(target_time)
	return _current_index < target_idx


func current() -> String:
	return TIME_ORDER[_current_index]


func reset_to_morning() -> void:
	_current_index = 0
	get_node("/root/GameManager").set_time("morning")


func is_after(time_id: String) -> bool:
	return _current_index >= _get_index(time_id)


func is_midnight() -> bool:
	return _current_index == 4


func _get_index(time_id: String) -> int:
	return TIME_ORDER.find(time_id)


func _ready() -> void:
	get_node("/root/GameManager").set_time("morning")
	_current_index = 0
