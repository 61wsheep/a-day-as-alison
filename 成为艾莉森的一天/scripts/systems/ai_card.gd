class_name AICard
extends RefCounted

## 角色卡按好感度裁剪（门控挡刀的成本面）。
##
## 背景：角色卡每次请求**全量**进 system prompt。三张卡各 ~21KB ≈ 5~6k tokens，
## 而里面最深的那几档（好感 90+ 的告白级台词）在好感 25 时也照样躺着——
## 守不守得住全靠模型自律，而且每一次都要为这个阶段用不到的深档付 prefill。
##
## 这里在装配 payload 时按当前好感度把"还没到档"的内容摘掉。
##
## 裁剪规则（**只认好感度，不认天数**——天数可上可下，好感度单调，不会误伤）：
##   ① 标题闸：
##      a. 标题里写"好感 NN+"（如 `## 好感 60+ 档`）→ 整节摘掉
##      b. 标题尾部挂 `[[gate:NN]]` → 整节摘掉（给没有数字档位可依的语气例句用）
##      节的范围 = 到下一个同级或更高级标题为止
##   ② 列表项闸：列表项以"好感 NN+"（或"第 N 天起且好感 NN+"）开头 → 只摘这一行及其续行
##
## ①② 都顺着现有卡片的写法走，所以绝大多数内容不需要加标记；`[[gate:NN]]`
## 只用来补①a 够不到的地方（语气例句的深档）。标记本身永远不进 prompt。

## 显式闸标记：`[[gate:60]]`
const MARK_OPEN := "[[gate:"


## 摘掉好感度未到档的内容。affection 为当前好感度（0-100）。
static func gate(text: String, affection: int) -> String:
	var out := PackedStringArray()
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line: String = lines[i]

		# ① 标题闸：整节摘掉
		var level := _heading_level(line)
		if level > 0:
			var h := _heading_gate(line)
			if h > 0 and affection < h:
				i += 1
				while i < lines.size():
					var lv := _heading_level(lines[i])
					if lv > 0 and lv <= level:
						break
					i += 1
				continue
			out.append(strip_marks(line))
			i += 1
			continue

		# ② 列表项闸：只摘这一条（含其缩进续行）
		var b := _bullet_gate(line)
		if b > 0 and affection < b:
			var indent := _indent_width(line)
			i += 1
			while i < lines.size():
				var nxt: String = lines[i]
				if nxt.strip_edges() == "" or _indent_width(nxt) <= indent:
					break
				i += 1
			continue

		out.append(strip_marks(line))
		i += 1
	return "\n".join(out)


## 读文件并按好感度裁剪。文件不存在返回空串（与旧 _read_file 行为一致）。
static func load_gated(path: String, affection: int) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return ""
	return gate(text.strip_edges(), affection)


## 去掉所有 `[[gate:NN]]` 标记（标记是给程序看的，绝不能进 prompt）。
static func strip_marks(line: String) -> String:
	var s := line
	while true:
		var at := s.find(MARK_OPEN)
		if at < 0:
			break
		var end := s.find("]]", at)
		if end < 0:
			break
		s = s.substr(0, at) + s.substr(end + 2)
	return s.strip_edges(false, true)


## 该行是几级标题（`## x` → 2）；不是标题返回 0。
static func _heading_level(line: String) -> int:
	var s := line.strip_edges(true, false)
	var n := 0
	while n < s.length() and s[n] == "#":
		n += 1
	if n == 0 or n >= s.length() or s[n] != " ":
		return 0
	return n


## 标题闸的档位：`## 好感 60+ 档` → 60，`## x [[gate:70]]` → 70，两者取大；没有则 0。
static func _heading_gate(line: String) -> int:
	if _heading_level(line) == 0:
		return 0
	return maxi(_find_affection_gate(line), _find_mark_gate(line))


## 列表项里的好感闸。只认**开头的**条件，正文里提到的"好感"不算数——
## 否则「标注"好感 60+/80+"的话题…」这种规则说明会被误摘。
static func _bullet_gate(line: String) -> int:
	var s := line.strip_edges(true, false)
	if s.length() < 2 or s[1] != " ":
		return 0
	if s[0] != "-" and s[0] != "*" and s[0] != "+":
		return 0
	var body := s.substr(2).strip_edges(true, false)
	# 允许"第 N 天起(且)"作前缀：天数本身不作为裁剪依据，但要能认出后面那一截
	if body.begins_with("第"):
		var q := body.find("天起")
		if q < 0:
			return 0
		body = body.substr(q + 2).strip_edges(true, false)
		if body.begins_with("且"):
			body = body.substr(1).strip_edges(true, false)
	if not body.begins_with("好感"):
		return 0
	return _find_affection_gate(body)


## 在字符串里找"好感 <数字>+"，返回数字；找不到返回 0。
static func _find_affection_gate(s: String) -> int:
	var at := s.find("好感")
	if at < 0:
		return 0
	var i := at + 2
	while i < s.length() and s[i] == " ":
		i += 1
	var num := ""
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		num += s[i]
		i += 1
	if num == "" or i >= s.length() or s[i] != "+":
		return 0
	return int(num)


## 在字符串里找 `[[gate:NN]]`，返回 NN；找不到返回 0。
static func _find_mark_gate(s: String) -> int:
	var at := s.find(MARK_OPEN)
	if at < 0:
		return 0
	var i := at + MARK_OPEN.length()
	var num := ""
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		num += s[i]
		i += 1
	if num == "":
		return 0
	return int(num)


static func _indent_width(line: String) -> int:
	var n := 0
	while n < line.length() and (line[n] == " " or line[n] == "\t"):
		n += 1
	return n
