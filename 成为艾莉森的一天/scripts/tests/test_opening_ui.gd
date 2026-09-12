extends Node

## 开场旁白序列 冒烟测试 —— 验证 opening.json 真的接到了启动流程。
## 用法：godot --headless scenes/tests/test_opening_ui.tscn
##
## 覆盖：
##   1. main.tscn 起来后 OpeningUI 自动开播第一轮五拍（绳→苔→树→看→撞）
##   2. 播放期间挡屏可见、玩家移动被锁
##   3. 长文超出阅读框 → 可滚；末拍读到底才放行并露出「睁开眼」按钮
##   4. 翻完五拍 → 收屏、发 finished、解锁玩家
##   5. 开场播完后接上晨间塔罗

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[OPENING] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[OPENING] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[OPENING] FAIL  ", check_name)


func _run() -> void:
	var bridge: Node = get_node_or_null("/root/AIBridge")
	if bridge:
		bridge.set_enabled(false)   # 离线：塔罗走数据牌，快速且确定性

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(0.3)

	var ui: CanvasLayer = scene.get_node_or_null("OpeningUI")
	_check("main.tscn 里有 OpeningUI", ui != null)
	if ui == null:
		_finish()
		return

	var player: Node = scene.get_node_or_null("Player")
	_check("开场已开播", ui.is_playing())
	_check("挡屏可见", ui.visible)
	_check("停在第一拍", ui.get("_index") == 0)
	_check("拍名是「绳」", ui._beat_label.text == "· 绳 ·")
	_check("正文已填充", ui._text_label.text.length() > 50)
	_check("翻页提示正确", ui._hint_label.text == "[E] 继续")
	_check("播放期间锁住玩家", player != null and bool(player._movement_locked))

	var queue: Array = ui.get("_queue")
	_check("第一轮五拍", queue.size() == 5)

	var want := ["绳", "苔", "树", "看", "撞"]
	var got: Array = []
	for b in queue:
		got.append(str(b.get("label", "")))
	_check("五拍顺序 绳→苔→树→看→撞", got == want)

	var finished := {"fired": false}
	ui.finished.connect(func(): finished["fired"] = true)

	# 翻到末拍（撞）。末拍另有门控：正文没读到底就不放行，得滚到底才收尾。
	for i in queue.size() - 1:
		ui._advance()
		await get_tree().process_frame
	await get_tree().process_frame
	_check("末拍时仍在播", ui.is_playing())

	# ---- 正文阅读框：长文超出框、可以滚（改造前直接被屏幕底边切掉） ----
	var scroll: ScrollContainer = ui.get("_scroll")
	_check("末拍正文超出阅读框", not bool(ui._compute_at_bottom()))
	_check("末拍未读到底拦住继续", bool(ui._gated()))
	_check("末拍未读到底提示改滚轮", ui._hint_label.text == "[滚轮] 读到最后")
	_check("末拍未读到底不露按钮", not ui._read_btn.visible)

	# ---- 读到底：放行 + 「睁开眼」按钮露面 ----
	scroll.scroll_vertical = int(1e6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("滚到底后已到底", bool(ui._compute_at_bottom()))
	_check("滚到底后放行继续", not bool(ui._gated()))
	_check("滚到底后提示「睁开眼」", ui._hint_label.text == "[E] 睁开眼")
	_check("滚到底后露出「睁开眼」按钮", ui._read_btn.visible)

	# ---- 前四拍不受门控：正文同样超出框，但不拦人、也不露按钮 ----
	ui.set("_index", 2)
	ui._show_current()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("非末拍正文也超出阅读框", not bool(ui._compute_at_bottom()))
	_check("非末拍不设门控", not bool(ui._gated()))
	_check("非末拍不露按钮", not ui._read_btn.visible)
	_check("非末拍提示「继续」", ui._hint_label.text == "[E] 继续")

	# 收回末拍再正常收尾
	ui.set("_index", queue.size() - 1)
	ui._show_current()
	await get_tree().process_frame
	ui._advance()
	await get_tree().process_frame
	_check("翻完五拍后收屏", not ui.is_playing())
	_check("收屏后按钮一并收起", not ui._read_btn.visible)
	_check("挡屏已隐藏", not ui.visible)
	_check("发出 finished 信号", bool(finished["fired"]))

	await _wait(0.5)

	# 晨间塔罗已挪进艾莉森小屋（走到魔法桌前按 E），开局不该再自动弹
	var tarot: Node = scene.get_node_or_null("TarotUI")
	var tarot_panel: Control = tarot.get("_panel") if tarot else null
	_check("开场播完不再自动弹塔罗", tarot_panel != null and not tarot_panel.visible)
	_check("结束后解锁玩家", player != null and not bool(player._movement_locked))

	# ---- 阶段 2：循环开场（第二轮起只播一行锚点旁白，自动收） ----
	var gm: Node = get_node("/root/GameManager")
	gm.reset_loop()
	await _wait(0.4)
	_check("循环开场已开播", ui.is_playing())
	_check("循环开场只有一行", ui.get("_queue").size() == 1)
	_check("循环开场自动推进", bool(ui.get("_auto")))
	_check("循环开场不显示拍名", ui._beat_label.text == "")
	_check("循环开场时锁住玩家", player != null and bool(player._movement_locked))
	_check("循环开场的锚点是「苔」", ui._text_label.text.contains("苔"))
	await _wait(3.2)
	_check("循环开场自动收屏", not ui.is_playing())
	_check("循环开场后仍不自动弹塔罗", tarot_panel != null and not tarot_panel.visible)

	_finish()


func _finish() -> void:
	print("[OPENING] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
