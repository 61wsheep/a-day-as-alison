extends SceneTree

## AIJsonUtils 三层 JSON 恢复的离线单测。
## 运行：godot --headless -s res://scripts/tests/test_ai_json_utils.gd --quit
## 不进 main.tscn，纯逻辑断言。

const AIJsonUtils := preload("res://scripts/systems/ai_json_utils.gd")

var _failures := 0
var _passes := 0


func _init() -> void:
	_test_direct_parse()
	_test_code_block_wrapped()
	_test_noise_around()
	_test_missing_required()
	_test_empty_input()
	_test_braces_fallback()

	print("[TEST] AIJsonUtils: %d 通过, %d 失败" % [_passes, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[TEST] FAIL  ", name)


func _test_direct_parse() -> void:
	var r := AIJsonUtils.parse_response('{"response_text":"你好","emotional_shift":3}', ["response_text", "emotional_shift"])
	_check("直接整段解析", r.get("success", false) == true and r.get("data", {}).get("response_text", "") == "你好")


func _test_code_block_wrapped() -> void:
	var raw := "好的，以下是回应：\n```json\n{\"response_text\":\"嗯。\",\"emotional_shift\":1}\n```\n以上。"
	var r := AIJsonUtils.parse_response(raw, ["response_text"])
	_check("```json``` 代码块提取", r.get("success", false) == true and r.get("data", {}).get("response_text", "") == "嗯。")


func _test_noise_around() -> void:
	var raw := "（思考中）{\"response_text\":\"风的方向变了。\",\"emotional_shift\":-2}（补充说明）"
	var r := AIJsonUtils.parse_response(raw, ["response_text"])
	_check("前后缀废话中提取{}", r.get("success", false) == true and r.get("data", {}).get("emotional_shift", 0) == -2)


func _test_missing_required() -> void:
	var raw := '{"response_text":"缺字段"}'
	var r := AIJsonUtils.parse_response(raw, ["response_text", "emotional_shift"])
	_check("缺 required 字段则失败", r.get("success", false) == false)


func _test_empty_input() -> void:
	var r := AIJsonUtils.parse_response("   ", ["response_text"])
	_check("空输入失败", r.get("success", false) == false and r.get("error", "") == "空响应")


func _test_braces_fallback() -> void:
	var raw := '回复如下\n{"response_text":"哦。","emotional_shift":0,"memory_update":"无"}'
	var r := AIJsonUtils.parse_response(raw, ["response_text", "emotional_shift", "memory_update"])
	_check("无代码块时提取{}兜底", r.get("success", false) == true and r.get("data", {}).get("response_text", "") == "哦。")
