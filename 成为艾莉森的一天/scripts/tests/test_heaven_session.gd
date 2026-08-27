extends SceneTree

## AIHeavenSession（天命/审判面具）mock 集成测试（零网络）。
## 运行：godot --headless -s res://scripts/tests/test_heaven_session.gd
## 验证：
##   - oracle：合法 schema / 非法牌名+非法 directive 的校验丢弃 / AI 失败回落数据牌
##   - judgment：顺从判定（obey/defy/neutral/未设局）/ 记忆落库白名单 / 终结闸 / 失败回落
## 存储隔离在 user://memory_session_test，不污染正式记忆。

const AIHeavenSession := preload("res://scripts/systems/ai_heaven_session.gd")
const HeavenMemory := preload("res://scripts/systems/heaven_memory.gd")

var _failures := 0
var _passes := 0
var _mode := "legal"          # mock 响应脚本：legal / illegal / error
var _planted_fs_id := ""      # oracle legal 埋下的伏笔 id


func _init() -> void:
	if AIHeavenSession == null or HeavenMemory == null:
		printerr("[TEST] 预加载失败，测试未运行")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var bridge: Node = root.get_node_or_null("AIBridge")
	var gm: Node = root.get_node_or_null("GameManager")
	if bridge == null or gm == null:
		printerr("[TEST] 无 AIBridge/GameManager autoload，退出")
		quit(1)
		return

	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_llm)
	_setup_memory()
	_reset_heaven(gm)
	gm.current_day = 5

	var base := Node.new()
	root.add_child(base)

	await _test_oracle_legal(base, gm)
	await _test_oracle_illegal(base, gm)
	await _test_oracle_fallback(base, gm)
	await _test_judgment_full(base, gm)
	_test_last_compliance_preserved(gm)
	await _test_end_gate(base, gm)
	await _test_judgment_fallback(base, gm)
	_test_compliance_defy_and_unset(gm)

	print("[TEST] HeavenSession: %d 通过, %d 失败" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[TEST] FAIL  ", name)


func _setup_memory() -> void:
	HeavenMemory.set_storage_dir("user://memory_session_test")
	var dir := DirAccess.open("user://")
	if dir:
		for f in ["events.jsonl", "day_summaries.json", "attitude_profile.json", "relation_cards.json", "foreshadows.json"]:
			dir.remove("memory_session_test/%s" % f)


func _reset_heaven(gm: Node) -> void:
	gm.heaven["benevolence"] = 0.0
	gm.heaven["engagement"] = 0.3
	gm.heaven["truth_proximity"] = 0.0
	gm.heaven["prophecy_resistance"] = 0
	gm.heaven["daily_prophecy"] = null
	gm.heaven["daily_compliance"] = ""
	gm.heaven["tomorrow_seed"] = ""
	gm.heaven["last_judgment"] = {}


# ---------------------------------------------------------------------------
# mock LLM：按 prompt 里的面具标识分发
# ---------------------------------------------------------------------------

func _mock_llm(payload: Dictionary) -> String:
	var user := str(payload.get("user", ""))
	if _mode == "error":
		return "[API_ERROR] 测试超时"
	if "天命面具" in user:
		return _mock_oracle()
	if "审判面具" in user:
		return _mock_judgment()
	return "{}"


func _mock_oracle() -> String:
	if _mode == "illegal":
		return JSON.stringify({
			"card_name": "不存在的牌",
			"prophecy": "雾起时，别相信你看到的桥。",
			"directive": {"type": "visit", "target": "moon"},
			"tone": "angry",
			"internal_note": "非法字段测试",
		})
	return JSON.stringify({
		"card_name": "XVII · 星星",
		"prophecy": "即使困在同一天里，今晚的星光也是新的。去广场看看吧。",
		"directive": {"type": "visit", "target": "plaza"},
		"tone": "testing",
		"internal_note": "试探他是否还愿意听话",
		"plant_foreshadow": {"text": "广场的许愿池会给出回应", "due_in_days": 3},
	})


func _mock_judgment() -> String:
	# 审判 prompt 注入的是 open 伏笔清单（(id) 标记），mock 应验全部当前 open 的，
	# 避免测试用例间残留 open 伏笔导致账本断言失败。
	var open_ids: Array = HeavenMemory.open_foreshadows().map(func(fs): return str(fs.get("id", "")))
	return JSON.stringify({
		"day_summary": "第五天。她去了广场，像每个顺从的日子一样。星光没有骗她——至少今晚没有。",
		"tomorrow_seed": "许愿池的水面下，有什么在等她。",
		"should_end_loop": true,
		"internal_note": "顺从得让我有些无趣",
		"memory_summary": "第五天：玩家顺从预言去了广场。",
		"key_event_ids": [_last_event_id, "evt_99999"],
		"attitude_profile_update": "玩家暂时顺从，但仍需观察。兴味未减。",
		"resolve_foreshadow_ids": open_ids,
		"mood_shift": "testing→curious",
	})


var _last_event_id := ""


# ---------------------------------------------------------------------------
# 测试用例
# ---------------------------------------------------------------------------

func _test_oracle_legal(base: Node, gm: Node) -> void:
	_mode = "legal"
	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.oracle()

	_check("oracle 成功", bool(r.get("ok", false)))
	_check("oracle 牌名原样通过", str(r.get("card_name", "")) == "XVII · 星星")
	_check("oracle tone 合法", str(r.get("tone", "")) == "testing")
	var prophecy: Dictionary = gm.heaven.get("daily_prophecy", {})
	var directive: Variant = prophecy.get("directive")
	_check("directive 已存 daily_prophecy", directive is Dictionary and str(directive.get("target", "")) == "plaza")
	var fs: Variant = r.get("foreshadow")
	if fs is Dictionary:
		_planted_fs_id = str(fs.get("id", ""))
	_check("伏笔已落账", _planted_fs_id != "" and HeavenMemory.open_foreshadows().size() == 1)


func _test_oracle_illegal(base: Node, gm: Node) -> void:
	_mode = "illegal"
	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.oracle()

	_check("illegal 仍解析成功", bool(r.get("ok", false)))
	_check("非法牌名兜底为 22 张之一", str(r.get("card_name", "")) in session._load_card_names())
	_check("非法 directive 被丢弃（当天不设局）", r.get("directive") == null)
	_check("非法 tone 回落 watching", str(r.get("tone", "")) == "watching")
	_mode = "legal"


func _test_oracle_fallback(base: Node, gm: Node) -> void:
	_mode = "error"
	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.oracle()

	_check("AI 失败回落数据牌", bool(r.get("fell_back", false)))
	_check("回落牌名在 22 张内", str(r.get("card_name", "")) in session._load_card_names())
	_check("回落预言非空", not str(r.get("prophecy", "")).is_empty())
	_check("回落不设局", r.get("directive") == null)
	_mode = "legal"


func _test_judgment_full(base: Node, gm: Node) -> void:
	# 重跑一次 legal oracle，确保 daily_prophecy = visit plaza
	var oracle_session := AIHeavenSession.new()
	oracle_session.setup(base)
	await oracle_session.oracle()

	# 程序化写入当天事件：访问了 plaza（顺从）
	var evt: Dictionary = HeavenMemory.record_event("visit", "heaven", ["plaza"], "玩家访问了广场", gm.current_day)
	_last_event_id = str(evt.get("id", ""))

	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.judgment()

	_check("judgment 成功", bool(r.get("ok", false)))
	_check("顺从判定 obey（Godot 算的，不是 AI 说的）", str(r.get("compliance", "")) == "obey")
	_check("compliance 已存 heaven", str(gm.heaven.get("daily_compliance", "")) == "obey")
	_check("明日种子已存", str(gm.heaven.get("tomorrow_seed", "")) == "许愿池的水面下，有什么在等她。")

	var summaries := HeavenMemory.recent_day_summaries(gm.current_day + 1, 3)
	_check("日结摘要已落库", summaries.size() == 1)
	if summaries.size() > 0:
		var ids: Array = summaries[0].get("key_events", [])
		_check("合法 key_event 保留", _last_event_id in ids)
		_check("伪造 key_event 被剔除", "evt_99999" not in ids)

	_check("态度画像已重写", "兴味未减" in str(HeavenMemory.get_attitude_profile().get("text", "")))
	_check("伏笔已被审判标记应验", HeavenMemory.open_foreshadows().size() == 0)

	# 第 5 天 < 软限 12：AI 提议终结应被拒绝
	_check("第 5 天终结提议被拒绝", bool(r.get("should_end_proposed", false)) and not bool(r.get("should_end_approved", true)))


## 跨天衔接：reset_loop 后昨日顺从应归档到 last_compliance，单日字段清空。
func _test_last_compliance_preserved(gm: Node) -> void:
	var day_before := int(gm.current_day)
	gm.reset_loop()
	_check("reset_loop 天数 +1", int(gm.current_day) == day_before + 1)
	_check("昨日顺从已归档 last_compliance", str(gm.heaven.get("last_compliance", "")) == "obey")
	_check("daily_prophecy 已清空", gm.heaven.get("daily_prophecy") == null)
	_check("daily_compliance 已清空", str(gm.heaven.get("daily_compliance", "x")) == "")
	gm.current_day = 5


func _test_end_gate(base: Node, gm: Node) -> void:
	gm.current_day = 14
	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.judgment()
	_check("第 14 天终结提议被批准", bool(r.get("should_end_approved", false)))
	gm.current_day = 5


func _test_judgment_fallback(base: Node, gm: Node) -> void:
	_mode = "error"
	var session := AIHeavenSession.new()
	session.setup(base)
	var r: Dictionary = await session.judgment()
	_check("judgment 失败回落", bool(r.get("fell_back", false)))
	_check("回落用固定模板", str(r.get("day_summary", "")) == AIHeavenSession.JUDGMENT_FALLBACK)
	_check("回落无明日种子", str(r.get("tomorrow_seed", "x")) == "")
	_mode = "legal"


func _test_compliance_defy_and_unset(gm: Node) -> void:
	# defy：directive 是 talk soraya，但玩家和另外两个 NPC 聊了、没理 soraya
	gm.current_day = 6
	gm.heaven["daily_prophecy"] = {"directive": {"type": "talk", "target": "soraya"}}
	HeavenMemory.record_event("talk", "padwin", ["padwin"], "玩家与 padwin 对话", 6)
	HeavenMemory.record_event("talk", "cactus_bishop", ["cactus_bishop"], "玩家与 cactus_bishop 对话", 6)
	_check("talk 指令 defy 判定", gm.compute_compliance() == "defy")

	# neutral：只和一个其他 NPC 聊了
	gm.current_day = 7
	gm.heaven["daily_prophecy"] = {"directive": {"type": "talk", "target": "soraya"}}
	HeavenMemory.record_event("talk", "padwin", ["padwin"], "玩家与 padwin 对话", 7)
	_check("talk 指令 neutral 判定", gm.compute_compliance() == "neutral")

	# 未设局：directive 为 null
	gm.heaven["daily_prophecy"] = {"directive": null}
	_check("未设局返回空串", gm.compute_compliance() == "")
	gm.current_day = 5
