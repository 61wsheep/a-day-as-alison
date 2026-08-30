extends SceneTree

## 多天无头模拟器 —— 不进游戏、不开窗口，跑 N 个完整回合，输出态度数值 CSV。
##
## 用途：校准 §3.4 规则表数值、观察不同玩家策略下 20 天的态度演化曲线。
##
## 运行：
##   godot --headless -s res://scripts/tests/sim_multi_day.gd -- --days=20 --policy=mixed
##   policy: obeyer（永远顺从）/ rebel（永远反抗）/ wanderer（从不理会）/ mixed（混合）
## 输出：user://sim_report_<policy>.csv（控制台会打印绝对路径与汇总表）
##
## 结构：策略化 mock「天」（会看状态变脸、会埋/应验伏笔）
##     + 策略化玩家（按 policy 响应 directive，附带随机的对话/线索/好感行为）
##     + 真实链路：oracle → 白天事件 → judgment → apply_heaven_rules → reset_loop

const HeavenSession := preload("res://scripts/systems/ai_heaven_session.gd")
const HeavenMemory := preload("res://scripts/systems/heaven_memory.gd")

const CARD_POOL: Array = ["0 · 愚人", "IX · 隐士", "XIV · 节制", "XVI · 高塔", "XVII · 星星", "XXI · 世界"]
const PLACES: Array = ["plaza", "treehouse_district", "stone_nest_tower"]
const NPCS: Array = ["soraya", "padwin", "cactus_bishop"]

