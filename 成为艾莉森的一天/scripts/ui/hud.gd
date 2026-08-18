extends CanvasLayer

## HUD — 显示时段、金币、天数 + 时间推进提示
##
## 监听 EventBus 信号自动刷新。

@onready var time_label: Label = $MarginContainer/HBoxContainer/TimeLabel
@onready var gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel
@onready var day_label: Label = $MarginContainer/HBoxContainer/DayLabel

var _tarot_label: Label


func _ready() -> void:
	_tarot_label = Label.new()
	_tarot_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	$MarginContainer/HBoxContainer.add_child(_tarot_label)
	_refresh()
	get_node("/root/EventBus").time_changed.connect(_on_time_changed)
	get_node("/root/EventBus").gold_changed.connect(_on_gold_changed)
	get_node("/root/EventBus").day_started.connect(_on_day_started)
	get_node("/root/EventBus").tarot_drawn.connect(_on_tarot_drawn)


func _on_tarot_drawn(card: Dictionary) -> void:
	_tarot_label.text = "🃏 " + str(card.get("name", ""))


func _refresh() -> void:
	var gm = get_node("/root/GameManager")
	time_label.text = _time_display_name(gm.current_time)
	gold_label.text = "Gold: %d" % gm.gold
	day_label.text = "Day %d" % gm.current_day


func _on_time_changed(time_id: String) -> void:
	time_label.text = _time_display_name(time_id)
	# 非午夜时段显示 T 键提示
	if time_id != "midnight":
		time_label.text += "  [T]"


func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount


func _on_day_started(day: int) -> void:
	day_label.text = "Day %d" % day
	_refresh()


func _time_display_name(time_id: String) -> String:
	match time_id:
		"morning":   return "Morning"
		"afternoon": return "Afternoon"
		"evening":   return "Evening"
		"night":     return "Night"
		"midnight":  return "Midnight"
		_:           return time_id
