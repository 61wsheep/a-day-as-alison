extends Node

## AI Bridge —— LLM 传输层（唯一负责 HTTP 的模块）。
##
## 职责：
##   - 组装并发送 OpenAI 兼容协议的 chat/completions 请求
##   - 超时 / 单飞守卫 / 取消
##   - API key 解析（环境变量 → user://ai_api_key.txt → res://ai/api_key.txt）
##   - mock 注入（测试用，零网络）
##
## 本模块不懂任何叙事。prompt 组装、JSON 校验、结算都在 AIDialogueSession。
## 接口与 ai_verify/utils/api_client.py 的 call_llm 对应。

const BASE_URL := "https://api.siliconflow.cn/v1/chat/completions"
const MODEL := "deepseek-ai/DeepSeek-V3"
const TIMEOUT_SEC := 60.0
const MAX_TOKENS := 1024
const TEMPERATURE := 0.8
## 断联兜底：首次请求若快速失败（连接被拒/重置等），自动重试 1 次。
## 超过该耗时阈值的失败不重试（说明是慢超时，重试只会让玩家等更久）。
const RETRY_MAX_ELAPSED_MS := 10000
## 网络遥测：每次请求追加一行到 user://ai_net.log（取证"断联"根因，不改变行为）。
## 导出包运行时请玩家回传：%APPDATA%\Godot\app_userdata\成为艾莉森的一天\ai_net.log
const NET_LOG_PATH := "user://ai_net.log"
const NET_LOG_MAX_BYTES := 262144   # >256KB 重置，只留最近一次运行

var _http: HTTPRequest
var _in_flight := false
var _api_key := ""
var _enabled := true
## --ai-off / AI_DISABLED 强制关闭：即使界面提交了 key 也不启用
var _force_off := false
var _mock_responder: Callable
# ---- 请求完成/取消状态（供 _send_once 轮询，避免 cancel_request 吞掉
#      request_completed 信号导致 await 永不返回 → _in_flight 永久卡死 → 全 BUSY）----
var _req_done := false           # request_completed 已回（含超时/取消时引擎回发的情形）
var _resp_result := 0
var _resp_code := 0
var _resp_body := PackedByteArray()
var _cancel_requested := false   # cancel_current() 已请求放弃本次请求


func _ready() -> void:
	_api_key = _resolve_key()
	if _api_key.is_empty():
		_enabled = false
		print("[AIBridge] 未找到 API key，AI 对话关闭（将回落 JSON 对话）。")
	if OS.has_environment("AI_DISABLED") or "--ai-off" in OS.get_cmdline_user_args():
		_force_off = true
		_enabled = false
		print("[AIBridge] 检测到 --ai-off / AI_DISABLED，AI 对话关闭。")
	_http = _make_http()
	_log_net("[NET] AIBridge 启动 enabled=%s force_off=%s key_len=%d（无 key → AI 关闭，落固定对话，不会联网）"
			% [str(_enabled), str(_force_off), _api_key.length()])


func is_available() -> bool:
	if not _enabled or _force_off:
		return false
	if _mock_responder.is_valid():
		return true   # mock 模式（测试）不需要 API key
	return not _api_key.is_empty() and _http != null


func set_enabled(v: bool) -> void:
	_enabled = v


## 是否被 --ai-off / AI_DISABLED 强制关闭（界面不可输入）。
func is_force_off() -> bool:
	return _force_off


## 当前存储的 key（供开始界面预填；masked 显示）。
func get_stored_key() -> String:
	return _api_key


## 供开始界面显示当前 AI 状态。
func get_status_text() -> String:
	if _force_off:
		return "AI 已禁用（--ai-off / AI_DISABLED）"
	if _enabled and not _api_key.is_empty():
		return "AI 已启用（已保存密钥）"
	return "未配置密钥（AI 将回落 JSON 对话）"


## 开始界面提交 key：动态启用 + 持久化到 user://ai_api_key.txt（下次启动自动加载）。
## 返回是否成功启用。空 key 直接返回 false。
func set_api_key(key: String) -> bool:
	var k := _clean_key(key)
	if k.is_empty():
		return false
	if _force_off:
		print("[AIBridge] AI 被强制关闭，忽略提交的 key。")
		return false
	_api_key = k
	_enabled = true
	if _http == null:
		_http = _make_http()
	# 持久化到 user://（res:// 导出只读；user:// 天然 gitignore）
	var f := FileAccess.open("user://ai_api_key.txt", FileAccess.WRITE)
	if f:
		f.store_string(k)
		f.close()
	_log_net("[NET] 界面提交 key 并启用 key_len=%d" % k.length())
	print("[AIBridge] API key 已保存并启用。")
	return true


