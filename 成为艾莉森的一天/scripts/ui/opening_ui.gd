extends CanvasLayer

## 开场旁白序列 —— 全屏旁白播放器（不是对话：没有立绘、没有选项、没有立绘位）。
##
## 第一轮（day 1）：播 opening.json 的 first_run 五拍（绳→苔→树→看→撞），
## 玩家按 E / 空格 / 回车 / 左键翻页；读完由 game.gd 接「晨间占卜」。
## 第二轮起：只播一行循环精简版（锚点是「苔」，不是床），自动停留后收。
##
## 播放期间由 game.gd 停住玩家移动与时间自动推进；本组件播完发 finished 信号。
## 数据：res://resources/data/opening.json

const OPENING_FILE := "res://resources/data/opening.json"
## 第几轮起改用 late_round 那句（与 GameManager.HARD_DAY_CAP=20 相配的收束感）
const LATE_ROUND_DAY := 15
## 循环精简版自动停留时长（秒）——一行锚点，看一眼就走
const CONDENSED_HOLD := 2.6
const FADE_IN := 0.6

signal finished

var _first_run_beats: Array = []
var _loop_main: String = ""
var _loop_alternates: Array = []
var _loop_late: String = ""

var _root: Control
var _beat_label: Label
var _text_label: Label
var _hint_label: Label
var _auto_timer: Timer

## 本轮要播的 [{label, text}]
var _queue: Array = []
var _index: int = 0
var _playing: bool = false
## true = 自动推进（循环精简版），false = 等玩家翻页（第一轮五拍）
var _auto: bool = false


func _ready() -> void:
	layer = 25   # 盖住对话(10)/占卜(20)/状态(12)，低于结局(30)
	_load_data()
	_build_ui()
	_hide_all()


func _load_data() -> void:
	var f := FileAccess.open(OPENING_FILE, FileAccess.READ)
	if f == null:
		push_warning("[OpeningUI] 读不到 %s，开场旁白将跳过" % OPENING_FILE)
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_warning("[OpeningUI] %s 解析失败，开场旁白将跳过" % OPENING_FILE)
		return
	var first: Dictionary = data.get("first_run", {})
	_first_run_beats = first.get("beats", [])
	var loop: Dictionary = data.get("loop_condensed", {})
	_loop_main = str(loop.get("main", ""))
	_loop_alternates = loop.get("alternates", [])
	_loop_late = str(loop.get("late_round", ""))


func _build_ui() -> void:
	# 整屏内容挂在一个 Control 下，便于整体淡入；CanvasLayer 本身没有 modulate
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.04, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# 拍名（· 绳 · / · 苔 · …），第一轮才有；循环精简版留空
	_beat_label = Label.new()
	_beat_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_beat_label.offset_left = -220
	_beat_label.offset_right = 220
	_beat_label.offset_top = 52
	_beat_label.offset_bottom = 82
	_beat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_beat_label.add_theme_font_size_override("font_size", 16)
	_beat_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.4, 0.85))
	_root.add_child(_beat_label)

	# 正文：居中一栏，竖向居中，行长控制在 ~44 字（1152 宽下 860px 栏宽）
	_text_label = Label.new()
	_text_label.set_anchors_preset(Control.PRESET_CENTER)
	_text_label.offset_left = -430
	_text_label.offset_right = 430
	_text_label.offset_top = -230
	_text_label.offset_bottom = 230
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.add_theme_constant_override("line_spacing", 9)
	_text_label.add_theme_color_override("font_color", Color(0.93, 0.92, 0.90))
	_root.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.offset_left = -280
	_hint_label.offset_top = -46
	_hint_label.offset_right = -28
	_hint_label.offset_bottom = -18
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	_root.add_child(_hint_label)

	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.timeout.connect(_advance)
	add_child(_auto_timer)


func _hide_all() -> void:
	visible = false


# ---------------------------------------------------------------------------
# 对外接口（game.gd 调用）
# ---------------------------------------------------------------------------
## 播第一轮完整开场（五拍）。返回是否真的开播（无数据则不开播，调用方照常继续）。
func play_first_run() -> bool:
	if _first_run_beats.is_empty():
		return false
	_queue.clear()
	for b in _first_run_beats:
		if b is Dictionary:
			_queue.append({"label": str(b.get("label", "")), "text": str(b.get("text", ""))})
	if _queue.is_empty():
		return false
	_start(false)
	return true


## 播循环精简版（第二轮起）：一行锚点旁白，自动停留后收。
func play_loop_condensed(day: int) -> bool:
	var text := _pick_condensed(day)
	if text.is_empty():
		return false
	_queue = [{"label": "", "text": text}]
	_start(true)
	return true


func is_playing() -> bool:
	return _playing


## 循环开场选句：第 15 轮起用 late_round（她开始记不清自己怎么走到那儿的），
## 其余按天在 [主句 + 4 条变体] 里轮换——同一段开场，每轮略有出入。
func _pick_condensed(day: int) -> String:
	if day >= LATE_ROUND_DAY and not _loop_late.is_empty():
		return _loop_late
	if _loop_main.is_empty():
		return ""
	var pool: Array = [_loop_main]
	pool.append_array(_loop_alternates)
	var i: int = (day - 2) % pool.size()
	if i < 0:
		i = 0
	return str(pool[i])


# ---------------------------------------------------------------------------
# 播放
# ---------------------------------------------------------------------------
func _start(auto: bool) -> void:
	_index = 0
	_auto = auto
	_playing = true
	visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_show_current()


func _show_current() -> void:
	if _index >= _queue.size():
		_finish()
		return
	var beat: Dictionary = _queue[_index]
	if _auto:
		_beat_label.text = ""
		_hint_label.text = ""
	else:
		_beat_label.text = "· %s ·" % str(beat.get("label", ""))
		_hint_label.text = "[E] 睁开眼" if _index == _queue.size() - 1 else "[E] 继续"
	_text_label.text = str(beat.get("text", ""))
	if _auto:
		_auto_timer.start(CONDENSED_HOLD)


func _advance() -> void:
	if not _playing:
		return
	_auto_timer.stop()
	_index += 1
	_show_current()


func _finish() -> void:
	_playing = false
	_auto_timer.stop()
	_hide_all()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	# 播放期间吞掉取消键：否则会被对话 UI 的兜底逻辑当成「退出对话」
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return
	if _auto:
		return
	var advance := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if advance:
		get_viewport().set_input_as_handled()
		_advance()
