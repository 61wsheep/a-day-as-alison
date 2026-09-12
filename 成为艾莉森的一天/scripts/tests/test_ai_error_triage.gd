extends SceneTree

## AIBridge 错误分诊单测（零网络）。
## 运行：godot --headless --path . -s res://scripts/tests/test_ai_error_triage.gd
##
## 背景：真机"AI 断线"排查时，全线 401 被 "AI 暂时无法回复" 这句通用提示掩盖，
## 玩家和开发都以为是网络问题。这里锁住三件事：
##   ① 401/403/402/429 必须归为永久错误（→ 不重试、不回落非流式）
##   ② 5xx / 网络层必须仍可重试
##   ③ 每种错误给玩家的提示各不相同，密钥问题必须直说密钥

var _failures := 0
var _passes := 0
var _bridge: Node = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_bridge = root.get_node_or_null("AIBridge")
	if _bridge == null:
		printerr("[TRIAGE] 无 AIBridge autoload，跳过")
		quit(1)
		return
	_test_http_fault()
	_test_sentinel_shape()
	_test_is_error_response()
	_test_error_toast()
	print("[TRIAGE] 错误分诊: %d 通过, %d 失败" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TRIAGE] PASS  ", name)
	else:
		_failures += 1
		printerr("[TRIAGE] FAIL  ", name)


## ① 归类：鉴权/额度是永久错误（"" 之外的值），5xx 与网络层仍可重试（""）。
func _test_http_fault() -> void:
	_check("401 归为鉴权（永久）", _bridge._http_fault(401) == "auth")
	_check("403 归为鉴权（永久）", _bridge._http_fault(403) == "auth")
	_check("402 归为额度（永久）", _bridge._http_fault(402) == "quota")
	_check("429 归为额度（永久）", _bridge._http_fault(429) == "quota")
	_check("400 归为参数（永久）", _bridge._http_fault(400) == "other")
	_check("500 可重试", _bridge._http_fault(500) == "")
	_check("503 可重试", _bridge._http_fault(503) == "")
	_check("网络层 code=0 可重试", _bridge._http_fault(0) == "")
	_check("200 不算错误", _bridge._http_fault(200) == "")


## ② 哨兵串带上正确的前缀，且带上原始响应体供排查。
func _test_sentinel_shape() -> void:
	var auth: String = _bridge._fault_sentinel(401, '{"code":30014,"message":"Token is invalid."}')
	_check("401 哨兵 = [AUTH_ERROR]", auth.begins_with("[AUTH_ERROR]"))
	_check("401 哨兵保留原始响应体", auth.find("Token is invalid") != -1)
	var quota: String = _bridge._fault_sentinel(429, "rate limited")
	_check("429 哨兵 = [QUOTA_ERROR]", quota.begins_with("[QUOTA_ERROR]"))
	var other: String = _bridge._fault_sentinel(400, "bad request")
	_check("400 哨兵 = [API_ERROR]", other.begins_with("[API_ERROR]"))


## ③ 判定：哨兵算失败，LLM 真实输出不算。
func _test_is_error_response() -> void:
	_check("[AUTH_ERROR] 判为失败", _bridge.is_error_response("[AUTH_ERROR] HTTP 401: x"))
	_check("[QUOTA_ERROR] 判为失败", _bridge.is_error_response("[QUOTA_ERROR] HTTP 429: x"))
	_check("[API_ERROR] 判为失败", _bridge.is_error_response("[API_ERROR] result=1"))
	_check("[BUSY] 判为失败", _bridge.is_error_response("[BUSY]"))
	_check("[DISABLED] 判为失败", _bridge.is_error_response("[DISABLED]"))
	_check("空串判为失败", _bridge.is_error_response("   "))
	_check("正常 JSON 判为成功",
		not _bridge.is_error_response('{"response_text":"你好","emotional_shift":1}'))
	_check("带 markdown 的 JSON 判为成功",
		not _bridge.is_error_response("```json\n{\"response_text\":\"嗯\"}\n```"))


## ④ 提示分诊：密钥问题必须直说密钥，不能一律赖网络。
func _test_error_toast() -> void:
	var auth: String = _bridge.error_toast("[AUTH_ERROR] HTTP 401: Token is invalid.")
	var quota: String = _bridge.error_toast("[QUOTA_ERROR] HTTP 429: rate limited")
	var generic: String = _bridge.error_toast("[API_ERROR] result=1 http=0")
	_check("401 提示点名密钥", auth.find("密钥") != -1)
	_check("429 提示点名频繁/额度", quota.find("频繁") != -1 or quota.find("额度") != -1)
	_check("网络错误仍用通用提示", generic.find("无法回复") != -1)
	_check("三种提示互不相同", auth != quota and quota != generic and auth != generic)
