extends Node

## 开始界面 → 主场景 过渡测试 引导层。
## 场景是 current_scene，会被 change_scene_to_file 释放；测试逻辑放到
## 挂在 root 的 Runner 节点（非 current_scene），切换后存活。
## 用法：godot --headless scenes/tests/test_start_transition.tscn

func _ready() -> void:
	# Runner 挂 root，入树后 _ready 自动开跑
	var runner := Node.new()
	runner.name = "TransRunner"
	runner.set_script(preload("res://scripts/tests/test_transition_runner.gd"))
	get_tree().root.add_child.call_deferred(runner)