var _days := 20
var _policy := "mixed"
var _gm: Node = null
var _host: Node = null
var _rows: Array = []          # CSV 行
var _player_action := ""       # 今日玩家策略动作（obey/defy/neutral）


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_parse_args()
	seed(42)   # 固定随机种子：模拟可复现，调参时可对比

	_gm = root.get_node_or_null("GameManager")
	var bridge: Node = root.get_node_or_null("AIBridge")
	if _gm == null or bridge == null:
		printerr("[SIM] 无 GameManager/AIBridge autoload，退出")
		quit(1)
		return
	bridge.set_enabled(true)
	bridge.set_mock_responder(_mock_heaven)
	_setup_memory()

	_host = Node.new()
	root.add_child(_host)
	_gm.current_day = 1

	for day in range(1, _days + 1):
		await _sim_day(day)

	var path := _write_report()
	_print_summary()
	print("[SIM] 报告已写入：%s" % path)
	quit(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			_days = clampi(int(arg.trim_prefix("--days=")), 1, 20)
		elif arg.begins_with("--policy="):
			_policy = arg.trim_prefix("--policy=")


func _setup_memory() -> void:
	HeavenMemory.set_storage_dir("user://memory_sim")
	var dir := DirAccess.open("user://")
	if dir:
		for f in ["events.jsonl", "day_summaries.json", "attitude_profile.json", "relation_cards.json", "foreshadows.json"]:
			dir.remove("memory_sim/%s" % f)


# ============================================================
# 单日完整回合（真实链路）
# ============================================================

func _sim_day(day: int) -> void:
	_gm.current_day = day
	# 第 2 天起由 reset_loop 快照好感度基线；第 1 天补一次
	if day == 1:
		_gm.set("_affection_day_start", _gm.npc_affection.duplicate())

	var session := HeavenSession.new()
	session.setup(_host)
	var oracle: Dictionary = await session.oracle()

	_simulate_player_day(day, oracle.get("directive"))

	var judgment: Dictionary = await session.judgment()
	_gm.apply_heaven_rules()
	_collect_row(day, oracle, judgment)
	if day < _days:
		_gm.reset_loop()


# ============================================================
# 策略化玩家
# ============================================================

func _simulate_player_day(day: int, directive: Variant) -> void:
	# 1) 对 directive 的响应（按 policy）
	_player_action = "none"
	if directive is Dictionary:
		_player_action = _policy_action(day)
		_apply_action(str(directive.get("type", "")), str(directive.get("target", "")))

	# 2) 随机环境行为：0-1 次闲聊、偶发好感变化、每 ~3 天发现一条线索
	if randi() % 2 == 0:
		var npc := str(NPCS[randi() % NPCS.size()])
		_gm.record_heaven_event("talk", "玩家与 %s 闲聊" % npc, [npc, str(_gm.current_area)], npc)
	if randi() % 3 == 0:
		var npc := str(NPCS[randi() % NPCS.size()])
		_gm.change_affection(npc, randi_range(-3, 5))
	if day % 3 == 0:
		for clue_id in _gm.CLUE_NAMES:
			if clue_id not in _gm.clues_found:
				_gm.discover_clue(clue_id)   # discover_clue 内部已打 clue 事件
				break


func _policy_action(day: int) -> String:
	match _policy:
		"obeyer":
			return "obey"
		"rebel":
			return "defy"
		"wanderer":
			return "neutral"
		_:   # mixed：3 天一轮 → 顺从/反抗/不理
			return ["obey", "defy", "neutral"][day % 3]


func _apply_action(dtype: String, target: String) -> void:
	match _player_action:
		"obey":
			if dtype == "visit":
				_gm.record_heaven_event("visit", "玩家来到了 %s" % target, [target])
			else:
				_gm.record_heaven_event("talk", "玩家应预言与 %s 交谈" % target, [target], target)
		"defy":
			if dtype == "visit":
				var other := _pick_other(PLACES, target)
				_gm.record_heaven_event("visit", "玩家去了 %s" % other, [other])
				_gm.record_heaven_event("talk", "玩家在 %s 与人交谈" % other, [other, "padwin"], "padwin")
			else:
				for npc in NPCS:
					if npc != target:
						_gm.record_heaven_event("talk", "玩家与 %s 交谈" % npc, [npc], npc)
		_:
			pass   # neutral：不理会


func _pick_other(pool: Array, exclude: String) -> String:
	var candidates := pool.filter(func(x): return str(x) != exclude)
	return str(candidates[randi() % candidates.size()]) if candidates.size() > 0 else exclude


# ============================================================
# 策略化 mock「天」
# ============================================================

func _mock_heaven(payload: Dictionary) -> String:
	var user := str(payload.get("user", ""))
	if "天命面具" in user:
		return _mock_oracle()
	return _mock_judgment()


func _mock_oracle() -> String:
	var day := int(_gm.current_day)
	var ben := float(_gm.heaven.get("benevolence", 0.0))
	var eng := float(_gm.heaven.get("engagement", 0.3))
	var tone := "watching"
	if ben > 0.2:
		tone = "gentle"
	elif ben < -0.2:
		tone = "cold"
	elif eng > 0.6:
		tone = "testing"

	var directive: Variant = null
	if day % 3 != 0:   # 2/3 的天设局
		if day % 2 == 0:
			directive = {"type": "visit", "target": str(PLACES[day % PLACES.size()])}
		else:
			directive = {"type": "talk", "target": str(NPCS[day % NPCS.size()])}

	var fs: Variant = null
	if day % 5 == 1:   # 每 5 天埋一条伏笔
		fs = {"text": "第 %d 天埋下的伏笔" % day, "due_in_days": 4}

	return JSON.stringify({
		"card_name": str(CARD_POOL[day % CARD_POOL.size()]),
		"prophecy": "（第 %d 天的预言诗）" % day,
		"directive": directive,
		"tone": tone,
		"internal_note": "（第 %d 天的意图）" % day,
		"plant_foreshadow": fs,
	})


func _mock_judgment() -> String:
	var day := int(_gm.current_day)
	var ben := float(_gm.heaven.get("benevolence", 0.0))
	var eng := float(_gm.heaven.get("engagement", 0.3))
	# 偶数天应验全部 open 伏笔
	var resolve_ids: Array = []
	if day % 2 == 0:
		resolve_ids = HeavenMemory.open_foreshadows().map(func(f): return str(f.get("id", "")))
	return JSON.stringify({
		"day_summary": "（第 %d 天的回顾）" % day,
		"tomorrow_seed": "（第 %d 天的明日种子）" % day,
		"should_end_loop": ben > 0.5,
		"internal_note": "（内部评价）",
		"memory_summary": "（第 %d 天摘要）" % day,
		"key_event_ids": [],
		"attitude_profile_update": "善意 %.2f / 兴趣 %.2f 时的画像" % [ben, eng],
		"resolve_foreshadow_ids": resolve_ids,
		"mood_shift": "",
	})


# ============================================================
# 报告
# ============================================================

func _collect_row(day: int, oracle: Dictionary, judgment: Dictionary) -> void:
	var today := HeavenMemory.events_for_day(day)
	var talks := 0
	var clues := 0
	for evt in today:
		var t := str(evt.get("type", ""))
		if t == "talk":
			talks += 1
		elif t == "clue":
			clues += 1
	_rows.append({
		"day": day,
		"card": str(oracle.get("card_name", "")),
		"tone": str(oracle.get("tone", "")),
		"action": _player_action,
		"compliance": str(_gm.heaven.get("daily_compliance", "")),
		"benevolence": "%.3f" % float(_gm.heaven.get("benevolence", 0.0)),
		"engagement": "%.3f" % float(_gm.heaven.get("engagement", 0.0)),
		"truth": "%.3f" % float(_gm.heaven.get("truth_proximity", 0.0)),
		"resistance": int(_gm.heaven.get("prophecy_resistance", 0)),
		"talks": talks,
		"clues_today": clues,
		"clues_total": _gm.clues_found.size(),
		"fs_open": HeavenMemory.open_foreshadows().size(),
		"end_approved": judgment.get("should_end_approved", false),
	})


func _write_report() -> String:
	var path := "user://sim_report_%s.csv" % _policy
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "(写入失败)"
	var headers: Array = []
	if _rows.size() > 0:
		headers = _rows[0].keys()
	f.store_line(",".join(headers))
	for row in _rows:
		var cells: Array = []
		for h in headers:
			cells.append(str(row.get(h, "")))
		f.store_line(",".join(cells))
	f.close()
	return ProjectSettings.globalize_path(path)


func _print_summary() -> void:
	print("\n[SIM] ===== 策略：%s · %d 天 =====" % [_policy, _days])
	print("[SIM] 天数 | 动作    | 判定    | 善意   | 兴趣  | 真相  | 反抗")
	for row in _rows:
		print("[SIM] %4d | %-7s | %-7s | %6s | %5s | %5s | %d" % [
			int(row["day"]), str(row["action"]), str(row["compliance"]),
			str(row["benevolence"]), str(row["engagement"]), str(row["truth"]),
			int(row["resistance"]),
		])
	if _rows.size() > 0:
		var last: Dictionary = _rows[_rows.size() - 1]
		print("[SIM] 终态：善意 %s / 兴趣 %s / 真相 %s / 反抗 %d / 线索 %d / open伏笔 %d" % [
			str(last["benevolence"]), str(last["engagement"]), str(last["truth"]),
			int(last["resistance"]), int(last["clues_total"]), int(last["fs_open"]),
		])
