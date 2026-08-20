extends Node

## 复现 S1 会话真实返回：用与游戏完全一致的 payload 打真实 API，
## 打印原始响应 + 解析结果，定位「AI 暂时无法回复」是请求层还是解析层。
## 场景运行：godot --headless scenes/tests/repro_s1_payload.tscn

func _ready() -> void:
	_run()


func _run() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null or not bridge.is_available():
		print("[REPRO] FAIL AI 不可用: %s" % (bridge.get_status_text() if bridge else "no bridge"))
		get_tree().quit(1)
		return
	# 伪造 npc_base 引用，让 session 能取 autoload
	var npc := Node.new()
	add_child(npc)
	var session = preload("res://scripts/systems/ai_dialogue_session.gd").new()
	session.setup(npc, "soraya")
	var payload: Dictionary = session._build_payload(true, "")
	print("[REPRO] payload system=%d 字, user=%d 字" % [str(payload.get("system", "")).length(), str(payload.get("user", "")).length()])
	print("[REPRO] user 开头:\n%s" % str(payload.get("user", "")).left(200))

	print("[REPRO] 发送真实请求 …")
	var raw: String = await bridge.request_llm_with_guard(payload, 30.0)
	if raw.begins_with("["):
		print("[REPRO] 请求层失败: %s" % raw.left(300))
		get_tree().quit(1)
		return
	print("[REPRO] RAW len=%d:\n%s" % [raw.length(), raw.left(1200)])
	var r := AIJsonUtils.parse_response(raw, ["response_text", "emotional_shift", "memory_update"])
	print("[REPRO] 解析 success=%s method=%s error=%s" % [r.get("success"), r.get("method", ""), r.get("error", "")])
	get_tree().quit(0 if r.get("success") else 1)
