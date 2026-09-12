extends Node

## 开始界面预填测试：user:// 已有 key 时，LineEdit 应预填、状态显示已启用。
## 前置由本测试自己写入（见 _run）——原先靠"先跑 test_api_key"留下的残留文件，
## 但 test_transition_runner 会把同一个槽位改写成 sk-transition-test，
## 于是本测试变成看执行顺序吃饭（先跑 menu 还是先跑 transition，结果相反）。
## 运行：godot --headless scenes/tests/test_start_menu.tscn

var _failures := 0
var _passes := 0


func _ready() -> void:
	# 安全兜底：5 秒强制退出，防死锁
	var guard := Timer.new()
	guard.one_shot = true
	guard.wait_time = 5.0
	guard.timeout.connect(func():
		print("[MENUTEST] 超时强制退出")
		get_tree().quit(2))
	add_child(guard)
	guard.start()
	_run()


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[MENUTEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[MENUTEST] FAIL  ", name)


func _run() -> void:
	print("[MENUTEST] 开始")
	var bridge = get_node("/root/AIBridge")
	bridge.set_api_key("sk-test-123")   # 自带前置，不再依赖别的测试的副作用
	_check("预置 key 存在", FileAccess.file_exists("user://ai_api_key.txt"))
	_check("AIBridge 已加载 key", not bridge.get_stored_key().is_empty())

	# 实例化开始界面
	var scene: CanvasLayer = (load("res://scenes/ui/start_menu.tscn") as PackedScene).instantiate()
	add_child(scene)
	print("[MENUTEST] 已实例化开始界面")

	var key_edit: LineEdit = null
	var status_label: Label = null
	var status_found := false
	for c in _all_controls(scene):
		if c is LineEdit and key_edit == null:
			key_edit = c
		if c is Label and not status_found:
			var t: String = (c as Label).text
			if "已启用" in t or "未配置" in t or "已禁用" in t:
				status_label = c
				status_found = true

	print("[MENUTEST] key_edit=", key_edit, " status_found=", status_found)
	_check("找到密钥输入框", key_edit != null)
	if key_edit:
		_check("输入框已预填 key", key_edit.text == "sk-test-123")
	if status_label:
		_check("状态显示已启用", status_label.text == "AI 已启用（已保存密钥）")

	print("[MENUTEST] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _all_controls(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_all_controls(c))
	return out
