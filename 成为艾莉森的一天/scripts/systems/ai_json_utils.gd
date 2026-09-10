class_name AIJsonUtils
extends RefCounted

## LLM 响应 JSON 三层恢复 + required 字段校验。
## 移植自 ai_verify/utils/json_parser.py 的 parse_json_response。
##
## 恢复顺序：
##   1. 整段直接 json.loads
##   2. 提取 ```json ... ``` 代码块
##   3. 提取第一个 { ... } 块
## 全部失败返回 { success: false }。


## 宽松模式缺失字段的默认值（仅对话面具用；天命/审判不开宽松）。
const LENIENT_DEFAULTS := {
	"emotional_shift": 0,
	"memory_update": "",
	"internal_note": "",
	"should_end_conversation": false,
	"topic_suggestions": [],
	"hints_to_other_npcs": [],
}


## 解析响应文本。raw 为空返回失败。required_fields 存在时检查必填字段。
## lenient=true 时（流式截断场景）：response_text 必须存在且非空，其余 required
## 缺失则补 LENIENT_DEFAULTS —— 保证被 max_tokens 砍断的那一轮仍能结算，不至于整轮回落。
static func parse_response(raw: String, required_fields: Array = [], lenient: bool = false) -> Dictionary:
	if raw.strip_edges().is_empty():
		return {"success": false, "error": "空响应"}

	# 第 1 层：整段直接解析
	var parsed: Variant = _try_parse(raw)
	if parsed is Dictionary and _check_fields(parsed, required_fields, lenient):
		return {"success": true, "data": parsed, "method": "direct"}

	# 第 2 层：提取 ```json ... ``` 代码块
	var code_block := _extract_code_block(raw)
	if code_block != "":
		parsed = _try_parse(code_block)
		if parsed is Dictionary and _check_fields(parsed, required_fields, lenient):
			return {"success": true, "data": parsed, "method": "regex_code_block"}

	# 第 3 层：提取第一个 { ... } 块
	var braces := _extract_braces(raw)
	if braces != "":
		parsed = _try_parse(braces)
		if parsed is Dictionary and _check_fields(parsed, required_fields, lenient):
			return {"success": true, "data": parsed, "method": "regex_braces"}

	# 第 4 层：截断修复（流式撞 max_tokens 上限时 JSON 会停在一半，前三层都救不回）
	var repaired := repair_truncated_json(raw)
	if repaired != "":
		parsed = _try_parse(repaired)
		if parsed is Dictionary and _check_fields(parsed, required_fields, lenient):
			return {"success": true, "data": parsed, "method": "repaired"}

	return {"success": false, "error": "JSON 解析失败"}


## 尝试解析 JSON，返回 Dictionary（失败返回 null）。
static func _try_parse(text: String) -> Variant:
	var j := JSON.new()
	var err := j.parse(text)
	if err == OK and j.data is Dictionary:
		return j.data
	return null


## 从原始文本提取 ```json ... ``` 或 ``` ... ``` 代码块。
static func _extract_code_block(raw: String) -> String:
	var re := RegEx.new()
	re.compile("```(?:json)?\\s*([\\s\\S]*?)```")
	var m: RegExMatch = re.search(raw)
	if m and m.get_group_count() >= 1:
		return m.get_string(1).strip_edges()
	return ""


## 提取第一个 { ... } 块（贪婪匹配到最后一个 }）。
static func _extract_braces(raw: String) -> String:
	var start := raw.find("{")
	var end := raw.rfind("}")
	if start == -1 or end == -1 or end <= start:
		return ""
	return raw.substr(start, end - start + 1)


## 检查 data 是否包含所有 required 字段。
static func _has_required(data: Dictionary, required_fields: Array) -> bool:
	for f in required_fields:
		if not data.has(f):
			return false
	return true


## 字段校验（含宽松模式）。宽松模式下 response_text 必须非空，其余 required 缺失补默认值。
static func _check_fields(data: Dictionary, required_fields: Array, lenient: bool) -> bool:
	if not lenient:
		return _has_required(data, required_fields)
	if str(data.get("response_text", "")).is_empty():
		return false
	for f in required_fields:
		if not data.has(f):
			data[f] = LENIENT_DEFAULTS.get(f, null)
	return true


# ---------------------------------------------------------------------------
# 流式（SSE）配套：增量抽取 + 截断修复
# ---------------------------------------------------------------------------

## 从**部分 JSON** 中抽取某字符串字段的当前值（供流式边收边显示）。
## 字段顺序无关；值未闭合时取到末尾；解转义 \n \t \" \\ \uXXXX（含代理对）。
static func extract_partial_string_field(raw: String, field: String) -> String:
	if raw.is_empty():
		return ""
	var needle := "\"" + field + "\""
	var ki := raw.find(needle)
	if ki == -1:
		return ""
	var i := ki + needle.length()
	i = _skip_ws(raw, i)
	if i >= raw.length() or raw[i] != ":":
		return ""
	i = _skip_ws(raw, i + 1)
	if i >= raw.length() or raw[i] != "\"":
		return ""
	var start := i + 1
	var end := raw.length()
	var esc := false
	i = start
	while i < raw.length():
		var c := raw[i]
		if esc:
			esc = false
		elif c == "\\":
			esc = true
		elif c == "\"":
			end = i
			break
		i += 1
	var body := raw.substr(start, end - start)
	# 未闭合且结尾是孤立反斜杠：去掉它，否则会吞掉我们补的闭合引号
	if end == raw.length():
		var trailing_bs := 0
		var k := body.length() - 1
		while k >= 0 and body[k] == "\\":
			trailing_bs += 1
			k -= 1
		if trailing_bs % 2 == 1:
			body = body.substr(0, body.length() - 1)
	return _unescape(body)


