extends SceneTree

## HeavenMemoryStore / MemoryQuery 离线单测（第一步地基，无 AI）。
## 运行：godot --headless -s res://scripts/tests/test_heaven_memory.gd --quit
## 存储隔离在 user://memory_test，不污染正式记忆。

const HeavenMemory := preload("res://scripts/systems/heaven_memory.gd")
const MemoryQuery := preload("res://scripts/systems/memory_query.gd")

var _failures := 0
var _passes := 0


func _init() -> void:
	_setup()
	_test_event_record_and_reload()
	_test_importance_rules()
	_test_recency_decay()
	_test_owner_isolation()
	_test_npc_query_isolation()
	_test_day_summary_whitelist()
	_test_attitude_profile_clamp()
	_test_foreshadow_lifecycle()

	print("[TEST] HeavenMemory: %d 通过, %d 失败" % [_passes, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _setup() -> void:
	HeavenMemory.set_storage_dir("user://memory_test")
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove("memory_test/events.jsonl")
		dir.remove("memory_test/day_summaries.json")
		dir.remove("memory_test/attitude_profile.json")
		dir.remove("memory_test/relation_cards.json")
		dir.remove("memory_test/foreshadows.json")


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[TEST] FAIL  ", name)


func _test_event_record_and_reload() -> void:
	var evt: Dictionary = HeavenMemory.record_event("clue", "heaven", ["clue_forest_fake", "tower"], "玩家发现线索：塔楼中的森林起源之书", 3)
	_check("事件写入返回 id", str(evt.get("id", "")).begins_with("evt_"))
	_check("事件进缓存", HeavenMemory.all_events().size() == 1)
	_check("按天检索", HeavenMemory.events_for_day(3).size() == 1 and HeavenMemory.events_for_day(4).size() == 0)
	# 模拟重启：清缓存强制从磁盘重载
	HeavenMemory.set_storage_dir("user://memory_test")
	_check("重启后从磁盘恢复", HeavenMemory.all_events().size() == 1)
	var evt2: Dictionary = HeavenMemory.record_event("visit", "heaven", ["plaza"], "玩家访问了广场", 4)
	_check("重载后 id 不重号", str(evt2.get("id", "")) != str(evt.get("id", "")))


func _test_importance_rules() -> void:
	var clue: Dictionary = HeavenMemory.record_event("clue", "heaven", [], "线索事件", 4)
	var visit: Dictionary = HeavenMemory.record_event("visit", "heaven", [], "访问事件", 4)
	_check("线索 importance=8", int(clue.get("importance", 0)) == 8)
	_check("访问 importance=2", int(visit.get("importance", 0)) == 2)
	var custom: Dictionary = HeavenMemory.record_event("talk", "heaven", [], "自定义", 4, 9)
	_check("importance 可覆盖", int(custom.get("importance", 0)) == 9)


func _test_recency_decay() -> void:
	var old: Dictionary = HeavenMemory.record_event("talk", "heaven", [], "三天前的对话", 1)
	var recent: Dictionary = HeavenMemory.record_event("talk", "heaven", [], "今天的对话", 4)
	var s_old := HeavenMemory.score_event(old, 4, [])
	var s_recent := HeavenMemory.score_event(recent, 4, [])
	_check("近期事件分数更高", s_recent > s_old)


func _test_owner_isolation() -> void:
	HeavenMemory.record_event("talk", "padwin", ["padwin"], "玩家与 padwin 密谈", 4)
	var soraya_view := HeavenMemory.top_events(4, [], ["soraya"], 10)
	var leaked := false
	for evt in soraya_view:
		if "padwin 密谈" in str(evt.get("fact", "")):
			leaked = true
	_check("soraya 检索不到 padwin 私密事件", not leaked)
	var heaven_view := HeavenMemory.top_events(4, [], ["heaven"], 10)
	var heaven_also_blind := false
	for evt in heaven_view:
		if "padwin 密谈" in str(evt.get("fact", "")):
			heaven_also_blind = true
	_check("天层检索也不含 NPC 私密事件", not heaven_also_blind)


func _test_npc_query_isolation() -> void:
	var block := MemoryQuery.assemble(MemoryQuery.MASK_NPC, {"current_day": 4, "npc_id": "soraya"})
	_check("soraya 注入块不含 padwin 私密", "padwin 密谈" not in block)


func _test_day_summary_whitelist() -> void:
	var real_id: String = str(HeavenMemory.all_events()[0].get("id", ""))
	var entry: Dictionary = HeavenMemory.apply_day_summary_ai(4, "第四天。玩家继续探索。", [real_id, "evt_99999"], "watching→testing")
	var ids: Array = entry.get("key_events", [])
	_check("合法 key_event 保留", real_id in ids)
	_check("伪造 key_event 被剔除", "evt_99999" not in ids)
	_check("摘要可检索", HeavenMemory.recent_day_summaries(5, 3).size() == 1)


func _test_attitude_profile_clamp() -> void:
	var long_text := "长".repeat(300)
	HeavenMemory.apply_attitude_profile_ai(long_text, 4)
	var profile := HeavenMemory.get_attitude_profile()
	_check("态度画像超长截断", str(profile.get("text", "")).length() == 150)
	_check("记录更新天数", int(profile.get("updated_day", 0)) == 4)


func _test_foreshadow_lifecycle() -> void:
	var fs: Dictionary = HeavenMemory.plant_foreshadow("塔楼钟声与循环有关", 2, 3)
	_check("伏笔埋设 open", str(fs.get("status", "")) == "open")
	_check("open 列表可见", HeavenMemory.open_foreshadows().size() == 1)
	_check("重复 resolve 拒绝", HeavenMemory.resolve_foreshadow("fs_999", 4) == false)
	_check("正常 resolve", HeavenMemory.resolve_foreshadow(str(fs["id"]), 4) == true)
	_check("resolve 后离开 open 列表", HeavenMemory.open_foreshadows().size() == 0)
	var fs2: Dictionary = HeavenMemory.plant_foreshadow("会烂尾的伏笔", 2, 2)
	var expired := HeavenMemory.expire_foreshadows(5)
	_check("过期伏笔转 expired", expired.size() == 1 and str(expired[0].get("id", "")) == str(fs2["id"]))
