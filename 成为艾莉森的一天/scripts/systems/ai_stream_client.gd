class_name AIStreamClient
extends RefCounted

## SSE（Server-Sent Events）流式客户端 —— 唯一负责流式 HTTP 的模块。
##
## 为什么不用 HTTPRequest：Godot 4.x 的 HTTPRequest 只能一次性拿回完整 body
## （无 chunk 读取 API，use_threads=true 也是整段缓冲）。要边收边显示必须用
## HTTPClient（RefCounted）自己 poll + read_response_body_chunk。
##
## 结构分两半：
##   - 解析核（feed_bytes/get_visible_text/...）：纯状态机，不碰网络，可离线单测。
##   - 传输壳（run）：connect → request → 轮询读 chunk → 交给解析核。
##
## 按字节切行：只在 0x0A 处断行。UTF-8 的续字节是 0x80–0xBF，前导字节 ≥0xC2，
## 都不含 0x0A，因此「半个汉字」在字节层面天然不可能出现，无需额外缓冲字形。

const PORT_TLS := 443
const READ_CHUNK_SIZE := 8192   # 每次 read_response_body_chunk 的上限

## 三级超时（毫秒）：首字节（连接+等响应头+首个数据）、空闲（距上次收到数据）、总时长。
const DEFAULT_FIRST_BYTE_MS := 8000
const DEFAULT_IDLE_MS := 12000
const DEFAULT_TOTAL_MS := 45000

const AIJsonUtilsScript := preload("res://scripts/systems/ai_json_utils.gd")

var _client: HTTPClient = null

# ---- 解析核状态 ----
var _line_buffer := PackedByteArray()   # 尚未遇到 0x0A 的当前行字节
var _raw_content := ""                  # 累加的 delta.content（即 LLM 的 JSON 原文）
var _delta_count := 0
var _done := false                      # 已收到 data: [DONE]
var _first_byte_ms := -1
var _err_body := PackedByteArray()      # 非 200 时的错误响应体


# ---------------------------------------------------------------------------
# 解析核（无网络，可单测）
# ---------------------------------------------------------------------------

## 喂入一段原始响应字节，内部按 0x0A 切行并解析 SSE。
func feed_bytes(chunk: PackedByteArray) -> void:
	for i in chunk.size():
		var b := chunk[i]
		if b == 0x0A:
			_consume_line(_line_buffer)
			_line_buffer = PackedByteArray()
		else:
			_line_buffer.append(b)


## 流结束时冲刷末尾没有换行的残行（个别服务端最后一行不带 \n）。
func flush_pending() -> void:
	if not _line_buffer.is_empty():
		_consume_line(_line_buffer)
		_line_buffer = PackedByteArray()


## 当前累加到的 LLM 原始文本（即 JSON，可能被 max_tokens 截断）。
func get_raw_content() -> String:
	return _raw_content


## 当前可显示的 NPC 台词（从半截 JSON 里增量抽取 response_text）；尚无则空串。
func get_visible_text() -> String:
	return AIJsonUtilsScript.extract_partial_string_field(_raw_content, "response_text")


func has_content() -> bool:
	return not _raw_content.is_empty()


func is_done() -> bool:
	return _done


func get_delta_count() -> int:
	return _delta_count


func get_first_byte_ms() -> int:
	return _first_byte_ms