## 修复被截断的 JSON（流式撞 max_tokens 上限时，模型输出停在一半）。
## 从第一个 { 起做「字符串/转义感知」扫描，若停在字符串内补引号，再按栈补全 } / ]；
## 仍解析不了则退回到「最后一个顶层逗号」处截断重试。无法修复返回空串。
static func repair_truncated_json(raw: String) -> String:
	var start := raw.find("{")
	if start == -1:
		return ""
	var out := ""
	var stack: Array = []
	var in_str := false
	var esc := false
	var last_top_comma := -1   # depth==1 且非字符串处的最后一个逗号（out 中的下标）
	var i := start
	while i < raw.length():
		var c := raw[i]
		if in_str:
			out += c
			if esc:
				esc = false
			elif c == "\\":
				esc = true
			elif c == "\"":
				in_str = false
		else:
			if c == "\"":
				in_str = true
				out += c
			elif c == "{":
				stack.append("}")
				out += c
			elif c == "[":
				stack.append("]")
				out += c
			elif c == "}" or c == "]":
				if not stack.is_empty():
					stack.pop_back()
				out += c
			elif c == ",":
				if stack.size() == 1:
					last_top_comma = out.length()
				out += c
			else:
				out += c
		i += 1

	var candidate := _close_json(out, in_str, esc, stack)
	if _try_parse(candidate) != null:
		return candidate
	# 兜底：丢掉残缺的尾部元素（截到最后一个顶层逗号），此时未闭合的只剩根对象
	if last_top_comma >= 0:
		var cut := _close_json(out.substr(0, last_top_comma), false, false, ["}"])
		if _try_parse(cut) != null:
			return cut
	return ""


## 闭合一段被截断的 JSON：补引号 → 丢弃尾部残缺 , / "key": → 按栈补 } ]。
static func _close_json(out: String, in_str: bool, esc: bool, stack: Array) -> String:
	var s := out
	if esc and s.ends_with("\\"):
		s = s.substr(0, s.length() - 1)
	if in_str:
		s += "\""
	s = _trim_incomplete_tail(s)
	for idx in range(stack.size() - 1, -1, -1):
		s += str(stack[idx])
	return s


## 丢弃尾部残缺的 `,` 或 `"key":`（截断恰好落在元素边界时的清尾）。
static func _trim_incomplete_tail(s: String) -> String:
	var cur := s.strip_edges(false, true)   # 去尾部空白
	var guard := 0
	while guard < 4:
		guard += 1
		if cur.is_empty():
			break
		if cur.ends_with(","):
			cur = cur.substr(0, cur.length() - 1).strip_edges(false, true)
			continue
		if cur.ends_with(":"):
			# 砍掉整个残缺的 "key":
			var close_q := cur.rfind("\"")
			var open_q := cur.rfind("\"", close_q - 1) if close_q > 0 else -1
			if open_q >= 0:
				cur = cur.substr(0, open_q).strip_edges(false, true)
			else:
				cur = cur.substr(0, cur.length() - 1).strip_edges(false, true)
			continue
		break
	return cur


static func _skip_ws(raw: String, i: int) -> int:
	while i < raw.length():
		var c := raw[i]
		if c == " " or c == "\n" or c == "\r" or c == "\t":
			i += 1
		else:
			break
	return i


## 解 JSON 字符串转义（\n \t \r \b \f \" \\ \/ \uXXXX，含 UTF-16 代理对）。
static func _unescape(s: String) -> String:
	if s.find("\\") == -1:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c != "\\" or i + 1 >= s.length():
			out += c
			i += 1
			continue
		var n := s[i + 1]
		match n:
			"n": out += "\n"; i += 2
			"t": out += "\t"; i += 2
			"r": out += "\r"; i += 2
			"b": out += "\b"; i += 2
			"f": out += "\f"; i += 2
			"\"": out += "\""; i += 2
			"\\": out += "\\"; i += 2
			"/": out += "/"; i += 2
			"u":
				if i + 6 <= s.length() and s.substr(i + 2, 4).is_valid_hex_number():
					var code := s.substr(i + 2, 4).hex_to_int()
					var advance := 6
					# 代理对：😀 → 合并为一个码点
					if code >= 0xD800 and code <= 0xDBFF and i + 12 <= s.length() \
							and s.substr(i + 6, 2) == "\\u" \
							and s.substr(i + 8, 4).is_valid_hex_number():
						var lo := s.substr(i + 8, 4).hex_to_int()
						if lo >= 0xDC00 and lo <= 0xDFFF:
							code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
							advance = 12
					out += String.chr(code)
					i += advance
				else:
					out += c
					i += 1
			_:
				out += n; i += 2
	return out


## 便捷取值：data 为 null 或缺失 key 时返回默认值。
static func safe_get(data: Variant, key: String, default: Variant = null) -> Variant:
	if data is Dictionary and data.has(key):
		return data[key]
	return default
