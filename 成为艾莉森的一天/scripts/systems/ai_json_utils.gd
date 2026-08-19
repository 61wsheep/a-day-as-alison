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


## 解析响应文本。raw 为空返回失败。required_fields 存在时检查必填字段。
static func parse_response(raw: String, required_fields: Array = []) -> Dictionary:
	if raw.strip_edges().is_empty():
		return {"success": false, "error": "空响应"}

	# 第 1 层：整段直接解析
	var parsed: Variant = _try_parse(raw)
	if parsed is Dictionary and _has_required(parsed, required_fields):
		return {"success": true, "data": parsed, "method": "direct"}

	# 第 2 层：提取 ```json ... ``` 代码块
	var code_block := _extract_code_block(raw)
	if code_block != "":
		parsed = _try_parse(code_block)
		if parsed is Dictionary and _has_required(parsed, required_fields):
			return {"success": true, "data": parsed, "method": "regex_code_block"}

	# 第 3 层：提取第一个 { ... } 块
	var braces := _extract_braces(raw)
	if braces != "":
		parsed = _try_parse(braces)
		if parsed is Dictionary and _has_required(parsed, required_fields):
			return {"success": true, "data": parsed, "method": "regex_braces"}

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


## 便捷取值：data 为 null 或缺失 key 时返回默认值。
static func safe_get(data: Variant, key: String, default: Variant = null) -> Variant:
	if data is Dictionary and data.has(key):
		return data[key]
	return default
