extends Node

## AIBridge API key 接口测试（开始界面数据流）。
## 运行：godot --headless res://scripts/tests/test_api_key.tscn

var _failures := 0
var _passes := 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[KEYTEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[KEYTEST] FAIL  ", name)


func _run() -> void:
	var bridge = get_node("/root/AIBridge")

	# 清理旧状态
	if DirAccess.dir_exists_absolute("user://"):
		var p := "user://ai_api_key.txt"
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# 1. 无 key 状态
	_check("无 key 时不可用", not bridge.is_available())
	_check("状态文本=未配置", bridge.get_status_text() == "未配置密钥（AI 将回落 JSON 对话）")

	# 2. 空 key 提交
	_check("空 key 提交失败", bridge.set_api_key("   ") == false)

	# 3. 合法 key 提交
	_check("set_api_key 成功", bridge.set_api_key("sk-test-123") == true)
	_check("提交后可用", bridge.is_available() == true)
	_check("get_stored_key 回读", bridge.get_stored_key() == "sk-test-123")
	_check("状态文本=已启用", bridge.get_status_text() == "AI 已启用（已保存密钥）")

	# 4. 持久化文件已写入
	var p := "user://ai_api_key.txt"
	_check("user://ai_api_key.txt 已写入", FileAccess.file_exists(p))
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		_check("文件内容正确", f.get_as_text().strip_edges() == "sk-test-123")
		f.close()

	print("[KEYTEST] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