## 单行 SSE 解析：只认 `data:` 行；`[DONE]` 置结束；其余取 choices[0].delta.content。
func _consume_line(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var line := bytes.get_string_from_utf8()
	if line.ends_with("\r"):
		line = line.substr(0, line.length() - 1)
	if line.is_empty() or line.begins_with(":"):
		return   # 空行 / SSE 注释心跳
	if not line.begins_with("data:"):
		return   # event: / id: / retry: 等一律忽略
	var payload := line.substr(5)
	if payload.begins_with(" "):
		payload = payload.substr(1)
	payload = payload.strip_edges()
	if payload == "[DONE]":
		_done = true
		return
	if payload.is_empty():
		return
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var choices: Variant = parsed.get("choices", [])
	if not (choices is Array) or choices.is_empty() or not (choices[0] is Dictionary):
		return
	var delta: Variant = choices[0].get("delta", {})
	if not (delta is Dictionary):
		return
	var piece := str(delta.get("content", ""))
	if piece.is_empty():
		return
	_raw_content += piece
	_delta_count += 1


# ---------------------------------------------------------------------------
# 传输壳
# ---------------------------------------------------------------------------

## 发起一次流式请求。
## on_delta(visible_text: String)：每收到新内容回调一次（传入当前可显示文本）。
## should_cancel() -> bool：返回 true 则立即中止并关闭连接。
## 返回字典：{ ok, raw, visible, http_code, first_byte_ms, total_ms, done, deltas,
##             cancelled, error }。
func run(host: String, path: String, headers: PackedStringArray, body: String,
		on_delta := Callable(), should_cancel := Callable(),
		first_byte_timeout := DEFAULT_FIRST_BYTE_MS,
		idle_timeout := DEFAULT_IDLE_MS,
		total_timeout := DEFAULT_TOTAL_MS) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	var last_data := t0
	var got_any := false
	var http_code := 0

	_client = HTTPClient.new()
	_client.set_read_chunk_size(READ_CHUNK_SIZE)
	var err := _client.connect_to_host(host, PORT_TLS, TLSOptions.client())
	if err != OK:
		return _fail(t0, "connect err=%s" % error_string(err))

	# 1) 建连
	while true:
		if _should_stop(should_cancel):
			return _cancelled(t0)
		if Time.get_ticks_msec() - t0 > first_byte_timeout:
			return _fail(t0, "连接超时")
		_client.poll()
		var s := _client.get_status()
		if s == HTTPClient.STATUS_CONNECTING or s == HTTPClient.STATUS_RESOLVING:
			await _frame(tree)
			continue
		if s == HTTPClient.STATUS_CONNECTED:
			break
		return _fail(t0, "连接失败 status=%d" % s)

	# 2) 发送
	var rerr := _client.request(HTTPClient.METHOD_POST, path, headers, body)
	if rerr != OK:
		return _fail(t0, "发送失败 %s" % error_string(rerr))

	# 3) 等响应头
	while not _client.has_response():
		if _should_stop(should_cancel):
			return _cancelled(t0)
		if Time.get_ticks_msec() - t0 > first_byte_timeout:
			return _fail(t0, "等待响应头超时")
		_client.poll()
		var s2 := _client.get_status()
		if s2 == HTTPClient.STATUS_REQUESTING or s2 == HTTPClient.STATUS_CONNECTED:
			await _frame(tree)
			continue
		if s2 == HTTPClient.STATUS_BODY:
			break
		return _fail(t0, "响应异常 status=%d" % s2)
	http_code = _client.get_response_code()

	# 4) 读 body（边收边喂解析核）
	while _client.get_status() == HTTPClient.STATUS_BODY:
		if _should_stop(should_cancel):
			return _cancelled(t0)
		var now := Time.get_ticks_msec()
		if now - t0 > total_timeout:
			return _fail(t0, "总时长超时", http_code)
		if got_any:
			if now - last_data > idle_timeout:
				return _fail(t0, "空闲超时（%dms 无数据）" % idle_timeout, http_code)
		_client.poll()
		var chunk := _client.read_response_body_chunk()
		if chunk.size() == 0:
			await _frame(tree)
			continue
		last_data = Time.get_ticks_msec()
		got_any = true
		if _first_byte_ms < 0:
			_first_byte_ms = last_data - t0
		if http_code == 200:
			feed_bytes(chunk)
			if on_delta.is_valid():
				on_delta.call(get_visible_text())
		else:
			_err_body.append_array(chunk)   # 错误响应体留给调用方做诊断
		if _done:
			break
	flush_pending()

	if http_code != 200:
		var msg := _err_body.get_string_from_utf8().substr(0, 300)
		return _fail(t0, "HTTP %d: %s" % [http_code, msg], http_code)

	var total := Time.get_ticks_msec() - t0
	_close()
	return {
		"ok": true,
		"raw": _raw_content,
		"visible": get_visible_text(),
		"http_code": http_code,
		"first_byte_ms": _first_byte_ms,
		"total_ms": total,
		"done": _done,
		"deltas": _delta_count,
		"cancelled": false,
		"error": "",
	}


## 主动关闭底层连接（取消 / 收尾）。
func close() -> void:
	_close()


func _close() -> void:
	if _client != null:
		_client.close()
		_client = null


func _should_stop(should_cancel: Callable) -> bool:
	if should_cancel.is_valid() and should_cancel.call():
		_close()
		return true
	return false


func _frame(tree: SceneTree) -> void:
	if tree != null:
		await tree.process_frame


func _fail(t0: int, message: String, http_code := 0) -> Dictionary:
	_close()
	return {
		"ok": false, "raw": _raw_content, "visible": get_visible_text(),
		"http_code": http_code, "first_byte_ms": _first_byte_ms,
		"total_ms": Time.get_ticks_msec() - t0, "done": _done, "deltas": _delta_count,
		"cancelled": false, "error": message,
		"err_body": _err_body.get_string_from_utf8(),
	}


func _cancelled(t0: int) -> Dictionary:
	return {
		"ok": false, "raw": _raw_content, "visible": get_visible_text(),
		"http_code": 0, "first_byte_ms": _first_byte_ms,
		"total_ms": Time.get_ticks_msec() - t0, "done": _done, "deltas": _delta_count,
		"cancelled": true, "error": "cancelled",
	}


# ---------------------------------------------------------------------------
# 测试辅助
# ---------------------------------------------------------------------------

## 重置解析核（单测复用同一实例时调用）。
func reset() -> void:
	_line_buffer = PackedByteArray()
	_raw_content = ""
	_delta_count = 0
	_done = false
	_first_byte_ms = -1
	_err_body = PackedByteArray()
