extends Node

## 好感度浮字 + 对话面板徽标（回归测试，零网络）。
## 需求：
##   1) 跟 AI NPC 对话时显式看到好感涨跌 —— 每句结算后上方出现「XX 好感 +3」
##      （涨绿降红，跨档附档位名）
##   2) 去掉对话框 NPC 名字旁那行绿的「AI 对话中」
## 用 mock LLM 走真实 npc_base + AIDialogueSession（S1），断言浮字内容/颜色/显隐时机。

const TestHelpers := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0
var _shift := 3   # 当前 mock 要给的情绪位移（每轮）


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 40.0
	guard.timeout.connect(func():
		printerr("[AFF] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[AFF] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[AFF] FAIL  ", check_name)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _mock_llm(_payload: Dictionary) -> String:
	return JSON.stringify({
		"response_text": "（回复）风从东边的林子来。",
		"emotional_shift": _shift,
		"memory_update": "记忆摘要",
		"hints_to_other_npcs": [],
		"should_end_conversation": false,
		"topic_suggestions": ["再说说", "我先走了", "石塔是什么"],
	})


func _run() -> void:
	var bridge := get_node_or_null("/root/AIBridge")
	var bus: Node = get_node("/root/EventBus")
	var gm: Node = get_node("/root/GameManager")
	if bridge == null:
		printerr("[AFF] 无 AIBridge autoload，跳过")
		get_tree().quit(1)
		return
	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_llm)

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	await _wait(1.0)
	# 翻完开场旁白（播放期间玩家锁着）
	await TestHelpers.dismiss_opening(scene)

	var dui: Node = scene.get_node_or_null("DialogueUI")
	var padwin: Node = scene.get_node_or_null("Areas/TreehouseDistrict/Padwin")
	_check("DialogueUI 挂入主场景", dui != null)
	_check("找到帕德温", padwin != null)
	if dui == null or padwin == null:
		bridge.set_mock_responder(Callable())
		bridge.set_enabled(false)
		get_tree().quit(1)
		return

	# -- 需求 2：绿的「AI 对话中」徽标已移除 --
	_check("AI 对话中徽标已移除", dui.get("_ai_badge") == null)
	_check("好感度浮字控件已建立", dui.get("_affection_label") != null)
	_check("浮字初始隐藏", not bool(dui._affection_label.visible))

	# -- 起一段真实 AI 会话（daily）--
	# 起点取 40（neutral 档下沿）：涨不跨档、跌能跨进 cold，两种后缀都能验到。
	gm.set_flag("met_padwin")
	gm.npc_affection["padwin"] = 40
	padwin._start_dialogue()
	await _wait(0.6)
	_check("进入 S1 AI 模式", bool(padwin._ai_mode))
	# 开场轮 emotional_shift=+3 → 40→43（同为 neutral 档，不带档位后缀）
	_check("开场轮好感度已结算", int(gm.npc_affection["padwin"]) == 43)
	_check("浮字显示", bool(dui._affection_label.visible))
	_check("浮字文案=帕德温 好感 +3", str(dui._affection_label.text) == "帕德温 好感 +3")
	_check("涨为绿色", dui._affection_label.get_theme_color("font_color").g
		> dui._affection_label.get_theme_color("font_color").r)

	# -- 玩家说一句 → 下一轮 AI 给负位移（-10 → ×0.8 惩罚后 -8）→ 43→35（跨到 cold 档）--
	_shift = -10
	bus.dialogue_free_input.emit("我今天不太想聊")
	await _wait(0.6)
	_check("下降后好感度已结算", int(gm.npc_affection["padwin"]) == 35)
	_check("浮字变为负值", str(dui._affection_label.text).begins_with("帕德温 好感 -8"))
	_check("跨档附档位名（冷淡）", str(dui._affection_label.text).contains("冷淡"))
	_check("降为红色", dui._affection_label.get_theme_color("font_color").r
		> dui._affection_label.get_theme_color("font_color").g)

	# -- 数值无实际变化时不提示（delta=0 不该闪「+0」）--
	var before_text := str(dui._affection_label.text)
	gm.change_affection("padwin", 0)
	await _wait(0.1)
	_check("delta=0 不刷新浮字", str(dui._affection_label.text) == before_text)

	# -- 对话外的好感度变化不弹浮字（委托奖励等有各自的呈现）--
	if bool(padwin._dialogue_active):
		padwin._end_dialogue()
	await _wait(0.2)
	dui._affection_label.hide()   # 清掉上一段对话残留的浮字
	gm.change_affection("padwin", 5)
	await _wait(0.1)
	_check("对话外变化不弹浮字", not bool(dui._affection_label.visible))

	bridge.set_mock_responder(Callable())
	bridge.set_enabled(false)
	scene.queue_free()
	await _wait(0.3)
	print("[AFF] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
