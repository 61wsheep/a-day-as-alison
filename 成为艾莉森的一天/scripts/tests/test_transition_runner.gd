extends Node

## 过渡测试 Runner —— 挂在 root，change_scene_to_file 后仍存活。
## 由 test_start_transition.gd 引导创建。

const HelpersScript := preload("res://scripts/tests/test_helpers.gd")

var _failures := 0
var _passes := 0
var _key_backup := ""


func _ready() -> void:
	# 安全兜底
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 8.0
	guard.timeout.connect(func():
		print("[TRANS] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run()


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[TRANS] PASS  ", name)
	else:
		_failures += 1
		printerr("[TRANS] FAIL  ", name)


func _run() -> void:
	# 本测试要把 sk-transition-test 填进开始界面并让它落盘（LineEdit → start_menu →
	# set_api_key 持久化），会覆盖本机真能用的密钥；开头备份、收尾还回去。
	_key_backup = HelpersScript.backup_api_key()
	await _wait(0.2)

	var scene: CanvasLayer = (load("res://scenes/ui/start_menu.tscn") as PackedScene).instantiate()
	add_child(scene)
	await _wait(0.2)

	var key_edit: LineEdit = null
	var start_btn: Button = null
	for c in _all_controls(scene):
		if c is LineEdit and key_edit == null:
			key_edit = c
		if c is Button and (c as Button).text.contains("开始") and start_btn == null:
			start_btn = c
	_check("找到输入框", key_edit != null)
	_check("找到开始按钮", start_btn != null)
	if key_edit == null or start_btn == null:
		get_tree().quit(1)
		return

	key_edit.text = "sk-transition-test"
	start_btn.pressed.emit()

	# 切换后等待 main 场景就绪（本节点在 root，不会被释放）
	await _wait(1.2)
	var main: Node = get_tree().root.get_node_or_null("Main")
	_check("场景已切到 main", main != null)
	if main:
		_check("main 场景路径正确", main.scene_file_path == "res://scenes/main.tscn")
	var bridge = get_node("/root/AIBridge")
	_check("key 已保存并启用", bridge.is_available() and bridge.get_stored_key() == "sk-transition-test")

	HelpersScript.restore_api_key(bridge, _key_backup)
	print("[TRANS] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _all_controls(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_all_controls(c))
	return out
