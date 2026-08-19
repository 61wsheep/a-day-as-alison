extends CanvasLayer

## 游戏开始界面 — 提交 SiliconFlow API key（可选），然后进入主场景。
##
## - 密钥输入框（secret 模式），支持 Enter 提交。
## - 已保存过的 key 预填 + 显示「AI 已启用」。
## - 空 key / AI 禁用：允许开始，AI 回落 JSON 对话（游戏完整可玩）。
## - AIBridge 是 autoload，_ready 在启动瞬间执行；这里通过 set_api_key()
##   动态启用并持久化到 user://ai_api_key.txt，无需重启。

const MAIN_SCENE := "res://scenes/main.tscn"

var _key_edit: LineEdit
var _status_label: Label
var _start_btn: Button


func _ready() -> void:
	layer = 30
	_build_ui()


func _build_ui() -> void:
	# 全屏暗色底
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.1, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# 背景装饰：森林概念图，全屏铺满（保持宽高比裁剪），半透明
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture = load("res://assets/sprites/forest_draft.png")
	bg.modulate = Color(1, 1, 1, 0.5)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	panel.offset_left = -300
	panel.offset_top = -200
	panel.offset_right = 300
	panel.offset_bottom = 200
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "成为艾莉森的一天"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "—— 探秘森林，揭示「天」的面目 ——"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	vbox.add_child(subtitle)

	# 密钥输入
	var key_label := Label.new()
	key_label.text = "SiliconFlow API Key（可选，不填则 AI 对话回落 JSON）"
	key_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(key_label)

	_key_edit = LineEdit.new()
	_key_edit.placeholder_text = "sk-..."
	_key_edit.secret = true
	_key_edit.secret_character = "•"
	_key_edit.add_theme_font_size_override("font_size", 16)
	_key_edit.text_submitted.connect(func(_t): _on_start())
	vbox.add_child(_key_edit)

	# 状态
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_status_label)

	_start_btn = Button.new()
	_start_btn.text = "开始游戏"
	_start_btn.add_theme_font_size_override("font_size", 22)
	_start_btn.pressed.connect(_on_start)
	vbox.add_child(_start_btn)

	_refresh_status()


func _refresh_status() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		_status_label.text = ""
		return
	if bridge.has_method("is_force_off") and bridge.is_force_off():
		_status_label.text = "AI 已禁用（--ai-off / AI_DISABLED）"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		_key_edit.editable = false
		return
	if bridge.has_method("get_stored_key") and bridge.is_available():
		var k := str(bridge.get_stored_key())
		if not k.is_empty():
			_key_edit.text = k
			_status_label.text = "AI 已启用（已保存密钥）"
			_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			return
	_status_label.text = "未配置密钥（AI 将回落 JSON 对话）"
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))


func _on_start() -> void:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge and bridge.has_method("set_api_key"):
		bridge.set_api_key(_key_edit.text)
	get_tree().change_scene_to_file(MAIN_SCENE)