func has_role_card(npc_id: String) -> bool:
	return FileAccess.file_exists("res://ai/npc_%s.txt" % npc_id)


## 注入脚本化响应（测试用）。fn(payload: Dictionary) -> String。
func set_mock_responder(fn: Callable) -> void:
	_mock_responder = fn


## 新建并配置 HTTPRequest，连接完成回调（统一走这里，避免漏连）。
func _make_http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT_SEC
	h.use_threads = true   # 后台线程请求，否则慢速 LLM 会冻结主循环（全键失灵）
	h.body_size_limit = 2 * 1024 * 1024
	h.request_completed.connect(_on_request_completed)
	add_child(h)
	return h


## request_completed 统一落地处。引擎正常完成/超时/部分取消都会到这里。
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_resp_result = result
	_resp_code = response_code
	_resp_body = body
	_req_done = true


## 取消当前在途请求。
## 注意：threaded 模式下 cancel_request() 有时会吞掉 request_completed（本仓库曾因此
## 整局卡 BUSY）——所以这里先置 _cancel_requested 让 _send_once 的等待循环尽快退出并
## 复位 _in_flight，再尽力断开底层连接；不依赖 cancel 是否回发信号。
func cancel_current() -> void:
	if _in_flight and _http != null:
		_cancel_requested = true
		_http.cancel_request()


## 发送一次 LLM 请求。payload: { system: String, user: String }
## 返回 raw 响应文本；失败返回以 [API_ERROR] 开头 / [DISABLED] / [BUSY]。
func request_llm(payload: Dictionary) -> String:
	if _in_flight:
		_log_net("[NET] BUSY：仍有请求在途被拒（若持续出现 → 上一条请求未按时结束，检查遥测）")
		return "[BUSY]"
	if not is_available():
		return "[DISABLED]"
	if _mock_responder.is_valid():
		_in_flight = true
		var r: String = await _mock_responder.call(payload)
		_in_flight = false
		return r

	_in_flight = true
	var t0 := Time.get_ticks_msec()
	var raw := await _send_once(payload)
	# 断联重试：仅当失败很快返回（连接层错误）时重试一次；慢超时/玩家取消/守护放弃不重试
	if raw.begins_with("[API_ERROR]") and not _cancel_requested \
			and Time.get_ticks_msec() - t0 < RETRY_MAX_ELAPSED_MS:
		_log_net("[NET] 快速失败触发自动重试 1 次：%s" % raw.left(60))
		print("[AIBridge] 请求快速失败（%s），重试一次…" % raw.left(48))
		raw = await _send_once(payload)
	_in_flight = false
	return raw


