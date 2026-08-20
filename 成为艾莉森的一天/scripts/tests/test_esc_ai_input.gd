extends Node

## 定位「AI 思考态下 Esc 不退出」：
## 1) 直接调 npc_base._input(esc)  → 测 Esc 分支逻辑
## 2) 走真实输入管线 Input.parse_input_event → 测事件是否到达节点
## 3) LineEdit 聚焦 + Esc（复现第 1 轮遗留焦点）
## 4) 兜底路径：npc_base._input 未命中时，dialogue_ui._unhandled_input
##    发 dialogue_exit_requested → npc_base._request_exit → _end_dialogue
## 场景运行：godot --headless scenes/tests/test_esc_ai_input.tscn

func _ready() -> void:
	_run()


func _run() -> void:
	var npc = preload("res://scripts/npc/npc_base.gd").new()
	add_child(npc)
	npc.npc_id = "soraya"
	npc._player_in_range = true

	# ---- 1) 直接调用 _input：伪造 AI 思考态 ----
	npc._ai_mode = true
	npc._dialogue_active = true
	npc._ai_thinking = true
	var act := InputEventAction.new()
	act.action = "ui_cancel"
	act.pressed = true
	npc._input(act)
	await get_tree().process_frame
	print("[ESC] 直接调用 _input：_dialogue_active=%s _ai_mode=%s" % [npc._dialogue_active, npc._ai_mode])
	var direct_ok: bool = not npc._dialogue_active

	# ---- 2) 走真实输入管线（伪造成 AI 思考态）----
	npc._ai_mode = true
	npc._dialogue_active = true
	npc._ai_thinking = true
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[ESC] 真实输入管线：_dialogue_active=%s _ai_mode=%s" % [npc._dialogue_active, npc._ai_mode])
	var pipeline_ok: bool = not npc._dialogue_active

	# ---- 3) LineEdit 聚焦 + Esc（复现第 1 轮遗留焦点）----
	npc._ai_mode = true
	npc._dialogue_active = true
	npc._ai_thinking = true
	var edit := LineEdit.new()
	add_child(edit)
	edit.grab_focus()
	await get_tree().process_frame
	print("[ESC] focus_owner=%s" % get_viewport().gui_get_focus_owner())
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[ESC] LineEdit 聚焦时输入管线：_dialogue_active=%s" % npc._dialogue_active)
	var focused_ok: bool = not npc._dialogue_active

	# ---- 4) 兜底路径：npc_base._input 未命中 → dialogue_ui 兜底发 dialogue_exit_requested ----
	npc._ai_mode = true
	npc._dialogue_active = true
	npc._ai_thinking = true
	var ui = preload("res://scripts/ui/dialogue_ui.gd").new()
	add_child(ui)
	ui._dlg_active = true   # 模拟：对话激活且 npc_base._input 未消费 Esc
	ui._unhandled_input(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[ESC] 兜底路径 dialogue_ui._unhandled_input：_dialogue_active=%s _ai_mode=%s" % [npc._dialogue_active, npc._ai_mode])
	var backup_ok: bool = not npc._dialogue_active

	print("[ESC] %s" % ("PASS 四条路径都能退出" if (direct_ok and pipeline_ok and focused_ok and backup_ok) else
		("PARTIAL direct=%s pipeline=%s focused=%s backup=%s" % [direct_ok, pipeline_ok, focused_ok, backup_ok])))
	get_tree().quit(0)
