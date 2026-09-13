extends SceneTree

## 对话链路守卫：脚本剧情条目不许把 AI 日谈永久挡住。
## 运行：godot --headless --path . -s res://scripts/tests/test_dialogue_ai_gate.gd
##
## 症状（真机反馈 2026-09-13）：与索拉雅对话选过「做你自己」之后，每次搭话都是同一段
## 固定台词，AI 对话再也起不来。**根因不是链路切换坏了**（S1/S2 判定本身没错），
## 而是优先级压制：
##   - _select_dialogue() 只认 priority 最高者
##   - ai:true 的 daily_* 池 pri=10
##   - awakened 条目 pri=80，条件 {"flag":["soraya_awakened"]} 是**粘性 flag**，
##     且 end_effects 为空 —— 一旦置位就永远压着 daily 池，于是永远走 JSON 路径
##
## 本测试锁两件事：
##   ① 行为：一次性剧情条目播完必须释放，落回 AI 日谈（索拉雅真机路径复现）
##   ② 静态：pri>10 且非 ai 的条目，凡是靠粘性 flag 命中的，必须自带释放
##      （flag_not 的那个 flag 由它自己置位）。防的是同一类坑换个 NPC 再犯。

const HelpersScript := preload("res://scripts/tests/test_helpers.gd")
const DIALOGUE_DIR := "res://resources/dialogues"
const SORAYA_SCENE := "res://scenes/npc_soraya.tscn"

## 靠外部机制释放、因而豁免静态检查的条目（键 = 文件名/条目 id）。
## 有豁免必须写清释放者，否则守卫会退化成人人加白名单。
const EXTERNAL_RELEASE := {
	"padwin/divine_offer": "委托完成后 quest_active_tarot_padwin_01 被清除（见 test_quest.gd:88 / test_tarot_quest.gd:170）",
}

var _failures := 0
var _passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _test_soraya_awakened_path()
	_static_scan()
	print("[AIGATE] 对话链路守卫: %d 通过, %d 失败" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		_passes += 1
		print("[AIGATE] PASS  ", name)
	else:
		_failures += 1
		printerr("[AIGATE] FAIL  ", name, ("  ← " + detail) if detail != "" else "")


# ------------------------------------------------------------
# ① 索拉雅真机路径：confront → 选「做你自己」→ 之后还能不能进 AI 日谈
# ------------------------------------------------------------

func _test_soraya_awakened_path() -> void:
	var gm = root.get_node_or_null("GameManager")
	if gm == null:
		printerr("[AIGATE] 无 GameManager autoload，跳过行为测试")
		return
	var npc: Node = (load(SORAYA_SCENE) as PackedScene).instantiate()
	root.add_child(npc)
	await process_frame

	# 清干净，别被本机存档里的 flag 干扰
	for f in ["met_soraya", "soraya_confronted", "soraya_awakened", "soraya_awakened_spoken"]:
		gm.flags.erase(f)
	gm.current_day = 5

	# 真机路径逐步重放，顺带确认每一步选中的条目（诊断信息也留在这）
	gm.set_flag("met_soraya")
	_check("第 2 天见过面 → confront（剧情必经，不是 bug）",
		str(npc._select_dialogue().get("id", "")) == "confront")

	# confront 里选「你是不是记得所有的循环」→ 释放 confront
	gm.set_flag("soraya_confronted")
	var after_confront: Dictionary = npc._select_dialogue()
	_check("面对过之后 → 落回 AI 日谈",
		bool(after_confront.get("ai", false)),
		"实际选中 " + str(after_confront.get("id", "")))

	# 继续选「做你自己」→ 觉醒
	gm.set_flag("soraya_awakened")
	var first: Dictionary = npc._select_dialogue()
	_check("觉醒后的第一次搭话 → 唤醒独白（该演，别删）",
		str(first.get("id", "")) == "awakened",
		"实际选中 " + str(first.get("id", "")))

	# 独白演完（end_effects 释放）→ 必须落回 AI 日谈
	var spoken := "soraya_awakened_spoken"
	gm.apply_effects(_entry_end_effects("soraya.json", "awakened"))
	_check("觉醒独白自带释放 flag（end_effects 非空）", gm.has_flag(spoken),
		"awakened.end_effects 里没有 %s，这段独白会永远压着 daily 池" % spoken)
	var second: Dictionary = npc._select_dialogue()
	_check("独白演完后 → 落回 AI 日谈（本次真机 bug 的判据）",
		bool(second.get("ai", false)),
		"实际选中 " + str(second.get("id", "")) + "（非 ai 条目会永久挡住 AI 对话）")

	npc.queue_free()


# ------------------------------------------------------------
# ② 静态守卫：同类坑换个 NPC 再犯也拦得住
# ------------------------------------------------------------

func _static_scan() -> void:
	var dir := DirAccess.open(DIALOGUE_DIR)
	if dir == null:
		_check("能打开对话目录", false, DIALOGUE_DIR)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data := _load_json("%s/%s" % [DIALOGUE_DIR, file])
		if data.is_empty():
			continue
		for entry in data.get("dialogues", []):
			_check_entry(file, entry)


func _check_entry(file: String, entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	var key := "%s/%s" % [file.replace(".json", ""), id]
	if bool(entry.get("ai", false)) or int(entry.get("priority", 0)) <= 10:
		return
	# 纯时间门（如 tower_voice/qna 的 {"time":"midnight"}）本身就会自己过期，不算粘性
	var cond: Dictionary = entry.get("conditions", {})
	if not cond.has("flag"):
		return
	if EXTERNAL_RELEASE.has(key):
		return
	var gated: Array = cond.get("flag_not", [])
	var self_set := _entry_set_flags(entry)
	var released := false
	for g in gated:
		if g in self_set:
			released = true
			break
	_check("%s：pri=%d 靠粘性 flag 命中，且自带释放" % [key, int(entry.get("priority", 0))],
		released,
		"它会在 flag 为真期间永久压住 pri=10 的 AI 日谈池；"
		+ "加 conditions.flag_not 并在 end_effects/选项 effects 里置位，或登记进 EXTERNAL_RELEASE")


## 该条目自己能置位的 flag（入口 end_effects + 各选项 effects/end_effects）。
func _entry_set_flags(entry: Dictionary) -> Array:
	var out: Array = []
	for f in entry.get("end_effects", {}).get("set_flag", []):
		out.append(f)
	for line in entry.get("lines", []):
		for choice in line.get("choices", []):
			for f in choice.get("effects", {}).get("set_flag", []):
				out.append(f)
			for f in choice.get("end_effects", {}).get("set_flag", []):
				out.append(f)
	return out


func _entry_end_effects(file: String, id: String) -> Dictionary:
	var data := _load_json("%s/%s" % [DIALOGUE_DIR, file])
	for entry in data.get("dialogues", []):
		if str(entry.get("id", "")) == id:
			return entry.get("end_effects", {})
	return {}


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
