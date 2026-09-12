extends Node

## 角色卡按好感度裁剪（AICard）回归测试。
## 用法：godot --headless --path . scenes/tests/test_ai_card.tscn
##
## 三件事必须守住：
##   ① 标记绝不进 prompt（`[[gate:NN]]` 是给程序看的）
##   ② 该挡的挡住（深档台词在低好感时够不着）
##   ③ 不该挡的别误伤（规则说明行、底线章节、任意档内容）

const AICardScript := preload("res://scripts/systems/ai_card.gd")

const CARDS := {
	"padwin": "res://ai/npc_padwin.txt",
	"soraya": "res://ai/npc_soraya.txt",
	"cactus": "res://ai/npc_cactus_bishop.txt",
}

var _failures := 0
var _passes := 0


func _ready() -> void:
	_run()
	if _failures > 0:
		printerr("[CARD] 失败 %d 项" % _failures)
		get_tree().quit(1)
	else:
		print("[CARD] 全部完成: %d 通过, 0 失败" % _passes)
		get_tree().quit(0)


func _check(check_name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[CARD] PASS  ", check_name)
	else:
		_failures += 1
		printerr("[CARD] FAIL  ", check_name)


func _low(id: String) -> String:
	return AICardScript.load_gated(CARDS[id], 25)


func _high(id: String) -> String:
	return AICardScript.load_gated(CARDS[id], 100)


func _run() -> void:
	_card_files_present()
	_marks_never_leak()
	_gates_strip_deep_tiers()
	_no_false_positives()
	_structure_survives()
	_clue_brief()
	_tian_facts_aligned()


## 天的「事实层」必须与侵蚀机制一致：跨天记忆是帕德温独有的裂口。
## 旧版写着"三位 NPC 都有察觉循环的能力"、"NPC 可以记得跨循环的事"——那两句
## 会让天给每个 NPC 都写跨天台词，一次把三张卡全写塌。锁死。
func _tian_facts_aligned() -> void:
	var text := FileAccess.get_file_as_string("res://ai/tian_system.txt")
	_check("tian 可读", text.length() > 1000)
	for stale in ["三位 NPC", "都拥有在不同程度上察觉循环存在的能力", "NPC 可以记得跨循环的事"]:
		_check("tian 无过时表述: %s" % stale, stale not in text)
	_check("tian 声明跨天记忆的唯一例外", "跨天记忆只有一个例外" in text)
	_check("tian 例外指向帕德温", "跨天记忆只有一个例外：帕德温" in text)
	_check("tian 有侵蚀代价层", "这座收容所有代价" in text and "症状，不是故事" in text)


func _card_files_present() -> void:
	for id in CARDS:
		_check("卡片可读: %s" % id, AICardScript.load_gated(CARDS[id], 50).length() > 2000)


## ① 标记是给程序看的，任何好感度下都不能出现在输出里
func _marks_never_leak() -> void:
	for id in CARDS:
		for aff in [0, 25, 50, 60, 70, 80, 100]:
			var out := AICardScript.load_gated(CARDS[id], aff)
			if "[[gate:" in out:
				_check("标记未泄漏: %s @%d" % [id, aff], false)
				return
	_check("标记在所有档位下都不泄漏", true)


## ② 该挡的挡住
func _gates_strip_deep_tiers() -> void:
	var low := _low("padwin")
	var high := _high("padwin")
	# 标题闸（[[gate:]]）：暧昧天花板 70 / 克制的言语流露 60
	_check("padwin 低好感摘掉暧昧天花板", "## 暧昧天花板" not in low and "## 暧昧天花板" in high)
	_check("padwin 低好感摘掉克制的言语流露", "## 克制的言语流露" not in low)
	_check("padwin 高好感保留克制的言语流露", "## 克制的言语流露" in high)
	# 关键词闸（标题里的"好感 NN+"）：话题池的 60+/80+ 档
	_check("padwin 低好感摘掉话题池 60+ 档", "## 好感 60+ 档" not in low)
	_check("padwin 高好感保留话题池 60+ 档", "## 好感 60+ 档" in high)
	# 关键词闸（列表项）
	_check("padwin 低好感摘掉深档台词", "有人递过番茄给我" not in low and "有人递过番茄给我" in high)

	var low_c := _low("cactus")
	var high_c := _high("cactus")
	_check("cactus 低好感摘掉「我替你醒着」", "我替你醒着" not in low_c and "我替你醒着" in high_c)
	_check("cactus 低好感摘掉对主角档", "唯一一个醒着、却没有被疼毁掉的人" not in low_c)

	var high_s := _high("soraya")
	_check("soraya 高好感保留少数真心话", "少数真心话" in high_s)
	_check("soraya 低好感摘掉少数真心话", "少数真心话" not in _low("soraya"))

	# 裁完确实更短（这是省 token 的那一面）
	_check("padwin 低好感确实更短", low.length() < high.length())
	_check("cactus 低好感确实更短", low_c.length() < high_c.length())


## ③ 不该挡的别误伤
func _no_false_positives() -> void:
	var low := _low("padwin")
	# 「标注"好感 60+/80+"的话题…」是规则说明行，不是档位——不能因为正文提到好感就摘掉
	_check("规则说明行不被误摘", "不得主动起" in low)
	# 任意档内容必须在
	_check("任意档内容保留", "打量与戒备生客" in low)
	# 底线章节是高压线，任何好感度都得在
	for id in CARDS:
		_check("底线章节始终保留: %s" % id, "底线（这些一出口，人设就塌）" in _low(id))
	# 好感 50 时，60 档仍应被摘、但 50 档本身（cactus 对主角）应保留
	_check("cactus 好感 50 保留对主角档", "唯一一个醒着、却没有被疼毁掉的人" in AICardScript.load_gated(CARDS["cactus"], 50))


## 裁剪不能把章节结构剪坏
func _structure_survives() -> void:
	for id in CARDS:
		var low := _low(id)
		var high := _high(id)
		_check("%s 仍有一级标题" % id, low.count("\n# ") > 0)
		_check("%s 标题只减不增" % id, low.count("\n## ") <= high.count("\n## "))
		_check("%s 无残留空标题" % id, not ("\n## \n" in low) and not ("\n### \n" in low))
		# 被摘掉的节不能留下"断头"——最后一个非空行不应是一个悬空的列表标记
		var tail: String = low.strip_edges().split("\n")[-1]
		_check("%s 结尾不是空列表项" % id, tail.strip_edges() != "-" and tail.strip_edges() != "#")


## 线索注入：名字 —— 描述；占位描述（"待补"）不给
func _clue_brief() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		_check("GameManager 可用", false)
		return
	var brief := str(gm.clue_brief("clue_padwin_no_memory"))
	_check("线索简报带名字", "帕德温挡脸的那只手" in brief)
	_check("线索简报带描述", "不是疹子" in brief)
	_check("线索简报是单行", not ("\n" in brief))
	# clue_forest_fake 的描述是文案同学的"（待补…）"占位——宁可什么都不给
	var placeholder := str(gm.clue_brief("clue_forest_fake"))
	_check("占位描述不注入", "待补" not in placeholder and placeholder == "塔楼中的森林起源之书")
	# 名字必须与 clues.json 对齐（两套名字分叉会让面板"标题和描述不是一回事"）
	var mismatched: Array = []
	for cid in gm.CLUE_NAMES:
		var desc := str(gm.clue_description(str(cid)))
		if desc == "":
			continue
		var f := FileAccess.open("res://resources/data/clues.json", FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		var json_name := str(parsed["clues"].get(cid, {}).get("name", ""))
		if json_name != "" and json_name != str(gm.CLUE_NAMES[cid]):
			mismatched.append(cid)
	_check("线索名与 clues.json 对齐", mismatched.is_empty())
