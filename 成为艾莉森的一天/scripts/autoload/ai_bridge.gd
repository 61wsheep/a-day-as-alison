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

## ---- API key 落盘位置（按优先级）----
## user:// 是玩家自己填的（导出包可写，天然不进版本库）；
## res:// 是打包时注入的出厂密钥（导出只读，玩家改不了，见 scripts/tools/inject_api_key.gd）。
const USER_KEY_PATH := "user://ai_api_key.txt"
const RES_KEY_PATH := "res://ai/api_key.txt"

## ---- 错误哨兵词表（上层一律用 is_error_response / error_toast，勿各自硬编码前缀）----
## 分语义是必要的：鉴权类和额度类是**永久错误**，重试与回落非流式都必然再失败一次，
## 只会白白多等一轮并污染日志；而且玩家看到的提示也该各不相同。
const ERR_API := "[API_ERROR]"        # 网络层 / 5xx / 其它瞬时故障
const ERR_AUTH := "[AUTH_ERROR]"      # 401/403 —— 密钥无效或无权
const ERR_QUOTA := "[QUOTA_ERROR]"    # 402/429 —— 余额不足或请求过频
const ERR_BUSY := "[BUSY]"
const ERR_DISABLED := "[DISABLED]"
const ERROR_PREFIXES := [ERR_API, ERR_AUTH, ERR_QUOTA, ERR_BUSY, ERR_DISABLED]

## ---- 流式（SSE）----
## 一级回滚开关：--ai-stream-off / AI_STREAM=0 即整体退回非流式（行为与改造前一致）。
## 流式失败也会自动回落非流式，故即使上游不支持也不会比现状更差。
const STREAM_JSON_MODE := true      # 流式下仍请求 response_format: json_object（被 400 拒则自动关掉重试）
const STREAM_FIRST_BYTE_MS := 8000  # 首字节看门狗
const STREAM_IDLE_MS := 12000       # 空闲看门狗（距上次收到数据）
const STREAM_TOTAL_MS := 45000      # 单次流式总时长上限
const AIStreamClientScript := preload("res://scripts/systems/ai_stream_client.gd")
const AIJsonUtilsScript := preload("res://scripts/systems/ai_json_utils.gd")

var _http: HTTPRequest
var _stream_client = null                   # 在途流式连接（AIStreamClient；不标类型避免依赖全局类缓存）
var _stream_on := true                      # 见 STREAM_JSON_MODE 上方说明
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
## _send_once 对最后一次失败的归类："" = 可重试（网络层/5xx）；"auth"/"quota"/"other" = 永久。
var _last_fault := ""


func _ready() -> void:
	_api_key = _resolve_key()
	if _api_key.is_empty():
		_enabled = false
		print("[AIBridge] 未找到 API key，AI 对话关闭（将回落 JSON 对话）。")
	if OS.has_environment("AI_DISABLED") or "--ai-off" in OS.get_cmdline_user_args():
		_force_off = true
		_enabled = false
		print("[AIBridge] 检测到 --ai-off / AI_DISABLED，AI 对话关闭。")
	if OS.get_environment("AI_STREAM") == "0" or "--ai-stream-off" in OS.get_cmdline_user_args():
		_stream_on = false
		print("[AIBridge] 检测到 --ai-stream-off / AI_STREAM=0，退回非流式。")
	_http = _make_http()
	_log_net("[NET] AIBridge 启动 enabled=%s force_off=%s key_len=%d（无 key → AI 关闭，落固定对话，不会联网）"
			% [str(_enabled), str(_force_off), _api_key.length()])


func is_available() -> bool:
	if not _enabled or _force_off:
		return false
	if _mock_responder.is_valid():
		return true   # mock 模式（测试）不需要 API key
	return not _api_key.is_empty() and _http != null


## 返回值是否属于「AI 没答上来」的哨兵串（不是 LLM 的真实输出）。
func is_error_response(raw: String) -> bool:
	for p in ERROR_PREFIXES:
		if raw.begins_with(p):
			return true
	return raw.strip_edges().is_empty()


## 把哨兵串翻译成给玩家看的话（分诊：密钥问题就说密钥，别一律赖网络）。
func error_toast(raw: String) -> String:
	if raw.begins_with(ERR_AUTH):
		return "API 密钥无效，请在开始界面重新填写"
	if raw.begins_with(ERR_QUOTA):
		return "AI 请求过于频繁或额度不足，稍后再试"
	if raw.begins_with(ERR_BUSY):
		return "AI 还在回上一条，稍等一下"
	if raw.begins_with(ERR_DISABLED):
		return "未配置 API 密钥，AI 对话已关闭"
	return "AI 暂时无法回复，已切回固定对话"