## 单次请求（无重试）。返回 raw 响应文本；失败以 [API_ERROR] 开头。
func _send_once(payload: Dictionary) -> String:
	var t0 := Time.get_ticks_msec()
	var stamp := Time.get_datetime_string_from_system()
	var body := JSON.stringify({
		"model": MODEL,
		# payload 可单独带 max_tokens 限幅（如对话轮次设小值提速）；缺省用全局 1024
		"max_tokens": int(payload.get("max_tokens", MAX_TOKENS)),
		"temperature": TEMPERATURE,
		# 强制 JSON 模式：避免模型输出 JSON 之外的文字导致整轮解析失败
		"response_format": {"type": "json_object"},
		"messages": [
			{"role": "system", "content": str(payload.get("system", ""))},
			{"role": "user", "content": str(payload.get("user", ""))},
		],
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % _api_key,
	])
	var err := _http.request(BASE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_log_net("%s | 发送失败 err=%s" % [stamp, error_string(err)])
		return "[API_ERROR] " + error_string(err)

	# 等结果：轮询「完成标记 / 取消标记 / 绝对超时」，任一先到即醒。
	# 不用裸 await _http.request_completed —— threaded 模式下 cancel_request() 可能吞掉该信号，
	# 导致这里永不返回、_in_flight 永久卡死（历史「按一次 Esc 整局全 BUSY」事故的根源）。
	_req_done = false
	_cancel_requested = false
	var deadline_ms := t0 + int(_http.timeout * 1000.0)
	while not _req_done and not _cancel_requested:
		if Time.get_ticks_msec() >= deadline_ms:
			break
		var tree := get_tree()
		if tree == null:
			await _http.request_completed   # 不在树内（个别无场景测试）：退回信号等待
			break
		await tree.process_frame

	var result := _resp_result
	var code := _resp_code
	var bytes := _resp_body
	var ms := Time.get_ticks_msec() - t0

	# 被取消（玩家 Esc / 守护硬超时）：不重试、丢弃半截结果，_in_flight 由上层复位
	if _cancel_requested:
		_log_net("%s | 已取消 | %dms | FAIL（玩家Esc/超时放弃）" % [stamp, ms])
		return "[API_ERROR] cancelled"
	# 绝对兜底：引擎既没回发结果也没超时信号 → 主动断开底层，按超时判失败
	if not _req_done:
		_http.cancel_request()
		_log_net("%s | 等待兜底超时 | %dms | FAIL" % [stamp, ms])
		return "[API_ERROR] result=%d http=%d" % [HTTPRequest.RESULT_TIMEOUT, code]

	print("[AIBridge] HTTP 完成 result=%d code=%d 耗时=%.1fs" % [result, code, ms / 1000.0])
	# 遥测一行：成功 result=0&http=200 记 OK；失败追加响应体前 160 字符（429/401/403/404 的直接证据）
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	var detail := ""
	if not ok and code >= 400 and bytes.size() > 0:
		detail = " body=%s" % bytes.get_string_from_utf8().substr(0, 160)
	_log_net("%s | result=%d http=%d | %dms | %s%s" % [stamp, result, code, ms, "OK" if ok else "FAIL", detail])

	if result != HTTPRequest.RESULT_SUCCESS:
		return "[API_ERROR] result=%d http=%d" % [result, code]
	if code != 200:
		return "[API_ERROR] HTTP %d: %s" % [code, bytes.get_string_from_utf8()]
	# OpenAI chat.completions 信封 → 解包 assistant content（LLM 的真实 JSON 在 content 里）
	var content := _extract_content(bytes.get_string_from_utf8())
	if content.is_empty():
		_log_net("%s | result=%d http=%d | %dms | 200 但缺 assistant content（信封/编码异常）" % [stamp, result, code, ms])
		return "[API_ERROR] 响应缺少 assistant content"
	return content


## 从 OpenAI chat.completions 响应信封中解包 assistant content。
## 非流式响应形如 {"choices":[{"message":{"role":"assistant","content":"..."}}]}，
## LLM 生成的 JSON 就在 content 字符串里。缺失/无法解析返回空串。
func _extract_content(response_text: String) -> String:
	var parsed: Variant = JSON.parse_string(response_text)
	if parsed is Dictionary:
		var choices: Array = parsed.get("choices", [])
		if choices.size() > 0 and choices[0] is Dictionary:
			var msg: Dictionary = choices[0].get("message", {})
			var content := str(msg.get("content", ""))
			if not content.is_empty():
				return content
	return ""


## 带硬超时兜底的请求。到点经 cancel_current → _cancel_requested 让 _send_once 尽快退出，
## _in_flight 必然复位，不再出现按一次 Esc/遇一次慢请求就永久全 BUSY 的锁死。
func request_llm_with_guard(payload: Dictionary, hard_timeout: float) -> String:
	var old_timeout := _http.timeout
	_http.timeout = hard_timeout
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = hard_timeout
	add_child(t)
	t.timeout.connect(cancel_current)
	t.start()
	var raw := await request_llm(payload)
	t.queue_free()
	_http.timeout = old_timeout
	return raw


## 网络遥测追加写：每次请求一行，供事后定位断联根因。行为无关，纯取证。
func _log_net(line: String) -> void:
	var f := FileAccess.open(NET_LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(NET_LOG_PATH, FileAccess.WRITE)   # 文件不存在则新建
	if f == null:
		return
	f.seek_end()
	if f.get_position() > NET_LOG_MAX_BYTES:
		f.close()
		f = FileAccess.open(NET_LOG_PATH, FileAccess.WRITE)   # 超限：清空重写，只留最近一次运行
		if f == null:
			return
		f.seek_end()
	f.store_line(line)
	f.close()


## 剔除可能混进 key 的脏字符（Windows 记事本 UTF-8 会带 BOM ﻿；还有误贴的空格/换行），
## 避免整包 401。strip_edges 处理不了 BOM，需单独去。
func _clean_key(raw: String) -> String:
	var k := raw.strip_edges()
	if k.begins_with(char(0xFEFF)):   # UTF-8 BOM（记事本保存会带）
		k = k.substr(1).strip_edges()
	return k


## API key 解析顺序：环境变量 → user://ai_api_key.txt → res://ai/api_key.txt。
func _resolve_key() -> String:
	var env_key := _clean_key(OS.get_environment("SILICONFLOW_API_KEY"))
	if not env_key.is_empty():
		return env_key
	for path in ["user://ai_api_key.txt", "res://ai/api_key.txt"]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var k := _clean_key(f.get_as_text())
				f.close()
				if not k.is_empty():
					return k
	return ""
