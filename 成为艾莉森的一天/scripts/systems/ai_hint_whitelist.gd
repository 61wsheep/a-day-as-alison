class_name AIHintWhitelist
extends RefCounted

## AI 输出 hint → 线索 id 白名单。
##
## AI 只输出"表现"，不能直接解锁线索。hints_to_other_npcs 是 AI 生成的自由文本，
## 必须经本白名单关键词映射到 GameManager 的合法 clue_id 才允许 discover_clue。
## 大剧情节点（soraya_confronted 等）仍走 JSON effects.discover_clue，AI 无权触碰。

const KEYWORDS := {
	"clue_padwin_no_memory": ["番茄", "过敏", "前世", "记不清", "不认识", "没有印象"],
	"clue_cactus_scar": ["勒痕", "颈", "伤疤", "主教", "自缢"],
	"clue_soraya_repeat": ["一模一样", "重复", "迎接", "机械", "说同样的话"],
	"clue_burn_scar": ["烧伤", "疤痕", "背上", "背"],
	"clue_forest_fake": ["起源", "塔楼里的书", "森林之书", "起源之书"],
	"clue_id_card": ["身份证", "树屋里的照片", "照片"],
}


## 解析 hint 文本，命中关键词则返回对应 clue_id，否则返回 ""。
static func resolve(hint: String) -> String:
	for clue_id in KEYWORDS:
		var kws: Array = KEYWORDS[clue_id]
		for kw in kws:
			if str(kw) in hint:
				return clue_id
	return ""
