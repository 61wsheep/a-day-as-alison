extends CanvasLayer

## HUD — 显示当前时段、金币数、天数。
##
## 监听 EventBus 信号自动刷新。

@onready var time_label: Label = $MarginContainer/HBoxContainer/TimeLabel
@onready var gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel
@onready var day_label: Label = $MarginContainer/HBoxContainer/DayLabel


func _ready() -> void:
	_refresh()
	get_node("/root/EventBus").time_changed.connect(_on_time_changed)
	get_node("/root/EventBus").gold_changed.connect(_on_gold_changed)
	get_node("/root/EventBus").day_started.connect(_on_day_started)


func _refresh() -> void:
	var gm = get_node("/root/GameManager")
	time_label.text = _time_display_name(gm.current_time)
	gold_label.text = "金币: %d" % gm.gold
	day_label.text = "第 %d 天" % gm.current_day


func _on_time_changed(time_id: String) -> void:
	time_label.text = _time_display_name(time_id)
	# 简单的颜色变化：夜晚/午夜用暗色调
	match time_id:
		"night", "midnight":
			time_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.6))
		_:
			time_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))


func _on_gold_changed(amount: int) -> void:
	gold_label.text = "金币: %d" % amount


func _on_day_started(day: int) -> void:
	day_label.text = "第 %d 天" % day
	_refresh()


func _time_display_name(time_id: String) -> String:
	match time_id:
		"morning":   return "清晨"
		"afternoon": return "上午"
		"evening":   return "傍晚"
		"night":     return "夜晚"
		"midnight":  return "午夜"
		_:           return time_id