## HTTP 码归类。返回 "" = 可重试（网络层错误 / 5xx 瞬时故障）；
## "auth" / "quota" / "other" = 永久错误 —— 重试与回落非流式都没有意义。
func _http_fault(code: int) -> String:
	if code == 401 or code == 403:
		return "auth"
	if code == 402 or code == 429:
		return "quota"
	if code >= 400 and code < 500:
		return "other"
	return ""   # 5xx 及其它：可能是瞬时的，值得重试


## 把 HTTP 错误码转成带语义的哨兵串（上层据此给玩家不同提示）。
func _fault_sentinel(code: int, body: String) -> String:
	var detail := body.strip_edges().substr(0, 200)
	match _http_fault(code):
		"auth": return "%s HTTP %d: %s" % [ERR_AUTH, code, detail]
		"quota": return "%s HTTP %d: %s" % [ERR_QUOTA, code, detail]
		_: return "%s HTTP %d: %s" % [ERR_API, code, detail]


## 流式是否启用（--ai-stream-off / AI_STREAM=0 关闭；仅供会话层决定走哪条路径）。
func is_stream_enabled() -> bool:
	return _stream_on


## 测试/运行时切换流式（不影响失败回落）。
func set_stream_enabled(v: bool) -> void:
	_stream_on = v


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
	var f := FileAccess.open(USER_KEY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(k)
		f.close()
	_log_net("[NET] 界面提交 key 并启用 key_len=%d" % k.length())
	print("[AIBridge] API key 已保存并启用。")
	return true


## 忘记密钥：内存状态与 user:// 落盘一并清掉，回到"未配置"。
##
## 存在的理由不只是产品功能（开始界面「清除」按钮）——它同时是测试的**唯一**退路：
## _ready() 在测试跑起来之前就把 key 读进内存了，此后无论怎么删文件，
## is_available() 都还是 true。没有这个方法，「无 key 状态」在开发机上根本不可达。
func clear_api_key() -> void:
	_api_key = ""
	_enabled = false
	if FileAccess.file_exists(USER_KEY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_KEY_PATH))
	_log_net("[NET] 已清除 API key（内存 + %s）" % USER_KEY_PATH)
	print("[AIBridge] API key 已清除，AI 对话关闭。")


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
	if _in_flight:
		_cancel_requested = true
		if _stream_client != null:
			_stream_client.close()   # 让流式轮询循环下一帧立即退出
		if _http != null:
			_http.cancel_request()


## 发送一次 LLM 请求。payload: { system: String, user: String }
## 返回 raw 响应文本；失败返回以 [API_ERROR] 开头 / [DISABLED] / [BUSY]。
func request_llm(payload: Dictionary) -> String:
	if _in_flight:
		_log_net("[NET] BUSY：仍有请求在途被拒（若持续出现 → 上一条请求未按时结束，检查遥测）")
		return ERR_BUSY
	if not is_available():
		return ERR_DISABLED
	if _mock_responder.is_valid():
		_in_flight = true
		var r: String = await _mock_responder.call(payload)
		_in_flight = false
		return r

	_in_flight = true
	var t0 := Time.get_ticks_msec()
	var raw := await _send_once(payload)
	# 断联重试：三个条件同时满足才重试 —— ①失败很快返回（慢超时重试只会让玩家等更久）
	# ②失败归类为可重试（网络层/5xx）③玩家没取消。
	# 鉴权/额度类错误（401/403/402/429）重试必然再失败一次，白白多等一轮还污染日志。
	if _last_fault == "" and is_error_response(raw) and not _cancel_requested \
			and Time.get_ticks_msec() - t0 < RETRY_MAX_ELAPSED_MS:
		_log_net("[NET] 快速失败触发自动重试 1 次：%s" % raw.left(60))
		print("[AIBridge] 请求快速失败（%s），重试一次…" % raw.left(48))
		raw = await _send_once(payload)
	else:
		if _last_fault != "":
			_log_net("[NET] 永久错误（%s）不重试：%s" % [_last_fault, raw.left(60)])
	_in_flight = false
	return raw


