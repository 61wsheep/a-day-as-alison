extends Node

## M2 任务系统纯逻辑测试 — unlock 门控、委托板数据视图、接受/进行中/完成全生命周期、
## pending_reading_for 命中、report 单步完成、奖励落地（金币/好感/flag）、重复 report 不二次发奖。
## 不实例化主场景（与主场景 UI 无耦合的部分）。

var _failures := 0
var _passes := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		printerr("[QUEST] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run.call_deferred()


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[QUEST] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[QUEST] FAIL  ", check_name)


func _run() -> void:
	var gm: Node = get_node("/root/GameManager")
	var qm: Node = get_node("/root/QuestManager")

	# -- 数据 --
	_check("quests.json 加载 1 条", qm.quests().size() == 1)
	_check("get_quest 命中", not qm.get_quest("tarot_padwin_01").is_empty())
	_check("get_quest 未命中返回空", qm.get_quest("nope").is_empty())

	# -- unlock 门控（day_min + affection_min）--
	gm.current_day = 1
	_check("day1 未解锁", not qm.unlock_met("tarot_padwin_01"))
	_check("day1 无可接受委托", qm.available_quests().is_empty())
	gm.current_day = 3
	_check("day3+aff50 解锁", qm.unlock_met("tarot_padwin_01"))
	_check("day3 有 1 条可接受委托", qm.available_quests().size() == 1)

	# -- 奖励文案 --
	_check("reward_text 拼装",
		qm.reward_text({"gold": 30, "affection": {"padwin": 10}}) == "金币 +30 · 帕德温 好感 +10")

	# -- 接受 --
	var accepted_ids: Array = []
	qm.quest_accepted.connect(func(id: String) -> void: accepted_ids.append(id))
	_check("初始未进行", not qm.is_active("tarot_padwin_01"))
	qm.accept("tarot_padwin_01")
	_check("接受后 active", qm.is_active("tarot_padwin_01"))
	_check("active flag 落地", gm.has_flag("quest_active_tarot_padwin_01"))
	_check("quest_accepted 发 1 次", accepted_ids.size() == 1)
	qm.accept("tarot_padwin_01")
	_check("重复接受不发信号", accepted_ids.size() == 1)
	_check("active_quests 视图含该委托", qm.active_quests().size() == 1 and
		str(qm.active_quests()[0].get("id", "")) == "tarot_padwin_01")
	_check("委托板可用列表清空", qm.available_quests().is_empty())
	_check("step_index_of(active)=0", qm.step_index_of("tarot_padwin_01") == 0)

	# -- pending_reading_for --
	_check("padwin 有待占卜委托", qm.pending_reading_for("padwin") == "tarot_padwin_01")
	_check("soraya 无待占卜委托", qm.pending_reading_for("soraya") == "")

	# -- report：错 NPC 不推进 --
	var gold_before: int = gm.gold
	qm.report({"type": "tarot_reading_for", "npc": "soraya"})
	_check("错误 NPC 不完成", qm.is_active("tarot_padwin_01"))
	_check("错误 NPC 不发金币", gm.gold == gold_before)

	# -- report：正确 NPC → 完成 + 奖励 --
	var completed_ids: Array = []
	qm.quest_completed.connect(func(id: String) -> void: completed_ids.append(id))
	qm.report({"type": "tarot_reading_for", "npc": "padwin"})
	_check("正确 NPC 完成委托", qm.is_completed("tarot_padwin_01"))
	_check("完成后不再 active", not qm.is_active("tarot_padwin_01"))
	_check("quest_completed 发 1 次", completed_ids.size() == 1)
	_check("金币 +30", gm.gold == gold_before + 30)
	_check("帕德温好感 +10（50→60）", int(gm.npc_affection.get("padwin", 0)) == 60)
	_check("故事解锁 flag 落地", gm.has_flag("padwin_watch_resolved"))
	_check("active flag 清除", not gm.has_flag("quest_active_tarot_padwin_01"))
	_check("completed_quests 视图含该委托", qm.completed_quests().size() == 1)
	_check("完成后 pending 清空", qm.pending_reading_for("padwin") == "")

	# -- 重复 report 不二次发奖 --
	var gold_after: int = gm.gold
	qm.report({"type": "tarot_reading_for", "npc": "padwin"})
	_check("重复 report 不二次发奖", gm.gold == gold_after)
	_check("重复 report 不发第二次完成信号", completed_ids.size() == 1)

	print("[QUEST] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
