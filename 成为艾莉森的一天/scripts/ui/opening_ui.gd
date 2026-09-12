extends CanvasLayer

## 开场旁白序列 —— 全屏旁白播放器（不是对话：没有立绘、没有选项、没有立绘位）。
##
## 第一轮（day 1）：播 opening.json 的 first_run 五拍（绳→苔→树→看→撞），
## 玩家按 E / 空格 / 回车 / 左键翻页；读完由 game.gd 接「晨间占卜」。
## 第二轮起：只播一行循环精简版（锚点是「苔」，不是床），自动停留后收。
##
## 正文装在固定高度的阅读框里可滚动 —— 五拍正文实测依次需要 337 / 523 / 713 /
## 599 / 713 px，而画布上正文可用高度只有 ~500px，不装滚动后四拍就会被屏幕底边
## 切掉（拍 3/5 各切掉 7 行，「你是不是女巫？」那句钩子根本读不到）。
## 最后一拍「撞」另有门控：读到底才放行翻页并露出「睁开眼」按钮，前四拍随时可翻。
##
## 播放期间由 game.gd 停住玩家移动与时间自动推进；本组件播完发 finished 信号。
## 数据：res://resources/data/opening.json

const OPENING_FILE := "res://resources/data/opening.json"
## 第几轮起改用 late_round 那句（与 GameManager.HARD_DAY_CAP=20 相配的收束感）
const LATE_ROUND_DAY := 15
## 循环精简版自动停留时长（秒）——一行锚点，看一眼就走
const CONDENSED_HOLD := 2.6
const FADE_IN := 0.6

## 正文阅读框：860px 栏宽（1152 宽下约 44 字一行），高度封顶，文字在框内滚。
## 实测五拍正文依次需要 337 / 523 / 713 / 599 / 713 px（首尾留白另加 112）。
## 490 让最长那四拍有得滚，最短的「绳」正好一屏读完、不必滚（也不设门控）。
const READ_W := 860.0
const READ_H := 490.0
## 框内首尾留白：必须大于 FADE_H —— 滚到顶/底时首末行才不会压在渐变带底下被吃掉
const READ_PAD := 56.0
## 框上下的渐变淡出高度，让滚出框的文字淡出而不是被硬边切断
const FADE_H := 48.0
## 必须与 _build_ui 里 Dim 的颜色一致，否则渐变遮罩的接缝会露出来
const DIM_COLOR := Color(0.02, 0.02, 0.04, 0.94)

signal finished

var _first_run_beats: Array = []
var _loop_main: String = ""
var _loop_alternates: Array = []
var _loop_late: String = ""

var _root: Control
var _beat_label: Label
var _scroll: ScrollContainer
var _text_col: VBoxContainer
var _fade_top: TextureRect
var _fade_bot: TextureRect
var _read_btn: Button
var _text_label: Label
var _hint_label: Label
var _auto_timer: Timer
## 末拍正文当前是否已滚到底（决定「睁开眼」按钮露不露面）
var _at_bottom: bool = false

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
	dim.color = DIM_COLOR
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

	# 正文阅读框：居中一栏（860px 宽，约 44 字一行），高度封顶，文字在框内滚。
	# 横向滚动关掉 —— ScrollContainer 会把子节点宽度压成框宽，autowrap 才按 860 折行。
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_CENTER)
	_scroll.offset_left = -READ_W * 0.5
	_scroll.offset_right = READ_W * 0.5
	_scroll.offset_top = -READ_H * 0.5
	_scroll.offset_bottom = READ_H * 0.5
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 藏起滚动条但不关滚动：能滚是靠上下渐变暗示的，多一根灰色条会破掉这个观感
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	# 键盘焦点不给它：翻页键要留给 _input 的末拍门控，别被空格抢去滚屏
	_scroll.focus_mode = Control.FOCUS_NONE
	_root.add_child(_scroll)

	_text_col = VBoxContainer.new()
	_text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_col.add_theme_constant_override("separation", 0)
	_scroll.add_child(_text_col)

	_text_col.add_child(_make_pad(READ_PAD))
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.add_theme_constant_override("line_spacing", 9)
	_text_label.add_theme_color_override("font_color", Color(0.93, 0.92, 0.90))
	_text_col.add_child(_text_label)
	_text_col.add_child(_make_pad(READ_PAD))

	# 上下渐变遮罩：压在滚出框的文字上，让它淡出而不是被硬边切断
	_fade_top = _make_fade(true)
	_fade_bot = _make_fade(false)
	_root.add_child(_fade_top)
	_root.add_child(_fade_bot)

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

	# 末拍门控的「睁开眼」按钮：只有最后一拍、且正文读到底时才露面（见 _refresh_gate）
	_read_btn = Button.new()
	_read_btn.text = "睁开眼"
	_read_btn.focus_mode = Control.FOCUS_NONE
	_read_btn.set_anchors_preset(Control.PRESET_CENTER)
	_read_btn.offset_left = -84
	_read_btn.offset_right = 84
	_read_btn.offset_top = READ_H * 0.5 + 14
	_read_btn.offset_bottom = READ_H * 0.5 + 54
	_read_btn.add_theme_font_size_override("font_size", 17)
	_read_btn.pressed.connect(_advance)
	_read_btn.visible = false
	_root.add_child(_read_btn)

	# 滚动条信号接在最后：框里还没内容时它们就会响，接早了会碰到空引用
	var bar := _scroll.get_v_scroll_bar()
	bar.value_changed.connect(_on_scroll_changed)
	bar.changed.connect(_refresh_gate)

	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.timeout.connect(_advance)
	add_child(_auto_timer)