## 单次请求（无重试）。返回 raw 响应文本；失败以 [API_ERROR] 开头。
func _send_once(payload: Dictionary) -> String:
	var t0 := Time.get_ticks_msec()
	var stamp := Time.get_datetime_string_from_system()
	_last_fault = ""
	var body := _build_body(payload, false, true)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % _api_key,
	])
	var err := _http.request(BASE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_log_net("%s | 发送失败 err=%s" % [stamp, error_string(err)])
		return ERR_API + " " + error_string(err)

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
		_last_fault = "other"
		return ERR_API + " cancelled"
	# 绝对兜底：引擎既没回发结果也没超时信号 → 主动断开底层，按超时判失败
	if not _req_done:
		_http.cancel_request()
		_log_net("%s | 等待兜底超时 | %dms | FAIL" % [stamp, ms])
		_last_fault = ""
		return "%s result=%d http=%d" % [ERR_API, HTTPRequest.RESULT_TIMEOUT, code]

	print("[AIBridge] HTTP 完成 result=%d code=%d 耗时=%.1fs" % [result, code, ms / 1000.0])
	# 遥测一行：成功 result=0&http=200 记 OK；失败追加响应体前 160 字符（429/401/403/404 的直接证据）
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	var detail := ""
	if not ok and code >= 400 and bytes.size() > 0:
		detail = " body=%s" % bytes.get_string_from_utf8().substr(0, 160)
	_log_net("%s | result=%d http=%d | %dms | %s%s" % [stamp, result, code, ms, "OK" if ok else "FAIL", detail])

	if result != HTTPRequest.RESULT_SUCCESS:
		_last_fault = ""   # 网络层失败：可能是瞬时的，允许重试
		return "%s result=%d http=%d" % [ERR_API, result, code]
	if code != 200:
		_last_fault = _http_fault(code)
		return _fault_sentinel(code, bytes.get_string_from_utf8())
	# OpenAI chat.completions 信封 → 解包 assistant content（LLM 的真实 JSON 在 content 里）
	var content := _extract_content(bytes.get_string_from_utf8())
	if content.is_empty():
		_log_net("%s | result=%d http=%d | %dms | 200 但缺 assistant content（信封/编码异常）" % [stamp, result, code, ms])
		return ERR_API + " 响应缺少 assistant content"
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


## 组装 OpenAI chat.completions 请求体（流式/非流式共用，避免两处信封漂移）。
## stream=true 时额外带 "stream": true；json_object=false 用于被上游 400 拒绝后的重试。
func _build_body(payload: Dictionary, stream: bool, json_object: bool) -> String:
	var d := {
		"model": MODEL,
		# payload 可单独带 max_tokens 限幅（如对话轮次设小值提速）；缺省用全局 1024
		"max_tokens": int(payload.get("max_tokens", MAX_TOKENS)),
		"temperature": TEMPERATURE,
		"messages": [
			{"role": "system", "content": str(payload.get("system", ""))},
			{"role": "user", "content": str(payload.get("user", ""))},
		],
	}
	if json_object:
		# 强制 JSON 模式：避免模型输出 JSON 之外的文字导致整轮解析失败
		d["response_format"] = {"type": "json_object"}
	if stream:
		d["stream"] = true
	return JSON.stringify(d)


## BASE_URL → {host, path}（HTTPClient 需要分开传；单一来源避免两处写死漂移）。
func _api_parts() -> Dictionary:
	var rest := BASE_URL.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	return {
		"host": rest.substr(0, slash) if slash >= 0 else rest,
		"path": rest.substr(slash) if slash >= 0 else "/",
	}


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


# ---------------------------------------------------------------------------
# 流式（SSE）
# ---------------------------------------------------------------------------

## 流式请求。on_delta(visible_text) 每收到新内容回调一次（传入当前可显示台词）。
## 返回契约与 request_llm 完全一致：成功=LLM 原始 JSON 文本；失败=带语义的哨兵串。
## 瞬时失败自动回落非流式（一次）；永久错误（鉴权/额度/4xx）直接返回，不回落（省一轮必败请求）。
func request_llm_stream(payload: Dictionary, on_delta: Callable) -> String:
	if _in_flight:
		_log_net("[NET] stream BUSY：仍有请求在途被拒")
		return ERR_BUSY
	if not is_available():
		return ERR_DISABLED

	# mock：把整段结果一次吐给 on_delta（测试零网络，且覆盖"流式路径"的接线）
	if _mock_responder.is_valid():
		_in_flight = true
		_cancel_requested = false
		var mr: String = await _mock_responder.call(payload)
		if on_delta.is_valid() and not _cancel_requested:
			on_delta.call(AIJsonUtilsScript.extract_partial_string_field(mr, "response_text"))
		_in_flight = false
		return mr

	_in_flight = true
	var t0 := Time.get_ticks_msec()
	var res := await _stream_once(payload, on_delta, STREAM_JSON_MODE)

	# 上游若因 response_format 拒流式（400）且尚未吐出任何内容 → 关掉 json_object 重试一次
	if not res.get("ok", false) and not _cancel_requested \
			and int(res.get("http_code", 0)) == 400 and int(res.get("deltas", 0)) == 0:
		_log_net("[NET] stream 400（疑似 response_format 被拒）→ 关 json_object 重试")
		res = await _stream_once(payload, on_delta, false)

	var raw := str(res.get("raw", ""))
	var first := int(res.get("first_byte_ms", -1))
	var total_ms := int(res.get("total_ms", 0))

	if res.get("cancelled", false):
		_log_net("[NET] stream | 已取消 | %dms | FAIL" % total_ms)
		_in_flight = false
		return ERR_API + " cancelled"

	if res.get("ok", false) and not raw.strip_edges().is_empty():
		_log_net("[NET] stream | 首字%dms | 总%dms | delta=%d | %s | OK"
				% [first, total_ms, int(res.get("deltas", 0)),
				"done" if res.get("done", false) else "no-done(截断)"])
		print("[AIBridge] 流式完成 首字=%.1fs 总=%.1fs" % [first / 1000.0, total_ms / 1000.0])
		_in_flight = false
		return raw

	var err := str(res.get("error", "空内容"))
	if res.get("ok", false):
		err = "流式返回空内容"

	# 永久错误（401/403/402/429/4xx）：回落非流式必然再失败一次，只是白白多等一轮、
	# 还把真正的原因淹没在噪音里（真机"AI 断线"日志就是这么来的）。直接给准确原因。
	var code := int(res.get("http_code", 0))
	var fault := _http_fault(code)
	if fault != "":
		_log_net("[NET] stream | %dms | FAIL 永久错误(%s) 不回落：%s" % [total_ms, fault, err])
		print("[AIBridge] 流式永久错误（%s），不回落非流式。" % err.left(60))
		_in_flight = false
		return _fault_sentinel(code, str(res.get("err_body", err)))

	# 瞬时失败 → 回落非流式（玩家仍能拿到回复，只是没有边收边显示）
	_log_net("[NET] stream | 首字%dms | %dms | FAIL 回落非流式：%s" % [first, total_ms, err])
	print("[AIBridge] 流式失败（%s），回落非流式请求…" % err.left(60))
	var fb := await _send_once(payload)
	_in_flight = false
	return fb


## 单次流式尝试（不含回落/重试）。on_delta 在成功路径每帧可能被回调多次。
func _stream_once(payload: Dictionary, on_delta: Callable, json_object: bool) -> Dictionary:
	_cancel_requested = false
	var parts := _api_parts()
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: text/event-stream",
		"Authorization: Bearer %s" % _api_key,
	])
	# 不请求 gzip：HTTPClient 不会自动解压，压缩流会直接坏掉
	_stream_client = AIStreamClientScript.new()
	var res: Dictionary = await _stream_client.run(
		str(parts.get("host", "")), str(parts.get("path", "/")), headers,
		_build_body(payload, true, json_object), on_delta,
		_is_cancel_requested, STREAM_FIRST_BYTE_MS, STREAM_IDLE_MS, STREAM_TOTAL_MS)
	_stream_client = null
	return res


## 供 AIStreamClient 每帧查询是否已被取消（Esc / 守护超时）。
func _is_cancel_requested() -> bool:
	return _cancel_requested


## 带硬超时的流式请求。到点经 cancel_current → 关闭流式连接让轮询循环尽快退出。
func request_llm_stream_with_guard(payload: Dictionary, hard_timeout: float, on_delta: Callable) -> String:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = hard_timeout
	add_child(t)
	t.timeout.connect(cancel_current)
	t.start()
	var raw := await request_llm_stream(payload, on_delta)
	t.queue_free()
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
	for path in [USER_KEY_PATH, RES_KEY_PATH]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var k := _clean_key(f.get_as_text())
				f.close()
				if not k.is_empty():
					return k
	return ""
