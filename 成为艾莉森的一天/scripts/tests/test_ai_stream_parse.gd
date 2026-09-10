extends SceneTree

## AIStreamClient 解析核的离线单测（零网络）。
## 运行：godot --headless -s res://scripts/tests/test_ai_stream_parse.gd --quit
##
## 重点验证「按字节切行」在任意分块边界下都不出半个汉字、不丢行、能识别 [DONE]，
## 以及流被截断（无 [DONE]、JSON 停在字符串内）时仍能给出可见文本。

const AIStreamClientScript := preload("res://scripts/systems/ai_stream_client.gd")

var _failures := 0
var _passes := 0


func _init() -> void:
	_test_byte_by_byte()
	_test_odd_chunk_sizes()
	_test_truncated_stream()
	_test_sse_noise_and_escapes()
	_test_no_trailing_newline()
	_test_backspace_field_agnostic()

	print("[TEST] AIStreamClient: %d 通过, %d 失败" % [_passes, _failures])
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


## 把一段完整 JSON 切成 n 片，组装成真实的 OpenAI 兼容 SSE 文本。
func _build_sse(full_json: String, piece_count: int) -> String:
	var pieces := _split_evenly(full_json, piece_count)
	var sse := ""
	for p in pieces:
		var event := {"choices": [{"delta": {"content": p}}]}
		sse += "data: " + JSON.stringify(event) + "\n\n"
	sse += "data: [DONE]\n\n"
	return sse


func _split_evenly(s: String, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	var total := s.length()
	var step := int(ceil(float(total) / float(n)))
	var i := 0
	while i < total:
		out.append(s.substr(i, step))
		i += step
	return out


func _feed_in_chunks(sse: String, chunk_size: int) -> AIStreamClientScript:
	var c = AIStreamClientScript.new()
	var bytes := sse.to_utf8_buffer()
	var i := 0
	while i < bytes.size():
		var end: int = min(i + chunk_size, bytes.size())
		c.feed_bytes(bytes.slice(i, end))
		i = end
	c.flush_pending()
	return c


const FULL := '{"response_text":"苔从石缝里钻出来，像谁忘了收的绳。","emotional_shift":2,"memory_update":"提到苔"}'
const EXPECT_TEXT := "苔从石缝里钻出来，像谁忘了收的绳。"


func _test_byte_by_byte() -> void:
	var c := _feed_in_chunks(_build_sse(FULL, 3), 1)
	_check("逐字节喂入：raw 完整", c.get_raw_content() == FULL)
	_check("逐字节喂入：可见文本正确", c.get_visible_text() == EXPECT_TEXT)
	_check("逐字节喂入：[DONE] 识别", c.is_done() == true)
	_check("逐字节喂入：delta 计数=3", c.get_delta_count() == 3)


func _test_odd_chunk_sizes() -> void:
	for size in [2, 3, 5, 7, 13, 64]:
		var c := _feed_in_chunks(_build_sse(FULL, 5), size)
		var ok: bool = c.get_raw_content() == FULL and c.get_visible_text() == EXPECT_TEXT \
			and c.is_done()
		_check("分块=%d 字节仍正确（跨块汉字不碎）" % size, ok)


func _test_truncated_stream() -> void:
	# 只喂第一片：JSON 停在 response_text 字符串中间，且没有 [DONE]
	var c = AIStreamClientScript.new()
	var first := _split_evenly(FULL, 3)[0]
	var event := {"choices": [{"delta": {"content": first}}]}
	c.feed_bytes(("data: " + JSON.stringify(event) + "\n\n").to_utf8_buffer())
	c.flush_pending()
	_check("截断流：raw 为半截", c.get_raw_content() == first)
	_check("截断流：仍能抽出可见文本", c.get_visible_text() == "苔从石缝里钻出来，")
	_check("截断流：is_done 为假", c.is_done() == false)


func _test_sse_noise_and_escapes() -> void:
	# 含 SSE 注释心跳、event: 行，以及 response_text 内的转义换行与引号
	var full := '{"response_text":"他说：\\"走吧\\"。\\n然后走了","emotional_shift":-1}'
	var sse := ": keep-alive\n\nevent: message\n"
	sse += _build_sse(full, 4)
	var c := _feed_in_chunks(sse, 6)
	_check("忽略注释/event 行", c.get_visible_text() == "他说：\"走吧\"。\n然后走了")


func _test_no_trailing_newline() -> void:
	# 最后一行没有 \n（连接直接断开）→ 靠 flush_pending 兜住
	var sse := _build_sse(FULL, 3)
	var bytes := sse.to_utf8_buffer()
	var last_nl := -1
	for i in range(bytes.size() - 1, -1, -1):
		if bytes[i] == 0x0A:
			last_nl = i
			break
	var c = AIStreamClientScript.new()
	c.feed_bytes(bytes.slice(0, last_nl))   # 故意丢掉最后一个换行之后的部分
	c.flush_pending()
	_check("无尾换行：末尾残行被冲刷", c.get_raw_content() == FULL and c.is_done() == true)


func _test_backspace_field_agnostic() -> void:
	# 字段顺序颠倒（response_text 不在最前）时，增量抽取仍应命中
	var full := '{"emotional_shift":3,"memory_update":"无","response_text":"风从西边来。"}'
	var c := _feed_in_chunks(_build_sse(full, 2), 4)
	_check("字段顺序无关：仍抽出 response_text", c.get_visible_text() == "风从西边来。")
