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

var _http: HTTPRequest
var _in_flight := false
var _api_key := ""
var _enabled := true
## --ai-off / AI_DISABLED 强制关闭：即使界面提交了 key 也不启用
var _force_off := false
var _mock_responder: Callable


func _ready() -> void:
	_api_key = _resolve_key()
	if _api_key.is_empty():
		_enabled = false
		print("[AIBridge] 未找到 API key，AI 对话关闭（将回落 JSON 对话）。")
	if OS.has_environment("AI_DISABLED") or "--ai-off" in OS.get_cmdline_user_args():
		_force_off = true
		_enabled = false
		print("[AIBridge] 检测到 --ai-off / AI_DISABLED，AI 对话关闭。")
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	_http.body_size_limit = 2 * 1024 * 1024
	add_child(_http)


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
	var k := key.strip_edges()
	if k.is_empty():
		return false
	if _force_off:
		print("[AIBridge] AI 被强制关闭，忽略提交的 key。")
		return false
	_api_key = k
	_enabled = true
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = TIMEOUT_SEC
		_http.body_size_limit = 2 * 1024 * 1024
		add_child(_http)
	# 持久化到 user://（res:// 导出只读；user:// 天然 gitignore）
	var f := FileAccess.open("user://ai_api_key.txt", FileAccess.WRITE)
	if f:
		f.store_string(k)
		f.close()
	print("[AIBridge] API key 已保存并启用。")
	return true


func has_role_card(npc_id: String) -> bool:
	return FileAccess.file_exists("res://ai/npc_%s.txt" % npc_id)


## 注入脚本化响应（测试用）。fn(payload: Dictionary) -> String。
func set_mock_responder(fn: Callable) -> void:
	_mock_responder = fn


## 取消当前在途请求。被 await 的 request_completed 会以 RESULT_CANCELLED 立即返回。
func cancel_current() -> void:
	if _in_flight and _http != null:
		_http.cancel_request()


## 发送一次 LLM 请求。payload: { system: String, user: String }
## 返回 raw 响应文本；失败返回以 [API_ERROR] 开头 / [DISABLED] / [BUSY]。
func request_llm(payload: Dictionary) -> String:
	if _in_flight:
		return "[BUSY]"
	if not is_available():
		return "[DISABLED]"
	if _mock_responder.is_valid():
		_in_flight = true
		var r: String = await _mock_responder.call(payload)
		_in_flight = false
		return r

	_in_flight = true
	var body := JSON.stringify({
		"model": MODEL,
		"max_tokens": MAX_TOKENS,
		"temperature": TEMPERATURE,
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
		_in_flight = false
		return "[API_ERROR] " + error_string(err)

	var resp: Array = await _http.request_completed
	_in_flight = false
	var result: int = resp[0]
	var code: int = resp[1]
	var bytes: PackedByteArray = resp[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return "[API_ERROR] result=%d http=%d" % [result, code]
	if code != 200:
		return "[API_ERROR] HTTP %d: %s" % [code, bytes.get_string_from_utf8()]
	return bytes.get_string_from_utf8()


## 带硬超时兜底的请求（Timer 兜底：超时 cancel → await 恢复 → 走失败）。
func request_llm_with_guard(payload: Dictionary, hard_timeout: float) -> String:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = hard_timeout
	add_child(t)
	t.timeout.connect(cancel_current)
	t.start()
	var raw := await request_llm(payload)
	t.queue_free()
	return raw


## API key 解析顺序：环境变量 → user://ai_api_key.txt → res://ai/api_key.txt。
func _resolve_key() -> String:
	var env_key := OS.get_environment("SILICONFLOW_API_KEY")
	if not env_key.is_empty():
		return env_key
	for path in ["user://ai_api_key.txt", "res://ai/api_key.txt"]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var k := f.get_as_text().strip_edges()
				f.close()
				if not k.is_empty():
					return k
	return ""
