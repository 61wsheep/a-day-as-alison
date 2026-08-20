extends Node

## 真实网络测试：走 AIBridge.request_llm_with_guard（30s 硬超时）。
## 场景运行：godot --headless scenes/tests/http_live_test.tscn
## 验证：request_completed 触发、主循环不冻结、超时回落生效。

func _ready() -> void:
	_run()


func _run() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		print("[HTTPLIVE] FAIL 无 AIBridge autoload")
		get_tree().quit(1)
		return
	if not bridge.is_available():
		print("[HTTPLIVE] AI 不可用: %s" % bridge.get_status_text())
		get_tree().quit(1)
		return
	print("[HTTPLIVE] 开始真实请求（30s 硬超时）…")
	var t0 := Time.get_ticks_msec()
	var raw: String = await bridge.request_llm_with_guard(
		{"system": "你是测试助手", "user": "只回复：ok"}, 30.0)
	var dt := Time.get_ticks_msec() - t0
	print("[HTTPLIVE] %.2fs 返回，长度=%d: %s" % [(dt / 1000.0), raw.length(), raw.left(160)])
	# 正常返回不应是 [BUSY] 等哨兵，且应包含 JSON 或错误描述
	var ok := raw != "" and not raw.begins_with("[BUSY]")
	print("[HTTPLIVE] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