## 阅读框内容的首尾留白垫片（VBoxContainer 按最小高度排它）
func _make_pad(h: float) -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0.0, h)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pad


## 阅读框上/下的渐变遮罩：从 DIM_COLOR 实色渐变到全透，盖住滚出框的文字。
## 鼠标穿透，免得吃掉滚轮。
func _make_fade(top: bool) -> TextureRect:
	var solid := DIM_COLOR
	var clear := Color(DIM_COLOR.r, DIM_COLOR.g, DIM_COLOR.b, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, solid if top else clear)
	grad.set_color(1, clear if top else solid)

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 16
	tex.height = 64
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)

	var fade := TextureRect.new()
	fade.texture = tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_CENTER)
	fade.offset_left = -READ_W * 0.5
	fade.offset_right = READ_W * 0.5
	if top:
		fade.offset_top = -READ_H * 0.5
		fade.offset_bottom = -READ_H * 0.5 + FADE_H
	else:
		fade.offset_top = READ_H * 0.5 - FADE_H
		fade.offset_bottom = READ_H * 0.5
	return fade


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
	_text_label.text = str(beat.get("text", ""))
	# 新一拍从头读起。这拍要不要滚得等布局跑完才知道，所以门控先算一次，
	# 再 deferred 补一次 —— 省得末拍开局就误判成「已读到底」。
	_scroll.scroll_vertical = 0
	_at_bottom = false
	_refresh_gate()
	_refresh_gate.call_deferred()
	if _auto:
		_auto_timer.start(CONDENSED_HOLD)


# ---------------------------------------------------------------------------
# 末拍门控：读到底才放行翻页
# ---------------------------------------------------------------------------
## 正文是否已滚到底。内容没占满一框时视为「已到底」——没有可滚的就不该拦人。
func _compute_at_bottom() -> bool:
	if _scroll == null:
		return true
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return true
	var max_scroll: float = bar.max_value - _scroll.size.y
	if max_scroll <= 1.0:
		return true
	return float(_scroll.scroll_vertical) >= max_scroll - 2.0


## 当前是否该拦住翻页：只有最后一拍、且正文还没读到底才算拦。
## 只拦 _input —— _advance() 本身不设防，测试与 test_helpers.dismiss_opening()
## 直接调它翻页，不能被门控卡死。
func _gated() -> bool:
	if _auto or _queue.is_empty():
		return false
	if _index != _queue.size() - 1:
		return false
	return not _compute_at_bottom()


## 刷新门控的呈现：右下角提示语 + 「睁开眼」按钮露不露面。
func _refresh_gate() -> void:
	if _read_btn == null:
		return
	if not _playing or _auto:
		_read_btn.visible = false
		return
	if _index != _queue.size() - 1:
		_read_btn.visible = false
		_hint_label.text = "[E] 继续"
		return
	_at_bottom = _compute_at_bottom()
	_read_btn.visible = _at_bottom
	_hint_label.text = "[E] 睁开眼" if _at_bottom else "[滚轮] 读到最后"


func _on_scroll_changed(_value: float) -> void:
	_refresh_gate()


func _advance() -> void:
	if not _playing:
		return
	_auto_timer.stop()
	_index += 1
	_show_current()


func _finish() -> void:
	_playing = false
	_auto_timer.stop()
	if _read_btn:
		_read_btn.visible = false
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
	# 末拍读到底之前：翻页键改成往下滚，不放行。鼠标滚轮不碰 —— 框自己会处理，
	# 在这儿吞掉反而会让滚轮失灵（_input 早于 GUI 派发）。
	if _gated():
		var step := int(_scroll.size.y * 0.75)
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_page_down"):
			get_viewport().set_input_as_handled()
			_scroll.scroll_vertical += step
			return
		if event.is_action_pressed("ui_page_up"):
			get_viewport().set_input_as_handled()
			_scroll.scroll_vertical -= step
			return
		if event.is_action_pressed("ui_down"):
			get_viewport().set_input_as_handled()
			_scroll.scroll_vertical += 60
			return
		if event.is_action_pressed("ui_up"):
			get_viewport().set_input_as_handled()
			_scroll.scroll_vertical -= 60
			return
		# 左键只吞不放行；滚轮等其它鼠标键放走
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
		return
	var advance := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if advance:
		get_viewport().set_input_as_handled()
		_advance()
